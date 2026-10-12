// SPDX-License-Identifier: GPL-2.0-or-later
module steamshim

import cachecli
import cachekey
import os
import sourcecommand
import tarstream
import tarcore
import math
import strconv

#flag -I @DIR
#include "steam-shim-abi.h"
@[typedef]
struct C.vinix_steam_passwd {
	pw_uid u32
}

@[typedef]
struct C.vinix_steam_group {
	gr_gid u32
}

@[typedef]
struct C.vinix_steam_utimbuf {
	actime  i64
	modtime i64
}

@[typedef]
struct C.vinix_steam_timespec {
	tv_sec  i64
	tv_nsec i64
}

fn C.getpwnam(&char) &C.vinix_steam_passwd
fn C.getgrnam(&char) &C.vinix_steam_group
fn C.vinix_steam_chown(&char, u32, u32) i32
fn C.vinix_steam_utime(&char, &C.vinix_steam_utimbuf) i32
fn C.lchown(&char, u32, u32) i32
fn C.vinix_steam_utimensat(i32, &char, &C.vinix_steam_timespec, i32) i32

fn C.execv(&char, &&char) i32
fn C.link(&char, &char) i32
fn C.lseek(i32, i64, i32) i64
fn C.truncate(&char, i64) i32

pub struct Extraction {
pub:
	extract   bool
	archive   string
	directory string
}

pub fn extraction_args(args []string, cwd string) ?Extraction {
	mut extract := false
	mut archive := ''
	mut directory := cwd
	mut index := 0
	for index < args.len {
		mut arg := args[index]
		if index == 0 && arg != '' && arg[0] == `x` && arg.bytes().all(it in [`x`, `z`, `J`, `v`,
			`f`]) {
			arg = '-' + arg
		}
		if arg in ['-C', '--directory'] {
			index++
			if index == args.len { return none }
			directory = args[index]
		} else if arg.starts_with('--directory=') {
			directory = arg.all_after('=')
		} else if arg in ['--no-same-permissions', '--no-same-owner', '--numeric-owner'] {
		} else if arg.starts_with('--blocking-factor=') || arg.starts_with('--checkpoint=') || arg.starts_with('--checkpoint-action=') {
		} else if arg in ['--blocking-factor', '--checkpoint', '--checkpoint-action'] {
			index++
			if index == args.len { return none }
		} else if arg.starts_with('-') && !arg.starts_with('--') {
			letters := arg[1..]
			mut position := 0
			for position < letters.len {
				letter := letters[position]
				if letter == `x` {
					extract = true
				} else if letter in [`z`, `J`, `v`] {
				} else if letter == `f` {
					if position + 1 < letters.len {
						archive = letters[position + 1..]
					} else {
						index++
						if index == args.len { return none }
						archive = args[index]
					}
					break
				} else {
					return none
				}
				position++
			}
		} else {
			return none
		}
		index++
	}
	if !extract || archive == '' || archive == '-' { return none }
	return Extraction{extract, archive, directory}
}

fn parent(path string) string {
	result := path.trim_right('/').all_before_last('/')
	return if result == '' { '/' } else { result }
}

fn mkdir(path string) ! {
	if os.is_dir(path) { return }
	if path == '' { return error('empty directory') }
	base := parent(path)
	if base != path { mkdir(base)! }
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}

fn joined(root string, path string) string {
	return if path.starts_with('/') { path } else { root + '/' + path }
}

pub fn inside(root string, path string) !bool {
	resolved := cachekey.resolve_path(path)!
	return resolved == root || resolved.starts_with(root + '/')
}

pub struct TarOptions {
pub:
	// Native guest defaults use the same private GNU tool root as delegated tar.
	decompressors       map[string]string
	preserve_attributes bool
}

struct SavedMember {
	member tarcore.Member
	mtime  string
}

fn decoder(name string, options TarOptions) string {
	if value := options.decompressors[name] { return value }
	root := os.getenv_opt('VINIX_STEAM_ROOT') or { '/usr/libexec/vinix-steam/root' }
	return root + '/usr/bin/' + name
}

