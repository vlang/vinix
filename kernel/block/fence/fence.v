// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A count of what has been written to disks, and a way to stop it.
//
// Hibernation needs two things of the block drivers that nothing else does.
//
// A machine that finds an image on its way up may only go back into it if
// this boot has not written to a disk: the image holds the state of every
// mounted filesystem as it was, and a disk changed since is one the resumed
// kernel would go on to corrupt. Rather than argue that nothing before the
// check writes, every write a block driver is asked for is counted here, from
// the first, and the check reads the count.
//
// And once the image of memory has been taken, the kernel it was taken from
// goes on running for as long as writing it takes. Anything that kernel then
// changes on a disk -- a block given to a file, a page swapped out -- is a
// change the image knows nothing of. So from the snapshot on, a write is held
// at the driver's door until the machine is off, or until hibernation fails
// and the kernel carries on, when it goes through as if nothing had happened.
// The thread that hibernates is let past for the image itself and for nothing
// else: a write of its own to any other place is refused, which is a bug
// shown rather than a disk changed.
//
// Reads, and a disk's own cache flush, change nothing and are not looked at.
@[has_globals]
module fence

import acpisync
import katomic
import sched

// How often a held writer looks again.
const held_poll_ms = u64(20)

__global (
	// Writes and discards block drivers have been asked for since boot.
	blockfence_writes u64
	// Nonzero from the snapshot until power-off or failure.
	blockfence_up u32
	// The thread that raised it, and whether it is writing the image now.
	blockfence_owner   u64
	blockfence_passing u32
	// Writers held, and writes of the owner's refused, since boot.
	blockfence_held    u64
	blockfence_refused u64
)

// A block driver is about to write to its device, or to discard part of it.
// Returns when it may; false when it may not at all, and the driver is to
// fail the request. May sleep: call it before any lock of the driver's is
// taken.
pub fn before_write() bool {
	katomic.inc(mut &blockfence_writes)
	if katomic.load(&blockfence_up) == 0 {
		return true
	}
	if acpisync.thread_id() == katomic.load(&blockfence_owner) {
		if katomic.load(&blockfence_passing) != 0 {
			return true
		}
		katomic.inc(mut &blockfence_refused)
		return false
	}
	katomic.inc(mut &blockfence_held)
	wait_lowered()
	return true
}

fn wait_lowered() {
	for katomic.load(&blockfence_up) != 0 {
		acpisync.sleep(held_poll_ms)
		// A thread with a signal coming is not put to sleep; it is still
		// held, and takes turns with the rest rather than spin.
		sched.reschedule()
	}
}

// Whether a write by the calling thread would be held or refused now. For a
// driver to ask again once it has its device's lock: a request that passed
// before_write() and then waited -- for a device that was asleep, as every
// device is while the snapshot is taken -- must not go to the device after
// the fence has gone up behind it. One that finds it closed lets go of its
// lock, calls wait_open() and starts again.
pub fn closed() bool {
	if katomic.load(&blockfence_up) == 0 {
		return false
	}
	return acpisync.thread_id() != katomic.load(&blockfence_owner)
		|| katomic.load(&blockfence_passing) == 0
}

// Wait, holding nothing, until writes go through again. For whoever is about
// to take a lock under which a write may be made -- the page cache takes its
// own before it calls a driver -- so that a writer is held where it holds
// nothing another thread could need, and not at the driver's door with that
// lock. The thread that raised the fence is not held: what it may not write
// is refused it at the driver.
pub fn wait_open() {
	if katomic.load(&blockfence_up) == 0 || acpisync.thread_id() == katomic.load(&blockfence_owner) {
		return
	}
	katomic.inc(mut &blockfence_held)
	wait_lowered()
}

// How many writes block drivers have been asked for since the machine
// started.
pub fn writes() u64 {
	return katomic.load(&blockfence_writes)
}

// Hold every write from now on but those the calling thread makes between
// pass(true) and pass(false).
pub fn raise() {
	katomic.store(mut &blockfence_owner, acpisync.thread_id())
	katomic.store(mut &blockfence_passing, u32(0))
	katomic.store(mut &blockfence_up, u32(1))
}

// Let the held writers go.
pub fn lower() {
	katomic.store(mut &blockfence_up, u32(0))
	katomic.store(mut &blockfence_passing, u32(0))
	katomic.store(mut &blockfence_owner, u64(0))
}

pub fn raised() bool {
	return katomic.load(&blockfence_up) != 0
}

// The owner is about to write the image, or has finished a piece of it.
pub fn pass(on bool) {
	katomic.store(mut &blockfence_passing, if on { u32(1) } else { u32(0) })
}

// Writers held at the fence and writes of the owner's refused, since boot.
pub fn held() (u64, u64) {
	return katomic.load(&blockfence_held), katomic.load(&blockfence_refused)
}

// Whether the calling thread is the one that raised the fence: it cannot
// wait for it to come down, since it is the one that would bring it down.
pub fn mine() bool {
	return katomic.load(&blockfence_up) != 0 && acpisync.thread_id() == katomic.load(&blockfence_owner)
}
