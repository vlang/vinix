// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only APFS analysis: PRIVATESIZE counts bytes freed immediately on deletion.
module main

import encoding.binary
import os

#include <sys/attr.h>
#include <unistd.h>

struct C.attrlist {
mut:
	bitmapcount u16
	reserved u16
	commonattr u32
	volattr u32
	dirattr u32
	fileattr u32
	forkattr u32
}
fn C.getattrlist(&char, voidptr, voidptr, usize, u32) i32

fn private_size(path string) !u64 {
	mut attrs := C.attrlist{bitmapcount: 5, forkattr: 0x00000008}
	mut buffer := [16]u8{}
	// FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW; only ATTR_CMNEXT_PRIVATESIZE requested.
	if C.getattrlist(&char(path.str), unsafe { &attrs }, unsafe { &buffer[0] }, usize(buffer.len), 0x00000021) != 0 {
		return error('getattrlist private size failed: ' + path)
	}
	if binary.little_endian_u32(buffer[..4]) != 12 { return error('unexpected getattrlist buffer length') }
	return binary.little_endian_u64(buffer[4..12])
}

struct Totals {
mut:
	bytes u64
	files int
}

fn collect(path string, mut totals Totals) ! {
	match os.lstat(path)!.get_filetype() {
		.directory { for name in os.ls(path)! { collect(path + '/' + name, mut totals)! } }
		.regular {
			bytes := private_size(path)!
			totals.bytes += bytes
			totals.files++
			if bytes >= 16 * 1024 * 1024 { println('APFS-PRIVATE bytes=${bytes} path=${path}') }
		}
		else {}
	}
}

fn main() {
	assert os.args.len >= 2, 'usage: apfs-private-size PATH...'
	for path in os.args[1..] {
		mut totals := Totals{}
		collect(path, mut totals)!
		println('APFS-PRIVATE-TOTAL bytes=${totals.bytes} files=${totals.files} path=${path}')
	}
}