fn compression(bytes []u8) string {
	if bytes.len >= 2 && bytes[..2] == [u8(0x1f), 0x8b] { return 'gzip' }
	if bytes.len >= 3 && bytes[..3].bytestr() == 'BZh' { return 'bzip2' }
	if bytes.len >= 6 && bytes[..6] == [u8(0xfd), `7`, `z`, `X`, `Z`, 0] { return 'xz' }
	// LZMA-alone's dictionary field is a power of two (or three halves), unlike
	// a tar member name. GNU xz and the original LZMA reader accept this format.
	if bytes.len >= 13 && bytes[0] < 225 {
		n := u32(bytes[1]) | (u32(bytes[2]) << 8) | (u32(bytes[3]) << 16) | (u32(bytes[4]) << 24)
		if n >= 4096 && (n & (n - 1) == 0 || (n % 3 == 0 && ((n / 3) & ((n / 3) - 1)) == 0)) {
			return 'xz'
		}
	}
	return ''
}

pub fn extract(archive string, directory string, options TarOptions) ! {
	root := cachekey.resolve_path(directory)!
	mkdir(root)!
	fd := unsafe { C.open(archive.str, C.O_RDONLY | C.O_CLOEXEC) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	mut prefix := [13]u8{}
	count := C.read(fd, &prefix[0], prefix.len)
	if count < 0 { return os.error_posix() }
	if count == 0 { return error('empty archive') }
	if C.lseek(fd, 0, C.SEEK_SET) < 0 { return os.error_posix() }
	kind := compression(prefix[..count])
	mut child := sourcecommand.ReaderChild{}
	mut owns_child := false
	defer { if owns_child { child.close() or {} } }
	if kind != '' {
		child = sourcecommand.spawn_reader([decoder(kind, options), '-dc', '--', archive], os.environ())!
		owns_child = true
	}
	mut reader := tarstream.from_descriptor_cancelled(if owns_child { child.descriptor } else { fd }, cachecli.cancelled)!
	reader.enable_sparse()
	defer { reader.close() }
	mut materialized := map[string]SavedMember{}
	mut directories := []SavedMember{}
	for {
		cachecli.checkpoint()!
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		target := joined(root, member.name).trim_right('/')
		if !inside(root, target)! {
			return error('archive path leaves destination: ' + member.name)
		}
		if member.kind == `2` && !inside(root, joined(parent(target), member.linkname))! {
			return error('archive link leaves destination: ' + member.name)
		}
		if member.kind == `1` && !inside(root, joined(root, member.linkname))! {
			return error('archive hard link leaves destination: ' + member.name)
		}
		if !member.regular() && member.kind !in [`1`, `2`, `5`, `S`] {
			return error('unsupported archive member: ' + member.name)
		}
		mkdir(parent(target))!
		if member.kind == `5` {
			os.mkdir(target, mode: 0o700) or { if err.code() != C.EEXIST { return err } }
		} else if member.kind == `2` {
			if os.exists(target) || os.is_link(target) { os.rm(target)! }
			os.symlink(member.linkname, target)!
		} else if member.kind == `1` {
			source := joined(root, member.linkname)
			if C.link(source.str, target.str) != 0 {
				previous := materialized[normalized(member.linkname)] or { return error('unable to resolve link inside archive') }
				copy_link(source, target, previous)!
			}
		} else {
			mut file := os.create(target)!
			mut closed := false
			defer { if !closed { file.close() } }
			mut buffer := []u8{len: 65536}
			logical, extents := reader.sparse_layout()
			if logical >= 0 {
				for extent in extents {
					file.seek(extent.offset, .start)!
					mut left := extent.length
					for left > 0 {
						take := if left < buffer.len { int(left) } else { buffer.len }
						mut part := unsafe { buffer[..take] }
						n := reader.read(mut part)!
						if n != take { return error('truncated sparse archive data') }
						unsafe { file.write_full_buffer(buffer.data, usize(n))! }
						left -= n
					}
				}
			} else {
				for {
					n := reader.read(mut buffer)!
					if n == 0 { break }
					unsafe { file.write_full_buffer(buffer.data, usize(n))! }
				}
			}
			file.close()
			closed = true
			if logical >= 0 && C.truncate(target.str, logical) != 0 { return os.error_posix() }
			os.chmod(target, int(member.mode & 0o777))!
		}
		saved := SavedMember{member, reader.modification_time()}
		materialized[normalized(member.name)] = saved
		if options.preserve_attributes {
			if member.kind == `5` {
				directories << saved
			} else {
				restore_attributes(target, saved, member.kind == `2`)!
			}
		}
	}
	// extractall applies directory metadata after children, in reverse name order.
	directories.sort(a.member.name > b.member.name)
	for saved in directories { restore_attributes(joined(root, saved.member.name), saved, false)! }
}

fn normalized(name string) string {
	mut parts := []string{}
	for part in name.split('/') {
		if part in ['', '.'] { continue }
		if part == '..' && parts.len > 0 && parts.last() != '..' {
			parts.pop()
		} else {
			parts << part
		}
	}
	return (if name.starts_with('/') { '/' } else { '' }) + parts.join('/')
}

fn copy_link(source string, target string, saved SavedMember) ! {
	from := os.stat(source)!
	same_inode := if to := os.stat(target) {
		from.dev == to.dev && from.inode == to.inode
	} else {
		false
	}
	if !same_inode {
		mut input := os.open(source)!
		defer { input.close() }
		mut output := os.create(target)!
		defer { output.close() }
		mut buffer := []u8{len: 65536}
		for {
			count := input.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if count == 0 { break }
			unsafe { output.write_full_buffer(buffer.data, usize(count))! }
		}
		output.close()
	}
	restore_attributes(target, saved, false)!
}

fn restore_attributes(target string, saved SavedMember, symbolic bool) ! {
	member := saved.member
	if os.getuid() == 0 {
		mut uid := u32(member.uid)
		mut gid := u32(member.gid)
		if member.uname != '' {
			entry := C.getpwnam(member.uname.str)
			if entry != unsafe { nil } { uid = entry.pw_uid }
		}
		if member.gname != '' {
			entry := C.getgrnam(member.gname.str)
			if entry != unsafe { nil } { gid = entry.gr_gid }
		}
		status := if symbolic {
			C.lchown(target.str, uid, gid)
		} else {
			C.vinix_steam_chown(target.str, uid, gid)
		}
		if status != 0 { return os.error_posix() }
	}
	if symbolic { return }
	os.chmod(target, int(member.mode))!
	if saved.mtime.contains_any('.eE') {
		value := strconv.atof64(saved.mtime)!
		seconds := i64(math.floor(value))
		nanos := i64(math.floor((value - f64(seconds)) * 1_000_000_000))
		times := [C.vinix_steam_timespec{seconds, nanos}, C.vinix_steam_timespec{seconds, nanos}]!
		if C.vinix_steam_utimensat(C.AT_FDCWD, target.str, &times[0], 0) != 0 {
			return os.error_posix()
		}
		return
	}
	times := C.vinix_steam_utimbuf{ actime: member.mtime, modtime: member.mtime }
	if C.vinix_steam_utime(target.str, &times) != 0 { return os.error_posix() }
}

pub fn tar_cli(argv []string) !int {
	parsed := extraction_args(argv, os.getwd()) or {
		root := os.getenv_opt('VINIX_STEAM_ROOT') or { '/usr/libexec/vinix-steam/root' }
		path := root + '/usr/bin/tar'
		values := [path, ...argv]
		mut args := []&char{}
		for value in values { args << unsafe { &char(value.str) } }
		args << &char(unsafe { nil })
		unsafe { C.execv(path.str, args.data) }
		return os.error_posix()
	}
	extract(parsed.archive, parsed.directory, TarOptions{}) or {
		eprintln('steam tar: ' + err.msg())
		return 2
	}
	return 0
}
