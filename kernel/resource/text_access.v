// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import errno
import klock

const text_access_buckets = 256

// One claim lives in a Handle, Pagemap or syscall frame. The owner retains
// the corresponding resource and releases the claim before that reference.
// A linked claim stays at the same address until release.
pub struct TextAccess {
mut:
	device u64
	inode u64
	executing bool
	previous &TextAccess = unsafe { nil }
	next &TextAccess = unsafe { nil }
}

struct TextAccessBucket {
mut:
	lock klock.Lock
	first &TextAccess = unsafe { nil }
}

__global (text_access_table [text_access_buckets]TextAccessBucket)

pub interface TextAccessVolume {
	text_access_volume() u64
}

struct TextAccessVolumeCall {
mut:
	volume TextAccessVolume
}

fn text_access_device(mut res Resource) u64 {
	if res is TextAccessVolume {
		// Keep optional interface dispatch off the manualfree heap.
		mut call := unsafe { &TextAccessVolumeCall(C.vinix_stack_alloc(sizeof(TextAccessVolumeCall))) }
		unsafe { call.volume = TextAccessVolume(res) }
		return call.volume.text_access_volume()
	}
	return res.stat.dev
}

fn text_access_index(device u64, inode u64) int {
	return int((device ^ inode ^ (inode >> 9)) & (text_access_buckets - 1))
}

// Match hard links and filesystem views by their backing inode. Unnumbered
// synthetic files fall back to their resource identity, independent of the box.
pub fn (mut claim TextAccess) acquire(res &Resource, executing bool) ? {
	stable_inode := res.stat.dev != 0 && res.stat.ino != 0
	mut file := unsafe { res }
	device := if stable_inode { text_access_device(mut file) } else { u64(0) }
	inode := if stable_inode { res.stat.ino } else { unsafe { u64(&res.refcount) } }
	mut bucket := unsafe { &text_access_table[text_access_index(device, inode)] }
	bucket.lock.acquire()
	defer { bucket.lock.release() }
	mut current := bucket.first
	for current != unsafe { nil } {
		if current.device == device && current.inode == inode && current.executing != executing {
			errno.set(errno.etxtbsy)
			return none
		}
		current = current.next
	}
	claim.device = device
	claim.inode = inode
	claim.executing = executing
	claim.next = bucket.first
	if bucket.first != unsafe { nil } { bucket.first.previous = unsafe { &claim } }
	bucket.first = unsafe { &claim }
}

pub fn (mut claim TextAccess) release() {
	if claim.inode == 0 { return }
	mut bucket := unsafe { &text_access_table[text_access_index(claim.device, claim.inode)] }
	bucket.lock.acquire()
	if claim.previous != unsafe { nil } {
		claim.previous.next = claim.next
	} else {
		bucket.first = claim.next
	}
	if claim.next != unsafe { nil } { claim.next.previous = claim.previous }
	claim.inode = 0
	claim.next = unsafe { nil }
	claim.previous = unsafe { nil }
	bucket.lock.release()
}
