// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only scan: report aligned zero ranges without punching or rewriting files.
module main

import crypto.sha256
import json2
import os
import time

#include <fcntl.h>
#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
struct C.log2phys {
mut:
	l2p_flags u32
	l2p_contigbytes i64
	l2p_devoffset i64
}
fn C.fcntl(int, int, ...voidptr) int

struct ZeroRange {
	offset i64
	length i64
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 3, 'zero-range-scan FILE NEW_RECEIPT'
	path := os.real_path(os.args[1])
	output := os.args[2]
	assert os.is_file(path) && !os.is_link(os.args[1])
	assert !os.exists(output) && !os.is_link(output)
	before := os.lstat(path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	zero := []u8{len: 65536}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	mut ranges := []ZeroRange{}
	mut offset := i64(0)
	mut zero_start := i64(-1)
	mut zero_length := i64(0)
	mut zero_bytes := i64(0)
	started := time.utc().str()
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			panic(err)
		}
		if n == 0 { break }
		assert n == buffer.len || offset + i64(n) == i64(before.size), 'short non-final read'
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
		for position := 0; position + 65536 <= n; position += 65536 {
			is_zero := unsafe { C.memcmp(&buffer[position], zero.data, 65536) == 0 }
			if is_zero && (offset + i64(position)) % 65536 == 0 {
				if zero_start < 0 { zero_start = offset + i64(position) }
				zero_length += 65536
				zero_bytes += 65536
			} else if zero_start >= 0 {
				ranges << ZeroRange{zero_start, zero_length}
				zero_start = -1
				zero_length = 0
			}
		}
		if n % 65536 != 0 && zero_start >= 0 {
			ranges << ZeroRange{zero_start, zero_length}
			zero_start = -1
			zero_length = 0
		}
		offset += i64(n)
	}
	if zero_start >= 0 { ranges << ZeroRange{zero_start, zero_length} }
	mut hashed := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &hashed[0] }, unsafe { &digest }) == 1
	after := os.lstat(path)!
	assert before.size == after.size && before.mode == after.mode && before.mtime == after.mtime
	assert offset == i64(before.size)
	mut records := []json2.Any{}
	for item in ranges {
		mut mapping := C.log2phys{l2p_contigbytes: item.length, l2p_devoffset: item.offset}
		result := C.fcntl(file.fd, C.F_LOG2PHYS_EXT, unsafe { &mapping })
		records << json2.Any({
			'offset': json2.Any(item.offset)
			'zero_bytes': json2.Any(item.length)
			'first_extent_bytes': json2.Any(mapping.l2p_contigbytes)
			'first_device_offset': json2.Any(mapping.l2p_devoffset)
			'fcntl_result': json2.Any(result)
			'errno': json2.Any(if result == 0 { 0 } else { C.errno })
		})
	}
	receipt := {
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'path': json2.Any(path)
		'file_bytes': json2.Any(offset)
		'file_mode': json2.Any(before.mode & 0o7777)
		'file_sha256': json2.Any(hashed[..].hex())
		'alignment_bytes': json2.Any(65536)
		'zero_bytes': json2.Any(zero_bytes)
		'zero_ranges': json2.Any(records)
		'source_sha256': json2.Any(sha256.sum(os.read_bytes(os.real_path(@FILE))!).hex())
		'binary_sha256': json2.Any(sha256.sum(os.read_bytes(os.executable())!).hex())
		'qualification': json2.Any('Read-only scan. Zero bytes may already be holes or clone shared. First physical extent samples do not establish total allocation or unique recovery. No files changed and no hole punching authorized by this receipt.')
	}
	os.write_file(output, json2.encode(receipt, prettify: true) + '\n')!
	println('ZERO-RANGE-SCAN zero_bytes=' + zero_bytes.str() + ' ranges=' + ranges.len.str() + ' receipt=' + output)
}
