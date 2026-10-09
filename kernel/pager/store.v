// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module pager

import errno
import event
import event.eventstruct
import klock
import krandom
import memory
import resource
import cgcontrol

const compressed_limit = 2048
const max_disk_slots = u64(1048576)

// A backing is immutable to mappings. One reference per nonresident tree
// node, plus independent fault/worker references. The registry lock protects
// reference counts and membership; the object lock protects its contents.
pub struct Backing {
mut:
	lock       klock.Lock
	changed    eventstruct.Event
	busy       bool     = true
	refs       int      = 2 // the newly detached mapping and its pageout worker
	mapping_refs int    = 1 // excludes temporary fault and worker pins
	swap_group &cgcontrol.Group = unsafe { nil }
	swap_charged bool
	next       &Backing = unsafe { nil }
	physical   voidptr
	compressed voidptr
	length     int
	slot       i64 = -1
	nonce      [12]u8
	tag        [32]u8
}

pub struct Snapshot {
pub:
	total            u64
	used             u64
	compressed_pages u64
	compressed_bytes u64
	pageouts         u64
	refaults         u64
	io_errors        u64
}

__global (
	store_lock         klock.Lock
	backings           &Backing = unsafe { nil }
	pager_device       &resource.Resource = unsafe { nil }
	disk_identity      resource.BlockIdentity
	disk_claim         int = -1
	disk_bitmap        &u8 = unsafe { nil }
	disk_slots         u64
	disk_used          u64
	disk_cursor        u64
	disk_draining      bool
	disk_sequence      u64
	encryption_key     [32]u8
	authentication_key [32]u8
	compressed_pages   u64
	compressed_bytes   u64
	pageouts           u64
	refaults           u64
	io_errors          u64
)

pub fn snapshot() Snapshot {
	store_lock.acquire()
	result := Snapshot{
		total:            disk_slots * memory.page_size
		used:             disk_used * memory.page_size
		compressed_pages: compressed_pages
		compressed_bytes: compressed_bytes
		pageouts:         pageouts
		refaults:         refaults
		io_errors:        io_errors
	}
	store_lock.release()
	return result
}

// Enable only a reserved raw block extent with a version-one Linux mkswap
// header. No regular files, holes, bad-page lists or implicit disk formatting.
// The header's 4 KiB units are independent of the native VM page granule.
pub fn enable(mut res resource.Resource, identity resource.BlockIdentity, claim int) ? {
	mut header := [4096]u8{}
	read := res.read(unsafe { nil }, &header[0], 0, 4096) or { return none }
	if read != 4096 || unsafe { C.memcmp(&header[4086], c'SWAPSPACE2', 10) } != 0
		|| read_u32(&header[1024]) != 1 || read_u32(&header[1032]) != 0 {
		errno.set(errno.einval)
		return none
	}
	bytes := (u64(read_u32(&header[1028])) + 1) * 4096
	if res.stat.size <= 0 || bytes > u64(res.stat.size) || bytes / memory.page_size < 2
		|| !identity.valid() || resource.backend_is_read_only(mut res) {
		errno.set(errno.einval)
		return none
	}
	slots := bytes / memory.page_size - 1
	if slots > max_disk_slots {
		errno.set(errno.e2big)
		return none
	}
	mut keys := [64]u8{}
	if !krandom.fill(&keys[0], sizeof(keys), false) {
		errno.set(errno.eagain)
		return none
	}
	defer { krandom.explicit_bzero(&keys[0], sizeof(keys)) }
	bitmap := memory.malloc_packed_fallible((slots + 7) / 8)
	if bitmap == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	store_lock.acquire()
	if pager_device != unsafe { nil } {
		store_lock.release()
		memory.free(bitmap)
		errno.set(errno.ebusy)
		return none
	}
	resource.retain_resource(mut res)
	pager_device = unsafe { &res }
	disk_identity = identity
	disk_claim = claim
	disk_bitmap = bitmap
	disk_slots = slots
	disk_used = 0
	disk_cursor = 0
	disk_sequence = 0
	disk_draining = false
	unsafe {
		C.memcpy(&encryption_key[0], &keys[0], 32)
		C.memcpy(&authentication_key[0], &keys[32], 32)
	}
	store_lock.release()
}

fn read_u32(input &u8) u32 {
	return unsafe { u32(input[0]) | u32(input[1]) << 8 | u32(input[2]) << 16 | u32(input[3]) << 24 }
}

// Takes ownership of the reference formerly held by a shadow PTE. Publishing
// the pending object before dropping VM locks prevents a fault zero-filling
// the page while the worker is compressing or writing it.
pub fn detached(physical voidptr) &Backing {
	return detached_for_group(physical, unsafe { nil })
}

