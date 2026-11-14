// SPDX-License-Identifier: GPL-2.0-or-later
import gpu.agx.event
import drm.syncobj

fn main() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000,
		unsafe { u64(&firmware) })
	for i := u32(0); i < event.max_stamps; i++ {
		slot := event.reserve_stamp() or { panic('allocate initial stamp') }
		assert slot == i
		assert driver[i] == (i << 24), 'slot ${i}: driver stamp ${driver[i]}'
		assert firmware[i] == 0
		assert (event.advance_stamp(slot) or { panic('advance initial stamp') }) == (i << 24) + 0x100
		assert !event.stamp_completed(slot)
	}
	assert event.reserve_stamp() == none
	event.reset_event_manager()
	driver = [128]u32{}
	mut em := event.EventManager{
		initialized:   true
		stamp_phys:    unsafe { u64(&driver) }
		fw_stamp_phys: unsafe { u64(&firmware) }
	}
	mut expected := u32(0)
	for _ in 0 .. 300 {
		slot := em.alloc_stamp() or { panic('allocate stamp') }
		assert slot == 0
		assert driver[0] == expected && firmware[0] == expected
		assert !em.check_completion(slot), 'a reused slot is not an armed command'
		value := em.next_stamp_value(slot) or { panic('advance stamp') }
		expected += 0x100
		assert value == expected
		assert !em.check_completion(slot), 'the previous owner must not satisfy the next command'
		driver[0] = value
		firmware[0] = value
		assert em.check_completion(slot)
		em.free_stamp(slot)
	}
	// Zero is a valid counter after wrap, not an unarmed-command sentinel.
	driver[0] = 0xffffff00
	firmware[0] = 0xffffff00
	slot := em.alloc_stamp() or { panic('allocate wrap stamp') }
	assert !em.check_completion(slot)
	assert (em.next_stamp_value(slot) or { panic('advance wrap stamp') }) == 0
	assert !em.check_completion(slot)
	mut fence := syncobj.DmaFence{}
	em.set_fence(slot, &fence)
	em.scan_completions()
	assert fence.signals == 0
	driver[0] = 0
	firmware[0] = 0
	em.scan_completions()
	assert fence.signals == 1 && em.check_completion(slot)
	em.scan_completions()
	assert fence.signals == 1, 'completion is signaled only once'
	em.free_stamp(slot)
	if _ := em.next_stamp_value(slot) {
		assert false, 'unowned slot advanced'
	}
	println('AGX events: initial slot counters, 300 slot reuses, stale completion isolation, counter wrap and fence signaling passed')
}
