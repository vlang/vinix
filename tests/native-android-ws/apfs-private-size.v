// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only APFS analysis: PRIVATESIZE counts bytes freed immediately on deletion.
// A set may additionally own extents shared only within that set; this is a lower
// bound at query time, not permission to remove an evidence bundle.
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

fn stable(before os.Stat, after os.Stat) ! {
	if before.dev != after.dev || before.inode != after.inode || before.mode != after.mode
		|| before.nlink != after.nlink || before.uid != after.uid || before.gid != after.gid
		|| before.size != after.size || before.mtime != after.mtime || before.ctime != after.ctime {
		return error('file metadata changed during measurement')
	}
}

fn private_size(path string, before os.Stat) !u64 {
	if before.nlink != 1 { return error('multiple hard links: ' + path) }
	mut attrs := C.attrlist{
		bitmapcount: 5
		commonattr: 0x80000000 // ATTR_CMN_RETURNED_ATTRS
		fileattr: 0x00000200 // ATTR_FILE_DATALENGTH; checks the returned layout against lstat.
		forkattr: 0x00000008 // ATTR_CMNEXT_PRIVATESIZE
	}
	mut buffer := [40]u8{}
	// PACK_INVAL_ATTRS | ATTR_CMN_EXTENDED | NOFOLLOW_ANY | UNIQUE.
	// The latter rejects a concurrent change to a multiply hard-linked target.
	if C.getattrlist(&char(path.str), unsafe { &attrs }, unsafe { &buffer[0] }, usize(buffer.len), 0x00002828) != 0 {
		return error('getattrlist private size failed: ' + path)
	}
	// getattrlist packs attributes at four-byte alignment. Both macOS hosts are LE.
	if binary.little_endian_u32(buffer[..4]) != buffer.len
		|| binary.little_endian_u32(buffer[4..8]) != 0x80000000
		|| binary.little_endian_u32(buffer[8..12]) != 0
		|| binary.little_endian_u32(buffer[12..16]) != 0
		|| binary.little_endian_u32(buffer[16..20]) != 0x00000200
		|| binary.little_endian_u32(buffer[20..24]) != 0x00000008 {
		return error('omitted, unsupported or unexpected getattrlist attributes: ' + path)
	}
	if binary.little_endian_u64(buffer[24..32]) != before.size {
		return error('getattrlist data length differs from lstat: ' + path)
	}
	bytes := binary.little_endian_u64(buffer[32..40])
	if bytes > u64(0x7fffffffffffffff) { return error('negative private size: ' + path) }
	stable(before, os.lstat(path)!)!
	return bytes
}

struct Totals {
mut:
	bytes u64
	logical_bytes u64
	files int
	directories int
	symlinks int
	details []string
}

fn collect(path string, mut totals Totals) ! {
	before := os.lstat(path)!
	match before.get_filetype() {
		.directory {
			totals.directories++
			for name in os.ls(path)!.sorted() { collect(path + '/' + name, mut totals)! }
			stable(before, os.lstat(path)!)!
		}
		.regular {
			bytes := private_size(path, before)!
			totals.bytes += bytes
			totals.logical_bytes += before.size
			totals.files++
			if bytes >= 16 * 1024 * 1024 { totals.details << 'APFS-PRIVATE bytes=${bytes} path=${path}' }
		}
		.symbolic_link { totals.symlinks++ }
		else { return error('unexpected artifact type: ' + path) }
	}
}

fn main() {
	$if prod { panic('assertions required') }
	$if !macos { panic('macOS getattrlist required') }
	assert os.args.len >= 2, 'usage: apfs-private-size PATH...'
	for path in os.args[1..] {
		assert os.real_path(path) == path && !os.is_link(path), 'canonical absolute path required'
		mut totals := Totals{}
		collect(path, mut totals)!
		for detail in totals.details { println(detail) }
		println('APFS-PRIVATE-TOTAL bytes=${totals.bytes} logical_bytes=${totals.logical_bytes} files=${totals.files} directories=${totals.directories} skipped_symlinks=${totals.symlinks} path=${path}')
	}
}
