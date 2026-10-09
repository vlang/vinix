@[has_globals]
module main

// Kernel entry point - shared definitions.
// Arch-specific kmain() and kmain_thread() are in main_amd64.v / main_arm64.v.

import event
import fs
import krandom
import lib.stubs
import limine
import memory
import proc
import sched
import pagecache
import socket.inet
import time

#include <symbols.h>
#include <stack_protector.h>

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile limine_base_revision = limine.LimineBaseRevision{
		revision: 2
	}
)

fn C._vinit(argc int, argv voidptr)

fn C.vinix_stack_guard_init()

pub fn main() {
	kmain()
}

// How long a write may sit in memory before it is pushed to the device.
const writeback_interval_seconds = i64(5)

// Filesystem writes land in a write-back page cache, which on its own hands a
// page to the disk only when the LRU evicts it. A small file -- the usual case
// -- is therefore still in memory when the machine stops, and a restart loses
// it, which is what made a persistent /root look like it was not persistent at
// all. Linux answers this with a writeback timer; so does this thread. sync(2)
// and reboot(2) are still the exact guarantees, and this only bounds the window
// for everything that never calls them, including a VM window simply closed.
// Quota-delayed disk writeback must not postpone retirement, OOM recovery or
// pressure delivery for every other workload on the machine.
fn maintenance_thread() {
	mut seconds := i64(0)
	for {
		mut interval := time.new_timer(time.TimeSpec{tv_sec: 1})
		event.await_one(mut interval.event, true) or {}
		interval.disarm()
		unsafe { free(interval) }
		memory.pressure_maintenance()
		proc.reap_processes()
		fs.reap_removed()
		fs.cgroup_pressure_maintenance()
		seconds++
		if seconds == 30 || seconds % 300 == 0 { krandom.stir() }
	}
}

fn writeback_thread() {
	for {
		mut interval := time.new_timer(time.TimeSpec{tv_sec: writeback_interval_seconds})
		event.await_one(mut interval.event, true) or {}
		interval.disarm()
		unsafe { free(interval) }
		pagecache.sync_all()
		sched.park_for_io()
		inet.publish_resolver()
	}
}
