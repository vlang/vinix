// SPDX-License-Identifier: GPL-2.0-or-later
// Prime observer allocations on every allowed CPU, then restore scheduling.
module perfreader

import perfheap

#include <sched.h>
#include <unistd.h>
#include <alloca.h>

fn C.alloca(u64) voidptr
fn C.sched_getaffinity(i32, u64, voidptr) i32
fn C.sched_setaffinity(i32, u64, voidptr) i32
fn C.sched_getcpu() i32
fn C.sched_yield() i32
fn C.usleep(u32) i32

pub const reads_per_cpu = 64

fn require(ok bool, message string) ! { if !ok { return error(message) } }

pub fn affinity() !u64 {
	unsafe {
		mask := &u64(C.alloca(sizeof(u64)))
		*mask = 0
		require(C.sched_getaffinity(0, sizeof(u64), voidptr(mask)) == 0 && *mask != 0,
			'bounded observer affinity read failed')!
		return *mask
	}
}

pub fn restore(value u64) ! {
	unsafe {
		mask := &u64(C.alloca(sizeof(u64)))
		*mask = value
		require(value != 0 && C.sched_setaffinity(0, sizeof(u64), voidptr(mask)) == 0,
			'observer affinity restoration failed')!
	}
	require(affinity()! == value, 'restored observer affinity differs')!
}

pub fn select_cpu(cpu i32) ! {
	require(cpu >= 0 && cpu < 64, 'observer CPU exceeds bounded affinity')!
	restore(u64(1) << u32(cpu))!
	for _ in 0 .. 2000 {
		if C.sched_getcpu() == cpu { return }
		C.sched_yield()
		C.usleep(1000)
	}
	return error('observer CPU placement did not become effective')
}

pub fn warm(path string, before &perfheap.Snapshot, after &perfheap.Snapshot) !u64 {
	original := affinity()!
	mut entry_cpu := C.sched_getcpu()
	require(entry_cpu >= 0, 'observer entry CPU is unavailable')!
	// A caller may have narrowed its mask just before entering, while its
	// migration is still pending. Resume on a CPU admitted by that mask.
	if entry_cpu >= 64 || original & (u64(1) << u32(entry_cpu)) == 0 {
		for cpu in 0 .. 64 {
			if original & (u64(1) << u32(cpu)) != 0 { entry_cpu = i32(cpu); break }
		}
	}
	mut restored := false
	defer {
		if !restored {
			select_cpu(entry_cpu) or {}
			restore(original) or {}
		}
	}
	for cpu in 0 .. 64 {
		if original & (u64(1) << u32(cpu)) == 0 { continue }
		select_cpu(i32(cpu))!
		for read in 0 .. reads_per_cpu {
			perfheap.read_snapshot(path, if read % 2 == 0 { before } else { after })!
		}
		require(C.sched_getcpu() == i32(cpu), 'observer warmup left selected CPU')!
	}
	// Avoid moving the measured workload to the last reader CPU as a side
	// effect of warmup. Scheduling becomes unrestricted again only afterward.
	select_cpu(entry_cpu)!
	restore(original)!
	restored = true
	return original
}
