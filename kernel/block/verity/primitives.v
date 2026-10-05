// SPDX-License-Identifier: GPL-2.0-or-later
module verity

import krandom

#include <verity.h>

struct C.vinix_verity {
mut:
	data_blocks u64
	total_blocks u64
	level_start [8]u64
	levels u32
	root_hash [32]u8
}

fn C.memset(dest voidptr, value i32, length usize) voidptr
fn C.memcpy(dest voidptr, src voidptr, length usize) voidptr
fn C.memcmp(first voidptr, second voidptr, length usize) i32

const block_bytes = u64(4096)
const max_image_blocks = u64(0x7fffffffffffffff) / block_bytes

// Headerless dm-verity v1, SHA-256, no salt, one backing device. Borrow every
// buffer and callback; no verification path allocates or exposes data.
@[export: 'vinix_verity_sha256']
fn hash_block(input voidptr, length usize, output &u8) {
	// The C ABI borrows 32 output bytes; pass their address without copying an
	// array value or giving the V compiler an escaping local to allocate.
	krandom.sha256_digest(unsafe { &u8(input) }, u64(length), unsafe { voidptr(output) })
}

fn hex_digit(value char) i32 {
	if value >= char(`0`) && value <= char(`9`) { return i32(value) - i32(`0`) }
	if value >= char(`a`) && value <= char(`f`) { return i32(value) - i32(`a`) + 10 }
	return -1
}

@[export: 'vinix_verity_init']
fn init_geometry(geometry &C.vinix_verity, blocks u64, hex &char, length usize) i32 {
	unsafe { C.memset(geometry, 0, sizeof(C.vinix_verity)) }
	if blocks == 0 || blocks > max_image_blocks || length != 64 { return -1 }
	unsafe {
		for i in 0 .. 32 {
			high := hex_digit(hex[i * 2])
			low := hex_digit(hex[i * 2 + 1])
			if high < 0 || low < 0 { return -1 }
			geometry.root_hash[i] = u8(high * 16 + low)
		}
		geometry.data_blocks = blocks
		mut counts := [8]u64{}
		mut remaining := blocks
		for remaining > 1 {
			remaining = (remaining + 127) / 128
			if geometry.levels == 8 { return -1 }
			counts[geometry.levels] = remaining
			geometry.levels++
		}
		geometry.total_blocks = geometry.data_blocks
		for i := geometry.levels; i > 0; i-- {
			geometry.level_start[i - 1] = geometry.total_blocks
			if counts[i - 1] > max_image_blocks - geometry.total_blocks { return -1 }
			geometry.total_blocks += counts[i - 1]
		}
	}
	return 0
}

fn whitespace(value char) bool {
	return value == char(` `) || value == char(`\t`) || value == char(`\r`) || value == char(`\n`)
}

fn find_text(text &char, needle &char) &char {
	unsafe {
		mut size := usize(0)
		for needle[size] != 0 { size++ }
		mut cursor := text
		for *cursor != 0 {
			mut i := usize(0)
			for i < size && cursor[i] != 0 && cursor[i] == needle[i] { i++ }
			if i == size { return cursor }
			cursor++
		}
		return nil
	}
}

// Fail closed for malformed, duplicate or conflicting root selection. The
// caller's device buffer is written only after the complete policy is valid.
@[export: 'vinix_verity_parse']
fn parse_policy(cmdline &char, geometry &C.vinix_verity, device &char, capacity usize) i32 {
	if usize(cmdline) == 0 { return 0 }
	unsafe {
		mut length := usize(0)
		for length < 4096 && cmdline[length] != 0 { length++ }
		if length == 4096 { return -1 }
		reserved := find_text(cmdline, c'vinix.verity')
		if usize(reserved) == 0 { return 0 }
		if usize(find_text(reserved + 1, c'vinix.verity')) != 0 { return -1 }
		conflicts := [charptr(c'vinix.disk='), charptr(c'vinix.qemu_persist='),
			charptr(c'vinix.qemu_root='), charptr(c'vinix.apple_ans='), charptr(c'vinix.ans_rw='),
			charptr(c'vinix.persist='), charptr(c'vinix.root'), charptr(c'root=')]!
		for needle in conflicts {
			if usize(find_text(cmdline, needle)) != 0 { return -1 }
		}
		mut value := &char(nil)
		mut size := usize(0)
		mut at := usize(0)
		for at < length {
			for at < length && whitespace(cmdline[at]) { at++ }
			start := at
			for at < length && !whitespace(cmdline[at]) { at++ }
			if at - start >= 13 && C.memcmp(cmdline + start, c'vinix.verity=', 13) == 0 {
				if usize(value) != 0 { return -1 }
				value = cmdline + start + 13
				size = at - start - 13
			}
		}
		if usize(value) == 0 || usize(reserved) != usize(value) - 13 || size < 2
			|| value[0] != char(`1`) || value[1] != char(`,`) { return -1 }
		path := value + 2
		end := value + size
		mut comma := path
		for usize(comma) < usize(end) && *comma != char(`,`) { comma++ }
		path_size := usize(comma) - usize(path)
		if usize(comma) == usize(end) || path_size <= 5 || path_size > 68
			|| path_size >= capacity || C.memcmp(path, c'/dev/', 5) != 0 { return -1 }
		for i := usize(5); i < path_size; i++ {
			value_byte := path[i]
			alnum := (value_byte >= char(`a`) && value_byte <= char(`z`))
				|| (value_byte >= char(`A`) && value_byte <= char(`Z`))
				|| (value_byte >= char(`0`) && value_byte <= char(`9`))
			if !alnum && (i == 5 || (value_byte != char(`_`) && value_byte != char(`-`) && value_byte != char(`.`))) {
				return -1
			}
		}
		digits := comma + 1
		if usize(digits) == usize(end) || *digits < char(`1`) || *digits > char(`9`) { return -1 }
		mut blocks := u64(0)
		comma = digits
		for usize(comma) < usize(end) && *comma != char(`,`) {
			if *comma < char(`0`) || *comma > char(`9`) { return -1 }
			digit := u64(u8(*comma)) - u64(`0`)
			if blocks > (~u64(0) - digit) / 10 { return -1 }
			blocks = blocks * 10 + digit
			comma++
		}
		if usize(comma) == usize(end)
			|| init_geometry(geometry, blocks, comma + 1, usize(end) - usize(comma) - 1) != 0 {
			return -1
		}
		C.memcpy(device, path, path_size)
		device[path_size] = 0
	}
	return 1
}

type BlockReader = fn (voidptr, u64, voidptr) i32

@[export: 'vinix_verity_check']
fn check_block(geometry &C.vinix_verity, block u64, data voidptr,
	reader BlockReader, context voidptr, scratch voidptr) i32 {
	if block >= geometry.data_blocks { return -1 }
	mut digest := [32]u8{}
	hash_block(data, usize(block_bytes), unsafe { &digest[0] })
	mut index := block
	unsafe {
		for level := u32(0); level < geometry.levels; level++ {
			position := geometry.level_start[level] + index / 128
			if position >= geometry.total_blocks || reader(context, position, scratch) != 0 {
				return -1
			}
			if C.memcmp(&digest[0], voidptr(usize(scratch) + usize(index % 128) * 32), 32) != 0 {
				return -1
			}
			hash_block(scratch, usize(block_bytes), &digest[0])
			index /= 128
		}
		return if C.memcmp(&digest[0], &geometry.root_hash[0], 32) == 0 { 0 } else { -1 }
	}
}
