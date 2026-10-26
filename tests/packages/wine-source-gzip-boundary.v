// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only diagnosis of the exact preserved, refused Wine archive stream.
module main

import crypto.sha256
import dl
import json2
import os
import time

type Version = fn () &char
type Initialize = fn (voidptr, i32, &char, i32) i32
type Inflate = fn (voidptr, i32) i32
type Finish = fn (voidptr) i32

// z_stream ABI, matching the unchanged strict reader's LP64 declarations.
struct Stream {
mut:
	next_in   voidptr
	avail_in  u32
	total_in  usize
	next_out  voidptr
	avail_out u32
	total_out usize
	message   voidptr
	state     voidptr
	allocate  voidptr
	release   voidptr
	opaque    voidptr
	data_type i32
	adler     usize
	reserved  usize
}

const archive = '/Users/alex/Library/Caches/vinix-codex/section14/wine-source-2026-10-26.tar.gz'
const expected = '3bb708ac3497c871afde2446bd3b1390908009c5cc34991f5fcba917e618c609'

struct Result {
	format             int
	archive            string
	archive_sha256     string
	compressed_bytes   u64
	gzip_member_end    u64
	decoded_bytes      u64
	trailing_bytes     u64
	trailing_all_zero  bool
	zlib_status        i32
	zlib_version       string
	trailer_hex        string
	source_sha256      string
	executable_sha256  string
	identity_unchanged bool
	elapsed_ms         u64
	scope              string
}

fn hash(path string, deadline u64) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		if time.sys_mono_now() >= deadline {
			return error('read-only diagnostic deadline exceeded')
		}
		n := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		digest.write(bytes[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn diagnose() !Result {
	started := time.sys_mono_now()
	deadline := started + u64(120 * time.second)
	before := os.lstat(archive)!
	if before.get_filetype() != .regular || before.size != 986275840 {
		return error('requires exact ordinary failed archive')
	}
	before_hash := hash(archive, deadline)!
	if before_hash != expected { return error('failed archive hash differs') }
	handle := dl.open('/usr/lib/libz.1.dylib', dl.rtld_now | dl.rtld_local)
	if handle == unsafe { nil } { return error('cannot load zlib') }
	defer { dl.close(handle) }
	for symbol in ['zlibVersion', 'inflateInit2_', 'inflate', 'inflateEnd'] {
		if dl.sym(handle, symbol) == unsafe { nil } { return error('missing zlib symbol') }
	}
	version := unsafe { Version(dl.sym(handle, 'zlibVersion')) }
	initialize := unsafe { Initialize(dl.sym(handle, 'inflateInit2_')) }
	inflate := unsafe { Inflate(dl.sym(handle, 'inflate')) }
	finish := unsafe { Finish(dl.sym(handle, 'inflateEnd')) }
	mut stream := Stream{}
	if initialize(&stream, 31, version(), i32(sizeof(Stream))) != 0 {
		return error('zlib initialization failed')
	}
	defer { finish(&stream) }
	mut input := os.open(archive)!
	defer { input.close() }
	mut compressed := []u8{len: 1024 * 1024}
	mut output := []u8{len: 1024 * 1024}
	mut read_bytes := u64(0)
	mut member_end := u64(0)
	mut decoded := u64(0)
	mut status := i32(0)
	mut trailing := u64(0)
	mut all_zero := true
	for {
		if time.sys_mono_now() >= deadline {
			return error('read-only diagnostic deadline exceeded')
		}
		n := input.read(mut compressed) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		read_bytes += u64(n)
		if member_end != 0 {
			trailing += u64(n)
			all_zero = all_zero && compressed[..n].all(it == 0)
			continue
		}
		stream.next_in = compressed.data
		stream.avail_in = u32(n)
		for {
			before_in := stream.avail_in
			stream.next_out = output.data
			stream.avail_out = u32(output.len)
			status = inflate(&stream, 0)
			produced := u32(output.len) - stream.avail_out
			decoded += produced
			if status == 1 {
				member_end = read_bytes - stream.avail_in
				trailing = stream.avail_in
				all_zero = compressed[n - int(stream.avail_in)..n].all(it == 0)
				break
			}
			if status == -5 && stream.avail_in == 0 && produced == 0 { break }
			if status != 0 { return error('gzip member refused: ${status}') }
			if before_in == stream.avail_in && produced == 0 {
				return error('gzip decoder made no progress')
			}
			if stream.avail_in == 0 && stream.avail_out != 0 { break }
		}
	}
	if member_end < 8 || status != 1 || read_bytes != u64(before.size)
		|| member_end + trailing != read_bytes {
		return error('incomplete gzip member or byte accounting differs')
	}
	input.seek(i64(member_end - 8), .start)!
	mut trailer := []u8{len: 8}
	if input.read(mut trailer)! != 8 { return error('gzip trailer read differs') }
	after := os.lstat(archive)!
	if after.dev != before.dev || after.inode != before.inode || after.mode != before.mode
		|| after.nlink != before.nlink || after.uid != before.uid || after.gid != before.gid
		|| after.rdev != before.rdev || after.size != before.size || after.mtime != before.mtime
		|| after.ctime != before.ctime || hash(archive, deadline)! != before_hash {
		return error('failed archive changed during read-only diagnosis')
	}
	return Result{1, archive, before_hash, read_bytes, member_end, decoded, trailing, all_zero, status, unsafe { cstring_to_vstring(version()) }, trailer.hex(), hash(@FILE, deadline)!, hash(os.executable(), deadline)!, true, (time.sys_mono_now() - started) / u64(time.millisecond), 'Read-only zlib first-member CRC32/length validation and exact trailing-byte inventory. No tar payload qualification, archive mutation, reader relaxation or deletion.'}
}

fn main() {
	if os.args != [os.args[0], '--check-reviewed'] {
		eprintln('requires --check-reviewed')
		exit(1)
	}
	result := diagnose() or {
		eprintln(err)
		exit(1)
	}
	println(json2.encode(result))
}