pub fn detached_for_group(physical voidptr, group &cgcontrol.Group) &Backing {
	if !cgcontrol.reserve_swap(group, memory.page_size) { return unsafe { nil } }
	mut backing := unsafe { &Backing(memory.malloc_packed_fallible(sizeof(Backing))) }
	if backing == unsafe { nil } { cgcontrol.release_swap(group, memory.page_size); return unsafe { nil } }
	unsafe { *backing = Backing{ physical: physical, swap_group: group, swap_charged: true } }
	store_lock.acquire()
	backing.next = backings
	backings = backing
	store_lock.release()
	return backing
}

pub fn retain(_backing &Backing) {
	mut backing := unsafe { _backing }
	store_lock.acquire()
	backing.refs++
	store_lock.release()
}

pub fn retain_mapping(_backing &Backing) {
	mut backing := unsafe { _backing }
	store_lock.acquire()
	backing.refs++
	backing.mapping_refs++
	store_lock.release()
}

pub fn release_mapping(_backing &Backing) {
	mut backing := unsafe { _backing }
	store_lock.acquire()
	assert backing.mapping_refs > 0
	backing.mapping_refs--
	if backing.mapping_refs == 0 && backing.swap_charged {
		cgcontrol.release_swap(backing.swap_group, memory.page_size)
		backing.swap_charged = false
	}
	store_lock.release()
	release(backing)
}

// Caller owns a mapping pin under its shadow lock. Compression and refault
// workers do not affect the number of owners sharing the logical page.
pub fn mapping_sharers(backing &Backing) u64 {
	store_lock.acquire()
	defer { store_lock.release() }
	return u64(backing.mapping_refs)
}

pub fn release(_backing &Backing) {
	if _backing == unsafe { nil } { return }
	mut backing := unsafe { _backing }
	store_lock.acquire()
	backing.refs--
	if backing.refs != 0 {
		store_lock.release()
		return
	}
	if backing.swap_charged { cgcontrol.release_swap(backing.swap_group, memory.page_size) }
	mut previous := unsafe { &Backing(nil) }
	mut current := backings
	for voidptr(current) != voidptr(backing) {
		previous = current
		current = current.next
	}
	if previous == unsafe { nil } { backings = backing.next } else { previous.next = backing.next }
	if backing.slot >= 0 { free_slot_locked(backing.slot) }
	if backing.compressed != unsafe { nil } {
		compressed_pages--
		compressed_bytes -= u64(backing.length)
	}
	store_lock.release()
	if backing.physical != unsafe { nil } { memory.pmm_free(backing.physical, 1) }
	if backing.compressed != unsafe { nil } {
		krandom.explicit_bzero(backing.compressed, usize(backing.length))
		memory.free(backing.compressed)
	}
	krandom.explicit_bzero(&backing.tag[0], sizeof(backing.tag))
	memory.free(backing)
}

fn reserve_slot(mut backing Backing) bool {
	store_lock.acquire()
	defer { store_lock.release() }
	if pager_device == unsafe { nil } || disk_draining || disk_used == disk_slots
		|| disk_sequence == u64(-1) {
		return false
	}
	for _ in 0 .. disk_slots {
		slot := disk_cursor
		disk_cursor = (disk_cursor + 1) % disk_slots
		mask := u8(1 << (slot % 8))
		if unsafe { disk_bitmap[slot / 8] } & mask != 0 { continue }
		unsafe { disk_bitmap[slot / 8] |= mask }
		disk_used++
		disk_sequence++
		backing.slot = i64(slot)
		for i in 0 .. 8 { backing.nonce[i] = u8(disk_sequence >> u32(i * 8)) }
		// The remaining nonce bytes are zero; the 64-bit sequence never wraps.
		return true
	}
	return false
}

fn free_slot_locked(slot i64) {
	unsafe { disk_bitmap[u64(slot) / 8] &= ~u8(1 << (u64(slot) % 8)) }
	disk_used--
}

fn finish(mut backing Backing) {
	backing.lock.acquire()
	backing.busy = false
	// Wake under the lock: the last reference cannot free the event while
	// trigger is still using it.
	event.trigger(mut backing.changed, true)
	backing.lock.release()
}

fn acquire(mut backing Backing) bool {
	for {
		backing.lock.acquire()
		if !backing.busy {
			backing.busy = true
			backing.lock.release()
			return true
		}
		generation := event.generation(mut backing.changed)
		backing.lock.release()
		if !event.may_wait() {
			errno.set(errno.eagain)
			return false
		}
		event.await_one_from_generation_masked(mut backing.changed, generation) or { return false }
	}
	return false
}

