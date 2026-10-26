// SPDX-License-Identifier: GPL-2.0-or-later
module accountmanifest

import hash.crc32
import os

// Reuse the system inflater used by androidhost/probe_zip.v. ZIP policy and
// allocation limits remain in V; no entry is inflated during directory scans.
#flag -lz
#include <zlib.h>

@[typedef]
struct C.z_stream {
mut:
	next_in   &u8
	avail_in  u32
	next_out  &u8
	avail_out u32
	total_out u64
}

fn C.zlibVersion() &char
fn C.inflateInit2_(&C.z_stream, i32, &char, i32) i32
fn C.inflate(&C.z_stream, i32) i32
fn C.inflateEnd(&C.z_stream) i32

struct AuthZipEntry {
	flags      u16
	method     u16
	checksum   u32
	compressed u32
	size       u32
	offset     u32
}

fn auth_zip_read(mut file os.File, at u64, mut bytes []u8) ! {
	file.seek(i64(at), .start)!
	mut count := 0
	for count < bytes.len {
		n := file.read_into_ptr(unsafe { &bytes[count] }, bytes.len - count)!
		if n <= 0 { return error('truncated authenticator ZIP input') }
		count += n
	}
}

fn auth_zip_name(bytes []u8, name string) bool {
	if bytes.len != name.len { return false }
	for i in 0 .. bytes.len { if bytes[i] != name[i] { return false } }
	return true
}

fn auth_zip_inflate(input []u8, size int) ![]u8 {
	mut stream := C.z_stream{}
	if C.inflateInit2_(&stream, -15, C.zlibVersion(), i32(sizeof(C.z_stream))) != 0 {
		return error('cannot initialize authenticator ZIP inflater')
	}
	defer { C.inflateEnd(&stream) }
	// One extra byte detects an understated size without growing the output.
	mut output := []u8{len: size + 1}
	mut accepted := false
	defer { if !accepted { unsafe { output.free() } } }
	stream.next_in = input.data
	stream.avail_in = u32(input.len)
	stream.next_out = output.data
	stream.avail_out = u32(output.len)
	if C.inflate(&stream, 4) != 1 || stream.total_out != u64(size) || stream.avail_in != 0 {
		return error('invalid bounded authenticator ZIP deflate stream')
	}
	output.trim(size)
	accepted = true
	return output
}

