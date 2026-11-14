// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.mmu
import gpu.agx.pgtable
import memory

// BufferInner::tpc and each Scene retain the same private, firmware-writable
// array. The manager lock serializes references. Replacing the queue's cache
// does not detach backing from an older scene that is still using it.
struct G13TailPointerCache {
mut:
	buffer     &mmu.UatBuffer = unsafe { nil }
	references u32
	retiring   bool
}

fn (mut mgr GpuManager) retain_g13_tpc_locked(mut owner G13RenderBufferResources,
	size u64) ?&G13TailPointerCache {
	if mgr.state != .running || owner.context == unsafe { nil } || !owner.context.active
		|| size == 0 || size > ~u64(0) - pgtable.uat_pg_mask {
		return none
	}
	old := owner.tail_pointer_cache
	if old != unsafe { nil } && !old.retiring && old.buffer.size >= size {
		if old.references == ~u32(0) { return none }
		mut cached := unsafe { old }
		cached.references++
		return cached
	}
	storage := memory.malloc_packed_fallible(sizeof(G13TailPointerCache))
	if storage == unsafe { nil } { return none }
	mut next := unsafe { &G13TailPointerCache(storage) }
	unsafe { *next = G13TailPointerCache{} }
	mut context := unsafe { owner.context }
	next.buffer = context.alloc_driver_buffer_aligned(size, true, pgtable.uat_pgsz) or {
		memory.free(storage)
		return none
	}
	next.references = 1 // render buffer's cached reference
	// A cache with no remaining scene owner can be unmapped now. If a
	// scene still uses it, the last scene performs that handshake instead.
	if !mgr.invalidate_g13_tpc_locked(mut context, old) {
		context.release_driver_buffer(next.buffer) // unpublished backing
		memory.free(storage)
		return none
	}
	owner.tail_pointer_cache = next
	mgr.release_g13_tpc_locked(mut context, old)
	next.references++ // newly constructed scene
	return next
}

// Invalidation is required only for the last owner. Cached backing must stay
// mapped when a scene retires while the render buffer or another scene owns it.
fn (mut mgr GpuManager) invalidate_g13_tpc_locked(mut context mmu.UatContext,
	cache &G13TailPointerCache) bool {
	if cache == unsafe { nil } { return true }
	assert cache.references != 0
	if cache.references != 1 { return true }
	mut owned := unsafe { cache }
	owned.retiring = true
	return mgr.invalidate_g13_driver_buffer(mut context, cache.buffer)
}

// The last reference is dropped after its UAT invalidation, or with firmware
// stopped. A failed scene construction can only drop a non-final cached ref.
fn (mut mgr GpuManager) release_g13_tpc_locked(mut context mmu.UatContext,
	cache &G13TailPointerCache) {
	if cache == unsafe { nil } { return }
	mut owned := unsafe { cache }
	assert owned.references != 0
	owned.references--
	if owned.references == 0 {
		context.release_driver_buffer(owned.buffer)
		memory.free(voidptr(owned))
	}
}