// Returns actual data frames released, rather than counting a fork reference
// as a freed frame. On any failure the original frame remains in the backing;
// it can be refaulted and is never replaced with zeroes.
pub fn store(_backing &Backing) u64 {
	mut backing := unsafe { _backing }
	defer {
		finish(mut backing)
		release(backing)
	}
	mut packed := [compressed_limit]u8{}
	length := compress(unsafe { &u8(u64(backing.physical) + memory.get_hhdm_offset()) },
		int(memory.page_size), &packed[0], compressed_limit)
	mut compressed := false
	if length != 0 {
		store_lock.acquire()
		if (compressed_pages + 1) * compressed_limit <= memory.total_bytes() / 8 {
			compressed_pages++
			compressed_bytes += u64(length)
			compressed = true
		}
		store_lock.release()
	}
	if compressed {
		backing.compressed = memory.malloc_packed_fallible(u64(length))
		if backing.compressed == unsafe { nil } {
			store_lock.acquire()
			compressed_pages--
			compressed_bytes -= u64(length)
			store_lock.release()
			krandom.explicit_bzero(&packed[0], sizeof(packed))
			return 0
		}
		backing.length = length
		unsafe { C.memcpy(backing.compressed, &packed[0], usize(length)) }
	} else if reserve_slot(mut backing) {
		if !write_disk(mut backing) {
			store_lock.acquire()
			free_slot_locked(backing.slot)
			backing.slot = -1
			io_errors++
			store_lock.release()
			krandom.explicit_bzero(&packed[0], sizeof(packed))
			return 0
		}
	} else {
		krandom.explicit_bzero(&packed[0], sizeof(packed))
		return 0
	}
	krandom.explicit_bzero(&packed[0], sizeof(packed))
	reclaimed := if memory.pmm_refcount(backing.physical) == 1 { u64(1) } else { u64(0) }
	memory.pmm_free(backing.physical, 1)
	backing.physical = unsafe { nil }
	store_lock.acquire()
	pageouts++
	store_lock.release()
	return reclaimed
}

// All I/O and its workspace allocation run without VM, backing or registry
// spinlocks. A live slot pins the activation's resource, bitmap and keys.
fn write_disk(mut backing Backing) bool {
	scratch := memory.pmm_alloc_fallible(3)
	if scratch == unsafe { nil } { return false }
	data := unsafe { &u8(u64(scratch) + memory.get_hhdm_offset()) }
	defer {
		krandom.explicit_bzero(data, usize(3 * memory.page_size))
		memory.pmm_free(scratch, 3)
	}
	unsafe { C.memcpy(data, voidptr(u64(backing.physical) + memory.get_hhdm_offset()), usize(memory.page_size)) }
	crypt(unsafe { &encryption_key }, unsafe { &backing.nonce }, data, int(memory.page_size))
	disk_tag(backing, data, unsafe { &backing.tag })
	mut res := pager_device
	written := res.write(unsafe { nil }, data, (u64(backing.slot) + 1) * memory.page_size, memory.page_size) or { return false }
	return written == i64(memory.page_size)
}

fn disk_tag(backing &Backing, data &u8, tag &[32]u8) {
	unsafe {
		C.memcpy(&data[memory.page_size], &backing.nonce[0], 12)
		for i in 0 .. 8 {
			data[memory.page_size + 12 + u64(i)] = u8(u64(backing.slot) >> u32(i * 8))
		}
	}
	authenticate(unsafe { &authentication_key }, data, int(memory.page_size + 20),
		unsafe { &data[memory.page_size + 32] }, tag)
}

fn read_disk(backing &Backing, output voidptr) bool {
	scratch := memory.pmm_alloc_fallible(3)
	if scratch == unsafe { nil } {
		memory.note_exhaustion()
		errno.set(errno.enomem)
		return false
	}
	data := unsafe { &u8(u64(scratch) + memory.get_hhdm_offset()) }
	defer {
		krandom.explicit_bzero(data, usize(3 * memory.page_size))
		memory.pmm_free(scratch, 3)
	}
	mut res := pager_device
	read := res.read(unsafe { nil }, data, (u64(backing.slot) + 1) * memory.page_size, memory.page_size) or {
		if errno.get() == errno.enomem { memory.note_exhaustion() }
		return false
	}
	if read != i64(memory.page_size) {
		errno.set(errno.eio)
		return false
	}
	mut tag := [32]u8{}
	disk_tag(backing, data, unsafe { &tag })
	if !valid_tag(unsafe { &tag }, unsafe { &backing.tag }) {
		krandom.explicit_bzero(&tag[0], sizeof(tag))
		errno.set(errno.eio)
		return false
	}
	krandom.explicit_bzero(&tag[0], sizeof(tag))
	crypt(unsafe { &encryption_key }, unsafe { &backing.nonce }, data, int(memory.page_size))
	unsafe { C.memcpy(output, data, usize(memory.page_size)) }
	return true
}

