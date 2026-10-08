// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import crypto.sha256
import math.big
import os
import strconv

#include "@DIR/stat_abi.h"
#include <errno.h>

@[typedef]
struct C.vinix_cache_stat {
	st_dev                 u64
	st_ino                 u64
	st_mode                u32
	st_size                i64
	st_atime               i64
	st_mtime               i64
	st_ctime               i64
	vinix_cache_atime_nsec i64
	vinix_cache_mtime_nsec i64
	vinix_cache_ctime_nsec i64
}

fn C.vinix_cache_lstat(&char, &C.vinix_cache_stat) i32
fn C.vinix_cache_fstat(i32, &C.vinix_cache_stat) i32
fn C.vinix_cache_stat_path(&char, &C.vinix_cache_stat) i32

pub struct FileError {
pub:
	number   int
	filename string
}

pub fn (e FileError) code() int { return e.number }

pub fn (e FileError) msg() string { return os.get_error_msg(e.number) }

fn file_error(path string) IError { return FileError{int(C.errno), path} }

fn path_is_file(path string) !bool {
	if path.contains('\x00') { return false }
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_stat_path(&char(path.str), &state) != 0 {
		if C.errno in [C.ENOENT, C.ENOTDIR, C.EBADF, C.ELOOP] { return false }
		return file_error(path)
	}
	return state.st_mode & u32(C.S_IFMT) == u32(C.S_IFREG)
}

pub fn add_field(mut digest sha256.Digest, value string) {
	length := u64(value.len)
	mut frame := [8]u8{}
	for index in 0 .. 8 { frame[index] = u8(length >> (56 - index * 8)) }
	digest.write(frame[..]) or { panic(err) }
	digest.write(value.bytes()) or { panic(err) }
}

fn nanoseconds(seconds i64, fraction i64) string {
	return (big.integer_from_i64(seconds) * big.integer_from_int(1000000000) + big.integer_from_i64(fraction)).str()
}

fn generation(mut digest sha256.Digest, state C.vinix_cache_stat) {
	for value in [state.st_dev.str(), state.st_ino.str(), state.st_size.str(),
		nanoseconds(state.st_mtime, state.vinix_cache_mtime_nsec),
		nanoseconds(state.st_ctime, state.vinix_cache_ctime_nsec)] {
		add_field(mut digest, value)
	}
}

fn file_contents(mut digest sha256.Digest, path string) ! {
	mut stream := os.open(path) or { return file_error(path) }
	defer { stream.close() }
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_fstat(i32(stream.fd), &state) != 0 { return file_error('') }
	if state.st_mode & u32(C.S_IFMT) == u32(C.S_IFDIR) { return FileError{int(C.EISDIR), path} }
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := stream.read(mut buffer) or {
			if err is os.Eof { break }
			return file_error('')
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
}

// Root locations never enter the framing. Byte sorting matches os.fsencode,
// including filesystem names that are not valid UTF-8.
pub fn hash_path(mut digest sha256.Digest, path string, label string, metadata_only bool) ! {
	add_field(mut digest, label)
	if path.contains('\x00') { return error('embedded null byte') }
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_lstat(&char(path.str), &state) != 0 {
		if C.errno == C.ENOENT {
			add_field(mut digest, 'missing')
			return
		}
		return file_error(path)
	}
	mode := state.st_mode & 0o7777
	add_field(mut digest, '0o' + strconv.format_uint(u64(mode), 8))
	if metadata_only { generation(mut digest, state) }
	kind := state.st_mode & u32(C.S_IFMT)
	if kind == u32(C.S_IFLNK) {
		add_field(mut digest, 'symlink')
		add_field(mut digest, os.readlink(path) or { return file_error(path) })
	} else if kind == u32(C.S_IFREG) {
		add_field(mut digest, 'file')
		add_field(mut digest, state.st_size.str())
		if !metadata_only { file_contents(mut digest, path)! }
	} else if kind == u32(C.S_IFDIR) {
		add_field(mut digest, 'directory')
		mut names := os.ls(path) or { return file_error(path) }
		names.sort()
		for name in names {
			hash_path(mut digest, join_path(path, name), label + '/' + name, metadata_only)!
		}
	} else {
		add_field(mut digest, 'special')
		add_field(mut digest, kind.str())
	}
}

pub fn tree_key(paths []string, metadata_only bool, namespace string) !string {
	mut digest := sha256.new()
	add_field(mut digest, namespace)
	for index, path in paths { hash_path(mut digest, path, 'root-' + index.str(), metadata_only)! }
	return digest.sum([]u8{}).hex()
}

pub fn content_key(paths []string, metadata_only bool) !string {
	return tree_key(paths, metadata_only, if metadata_only {
		'vinix-metadata-key-v1'
	} else {
		'vinix-content-key-v1'
	})
}

pub fn root_generation(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	mut digest := sha256.new()
	add_field(mut digest, 'vinix-root-generation-v1')
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_lstat(&char(path.str), &state) != 0 {
		if C.errno != C.ENOENT { return file_error(path) }
		add_field(mut digest, 'missing')
		return digest.sum([]u8{}).hex()
	}
	generation(mut digest, state)
	if state.st_mode & u32(C.S_IFMT) == u32(C.S_IFLNK) {
		add_field(mut digest, os.readlink(path) or { return file_error(path) })
	}
	return digest.sum([]u8{}).hex()
}
