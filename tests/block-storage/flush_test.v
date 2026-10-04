module virtio_blk

import x86.hpet as hpet_clock

__global simulated_device &VirtioBlockDevice
__global withhold_completion bool
__global status_code u8

fn hardware_tick() {
	mut device := simulated_device
	if !withhold_completion && device.next_available != device.last_used {
		unsafe {
			*&u8(device.request_virt + sizeof(RequestHeader)) = status_code
			*&u16(device.used + 2) = device.next_available
		}
	}
}

fn setup() &VirtioBlockDevice {
	request := u64(unsafe { calloc(1, 4096) })
	mut device := &VirtioBlockDevice{
		base:            u64(unsafe { calloc(1, 4096) })
		desc:            u64(unsafe { calloc(1, 4096) })
		avail:           u64(unsafe { calloc(1, 4096) })
		used:            u64(unsafe { calloc(1, 4096) })
		queue_size:      8
		request_virt:    request
		request_phys:    request
		ready:           true
		flush_supported: true
	}
	simulated_device = device
	withhold_completion = false
	status_code = 0
	hpet_clock.set_hook(hardware_tick)
	return device
}

fn test_flush_has_no_data_descriptor_and_propagates_status() {
	mut device := setup()
	device.sync(unsafe { nil }) or { assert false }
	header := unsafe { &RequestHeader(device.request_virt) }
	assert header.type_ == 4
	assert header.sector == 0
	assert unsafe { *&u64(device.desc) } == device.request_phys
	assert unsafe { *&u32(device.desc + 8) } == sizeof(RequestHeader)
	assert unsafe { *&u16(device.desc + 12) } == descriptor_next
	assert unsafe { *&u16(device.desc + 14) } == 2
	status := device.desc + 2 * 16
	assert unsafe { *&u64(status) } == device.request_phys + sizeof(RequestHeader)
	assert unsafe { *&u32(status + 8) } == 1
	assert unsafe { *&u16(status + 12) } == descriptor_write
	assert device.last_used == 1
	status_code = 1
	mut failed := false
	device.sync(unsafe { nil }) or { failed = true }
	assert failed
	assert device.last_used == 2
}

fn test_unsupported_flush_cannot_claim_persistence() {
	mut device := setup()
	device.flush_supported = false
	mut failed := false
	device.sync(unsafe { nil }) or { failed = true }
	assert failed
	assert device.next_available == 0
}

fn test_timed_out_flush_keeps_buffers_until_late_completion() {
	mut device := setup()
	withhold_completion = true
	mut failed := false
	device.sync(unsafe { nil }) or { failed = true }
	assert failed
	assert device.next_available == 1
	assert device.last_used == 0
	// Repeated timeouts must not overwrite or submit the outstanding request.
	device.sync(unsafe { nil }) or {}
	assert device.next_available == 1
	assert device.last_used == 0
	withhold_completion = false
	device.sync(unsafe { nil }) or { assert false }
	assert device.next_available == 2
	assert device.last_used == 2
}
