// Production queue engine against an in-memory transport. Tests inject actual
// used entries, partial allocation failures and synchronous stack callbacks.
@[has_globals]
module virtio_net

import socket.inet

fn reset_fixture() {
	assert live_allocations == 0
	allocations = 0
	fail_allocation = 0
	bad_ring_bus = 0
	pci_legacy = true
	offer_any_layout = true
	queue_max = 256
	installed = [2]u16{}
	installed_count = 0
	notifications = [2]int{}
	reset_count = 0
	reset_succeeds = true
	disabled = false
	barriers = 0
	virtio_net_ready = false
	inet.reset()
}

fn finish_fixture() {
	stop()
	free_queues()
	assert live_allocations == 0
}

fn rx_completion(position u16, id u32, length u32) {
	entry := rx_queue.used + 4 + u64(position % rx_queue.size) * 8
	unsafe {
		*&u32(entry) = id
		*&u32(entry + 4) = length
	}
}

fn test_start_and_receive_can_synchronously_transmit() {
	reset_fixture()
	assert start()
	assert installed == [u16(256), 256]!
	assert device_status == 7
	assert unsafe { *&u16(rx_queue.avail) } == 1
	assert unsafe { *&u16(tx_queue.avail) } == 1
	assert tx_queue.next_available == 1 // DHCP during attach
	inet.echo()
	rx_completion(0, 0, 74)
	unsafe {
		*&u16(rx_queue.used + 2) = 1
	}
	poll()
	assert inet.received() == 1
	assert tx_queue.next_available == 2 // response during RX, no recursive lock
	assert rx_queue.next_available == 257
	finish_fixture()
}

fn test_all_partial_allocations_are_freed_before_installation() {
	for failure in 1 .. 5 {
		reset_fixture()
		fail_allocation = failure
		assert !start()
		assert live_allocations == 0
		assert installed_count == 0
		assert !virtio_net_ready
	}
}

fn test_unrepresentable_pfn_is_freed_without_installing() {
	for address in [u64(1) << 44, u64(4097)] {
		reset_fixture()
		bad_ring_bus = address
		assert !start()
		assert live_allocations == 0 && installed_count == 0
	}
}

fn test_mmio_still_uses_64_and_absent_poll_is_harmless() {
	reset_fixture()
	poll()
	assert live_allocations == 0 && notifications == [0, 0]!
	pci_legacy = false
	assert start()
	assert installed == [u16(64), 64]!
	finish_fixture()
}

fn test_no_any_layout_is_refused_before_allocating() {
	reset_fixture()
	offer_any_layout = false
	assert !start()
	assert allocations == 0 && installed_count == 0
}

fn test_failed_attach_stops_dma_before_cleanup() {
	reset_fixture()
	inet.deny_attach()
	assert !start()
	assert !virtio_net_ready && disabled && reset_count >= 2
	// Platform probe performs cleanup after the queue engine stops DMA.
	free_queues()
	assert live_allocations == 0
}

fn test_failed_reset_still_disables_dma_before_cleanup() {
	reset_fixture()
	assert start()
	reset_succeeds = false
	stop()
	assert !virtio_net_ready && disabled
	free_queues()
	assert live_allocations == 0
}

fn test_invalid_and_duplicate_rx_ids_are_not_reposted() {
	reset_fixture()
	assert start()
	rx_completion(0, 0x10000, 74)
	rx_completion(1, 0xffffffff, 74)
	rx_completion(2, 256, 74)
	rx_completion(3, 7, 74)
	rx_completion(4, 7, 74)
	rx_completion(5, 8, 3000) // valid ID, bad length: recycle without delivery
	unsafe {
		*&u16(rx_queue.used + 2) = 6
	}
	poll()
	assert inet.received() == 1
	assert rx_queue.last_used == 6
	assert rx_queue.next_available == 258
	assert unsafe { *&u16(rx_queue.avail + 4) } == 7
	assert unsafe { *&u16(rx_queue.avail + 6) } == 8
	finish_fixture()
}

fn test_busy_poller_and_bounded_corrupt_producer() {
	reset_fixture()
	assert start()
	rx_lock.acquire()
	poll() // skips a concurrent RX owner
	rx_lock.release()
	tx_lock.acquire()
	poll() // skips a concurrent sender; RX remains available
	tx_lock.release()
	unsafe {
		*&u16(rx_queue.used + 2) = 257
	}
	poll()
	assert rx_queue.last_used == 0 && rx_queue.next_available == 256
	finish_fixture()
}

fn test_tx_full_reclaim_and_wrap_without_allocations() {
	reset_fixture()
	assert start()
	before := allocations
	frame := [64]u8{}
	for _ in 1 .. 256 {
		assert send(unsafe { &frame[0] }, 64) == 0
	}
	assert send(unsafe { &frame[0] }, 64) == -1
	unsafe {
		*&u32(tx_queue.used + 4) = 3
		*&u16(tx_queue.used + 2) = 1
	}
	assert send(unsafe { &frame[0] }, 64) == 0
	assert !tx_queue.free[3]
	tx_queue.last_used = 65535
	unsafe {
		*&u32(tx_queue.used + 4 + 255 * 8) = 0xffffffff
		*&u16(tx_queue.used + 2) = 0
	}
	poll()
	assert tx_queue.last_used == 0
	assert allocations == before
	finish_fixture()
}
