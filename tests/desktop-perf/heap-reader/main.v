// SPDX-License-Identifier: GPL-2.0-or-later
// Native admission/refusal and forced cross-CPU cleanup for the shared warmup.
module main

import perfheap
import perfreader

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <alloca.h>

fn C.alloca(u64) voidptr
fn C.dup2(i32, i32) i32
fn C.sysconf(i32) i64
fn C.sleep(u32) u32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32
fn C.sched_getcpu() i32

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn grace() { mut left := u32(13); for left > 0 { left = C.sleep(left) } }

fn run() ! {
	unsafe {
		fd := C.open($if arm64 { c'/dev/console' } $else { c'/dev/com1' }, C.O_WRONLY)
		require(fd >= 0 && C.dup2(fd, 1) >= 0 && C.dup2(fd, 2) >= 0, 'console setup failed')!
		if fd > 2 { C.close(fd) }
		perfheap.require_page_size(C.sysconf(C._SC_PAGESIZE))!
		require(perfreader.affinity()! == 3, 'exactly two allowed CPUs required')!
		before := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		after := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		delta := &perfheap.Delta(C.alloca(sizeof(perfheap.Delta)))
		*before = perfheap.Snapshot{}; *after = perfheap.Snapshot{}; *delta = perfheap.Delta{}
		mut refused := 0
		for cpu in [i32(-1), 64, 2]! {
			perfreader.select_cpu(cpu) or { refused++ }
			require(perfreader.affinity()! == 3, 'CPU refusal changed original mask')!
		}
		perfreader.restore(0) or { refused++ }
		require(perfreader.affinity()! == 3, 'empty-mask refusal changed affinity')!
		perfreader.select_cpu(1)!
		perfreader.restore(3)!
		_ := perfreader.warm('/proc/not-a-slab-reader', before, after) or { refused++; u64(0) }
		require(refused == 5 && perfreader.affinity()! == 3,
			'failed reader did not restore affinity')!
		perfreader.restore(1)!
		require(perfreader.warm('/proc/slabinfo', before, after)! == 1
			&& perfreader.affinity()! == 1, 'subset warmup broadened affinity')!
		perfreader.restore(3)!
		require(perfreader.warm('/proc/slabinfo', before, after)! == 3
			&& perfreader.affinity()! == 3, 'full warmup failed to restore affinity')!
		grace()
		perfreader.select_cpu(0)!
		perfheap.read_snapshot('/proc/slabinfo', before)!
		for _ in 0 .. 200 { perfheap.read_snapshot('/proc/slabinfo', after)! }
		require(C.sched_getcpu() == 0, 'measured reader left CPU 0')!
		grace()
		perfreader.select_cpu(1)!
		perfheap.read_snapshot('/proc/slabinfo', after)!
		require(C.sched_getcpu() == 1, 'final reader left CPU 1')!
		perfheap.compare(before, after, delta)!
		perfheap.qualify_flatness(before, after)!
		perfreader.restore(3)!
		C.printf(c'HEAP-READER-CONTROL mask=3 subset=1 refused=5 restored=3 cross=0/1 reads_per_cpu=%d\n',
			i32(perfreader.reads_per_cpu))
		for i, row in before.classes {
			C.printf(c'LINUX PERFHEAP CLASS: size=%lu live=%lu/%lu pages=%lu/%lu\n',
				row.size, row.objects, after.classes[i].objects, row.pages, after.classes[i].pages)
		}
		C.printf(c'LINUX PERFHEAP STORAGE: large=%lu/%lu written=%lu/%lu\n',
			before.large_pages, after.large_pages, before.written_after_free, after.written_after_free)
		C.printf(c'LINUX PERFHEAP SUMMARY: schema=%s pages=%d classes=%d reads=200 failures=0\n',
			&char(perfheap.schema.str), i32(perfheap.page_size), i32(perfheap.class_count))
	}
}

fn main() {
	run() or { unsafe { C.printf(c'LINUX PERFHEAP FAIL: %s\n', &char(err.msg().str)) } }
	unsafe { C.fflush(C.stdout) }
	for { C.pause() }
}
