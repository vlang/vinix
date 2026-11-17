module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import aarch64.timer

fn C.__asan_poison_memory_region(voidptr, usize)
fn C.__asan_unpoison_memory_region(voidptr, usize)

fn context_case(abi hw.FirmwareAbi, mode int, initial u32, private_count int, readonly_count int, late bool, refuse_map bool) {
	mut header := channel.RingHeader{read_ptr: initial, write_ptr: initial}
	mut ring := [256]fw.FwDeviceControlMsg{}
	mut manager := GpuManager{state: .running, mode: mode, hw_config: hw.HwConfig{gpu_gen: if mode == 14 { .g17 } else { .g13 }, firmware_abi: abi},
		g13_private: alloc.new_heap_with_explicit_gc('private', alloc.g13_private_start, alloc.g13_private_end),
		g13_gpu_readonly: alloc.new_heap_with_explicit_gc('readonly', alloc.g13_gpu_readonly_start, alloc.g13_gpu_readonly_end),
		channels: GpuChannels{device_ctrl: channel.new_tx_channel('context', 1, u64(&header), 1, u64(&ring), 256, 48)}, context_refuse_map: refuse_map}
	mut old_private := []&alloc.Allocation{}; mut old_readonly := []&alloc.Allocation{}
	old_private.flags |= .noslices; old_readonly.flags |= .noslices
	for i in 0 .. private_count {
		va := manager.g13_private.alloc(u64(i + 1), 0) or { panic('private garbage') }
		old_private << manager.g13_private.allocations.last(); manager.g13_private.release(va)
	}
	for i in 0 .. readonly_count {
		va := manager.g13_gpu_readonly.alloc(u64(i + 1), 0) or { panic('readonly garbage') }
		old_readonly << manager.g13_gpu_readonly.allocations.last(); manager.g13_gpu_readonly.release(va)
	}
	pin_p := manager.g13_private.alloc(1, 0) or { panic('private pin') }; pp := manager.g13_private.allocations.last()
	pin_r := manager.g13_gpu_readonly.alloc(1, 0) or { panic('readonly pin') }; rp := manager.g13_gpu_readonly.allocations.last()
	if late { manager.late_va = pin_p; manager.late_ro_va = pin_r }
	mut data := [64]u8{}
	for i in 0 .. 64 { data[i] = u8(i * 3 + mode) }
	address := alloc.g13_shared_start + u64(initial + 1) * alloc.gpu_page_size
	expected := expected_context(abi, &data, address)
	mut queue := G13QueueResources{context: SharedBuffer{va: address, phys: unsafe { u64(&data[0]) }, size: 64, mapped: true}}
	context_test_queue = unsafe { &queue }; context_test_unpublished = false; active = unsafe { &manager }
	timer.on_tick(acknowledge); timer.reset()
	if mode == 6 { header.read_ptr = (initial + 1) % 256 }
	if mode == 7 { header.write_ptr = 256 }
	if mode == 8 { manager.hw_config.firmware_abi = .unknown }
	if mode == 9 { manager.state = .starting }
	if mode == 10 { queue.context.mapped = false }
	if mode == 11 { queue.context.phys = 0 }
	if mode == 12 { queue.context.va = 0 }
	if mode == 13 { queue.context.size = 63 }
	if mode == 15 { manager.state = .error }
	if mode == 16 { manager.state = .stopped }
	manager.lock.acquire()
	result := manager.free_g13_queue_resources_locked(mut queue, true)
	success := mode in [0, 1]!
	unpublished := mode >= 6
	assert result == (success && !refuse_map), 'queue release must depend on context acknowledgement and mapping cleanup'
	assert queue.context_retirement == if success { G13ContextRetirement.complete } else if unpublished { G13ContextRetirement.fresh } else { G13ContextRetirement.pending },
		'publication acceptance must preserve retirement state'
	assert manager.context_map_calls == if success { 1 } else { 0 }
	assert manager.context_backing_calls == if result { 1 } else { 0 }
	for record in old_private { assert (C.__asan_address_is_poisoned(record) != 0) == success, 'only acknowledged context retirement may collect captured private garbage' }
	for record in old_readonly { assert (C.__asan_address_is_poisoned(record) != 0) == success, 'each heap must use its own captured count' }
	assert C.__asan_address_is_poisoned(pp) == 0 && C.__asan_address_is_poisoned(rp) == 0, 'captured collection must preserve live and later-released pins'
	if mode < 6 {
		for i in 0 .. 48 { assert unsafe { (&u8(&ring[initial]))[i] } == expected[i], 'published context command must preserve the raw firmware IDs and pointer' }
		assert pp.in_use == !late && rp.in_use == !late, 'post-snapshot releases must actually execute and remain reserved'
	}
	if success && refuse_map {
		assert !queue.context.mapped && !queue.released
		// UAT retries must not read context bytes or collect a second snapshot.
		C.__asan_poison_memory_region(&data[0], 64)
		manager.g13_private.release(pin_p); manager.g13_gpu_readonly.release(pin_r)
		before := manager.doorbells; manager.context_refuse_map = false
		assert manager.free_g13_queue_resources_locked(mut queue, true), 'complete UAT retries must skip context bytes and repeated collection'
		assert manager.doorbells == before && manager.context_map_calls == 2 && manager.context_backing_calls == 1
		assert C.__asan_address_is_poisoned(pp) == 0 && C.__asan_address_is_poisoned(rp) == 0, 'complete retries must not collect later releases'
		C.__asan_unpoison_memory_region(&data[0], 64)
	} else if !success && !unpublished {
		before := manager.doorbells; before_wp := header.write_ptr
		header.read_ptr = header.write_ptr; manager.state = .running; manager.mode = 0
		manager.channels.device_ctrl.faulted = 0
		assert !manager.free_g13_queue_resources_locked(mut queue, true), 'published retirement failure must never replay possibly recycled IDs'
		assert manager.doorbells == before && header.write_ptr == before_wp && queue.context.mapped && !queue.released
		manager.state = .stopped; context_test_unpublished = true
		assert manager.free_g13_queue_resources_locked(mut queue, false)
		assert manager.context_backing_calls == 1 && manager.context_map_calls == 0
	} else if unpublished {
		assert manager.doorbells == 0 && manager.context_backing_calls == 0
		header.read_ptr = initial; header.write_ptr = initial; manager.channels.device_ctrl.faulted = 0
		manager.state = .running; manager.mode = 0; manager.hw_config = hw.HwConfig{gpu_gen: .g13, firmware_abi: abi}
		manager.context_refuse_map = false; queue.context.mapped = true
		queue.context.va = address; queue.context.phys = unsafe { u64(&data[0]) }; queue.context.size = 64
		assert manager.free_g13_queue_resources_locked(mut queue, true), 'unpublished retirement failure must remain retryable after transport/input repair'
		assert manager.doorbells == 1 && manager.context_backing_calls == 1
	}
	before := manager.context_backing_calls
	assert manager.free_g13_queue_resources_locked(mut queue, true) && manager.context_backing_calls == before
	manager.lock.release()
	mut heaps := [&manager.g13_private, &manager.g13_gpu_readonly]!
	for mut heap in heaps { for record in heap.allocations { if record.in_use { heap.release(record.va) } }; heap.gc(); unsafe { heap.allocations.free() } }
	unsafe { old_private.free(); old_readonly.free() }
	active = unsafe { nil }; context_test_queue = unsafe { nil }; timer.on_tick(fn () {})
}
fn check_unpublished_context() {
	mut manager := GpuManager{state: .starting}
	mut data := [64]u8{}
	mut queue := G13QueueResources{context: SharedBuffer{va: 1, phys: unsafe { u64(&data[0]) }, size: 64, mapped: true}}
	context_test_queue = unsafe { &queue }; context_test_unpublished = true
	assert manager.free_g13_queue_resources_locked(mut queue, false)
	assert manager.doorbells == 0 && manager.context_map_calls == 0 && manager.context_backing_calls == 1
	context_test_queue = unsafe { nil }; context_test_unpublished = false
}
pub fn check_context_retirement() {
	check_context_wire(); check_unpublished_context()
	mut cases := 0
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! { for mode in 0 .. 17 { for initial in [u32(0), 254, 255]! {
		for pc in [0, 1, 3]! { for rc in [0, 2, 5]! { for late in [false, true]! { for refuse in [false, true]! {
			context_case(abi, mode, initial, pc, rc, late, refuse); cases++
		} } } }
	} } }
	assert cases == 3672
	println('AGX context retirement: 3672 real queue/heap/channel cases gate unmapping, retain ambiguous publication, preserve retry/GC snapshots and release backing once')
}