// Read one unique, bounded APK member. The opened file and all returned bytes
// belong to the caller. Scan the complete directory before accepting a match;
// duplicate names, malformed suffixes and local/central disagreement fail closed.
fn read_authenticator_zip_entry(mut file os.File, name string, limit u64) ![]u8 {
	if name == '' || name.len > 4096 || limit < 8 || limit > 128 * 1024 * 1024 {
		return error('invalid authenticator ZIP selection')
	}
	file.seek(0, .end)!
	length := file.tell()!
	if length < 22 || length > 1024 * 1024 * 1024 { return error('invalid authenticator APK size') }
	tail_size := if length > 65557 { 65557 } else { int(length) }
	mut tail := []u8{len: tail_size}
	defer { unsafe { tail.free() } }
	auth_zip_read(mut file, u64(length - tail_size), mut tail)!
	mut end := tail.len - 22
	for end >= 0 {
		if le32(tail, end) == 0x06054b50 && end + 22 + int(le16(tail, end + 20)) == tail.len { break }
		end--
	}
	if end < 0 || le16(tail, end + 4) != 0 || le16(tail, end + 6) != 0 {
		return error('missing or split authenticator ZIP end record')
	}
	count := le16(tail, end + 10)
	central_size, central_start := le32(tail, end + 12), le32(tail, end + 16)
	central_end := u64(length - tail_size + end)
	if count == 0xffff || le16(tail, end + 8) != count || central_size == 0xffffffff
		|| central_start == 0xffffffff || u64(central_start) + central_size != central_end {
		return error('invalid authenticator ZIP directory bounds')
	}
	mut header := []u8{len: 46}
	mut member_name := []u8{len: name.len}
	defer { unsafe { header.free(); member_name.free() } }
	mut selected := AuthZipEntry{}
	mut seen := false
	mut cursor := u64(central_start)
	for _ in 0 .. int(count) {
		if cursor > central_end || central_end - cursor < 46 { return error('truncated authenticator ZIP directory') }
		auth_zip_read(mut file, cursor, mut header)!
		if le32(header, 0) != 0x02014b50 { return error('invalid authenticator ZIP directory entry') }
		name_size := int(le16(header, 28))
		record_size := u64(46 + name_size + int(le16(header, 30)) + int(le16(header, 32)))
		if name_size == 0 || record_size > central_end - cursor || le16(header, 34) != 0
			|| le32(header, 20) == 0xffffffff || le32(header, 24) == 0xffffffff || le32(header, 42) == 0xffffffff {
			return error('invalid authenticator ZIP directory metadata')
		}
		if name_size == name.len {
			auth_zip_read(mut file, cursor + 46, mut member_name)!
			if auth_zip_name(member_name, name) {
				if seen { return error('duplicate authenticator ZIP entry') }
				selected = AuthZipEntry{le16(header, 8), le16(header, 10), le32(header, 16),
					le32(header, 20), le32(header, 24), le32(header, 42)}
				if selected.size < 8 || u64(selected.size) > limit || u64(selected.compressed) > limit
					|| selected.flags & ~u16(0x080e) != 0 || selected.method !in [u16(0), 8]
					|| (selected.method == 0 && selected.size != selected.compressed) {
					return error('unsupported or oversized authenticator ZIP entry')
				}
				seen = true
			}
		}
		cursor += record_size
	}
	if cursor != central_end || !seen { return error('authenticator ZIP member is absent or directory is malformed') }
	if u64(selected.offset) > u64(central_start) || u64(central_start) - selected.offset < 30 {
		return error('invalid authenticator ZIP local header offset')
	}
	mut local := []u8{len: 30}
	defer { unsafe { local.free() } }
	auth_zip_read(mut file, selected.offset, mut local)!
	if le32(local, 0) != 0x04034b50 || le16(local, 6) != selected.flags || le16(local, 8) != selected.method
		|| int(le16(local, 26)) != name.len {
		return error('inconsistent authenticator ZIP local header')
	}
	start := u64(selected.offset) + 30 + u64(le16(local, 26)) + u64(le16(local, 28))
	if start > central_start || u64(selected.compressed) > u64(central_start) - start {
		return error('truncated authenticator ZIP member')
	}
	auth_zip_read(mut file, u64(selected.offset) + 30, mut member_name)!
	if !auth_zip_name(member_name, name) { return error('inconsistent authenticator ZIP member name') }
	if selected.flags & 8 == 0 {
		if le32(local, 14) != selected.checksum || le32(local, 18) != selected.compressed || le32(local, 22) != selected.size {
			return error('inconsistent authenticator ZIP member sizes or checksum')
		}
	} else {
		mut descriptor := []u8{len: 12}
		defer { unsafe { descriptor.free() } }
		mut at := start + selected.compressed
		if at > central_start || u64(central_start) - at < 12 { return error('truncated authenticator ZIP descriptor') }
		auth_zip_read(mut file, at, mut descriptor)!
		if le32(descriptor, 0) == 0x08074b50 {
			at += 4
			if u64(central_start) - at < 12 { return error('truncated authenticator ZIP descriptor') }
			auth_zip_read(mut file, at, mut descriptor)!
		}
		if le32(descriptor, 0) != selected.checksum || le32(descriptor, 4) != selected.compressed || le32(descriptor, 8) != selected.size {
			return error('inconsistent authenticator ZIP descriptor')
		}
	}
	mut compressed := []u8{len: int(selected.compressed)}
	defer { unsafe { compressed.free() } }
	auth_zip_read(mut file, start, mut compressed)!
	result := if selected.method == 0 { compressed.clone() } else { auth_zip_inflate(compressed, int(selected.size))! }
	if result.len != int(selected.size) || crc32.sum(result) != selected.checksum {
		unsafe { result.free() }
		return error('authenticator ZIP member checksum mismatch')
	}
	return result
}
