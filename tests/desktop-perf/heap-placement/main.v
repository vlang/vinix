// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only placement diagnostic, separate from the performance qualification.
module main

import perfheap

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sched.h>
#include <alloca.h>

fn C.alloca(u64) voidptr
fn C.dup2(i32, i32) i32
fn C.sysconf(i32) i64
fn C.sched_getaffinity(i32, u64, voidptr) i32
fn C.sched_setaffinity(i32, u64, voidptr) i32
fn C.sched_getcpu() i32
fn C.sched_yield() i32
fn C.usleep(u32) i32
fn C.sleep(u32) u32
fn C.pause() i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn grace() { mut left := u32(13); for left > 0 { left = C.sleep(left) } }

fn select_cpu(cpu i32, mask &u64) ! {
	unsafe { *mask = u64(1) << u32(cpu) }
	require(C.sched_setaffinity(0, sizeof(u64), voidptr(mask)) == 0, 'CPU selection failed')!
	for _ in 0 .. 2000 {
		if C.sched_getcpu() == cpu { return }
		C.sched_yield()
		C.usleep(1000)
	}
	return error('selected CPU placement did not become effective')
}

fn read_on(cpu i32, mask &u64, snapshot &perfheap.Snapshot) ! {
	select_cpu(cpu, mask)!
	perfheap.read_snapshot('/proc/slabinfo', snapshot)!
	require(C.sched_getcpu() == cpu, 'reader left selected CPU')!
}

fn run() ! {
	unsafe {
		fd := C.open($if arm64 { c'/dev/console' } $else { c'/dev/com1' }, C.O_WRONLY)
		require(fd >= 0 && C.dup2(fd, 1) >= 0 && C.dup2(fd, 2) >= 0, 'console setup failed')!
		if fd > 2 { C.close(fd) }
		perfheap.require_page_size(C.sysconf(C._SC_PAGESIZE))!
		saved := &u64(C.alloca(sizeof(u64)))
		mask := &u64(C.alloca(sizeof(u64)))
		*saved = 0
		require(C.sched_getaffinity(0, sizeof(u64), voidptr(saved)) == 0 && *saved == 3,
			'exactly two allowed CPUs required')!
		mut restored := false
		defer {
			if !restored { C.sched_setaffinity(0, sizeof(u64), voidptr(saved)) }
		}
		before := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		after := &perfheap.Snapshot(C.alloca(sizeof(perfheap.Snapshot)))
		delta := &perfheap.Delta(C.alloca(sizeof(perfheap.Delta)))
		*before = perfheap.Snapshot{}; *after = perfheap.Snapshot{}; *delta = perfheap.Delta{}
		read_on(0, mask, before)!
		read_on(0, mask, after)!
		perfheap.compare(before, after, delta)!
		C.printf(c'HEAP-PLACEMENT BEGIN schema=%s allowed=3 cases=4 qualification=false\n', &char(perfheap.schema.str))
		C.fflush(C.stdout)
		for case_id in 0 .. 4 {
			// First cross-CPU pair leaves CPU 1 unwarmed by this reader.
			// Later pairs touch the reader on both CPUs, including its buffers.
			for cpu in 0 .. if case_id == 0 { 1 } else { 2 } {
				select_cpu(i32(cpu), mask)!
				for _ in 0 .. 64 { perfheap.read_snapshot('/proc/slabinfo', after)! }
			}
			grace()
			first := if case_id == 2 { i32(1) } else { i32(0) }
			last := if case_id == 3 { i32(0) } else { i32(1) - first }
			read_on(first, mask, before)!
			for _ in 0 .. 200 { perfheap.read_snapshot('/proc/slabinfo', after)! }
			require(C.sched_getcpu() == first, 'measured reads left selected CPU')!
			grace()
			read_on(last, mask, after)!
			perfheap.compare(before, after, delta)!
			C.printf(c'HEAP-PLACEMENT CASE id=%d before_cpu=%d after_cpu=%d warm_cpus=%d reads=200\n',
				i32(case_id), first, last, i32(if case_id == 0 { 1 } else { 2 }))
			for i, row in before.classes {
				C.printf(c'HEAP-PLACEMENT CLASS id=%d size=%lu objects=%lu/%lu pages=%lu/%lu\n',
					i32(case_id), row.size, row.objects, after.classes[i].objects, row.pages, after.classes[i].pages)
			}
			C.printf(c'HEAP-PLACEMENT STORAGE id=%d large=%lu/%lu written=%lu/%lu\n',
				i32(case_id), before.large_pages, after.large_pages, before.written_after_free, after.written_after_free)
			C.fflush(C.stdout)
		}
		require(C.sched_setaffinity(0, sizeof(u64), voidptr(saved)) == 0, 'affinity restoration failed')!
		*mask = 0
		require(C.sched_getaffinity(0, sizeof(u64), voidptr(mask)) == 0 && *mask == *saved, 'restored mask differs')!
		restored = true
		C.printf(c'HEAP-PLACEMENT SUMMARY cases=4 restored=3 qualification=false\n')
	}
}

fn main() {
	run() or { unsafe { C.printf(c'HEAP-PLACEMENT FAIL %s\n', &char(err.msg().str)) } }
	unsafe { C.fflush(C.stdout) }
	for { C.pause() }
}
