// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed-extent diagnostic overlay. This does not qualify signed packages.
module wineoverlay

import crypto.sha256
import os

pub struct Span {
pub:
	offset u64
	size u64
}

pub fn digest(path string) !string { return range_digest(path, 0, os.file_size(path)) }

pub fn range_digest(path string, offset u64, size u64) !string {
	mut file := os.open(path)!
	defer { file.close() }
	if offset > os.file_size(path) || size > os.file_size(path) - offset { return error('digest range exceeds file') }
	file.seek(i64(offset), .start)!
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: 32}
	defer { unsafe { buffer.free(); sum.free(); hash.free(); free(hash) } }
	mut remaining := size
	for remaining > 0 {
		count := int(if remaining < u64(buffer.len) { remaining } else { u64(buffer.len) })
		n := file.read(mut buffer[..count])!
		if n != count { return error('short digest read') }
		hash.write(buffer[..n])!
		remaining -= u64(n)
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn octal(bytes []u8) !u64 {
	mut value := u64(0)
	mut started := false
	mut ended := false
	for byte in bytes {
		if byte == 0 || byte == ` ` { if started { ended = true }; continue }
		if ended || byte < `0` || byte > `7` || value > (~u64(0) - u64(byte - `0`)) / 8 { return error('invalid USTAR number') }
		started = true
		value = value * 8 + u64(byte - `0`)
	}
	return value
}

fn zero(bytes []u8) bool {
	for byte in bytes { if byte != 0 { return false } }
	return true
}

fn matches(bytes []u8, start int, text string) bool {
	for index, byte in text { if bytes[start + index] != byte { return false } }
	return true
}

// Locate exactly one ordinary ./sbin/init in a bounded plain USTAR extent.
// Header checksums and the complete trailing zero region are checked. Extended
// name records are refused, so they cannot redirect the fixed member name.
pub fn init_span(path string, tar Span) !Span {
	length := os.file_size(path)
	if tar.offset > length || tar.size > length - tar.offset || tar.size < 1024 || tar.size % 512 != 0 {
		return error('invalid USTAR extent')
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 512}
	defer { unsafe { header.free() } }
	mut position := u64(0)
	mut found := Span{}
	mut count := 0
	mut zero_blocks := 0
	for position < tar.size {
		file.seek(i64(tar.offset + position), .start)!
		if file.read(mut header)! != 512 { return error('short USTAR header') }
		position += 512
		if zero(header) { zero_blocks++; continue }
		if zero_blocks != 0 { return error('USTAR data after end marker') }
		count++
		if count > 100000 { return error('USTAR member bound exceeded') }
		mut checksum := u64(0)
		for index, byte in header { checksum += if index >= 148 && index < 156 { u64(32) } else { u64(byte) } }
		if octal(header[148..156])! != checksum || !matches(header, 257, 'ustar\x00') { return error('invalid USTAR checksum or magic') }
		if header[156] !in [u8(0), `0`, `1`, `2`, `5`] { return error('unsupported USTAR member type') }
		size := octal(header[124..136])!
		if size > tar.size - position || (size + 511) / 512 * 512 > tar.size - position { return error('USTAR member exceeds extent') }
		if matches(header, 0, './sbin/init') && header[11] == 0 && zero(header[345..500]) {
			if found.size != 0 || size == 0 || header[156] !in [u8(0), `0`] { return error('init must be one nonempty ordinary USTAR member') }
			found = Span{tar.offset + position, size}
		}
		position += (size + 511) / 512 * 512
	}
	if found.size == 0 || zero_blocks < 2 { return error('USTAR init or end marker missing') }
	return found
}

// Target must be a fresh independent clone. The old member's declared size is
// preserved; a smaller ELF is followed by zeros. No TAR/ISO headers are changed.
pub fn patch_init(original string, target string, guest string, tar Span, expected_old string) !Span {
	source_info := os.lstat(original)!
	target_info := os.lstat(target)!
	guest_info := os.lstat(guest)!
	if source_info.get_filetype() != .regular || target_info.get_filetype() != .regular || guest_info.get_filetype() != .regular
		|| target_info.nlink != 1 || (source_info.dev == target_info.dev && source_info.inode == target_info.inode)
		|| source_info.size != target_info.size { return error('overlay requires independent ordinary files') }
	span := init_span(original, tar)!
	if guest_info.size == 0 || guest_info.size > span.size { return error('diagnostic guest exceeds original init slot') }
	if range_digest(original, span.offset, span.size)! != expected_old { return error('original init digest differs') }
	mut input := os.open(guest)!
	defer { input.close() }
	mut output := os.open_file(target, 'r+')!
	defer { output.close() }
	output.seek(i64(span.offset), .start)!
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	mut remaining := span.size
	mut guest_left := guest_info.size
	for remaining > 0 {
		n := int(if remaining < u64(buffer.len) { remaining } else { u64(buffer.len) })
		for index in 0 .. n { buffer[index] = 0 }
		read_count := int(if guest_left < u64(n) { guest_left } else { u64(n) })
		if read_count > 0 && input.read(mut buffer[..read_count])! != read_count { return error('short overlay guest read') }
		if output.write(buffer[..n])! != n { return error('short overlay write') }
		guest_left -= u64(read_count); remaining -= u64(n)
	}
	output.close()
	verify_delta(original, target, guest, span)!
	return span
}

// Full logical-byte comparison, including compressed/sparse files: no byte
// outside the declared member may change; its payload is guest plus zero tail.
pub fn verify_delta(original string, target string, guest string, span Span) ! {
	length := os.file_size(original)
	guest_size := os.file_size(guest)
	if os.file_size(target) != length || span.offset > length || span.size > length - span.offset || guest_size > span.size {
		return error('overlay comparison bounds differ')
	}
	mut a := os.open(original)!; defer { a.close() }
	mut b := os.open(target)!; defer { b.close() }
	mut g := os.open(guest)!; defer { g.close() }
	mut before := []u8{len: 65536}; mut after := []u8{len: 65536}; mut payload := []u8{len: 65536}
	defer { unsafe { before.free(); after.free(); payload.free() } }
	mut position := u64(0)
	for position < length {
		n := int(if length - position < u64(before.len) { length - position } else { u64(before.len) })
		if a.read(mut before[..n])! != n || b.read(mut after[..n])! != n { return error('short overlay comparison read') }
		for index in 0 .. n {
			absolute := position + u64(index)
			if absolute < span.offset || absolute >= span.offset + span.size {
				if before[index] != after[index] { return error('overlay changed bytes outside init') }
			} else if absolute >= span.offset + guest_size && after[index] != 0 { return error('overlay init tail is not zero') }
		}
		position += u64(n)
	}
	// Compare the meaningful guest prefix separately, with bounded buffers.
	b.seek(i64(span.offset), .start)!
	mut left := guest_size
	for left > 0 {
		n := int(if left < u64(after.len) { left } else { u64(after.len) })
		if b.read(mut after[..n])! != n || g.read(mut payload[..n])! != n || after[..n] != payload[..n] { return error('overlay guest payload differs') }
		left -= u64(n)
	}
}
