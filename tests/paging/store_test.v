module pager

import memory
import errno
import resource
import time

fn random_frame() voidptr {
	physical := memory.pmm_alloc_fallible(1)
	mut random := u32(97)
	for i in 0 .. 4096 {
		random ^= random << 13
		random ^= random >> 17
		random ^= random << 5
		unsafe { (&u8(physical))[i] = u8(random) }
	}
	return physical
}

fn assert_random(physical voidptr) {
	mut random := u32(97)
	for i in 0 .. 4096 {
		random ^= random << 13
		random ^= random >> 17
		random ^= random << 5
		assert unsafe { (&u8(physical))[i] } == u8(random)
	}
}

fn swap_disk(pages int) &resource.Resource {
	mut res := &resource.Resource{ swap_data: []u8{len: pages * 4096}, stat: resource.Stat{ size: i64(pages * 4096) } }
	unsafe {
		C.memcpy(&res.swap_data[4086], c'SWAPSPACE2', 10)
		res.swap_data[1024] = 1
		res.swap_data[1028] = u8(pages - 1)
	}
	return res
}

fn test_compression_fallback_and_fork_references_release_every_owner() {
	mut backing := detached(memory.pmm_alloc_fallible(1))
	assert store(backing) == 1
	assert snapshot().compressed_pages == 1
	retain(backing) // fork's nonresident entry
	for _ in 0 .. 2 {
		loaded := load(backing) or { panic('compressed load') }
		for i in 0 .. 4096 {
			assert unsafe { (&u8(loaded))[i] } == 0
		}
		memory.pmm_free(loaded, 1)
		release(backing)
	}
	assert snapshot().compressed_pages == 0 && memory.heap_objects == 0
	backing = detached(random_frame())
	assert store(backing) == 0 // no disk: original remains recoverable
	loaded := load(backing) or { panic('fallback load') }
	assert_random(loaded)
	release(backing)
	memory.pmm_free(loaded, 1)
	assert memory.live_pages == 0
}

fn pending_load(backing &Backing) voidptr { return load(backing) or { panic('pending load') } }

fn test_pending_pageout_wait_and_raced_unmap_keep_backing_alive() {
	backing := detached(random_frame())
	retain(backing) // independent source pin
	worker := spawn pending_load(backing)
	time.sleep(10 * time.millisecond)
	release(backing) // mapping removed during pending pageout
	store(backing)
	loaded := worker.wait()
	assert_random(loaded)
	release(backing)
	memory.pmm_free(loaded, 1)
	assert memory.live_pages == 0
}

fn test_encrypted_slots_integrity_io_failure_reuse_and_swapoff() {
	mut res := swap_disk(3)
	identity := resource.BlockIdentity{ disk_id: 1, length: 3 * 4096 }
	enable(mut res, identity, 42) or { panic('swapon') }
	assert res.refcount == 2 && snapshot().total == 8192
	first := detached(random_frame())
	assert store(first) == 1
	assert first.slot == 0 && snapshot().used == 4096
	assert unsafe { C.memcmp(&res.swap_data[4096], c'\x01\x02', 2) } != 0
	loaded := load(first) or { panic('disk refault') }
	assert_random(loaded)
	assert unsafe { C.memcmp(&res.swap_data[4096], loaded, 4096) } != 0
	memory.pmm_free(loaded, 1)
	res.swap_data[4096 + 37] ^= 0x80
	if _ := load(first) {
		assert false
	}
	assert snapshot().used == 4096 // failed read cannot discard its slot
	res.swap_data[4096 + 37] ^= 0x80
	res.short_io = true
	if _ := load(first) {
		assert false
	}
	res.short_io = false
	res.fail_write = true
	failed := detached(random_frame())
	assert store(failed) == 0 && snapshot().used == 4096
	res.fail_write = false
	recovered := load(failed) or { panic('failed write fallback') }
	assert_random(recovered)
	memory.pmm_free(recovered, 1)
	release(failed)
	second := detached(random_frame())
	assert store(second) == 1 && snapshot().used == 8192
	full := detached(random_frame())
	assert store(full) == 0
	release(full)
	release(first)
	third := detached(random_frame())
	assert store(third) == 1 && third.slot == 0
	assert unsafe { C.memcmp(&res.swap_data[4096], &res.swap_data[8192], 4096) } != 0
	memory.fail_alloc = true
	if _ := disable(identity) {
		assert false
	}
	memory.fail_alloc = false
	assert snapshot().total == 8192 // activation remains available
	assert disable(identity) or { panic('swapoff') } == 42
	assert snapshot().total == 0 && res.refcount == 1
	for backing in [second, third] {
		frame := load(backing) or { panic('swapoff resident backing') }
		assert_random(frame)
		memory.pmm_free(frame, 1)
		release(backing)
	}
	assert memory.live_pages == 0 && memory.heap_objects == 0
}

fn test_invalid_header_never_enables_or_changes_device() {
	mut res := swap_disk(3)
	res.swap_data[4086] = 0
	if _ := enable(mut res, resource.BlockIdentity{ disk_id: 2, length: 12288 }, 1) {
		assert false
	}
	assert res.refcount == 1 && snapshot().total == 0 && memory.heap_objects == 0
}

fn test_refault_errors_distinguish_corrupt_compression_and_disk_memory_exhaustion() {
	mut compressed := detached(memory.pmm_alloc_fallible(1))
	assert store(compressed) == 1
	length := compressed.length
	compressed.length = 0
	errno.set(0)
	if _ := load(compressed) { assert false }
	assert errno.get() == errno.eio
	compressed.length = length
	release(compressed)
	mut res := swap_disk(3)
	identity := resource.BlockIdentity{disk_id: 3, length: 3 * 4096}
	enable(mut res, identity, 44) or { panic('error fixture swapon') }
	disk := detached(random_frame())
	assert store(disk) == 1
	res.fail_read = true
	res.fail_read_errno = errno.enomem
	if _ := load(disk) { assert false }
	assert errno.get() == errno.enomem
	res.fail_read_errno = 0
	if _ := load(disk) { assert false }
	assert errno.get() == errno.eio
	res.fail_read = false
	release(disk)
	assert disable(identity) or { panic('error fixture swapoff') } == 44
	assert memory.live_pages == 0 && memory.heap_objects == 0
}
