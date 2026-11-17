module gpu

import gpu.agx.alloc
import gpu.agx.channel
import gpu.agx.fw
import gpu.agx.hw
import aarch64.timer

fn deferred_case(abi hw.FirmwareAbi, mode int, initial u32, order [4]int) {
	mut header := channel.RingHeader{read_ptr: initial, write_ptr: initial}
	mut ring := [256]fw.FwDeviceControlMsg{}
	mut manager := GpuManager{state: .running, mode: mode,
		hw_config: hw.HwConfig{gpu_gen: .g13, firmware_abi: abi},
		g13_private: alloc.new_heap_with_explicit_gc('private', 0x4000, 0x100000),
		g13_gpu_readonly: alloc.new_heap_with_explicit_gc('readonly', 0x4000, 0x100000),
		channels: GpuChannels{device_ctrl: channel.new_tx_channel('defer', 1, u64(&header), 1, u64(&ring), 256, 48)}}
	mut data := [4][64]u8{}
	mut queues := [4]G13QueueResources{}
	for i in 0 .. 4 {
		for j in 0 .. 64 { data[i][j] = u8(i * 13 + j) }
		queues[i].context = SharedBuffer{va: 0xffffffa800004000 + u64(i) * 0x4000,
			phys: unsafe { u64(&data[i][0]) }, size: 64, mapped: true}
	}
	active = unsafe { &manager }; context_test_queue = unsafe { nil }
	timer.on_tick(acknowledge); timer.reset(); manager.lock.acquire()
	for index in order {
		mut queue := unsafe { &queues[index] }
		for _ in 0 .. 3 { assert !manager.defer_g13_context_locked(mut queue), 'retirement request stays deferred and idempotent' }
	}
	assert manager.doorbells == 0, 'retirement requests must never publish before allocator borrow'
	mut cursor := manager.g13_context_head
	for index in order {
		assert cursor == unsafe { &queues[index] }, 'deferred contexts follow release FIFO rather than creation order'
		cursor = cursor.context_next
	}
	assert cursor == unsafe { nil } && manager.g13_context_tail == unsafe { &queues[order[3]] }, 'duplicate retirement must not duplicate or cycle the FIFO'
	manager.state = .starting; manager.collect_g13_context_garbage_locked()
	assert manager.g13_context_head == unsafe { &queues[order[0]] } && manager.doorbells == 0
	manager.state = .running
	if mode == 6 { header.read_ptr = (initial + 1) % 256 }
	if mode == 7 { header.write_ptr = 256 }
	manager.collect_g13_context_garbage_locked()
	first_sent := if mode in [0, 2, 3]! { 4 } else if mode in [4, 5]! { 1 } else { 0 }
	assert manager.doorbells == first_sent
	mut remaining := 0
	cursor = manager.g13_context_head
	for position, index in order {
		queue := unsafe { &queues[index] }
		if position < first_sent {
			assert queue.context_retirement == if mode == 0 { G13ContextRetirement.complete } else { G13ContextRetirement.pending }
			assert queue.context_next == unsafe { nil }, 'consumed snapshot nodes must shed intrusive links'
			expected := expected_context(abi, &data[index], queue.context.va)
			for byte in 0 .. 48 { assert unsafe { (&u8(&ring[(initial + u32(position)) % 256]))[byte] } == expected[byte] }
		} else {
			assert queue.context_retirement == .queued && cursor == queue, 'unpublished failures requeue once in FIFO order'
			cursor = cursor.context_next; remaining++
		}
		assert queue.context.mapped && !queue.released, 'deferred collection must not release queue or VM backing'
	}
	assert cursor == unsafe { nil }
	if remaining == 0 { assert manager.g13_context_head == unsafe { nil } && manager.g13_context_tail == unsafe { nil } }
	// Repair transport and simulate late consumption. Only unpublished nodes
	// may run on this later borrow; pending nodes must never be replayed.
	header.write_ptr = if header.write_ptr < 256 { header.write_ptr } else { initial }
	header.read_ptr = header.write_ptr; manager.channels.device_ctrl.faulted = 0
	manager.state = .running; manager.mode = 0
	manager.collect_g13_context_garbage_locked()
	assert manager.doorbells == first_sent + remaining, 'a detached snapshot must retry each unpublished node at most once per borrow'
	assert manager.g13_context_head == unsafe { nil } && manager.g13_context_tail == unsafe { nil }
	before := manager.doorbells
	manager.collect_g13_context_garbage_locked()
	assert manager.doorbells == before
	for position, index in order {
		mut queue := unsafe { &queues[index] }
		assert queue.context_next == unsafe { nil }
		complete := mode == 0 || position >= first_sent
		assert manager.defer_g13_context_locked(mut queue) == complete
		assert queue.context_retirement == if complete { G13ContextRetirement.complete } else { G13ContextRetirement.pending }
	}
	manager.lock.release(); active = unsafe { nil }; timer.on_tick(fn () {})
}
pub fn check_context_deferral() {
	check_stopped_context_snapshot()
	mut cases := 0
	for a in 0 .. 4 { for b in 0 .. 4 { for c in 0 .. 4 { for d in 0 .. 4 {
		if a == b || a == c || a == d || b == c || b == d || c == d { continue }
		for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial]! { for mode in [0, 2, 3, 4, 5, 6, 7]! {
			for initial in [u32(0), 253, 255]! { deferred_case(abi, mode, initial, [a, b, c, d]!); cases++ }
		} }
	} } } }
	assert cases == 1008
	println('AGX deferred contexts: 1008 four-context FIFO/snapshot/failure cases defer publication, preserve owners and retry only unpublished nodes')
}

fn check_stopped_context_snapshot() {
	mut manager := GpuManager{state: .stopped}
	manager.g13_queues.flags |= .noslices
	mut data := [64]u8{}
	mut queue := G13QueueResources{context: SharedBuffer{va: 0xffffffa800004000,
		phys: unsafe { u64(&data[0]) }, size: 64, mapped: true}}
	manager.lock.acquire()
	manager.g13_queues << &queue
	assert !manager.defer_g13_context_locked(mut queue)
	context_test_queue = unsafe { &queue }; context_test_unpublished = true
	manager.release_all_g13_queue_resources()
	assert queue.released && queue.context_next == unsafe { nil } && manager.g13_queues.len == 0
	assert manager.g13_context_head == unsafe { nil } && manager.g13_context_tail == unsafe { nil }
	assert manager.context_backing_calls == 1 && manager.doorbells == 0
	C.__asan_poison_memory_region(&queue, sizeof(queue))
	manager.state = .running
	manager.collect_g13_context_garbage_locked()
	C.__asan_unpoison_memory_region(&queue, sizeof(queue))
	manager.lock.release(); unsafe { manager.g13_queues.free() }
	context_test_queue = unsafe { nil }; context_test_unpublished = false
}
