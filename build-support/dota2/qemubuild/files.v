// SPDX-License-Identifier: GPL-2.0-or-later
module qemubuild

import cachekey
import crypto.sha256
import hosttest
import os
import strings

#include <stdio.h>
#include <errno.h>
#include <sys/stat.h>
#include "@DIR/stat_abi.h"

fn C.fopen(&char, &char) &C.FILE
fn C.fread(voidptr, usize, usize, &C.FILE) usize
fn C.ferror(&C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.fileno(&C.FILE) i32
fn C.fstat(i32, &C.stat) i32
fn C.clearerr(&C.FILE)
fn C.fwrite(voidptr, usize, usize, &C.FILE) usize
fn C.utimensat(i32, &char, &C.timespec, i32) i32
fn C.chflags(&char, u32) i32
fn C.lchflags(&char, u32) i32
fn C.unlink(&char) i32

@[typedef]
struct C.vinix_dota_stat {
	st_mode               u32
	st_atime              i64
	st_mtime              i64
	vinix_dota_atime_nsec i64
	vinix_dota_mtime_nsec i64
	st_flags              u32
}

pub struct FileError {
pub:
	number   int
	filename string
}

pub fn (e FileError) code() int { return e.number }

pub fn (e FileError) msg() string { return os.get_error_msg(e.number) }

fn io_error(path string) IError { return FileError{int(C.errno), path} }

fn inspect(path string, link bool) !os.Stat {
	if path.contains('\x00') { return error('embedded null byte') }
	return if link {
		os.lstat(path) or { return FileError{err.code(), path} }
	} else {
		os.stat(path) or { return FileError{err.code(), path} }
	}
}

// Match pathlib's false result for absent, non-directory and looping paths,
// while retaining other stat errors such as an inaccessible parent.
fn kind(path string, link bool) !int {
	state := inspect(path, link) or {
		if err.code() in [int(C.ENOENT), int(C.ENOTDIR), int(C.EBADF), int(C.ELOOP)] { return -1 }
		return err
	}
	return int(state.mode & u32(C.S_IFMT))
}

pub fn is_file(path string) !bool { return kind(path, false)! == C.S_IFREG }

pub fn is_dir(path string) !bool { return kind(path, false)! == C.S_IFDIR }

pub fn is_link(path string) !bool { return kind(path, true)! == C.S_IFLNK }

pub fn exists(path string) !bool { return kind(path, false)! >= 0 }

pub fn read(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	stream := C.fopen(path.str, c'rb')
	if isnil(stream) { return io_error(path) }
	defer { C.fclose(stream) }
	mut state := C.stat{}
	if C.fstat(C.fileno(stream), &state) != 0 { return io_error('') }
	if state.st_mode & u32(C.S_IFMT) == u32(C.S_IFDIR) { return FileError{int(C.EISDIR), path} }
	mut result := strings.new_builder(8192)
	mut buffer := []u8{len: 8192}
	for {
		count := C.fread(buffer.data, 1, usize(buffer.len), stream)
		number := int(C.errno)
		if count > 0 { result.write(buffer[..int(count)])! }
		if C.ferror(stream) != 0 {
			if number == C.EINTR {
				C.clearerr(stream)
				continue
			}
			return FileError{number, ''}
		}
		if count == 0 { break }
	}
	return result.str()
}

pub fn read_text(path string) !string {
	data := read(path)!
	hosttest.module_decode_utf8(data)!
	return data.replace('\r\n', '\n').replace('\r', '\n')
}

pub fn write(path string, data string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	stream := C.fopen(path.str, c'wb')
	if isnil(stream) { return io_error(path) }
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	if C.fwrite(data.str, 1, usize(data.len), stream) != usize(data.len) { return io_error('') }
	closed = true
	if C.fclose(stream) != 0 { return io_error('') }
}

pub fn mkdir(path string, parents bool, exist_ok bool) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	if unsafe { C.mkdir(path.str, 0o777) } == 0 { return }
	number := int(C.errno)
	if number == C.ENOENT && parents {
		parent := path.trim_right('/').all_before_last('/')
		if parent != '' && parent != path {
			mkdir(parent, true, true)!
			mkdir(path, false, exist_ok)!
			return
		}
	}
	if exist_ok && is_dir(path)! { return }
	return FileError{number, path}
}

pub fn unlink(path string) ! { if C.unlink(path.str) != 0 { return io_error(path) } }

pub struct RenameError {
pub:
	number      int
	source      string
	destination string
}

pub fn (e RenameError) msg() string { return os.get_error_msg(e.number) }

pub fn (e RenameError) code() int { return e.number }

pub fn replace(source string, destination string) ! {
	if C.rename(source.str, destination.str) != 0 {
		return RenameError{int(C.errno), source, destination}
	}
}

pub fn copy2(source string, destination string) ! {
	state := inspect(source, false)!
	if target := os.stat(destination) {
		if state.dev == target.dev && state.inode == target.inode {
			return CopyError{[CopyFailure{source, destination, 'SameFileError'}]}
		}
	}
	hosttest.module_copy_file(source, destination)!
	copy_stat(source, destination, true)!
}

