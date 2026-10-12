// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import os
import json2
import tarcore
import tarstream

#include <pwd.h>
#include <grp.h>
#include <sys/stat.h>

fn C.mkdir(&char, u32) int
fn C.mkfifo(&char, u32) int
fn C.mknod(&char, u32, u64) int
fn C.major(u64) u32
fn C.minor(u64) u32
fn C.makedev(u32, u32) u64

$if linux {
	#include <sys/sysmacros.h>
}

struct C.passwd {
	pw_name &char
}

struct C.group {
	gr_name &char
}

fn C.getpwuid(u32) &C.passwd
fn C.getgrgid(u32) &C.group

fn tar_member(path string, name string) !tarcore.Member {
	state := os.lstat(path)!
	mut member := tarcore.Member{ name: name.trim_left('/'), mode: i64(state.mode & 0o7777), uid: state.uid, gid: state.gid, mtime: state.mtime }
	user := C.getpwuid(state.uid)
	if user != unsafe { nil } { member.uname = unsafe { user.pw_name.vstring().clone() } }
	group := C.getgrgid(state.gid)
	if group != unsafe { nil } { member.gname = unsafe { group.gr_name.vstring().clone() } }
	match state.get_filetype() {
		.regular { member.size = i64(state.size) }
		.directory { member.kind = `5` }
		.symbolic_link {
			member.kind = `2`
			member.linkname = os.readlink(path)!
		}
		.fifo { member.kind = `6` }
		.character_device, .block_device {
			member.kind = if state.get_filetype() == .character_device { u8(`3`) } else { u8(`4`) }
			member.major = i64(C.major(state.rdev))
			member.minor = i64(C.minor(state.rdev))
		}
		else { return error('unsupported archive input: ' + path) }
	}
	return member
}

fn extract_path(root string, name string) !string {
	// Boot inputs are trusted, but a corrupt archive must not write beyond the
	// private overlay or follow a directory symlink out of it.
	if name.starts_with('/') || name.split('/').any(it == '..') {
		return error('archive member escapes overlay: ' + name)
	}
	mut path := root
	for part in name.split('/').filter(it != '' && it != '.') {
		path = join([path, part])
		if os.is_link(path) && path != join([root, name]) {
			return error('archive member traverses a symlink: ' + name)
		}
	}
	return path
}

fn extract_archive(mut archive Archive, root string) ! {
	parents(root)!
	mut directories := []tarcore.Member{}
	for {
		member := archive.reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		target := extract_path(root, member.name)!
		parents(parent(target))!
		if member.kind == `5` {
			if !os.is_dir(target) { os.mkdir(target)! }
			directories << member
		} else if member.regular() {
			if os.is_link(target) { os.rm(target)! }
			mut file := os.create(target)!
			mut buffer := []u8{len: 1024 * 1024}
			mut succeeded := false
			defer {
				file.close()
				if !succeeded { os.rm(target) or {} }
			}
			for {
				count := archive.reader.read(mut buffer)!
				if count == 0 { break }
				write_bytes(mut file, buffer[..count])!
			}
			file.close()
			succeeded = true
			os.chmod(target, int(member.mode))!
			os.utime(target, member.mtime, member.mtime)!
		} else if member.kind in [u8(`1`), `2`] {
			if os.exists(target) || os.is_link(target) { os.rm(target)! }
			if member.kind == `2` {
				os.symlink(member.linkname, target)!
			} else {
				source := extract_path(root, member.linkname)!
				if C.link(source.str, target.str) != 0 { return os.error_posix() }
			}
		} else if member.kind == `6` {
			if C.mkfifo(target.str, u32(member.mode)) != 0 { return os.error_posix() }
		} else if member.kind in [u8(`3`), `4`] {
			kind := if member.kind == `3` { C.S_IFCHR } else { C.S_IFBLK }
			if C.mknod(target.str, u32(member.mode) | u32(kind), C.makedev(u32(member.major), u32(member.minor))) != 0 {
				return os.error_posix()
			}
		}
	}
	for index := directories.len - 1; index >= 0; index-- {
		member := directories[index]
		target := extract_path(root, member.name)!
		os.chmod(target, int(member.mode))!
		os.utime(target, member.mtime, member.mtime)!
	}
}

fn (mut context Context) tar_primitive(operation string, row map[string]ah.Value) !ah.Value {
	if operation == 'tar_open' {
		path := text(row, 'path')
		mut archive := &Archive{ path: path, reading: text(row, 'mode').starts_with('r') }
		if archive.reading {
			archive.reader = tarstream.open(path)!
		} else {
			archive.writer = tarcore.create_stream(path)!
		}
		id := context.archives.len
		context.archives << archive
		return ah.Value(id)
	}
	id := int(number(ah.field(row, 'id'))!)
	if id < 0 || id >= context.archives.len || context.archives[id].closed {
		return error('retired native archive handle')
	}
	mut archive := context.archives[id]
	return match operation {
		'tar_next' {
			member := archive.reader.next() or {
				if err is tarstream.End { return null() }
				return err
			}
			ah.Value(member.name)
		}
		'tar_extract' {
			extract_archive(mut archive, text(row, 'path'))!
			null()
		}
		'tar_info' {
			mut member := tar_member(text(row, 'path'), text(row, 'name'))!
			state := os.lstat(text(row, 'path'))!
			if member.regular() && state.nlink > 1 {
				identity := state.dev.str() + ':' + state.inode.str()
				if name := archive.inodes[identity] {
					member.kind = `1`
					member.linkname = name
					member.size = 0
				} else {
					archive.inodes[identity] = member.name
				}
			}
			info := context.infos.len
			context.infos << member
			ah.Value({
				'id':      ah.Value(info)
				'regular': ah.Value(member.regular())
				'size':    ah.Value(member.size)
				'mode':    ah.Value(member.mode)
			})
		}
		'tar_add' {
			info := int(number(ah.field(row, 'info'))!)
			if info < 0 || info >= context.infos.len {
				return error('invalid archive member handle')
			}
			mut member := context.infos[info]
			fields := ah.field(row, 'fields').object()
			if 'type' in fields { member.kind = text(fields, 'type')[0] }
			if 'size' in fields { member.size = number(fields['size']!)! }
			if 'linkname' in fields { member.linkname = text(fields, 'linkname') }
			archive.writer.write(tarcore.header(member)!)!
			if 'path' in row {
				mut file := os.open(text(row, 'path'))!
				defer { file.close() }
				mut remaining := member.size
				mut buffer := []u8{len: 1024 * 1024}
				for remaining > 0 {
					limit := if remaining < buffer.len { int(remaining) } else { buffer.len }
					mut portion := unsafe { buffer[..limit] }
					count := file.read(mut portion)!
					if count == 0 { return error('unexpected end of archived file') }
					archive.writer.write(buffer[..count])!
					remaining -= count
				}
			}
			archive.writer.padding(member.size)!
			null()
		}
		'tar_exit' {
			archive.closed = true
			if archive.reading {
				archive.reader.close()
			} else {
				defer { archive.writer.close() }
				if ah.field(row, 'error') is json2.Null { archive.writer.finish()! }
				archive.writer.close_checked()!
			}
			ah.Value(false)
		}
		else { return error('unknown native archive primitive') }
	}
}
