// SPDX-License-Identifier: GPL-2.0-or-later
// Native schema/read cleanup probe; no application performance claim.
module main

import perfheap

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <alloca.h>

fn C.dup2(i32, i32) i32
fn C.sysconf(i32) i64
fn C.sleep(u32) u32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32
fn C.alloca(u64) voidptr

fn wait_grace() { mut left := u32(13); for left > 0 { left = C.sleep(left) } }

fn run() ! {
	unsafe {
		console := $if arm64 { c'/dev/console' } $else { c'/dev/com1' }
		fd := C.open(console, C.O_WRONLY)
		if fd < 0 || C.dup2(fd, 1) < 0 || C.dup2(fd, 2) < 0 { return error('console setup failed') }
		if fd > 2 { C.close(fd) }
		perfheap.require_page_size(C.sysconf(C._SC_PAGESIZE))!
		before := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		after := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		delta := &perfheap.Delta(C.alloca(sizeof(perfheap.Delta)))
		*before = perfheap.Snapshot{}
		*after = perfheap.Snapshot{}
		*delta = perfheap.Delta{}
		perfheap.read_snapshot('/proc/slabinfo', before)!
		perfheap.read_snapshot('/proc/slabinfo', after)!
		perfheap.compare(before, after, delta)!
		for _ in 0 .. 64 { perfheap.read_snapshot('/proc/slabinfo', after)! }
		wait_grace()
		perfheap.read_snapshot('/proc/slabinfo', before)!
		for _ in 0 .. 200 { perfheap.read_snapshot('/proc/slabinfo', after)! }
		wait_grace()
		perfheap.read_snapshot('/proc/slabinfo', after)!
		perfheap.compare(before, after, delta)!
		for i, row in before.classes {
			C.printf(c'LINUX PERFHEAP CLASS: size=%lu live=%lu/%lu pages=%lu/%lu\n',
				row.size, row.objects, after.classes[i].objects, row.pages, after.classes[i].pages)
		}
		C.printf(c'LINUX PERFHEAP STORAGE: large=%lu/%lu written=%lu/%lu\n', before.large_pages,
			after.large_pages, before.written_after_free, after.written_after_free)
		perfheap.qualify_flatness(before, after)!
		C.printf(c'LINUX PERFHEAP SUMMARY: schema=%s pages=%d classes=%d reads=200 failures=0\n',
			&char(perfheap.schema.str), i32(perfheap.page_size), i32(perfheap.class_count))
	}
}

fn main() {
	run() or { unsafe { C.printf(c'LINUX PERFHEAP FAIL: %s\n', &char(err.msg().str)) } }
	unsafe { C.fflush(C.stdout) }
	for { C.pause() }
}