fn copy_stat(source string, destination string, follow bool) ! {
	mut state := C.vinix_dota_stat{}
	result := if follow {
		unsafe { C.stat(source.str, &state) }
	} else {
		unsafe { C.lstat(source.str, &C.stat(&state)) }
	}
	if result != 0 { return io_error(source) }
	times := [C.timespec{state.st_atime, state.vinix_dota_atime_nsec},
		C.timespec{state.st_mtime, state.vinix_dota_mtime_nsec}]!
	if C.utimensat(C.AT_FDCWD, destination.str, &times[0], if follow {
		0
	} else {
		C.AT_SYMLINK_NOFOLLOW
	}) != 0 {
		return io_error(destination)
	}
	$if linux {
		copy_xattrs(source, destination, follow)!
	}
	if follow && C.chmod(destination.str, state.st_mode & 0o7777) != 0 {
		return io_error(destination)
	}
	$if darwin {
		flags_result := if follow {
			C.chflags(destination.str, state.st_flags)
		} else {
			C.lchflags(destination.str, state.st_flags)
		}
		if flags_result != 0 && C.errno != C.ENOTSUP && C.errno != C.EOPNOTSUPP {
			return io_error(destination)
		}
	}
}

pub fn digest(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	stream := C.fopen(path.str, c'rb')
	if isnil(stream) { return io_error(path) }
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	mut state := C.stat{}
	if C.fstat(C.fileno(stream), &state) != 0 { return io_error('') }
	if state.st_mode & u32(C.S_IFMT) == u32(C.S_IFDIR) { return FileError{int(C.EISDIR), path} }
	mut buffer := []u8{len: 1024 * 1024}
	mut hash := sha256.new()
	for {
		count := C.fread(buffer.data, 1, usize(buffer.len), stream)
		number := int(C.errno)
		if count > 0 { hash.write(buffer[..int(count)])! }
		if C.ferror(stream) != 0 {
			if number == C.EINTR {
				C.clearerr(stream)
				continue
			}
			return FileError{number, ''}
		}
		if count == 0 { break }
	}
	closed = true
	if C.fclose(stream) != 0 { return io_error('') }
	return hash.sum([]u8{}).hex()
}

pub fn join(parent string, name string) string {
	if name.starts_with('/') { return name }
	if parent == '' { return name }
	return parent + if parent.ends_with('/') { name } else { '/' + name }
}

pub fn basename(path string) string { return path.trim_right('/').all_after_last('/') }

// pathlib's recursive glob yields directory links without following them.
fn descendants(path string, mut result []string) ! {
	names := os.ls(path) or {
		if err.code() in [int(C.EACCES), int(C.ENOENT), int(C.ENOTDIR)] { return }
		return FileError{err.code(), path}
	}
	for name in names {
		child := join(path, name)
		result << child
		if !is_link(child)! && is_dir(child)! { descendants(child, mut result)! }
	}
}

pub fn paths(path string) ![]string {
	mut result := []string{}
	if !is_dir(path)! { return result }
	descendants(path, mut result)!
	result.sort_with_compare(path_compare)
	return result
}

fn path_compare(a &string, b &string) int {
	left := a.split('/')
	right := b.split('/')
	for index in 0 .. if left.len < right.len { left.len } else { right.len } {
		if left[index] < right[index] { return -1 }
		if left[index] > right[index] { return 1 }
	}
	return if left.len < right.len {
		-1
	} else if left.len > right.len {
		1
	} else {
		0
	}
}

pub fn tree_digest(path string) !string {
	mut hash := sha256.new()
	for entry in paths(path)! {
		if is_file(entry)! || is_link(entry)! {
			hash.write(entry[path.trim_right('/').len + 1..].bytes())!
			hash.write([u8(0)])!
			hash.write((if is_link(entry)! { os.readlink(entry)! } else { digest(entry)! }).bytes())!
			hash.write([u8(0)])!
		}
	}
	return hash.sum([]u8{}).hex()
}

pub fn tool(name string, environment map[string]string) !string {
	value := cachekey.which(name, environment)!
	if value == '' { return failed('missing build tool: ' + name) }
	return value
}

pub fn shell_quote(value string) string {
	if value == '' { return "''" }
	if value.bytes().all(it.is_alnum() || it in [`_`, `@`, `%`, `+`, `=`, `:`, `,`, `.`, `/`, `-`]) {
		return value
	}
	return "'" + value.replace("'", '\'"\'"\'') + "'"
}

pub fn wrapper(path string, contents string) ! {
	write(path, '#!/bin/sh\n' + contents + '\n')!
	os.chmod(path, 0o755)!
}

pub fn copy_file(source string, destination string) ! {
	hosttest.module_copy_file(source, destination)!
}

pub fn resolve(path string) !string { return hosttest.module_resolve(path)! }

pub fn remove_tree(path string) ! { hosttest.remove_work_dir(path)! }

pub fn separate(work string, source string) bool {
	return work != source && !work.starts_with(source.trim_right('/') + '/') && !source.starts_with(work.trim_right('/') + '/')
}
