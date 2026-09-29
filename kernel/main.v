@[has_globals]
module main

// Kernel entry point - shared definitions.
// Arch-specific kmain() and kmain_thread() are in main_amd64.v / main_arm64.v.

import event
import fs
import lib.stubs
import limine
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
fn writeback_thread() {
	for {
		mut interval := time.new_timer(time.TimeSpec{
			tv_sec: writeback_interval_seconds
			tv_nsec: 0
		})
		event.await_one(mut interval.event, true) or {}
		interval.disarm()
		unsafe { free(interval) }
		// A device that cannot take the write keeps its pages dirty and
		// retryable, so the next round tries again rather than giving up.
		pagecache.sync_all()
		// DHCP runs from the scheduler's poll callback, which cannot write to
		// the root filesystem. This is a thread that can.
		inet.publish_resolver()
		// Removed files whose grace period has run out, when no more unlinks
		// come to free them.
		fs.reap_removed()
	}
}
