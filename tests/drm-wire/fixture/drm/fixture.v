@[has_globals]
module drm

import usercopy
import memory
import errno

struct DrmIoctl {
	cmd        u32
	size       u32
	direction  u32
	abi        u32
	extensible bool
	flags      u32
	handler    fn (&DrmDevice, voidptr, voidptr) int = unsafe { nil }
}

struct DrmDriver {
	ioctls    []DrmIoctl
	ioctl_abi fn (&DrmDevice, voidptr) u32 = unsafe { nil }
}

struct DrmDevice {
	driver     &DrmDriver = unsafe { nil }
	registered bool       = true
}

struct DrmNode {
	dev &DrmDevice
}

__global handler_status = 0
__global handler_calls = 0
__global activity_calls = 0
__global handler_input = u32(0)

fn account_activity(_ &DrmDevice, _ u32) { activity_calls++ }

fn drm_ioctl(_ &DrmDevice, _ u32, _ voidptr, _ voidptr) int { return -95 }

fn modern_abi(_ &DrmDevice, _ voidptr) u32 { return 2 }

fn handle(_ &DrmDevice, _ voidptr, data voidptr) int {
	mut word := unsafe { &u32(data) }
	handler_input = *word
	unsafe { *word += 0x100 }
	handler_calls++
	return handler_status
}

fn common_ioctl_layout(cmd u32) ?DrmIoctlLayout {
	if cmd == 9 { return DrmIoctlLayout{ size: 24, direction: 3 } }
	return none
}

pub fn run_checks() {
	check_node_transport()
	driver := DrmDriver{
		ioctls: [DrmIoctl{ cmd: 0x41, size: 32, direction: 3, abi: 1 },
			DrmIoctl{ cmd: 0x41, size: 16, direction: 3, abi: 2, extensible: true },
			DrmIoctl{ cmd: 9 }]
	}
	device := DrmDevice{ driver: &driver }
	assert (ioctl_layout(&device, 0x41, 32, 3, 1) or { panic('legacy layout') }).driver_index == 0
	assert (ioctl_layout(&device, 0x41, 16, 3, 0) or { panic('new layout') }).driver_index == 1
	assert (ioctl_layout(&device, 0x41, 32, 3, 2) or { panic('extended layout') }).driver_index == 1
	assert (ioctl_layout(&device, 9, 24, 3, 0) or { panic('metadata fallback') }).driver_index == -1
	if _ := ioctl_layout(&device, 0x41, 16, 3, 1) {
		assert false
	}
	if _ := ioctl_layout(&device, 0x41, 32, 0, 1) {
		assert false
	}
	for direction := u32(0); direction < 4; direction++ {
		layout := ioctl_layout(&device, 0x41, 32, direction, 2) or { panic('direction intersection') }
		assert layout.direction == direction
		assert ioctl_buffer_size(&layout, 32) == if direction == 0 { u32(16) } else { u32(32) }
		assert ioctl_buffer_size(&layout, 8) == 16
	}
	assert ioctl_buffer_size(&DrmIoctlLayout{ size: 16 }, 160) == 16
	readonly_driver := DrmDriver{ ioctls: [DrmIoctl{ cmd: 0x42, size: 16, direction: 2, abi: 2, extensible: true }] }
	readonly_device := DrmDevice{ driver: &readonly_driver }
	for direction := u32(0); direction < 4; direction++ {
		layout := ioctl_layout(&readonly_device, 0x42, 32, direction, 2) or { panic('readonly direction') }
		assert layout.direction == (direction & 2)
	}
	if _ := ioctl_layout(&device, 0x41, 32, 3, 3) {
		assert false
	}
	mut input := [164]u8{}
	input[0] = 0x12
	input[1] = 0x34
	mut buffer := [16]u8{init: 0xaa}
	assert copy_ioctl_input(unsafe { &buffer[0] }, 12, unsafe { u64(&input[0]) }, 4) == 0
	assert buffer[0] == 0x12 && buffer[1] == 0x34 && buffer[4] == 0 && buffer[11] == 0
	assert buffer[12] == 0xaa, 'kernel buffer guard was overwritten'
	mut extended := [164]u8{init: 0xaa}
	input[159] = 1
	assert copy_ioctl_input(unsafe { &extended[0] }, 160, unsafe { u64(&input[0]) }, 160) == 0
	assert extended[159] == 1 && extended[160] == 0xaa
	mut echo := [164]u8{init: 0xbb}
	assert copy_ioctl_output(unsafe { u64(&echo[0]) }, unsafe { &extended[0] }, 160, 160)
	assert echo[159] == 1 && echo[160] == 0xbb, 'unknown read/write bytes must be echoed unchanged'
	usercopy.fail_at(unsafe { u64(&input[12]) })
	assert copy_ioctl_input(unsafe { &extended[0] }, 160, unsafe { u64(&input[0]) }, 160) == -14
	usercopy.fail_at(0)
	assert copy_ioctl_input(unsafe { &buffer[0] }, 12, ~u64(0) - 2, 4) == -14
	buffer[0] = 0x12
	mut output := [164]u8{init: 0xbb}
	assert copy_ioctl_output(unsafe { u64(&output[0]) }, unsafe { &buffer[0] }, 12, 4)
	assert output[0] == 0x12 && output[4] == 0xbb
	assert copy_ioctl_output(unsafe { u64(&output[0]) }, unsafe { &buffer[0] }, 12, 160)
	assert output[12] == 0 && output[159] == 0 && output[160] == 0xbb
	assert !copy_ioctl_output(~u64(0) - 2, unsafe { &buffer[0] }, 12, 4)
	assert copy_ioctl_input(unsafe { &buffer[0] }, 12, 0, 0) == 0
	assert copy_ioctl_output(0, unsafe { &buffer[0] }, 12, 0)
	println('DRM wire: ABI dispatch, direction intersections, legacy metadata fallback, zero extension, unknown-tail echo, bounds and copy faults passed')
}