// A fault owns a backing reference throughout this call. Encoded private
// refaults get separate frames; physical fallback pages retain COW references.
// Shared faults install one winner in their common shadow map.
pub fn load(_backing &Backing) ?voidptr {
	mut backing := unsafe { _backing }
	if !acquire(mut backing) { return none }
	defer { finish(mut backing) }
	if backing.physical != unsafe { nil } {
		if !memory.pmm_retain(backing.physical, 1) { return none }
		store_lock.acquire(); refaults++; store_lock.release()
		return backing.physical
	}
	physical := memory.pmm_alloc_user_nozero(1)
	if physical == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	output := voidptr(u64(physical) + memory.get_hhdm_offset())
	mut valid := true
	if backing.physical != unsafe { nil } {
		unsafe { C.memcpy(output, voidptr(u64(backing.physical) + memory.get_hhdm_offset()), usize(memory.page_size)) }
	} else if backing.compressed != unsafe { nil } {
		valid = decompress(backing.compressed, backing.length, output, int(memory.page_size))
	} else {
		valid = read_disk(backing, output)
	}
	if !valid {
		memory.pmm_free(physical, 1)
		store_lock.acquire()
		io_errors++
		store_lock.release()
		return none
	}
	store_lock.acquire()
	refaults++
	store_lock.release()
	return physical
}

// A failed pageout can put its original frame back without allocating or
// waiting. The returned PMM reference is independent of the backing pin.
pub fn fallback_frame(_backing &Backing) voidptr {
	mut backing := unsafe { _backing }
	backing.lock.acquire()
	defer { backing.lock.release() }
	if backing.busy || backing.physical == unsafe { nil } { return unsafe { nil } }
	if !memory.pmm_retain(backing.physical, 1) { return unsafe { nil } }
	return backing.physical
}

// Drain disk backings into resident frames before releasing the device. This
// preserves mappings even if some have PROT_NONE or no current local PTE.
// Failure leaves the activation usable, including its remaining disk slots.
pub fn disable(identity resource.BlockIdentity) ?int {
	store_lock.acquire()
	if pager_device == unsafe { nil } || identity.disk_id != disk_identity.disk_id
		|| identity.start != disk_identity.start || identity.length != disk_identity.length {
		store_lock.release()
		errno.set(errno.einval)
		return none
	}
	if disk_draining {
		store_lock.release()
		errno.set(errno.ebusy)
		return none
	}
	disk_draining = true
	mut current := backings
	if current != unsafe { nil } { current.refs++ }
	store_lock.release()
	mut valid := true
	for current != unsafe { nil } {
		if valid { valid = materialize(mut current) }
		store_lock.acquire()
		mut next := current.next
		if next != unsafe { nil } { next.refs++ }
		store_lock.release()
		release(current)
		current = next
	}
	store_lock.acquire()
	if !valid || disk_used != 0 {
		disk_draining = false
		store_lock.release()
		if valid { errno.set(errno.ebusy) }
		return none
	}
	mut res := pager_device
	bitmap := disk_bitmap
	claim := disk_claim
	pager_device = unsafe { nil }
	disk_bitmap = unsafe { nil }
	disk_slots = 0
	disk_claim = -1
	krandom.explicit_bzero(&encryption_key[0], sizeof(encryption_key))
	krandom.explicit_bzero(&authentication_key[0], sizeof(authentication_key))
	store_lock.release()
	memory.free(bitmap)
	resource.release_resource(mut res)
	return claim
}

fn materialize(mut backing Backing) bool {
	if !acquire(mut backing) { return false }
	defer { finish(mut backing) }
	if backing.slot < 0 { return true }
	physical := memory.pmm_alloc_user_nozero(1)
	if physical == unsafe { nil } {
		errno.set(errno.enomem)
		return false
	}
	if !read_disk(&backing, voidptr(u64(physical) + memory.get_hhdm_offset())) {
		memory.pmm_free(physical, 1)
		return false
	}
	backing.physical = physical
	store_lock.acquire()
	free_slot_locked(backing.slot)
	backing.slot = -1
	store_lock.release()
	return true
}
