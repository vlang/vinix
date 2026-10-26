// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only APFS extent samples. Shared samples do not establish total recovery.
module main

import crypto.sha256
import json2
import os
import time

#include <fcntl.h>
struct C.log2phys {
mut:
	l2p_flags u32
	l2p_contigbytes i64
	l2p_devoffset i64
}
fn C.fcntl(int, int, ...voidptr) int

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len >= 3, 'apfs-extent-sample NEW_RECEIPT FILE...'
	output := os.args[1]
	assert !os.exists(output) && !os.is_link(output)
	mut records := []json2.Any{}
	for path in os.args[2..] {
		assert os.is_file(path) && !os.is_link(path), 'ordinary file required: ' + path
		mut file := os.open(path)!
		size := i64(os.file_size(path))
		mut samples := []json2.Any{}
		for offset in [i64(0), size / 4, size / 2, size * 3 / 4] {
			mut mapping := C.log2phys{l2p_contigbytes: size - offset, l2p_devoffset: offset}
			result := C.fcntl(file.fd, C.F_LOG2PHYS_EXT, unsafe { &mapping })
			samples << json2.Any({
				'logical_offset': json2.Any(offset)
				'fcntl_result': json2.Any(result)
				'errno': json2.Any(if result == 0 { 0 } else { C.errno })
				'contiguous_bytes': json2.Any(mapping.l2p_contigbytes)
				'device_offset': json2.Any(mapping.l2p_devoffset)
			})
		}
		file.close()
		records << json2.Any({'path': json2.Any(path), 'size': json2.Any(size), 'samples': json2.Any(samples)})
	}
	result := {
		'completed_utc': json2.Any(time.utc().str())
		'source_sha256': json2.Any(sha256.sum(os.read_bytes(os.real_path(@FILE))!).hex())
		'binary_sha256': json2.Any(sha256.sum(os.read_bytes(os.executable())!).hex())
		'records': json2.Any(records)
		'qualification': json2.Any('Read-only samples. Equal device offsets show sharing at sampled ranges. Different offsets do not prove unique allocation or total physical recovery. No deletion authorized by these samples.')
	}
	os.write_file(output, json2.encode(result, prettify: true) + '\n')!
	println('APFS-EXTENT-SAMPLE files=' + records.len.str() + ' receipt=' + output)
}