fn expect_error(mut node DrmNode, request u64, data voidptr, code u64) {
	errno.set(0)
	if _ := node.ioctl(unsafe { nil }, request, data) { panic('expected ioctl failure') }
	assert errno.get() == code
	assert memory.outstanding() == 0
}

fn check_node_transport() {
	driver := DrmDriver{
		ioctl_abi: modern_abi
		ioctls:    [DrmIoctl{
			cmd:        0x41
			size:       16
			direction:  3
			abi:        2
			extensible: true
			flags:      ioctl_no_activity
			handler:    handle
		}]
	}
	device := DrmDevice{ driver: &driver }
	mut node := DrmNode{ dev: &device }
	mut bytes := [40]u8{}
	bytes[0] = 7
	bytes[31] = 0xab
	base := u64(0x41) | (u64(`d`) << 8) | (u64(32) << 16)
	handler_status = -22
	expect_error(mut node, base | (u64(3) << 30), unsafe { &bytes[0] }, 22)
	assert handler_input == 7 && bytes[1] == 1 && bytes[31] == 0xab
	assert activity_calls == 0, 'failed ioctls must not count as successful activity'
	handler_status = 0
	bytes[0] = 99
	assert (node.ioctl(unsafe { nil }, base | (u64(2) << 30), unsafe { &bytes[0] }) or { panic('read ioctl') }) == 0
	assert handler_input == 0 && bytes[0] == 0 && bytes[1] == 1 && bytes[31] == 0
	bytes[0] = 99
	assert (node.ioctl(unsafe { nil }, base | (u64(1) << 30), unsafe { &bytes[0] }) or { panic('write ioctl') }) == 0
	assert handler_input == 355 && bytes[0] == 99 && bytes[1] == 1
	assert (node.ioctl(unsafe { nil }, base, unsafe { nil }) or { panic('no-copy ioctl') }) == 0
	assert handler_input == 0
	assert activity_calls == 0, 'new command numbers must not use legacy activity classification'
	calls := handler_calls
	large_request := (base & ~(u64(0x3fff) << 16)) | (u64(160) << 16) | (u64(3) << 30)
	memory.fail_next(true)
	expect_error(mut node, large_request, unsafe { &bytes[0] }, 12)
	memory.fail_next(false)
	assert handler_calls == calls
	usercopy.fail_at(unsafe { u64(&bytes[31]) })
	expect_error(mut node, base | (u64(3) << 30), unsafe { &bytes[0] }, 14)
	assert handler_calls == calls, 'faulting input must not reach the handler'
	handler_status = -22
	expect_error(mut node, base | (u64(2) << 30), unsafe { &bytes[0] }, 14)
	assert handler_calls == calls + 1, 'output copy faults override the driver errno'
	usercopy.fail_at(0)
	assert memory.outstanding() == 0
	handler_status = 0
	mut large := [164]u8{}
	large[159] = 0xcd
	assert (node.ioctl(unsafe { nil }, large_request, unsafe { &large[0] }) or { panic('heap ioctl') }) == 0
	assert large[1] == 1 && large[159] == 0xcd && memory.outstanding() == 0
	memory.fail_next(true)
	assert (node.ioctl(unsafe { nil }, base, unsafe { nil }) or { panic('stack fast path') }) == 0
	memory.fail_next(false)
	expect_error(mut node, base | (u64(3) << 30), unsafe { nil }, 14)
	handler_status = -22
	legacy_driver := DrmDriver{
		ioctls: [DrmIoctl{ cmd: 0x41, size: 16, direction: 3, abi: 1, handler: handle }]
	}
	legacy_device := DrmDevice{ driver: &legacy_driver }
	mut legacy := DrmNode{ dev: &legacy_device }
	bytes[0] = 7
	bytes[1] = 0
	legacy_request := u64(0x41) | (u64(`d`) << 8) | (u64(16) << 16) | (u64(3) << 30)
	expect_error(mut legacy, legacy_request, unsafe { &bytes[0] }, 22)
	assert bytes[0] == 7 && bytes[1] == 0, 'legacy errors retain their original no-output behavior'
	calls_before_legacy_reject := handler_calls
	expect_error(mut legacy, base | (u64(3) << 30), unsafe { &bytes[0] }, 22)
	expect_error(mut legacy, legacy_request & ~(u64(1) << 30), unsafe { &bytes[0] }, 22)
	assert handler_calls == calls_before_legacy_reject
	empty_driver := DrmDriver{
		ioctls: [DrmIoctl{ cmd: 0x41, size: 16, direction: 3, extensible: true }]
	}
	empty_device := DrmDevice{ driver: &empty_driver }
	mut empty := DrmNode{ dev: &empty_device }
	memory.fail_next(true)
	expect_error(mut empty, base | (u64(3) << 30), unsafe { nil }, 22)
	memory.fail_next(false)
	println('DRM node: unknown-byte echo, zeroed reads, direction intersections, error outputs, fault precedence and fallible buffer lifetime passed')
}
