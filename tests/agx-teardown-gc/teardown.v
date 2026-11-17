module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.mmu
import aarch64.timer
import memory

fn (mut manager GpuManager) teardown_buffer(class int) SharedBuffer {
	mut heap := match class { 0 { &manager.g13_private } 1 { &manager.g13_gpu_readonly } 2 { &manager.g13_shared } else { &manager.g13_readonly } }
	address := heap.alloc(1, 0) or { panic('owned buffer') }
	manager.teardown_owned << OwnedBuffer{class: class, record: heap.allocations.last()}
	return SharedBuffer{va: address, phys: u64(manager.teardown_owned.len), size: alloc.gpu_page_size,
		allocator: match class { 0 { buffer_allocator_g13_private } 1 { buffer_allocator_g13_gpu_readonly } 2 { buffer_allocator_g13_shared } else { buffer_allocator_g13_readonly } }, mapped: true}
}
fn (mut manager GpuManager) teardown_call(kind int, invalidate bool, mut queue G13QueueResources,
	mut render G13RenderJobResources, mut compute G13ComputeJobResources) bool {
	return match kind {
		0 { manager.free_g13_render_buffer_locked(mut queue.render_buffer); true }
		1 { manager.free_g13_queue_resources_locked(mut queue, invalidate) }
		2 { manager.free_g13_render_job_locked(mut render, invalidate) }
		else { manager.free_g13_compute_job_locked(mut compute, invalidate) }
	}
}
fn teardown_case(kind int, mode int, abi hw.FirmwareAbi, large bool, invalidate bool, late bool) {
	mut header := channel.RingHeader{}
	mut ring := [256]fw.FwDeviceControlMsg{}
	mut manager := GpuManager{state: .running, hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
		g13_private: alloc.new_heap_with_explicit_gc('private', alloc.g13_private_start, alloc.g13_private_end),
		g13_gpu_readonly: alloc.new_heap_with_explicit_gc('gpu-ro', alloc.g13_gpu_readonly_start, alloc.g13_gpu_readonly_end),
		g13_shared: alloc.new_heap_with_garbage('shared', alloc.g13_shared_start, alloc.g13_shared_end, false),
		g13_readonly: alloc.new_heap_with_garbage('shared-ro', alloc.g13_readonly_start, alloc.g13_readonly_end, false),
		channels: GpuChannels{device_ctrl: channel.new_tx_channel('teardown', 1, u64(&header), 1, u64(&ring), 256, 48)}}
	manager.teardown_owned.flags |= .noslices
	size := if large { u64(16_793_600) } else { alloc.gpu_page_size }
	old_private := manager.g13_private.alloc(size, 0) or { panic('old private') }
	old_readonly := manager.g13_gpu_readonly.alloc(size, 0) or { panic('old readonly') }
	old_p := manager.g13_private.allocations[0]; old_r := manager.g13_gpu_readonly.allocations[0]
	pin_private := manager.g13_private.alloc(1, 0) or { panic('private pin') }
	pin_readonly := manager.g13_gpu_readonly.alloc(1, 0) or { panic('readonly pin') }
	pp := manager.g13_private.allocations[1]; rp := manager.g13_gpu_readonly.allocations[1]
	mut context := mmu.UatContext{}
	mut driver := [8]mmu.UatBuffer{}
	for i in 0 .. 8 { driver[i] = mmu.UatBuffer{id: u32(i)} }
	mut queue := G13QueueResources{}
	mut render := G13RenderJobResources{context: unsafe { &context }, queue: unsafe { &queue }, submitted: true}
	mut compute := G13ComputeJobResources{context: unsafe { &context }, queue: unsafe { &queue }, submitted: true}
	if kind in [0, 1]! {
		queue.render_buffer = G13RenderBufferResources{initialized: true, context: unsafe { &context },
			blocks: [unsafe { &driver[0] }, unsafe { &driver[1] }], block_list: unsafe { &driver[2] }, page_list: unsafe { &driver[3] },
			info: manager.teardown_buffer(0), block_control: manager.teardown_buffer(2), counter: manager.teardown_buffer(2),
			stats: manager.teardown_buffer(2), kernel_buffer: manager.teardown_buffer(2)}
	}
	if kind == 1 {
		for i in 0 .. 3 {
			queue.subqueues[i].info = manager.teardown_buffer(i % 4)
			queue.subqueues[i].ring = manager.teardown_buffer(2)
			queue.subqueues[i].state = manager.teardown_buffer(0)
			queue.subqueues[i].gpu_buffer = manager.teardown_buffer(1)
		}
		queue.notifier = manager.teardown_buffer(0); queue.threshold = manager.teardown_buffer(2)
		queue.notifier_list = manager.teardown_buffer(3); queue.context = manager.teardown_buffer(0)
	} else if kind == 2 {
		render.fragment = manager.teardown_buffer(0); render.vertex = manager.teardown_buffer(0)
		render.barrier = manager.teardown_buffer(0); render.init_buffer = manager.teardown_buffer(2)
		render.fragment_microsequence = manager.teardown_buffer(1); render.vertex_microsequence = manager.teardown_buffer(1)
		render.scene = G13RenderSceneResources{aux_framebuffer: unsafe { &driver[0] }, preempt: unsafe { &driver[1] },
			tilemap: unsafe { &driver[2] }, heapmeta: unsafe { &driver[3] }, user_buffer: unsafe { &driver[4] },
			timestamps: manager.teardown_buffer(2), scene: manager.teardown_buffer(2)}
		render.vertex_event_reserved = true; render.fragment_event_reserved = true; render.scene_reserved = true
		queue.render_buffer.active_scenes = 1; queue.render_buffer.slot_reserved = true; manager.g13_tvb_slots[0] = true
	} else if kind == 3 {
		compute.command = manager.teardown_buffer(0); compute.microsequence = manager.teardown_buffer(1)
		compute.timestamps = manager.teardown_buffer(2); compute.preempt = unsafe { &driver[0] }; compute.event_reserved = true
	}
	manager.g13_private.release(old_private); manager.g13_gpu_readonly.release(old_readonly)
	mut uat := TeardownUat{}; uat_mgr = unsafe { &uat }; active = unsafe { &manager }
	timer.on_tick(acknowledge); timer.reset(); manager.mode = 2; memory.reset()
	manager.lock.acquire(); manager.collect_g13_heap_garbage_locked()
	assert C.__asan_address_is_poisoned(old_p) == 0 && C.__asan_address_is_poisoned(old_r) == 0
	if late && invalidate && kind != 0 {
		manager.teardown_refuse = true
		assert !manager.teardown_call(kind, invalidate, mut queue, mut render, mut compute)
		assert memory.count() == 0 && context.released_mask == 0, 'refused cleanup must retain every owner'
		manager.teardown_refuse = false
	}
	assert manager.teardown_call(kind, invalidate, mut queue, mut render, mut compute)
	assert memory.count() == manager.teardown_owned.len
	assert C.__asan_address_is_poisoned(old_p) == 0 && C.__asan_address_is_poisoned(old_r) == 0,
		'teardown must preserve unrelated pending firmware ranges'
	mut pc := u64(1); mut rc := u64(1)
	for owned in manager.teardown_owned {
		assert (C.__asan_address_is_poisoned(owned.record) != 0) == (owned.class >= 2), 'private teardown must defer metadata while shared release stays immediate'
		if owned.class == 0 { pc++ } else if owned.class == 1 { rc++ }
	}
	count_p, _ := manager.g13_private.garbage(); count_r, _ := manager.g13_gpu_readonly.garbage()
	assert count_p == pc && count_r == rc
	mask := context.released_mask
	assert mask == if kind in [0, 1]! { u64(15) } else if kind == 2 { u64(31) } else { u64(1) }
	assert manager.teardown_call(kind, invalidate, mut queue, mut render, mut compute)
	assert memory.count() == manager.teardown_owned.len && context.released_mask == mask, 'teardown retries must not release ownership twice'
	assert C.__asan_address_is_poisoned(pp) == 0 && C.__asan_address_is_poisoned(rp) == 0 && pp.in_use && rp.in_use
	if late { manager.late_va = pin_private; manager.late_ro_va = pin_readonly }
	manager.mode = mode; timer.reset()
	if mode == 6 { header.read_ptr = (header.write_ptr + 1) % 256 }
	if mode == 7 { header.write_ptr = 256 }
	manager.collect_g13_heap_garbage_locked(); manager.lock.release()
	success := large && mode in [0, 1]!
	assert (C.__asan_address_is_poisoned(old_p) != 0) == success && (C.__asan_address_is_poisoned(old_r) != 0) == success
	for owned in manager.teardown_owned { if owned.class < 2 {
		assert (C.__asan_address_is_poisoned(owned.record) != 0) == success, 'only an acknowledged later barrier may retire teardown metadata'
	} }
	assert C.__asan_address_is_poisoned(pp) == 0 && C.__asan_address_is_poisoned(rp) == 0, 'later releases must survive the captured prefix'
	mut heaps := [&manager.g13_private, &manager.g13_gpu_readonly]!
	for mut heap in heaps { for record in heap.allocations { if record.in_use { heap.release(record.va) } }; heap.gc(); unsafe { heap.allocations.free() } }
	unsafe { manager.g13_shared.allocations.free(); manager.g13_readonly.allocations.free(); manager.teardown_owned.free() }
	active = unsafe { nil }; uat_mgr = unsafe { nil }; timer.on_tick(fn () {})
}
pub fn check_teardown_gc() {
	mut cases := 0
	for kind in 0 .. 4 { for mode in 0 .. 8 { for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! {
		for large in [false, true]! { for invalidate in [false, true]! { for late in [false, true]! {
			teardown_case(kind, mode, abi, large, invalidate, late); cases++
		} } }
	} } }
	assert cases == 512
	println('AGX teardown GC: 512 production teardown/heap/channel cases retain pending ranges, release backing once and collect only acknowledged prefixes')
}
