module drm

import usercopy

struct DrmIoctl {
	cmd        u32
	size       u32
	direction  u32
	abi        u32
	extensible bool
	flags      u32
}

struct DrmDriver {
	ioctls []DrmIoctl
}

struct DrmDevice {
	driver &DrmDriver = unsafe { nil }
}

fn common_ioctl_layout(cmd u32) ?DrmIoctlLayout {
	if cmd == 9 { return DrmIoctlLayout{ size: 24, direction: 3 } }
	return none
}

pub fn run_checks() {
	driver := DrmDriver{
		ioctls: [DrmIoctl{ cmd: 0x41, size: 32, direction: 3, abi: 1 },
			DrmIoctl{ cmd: 0x41, size: 16, direction: 3, abi: 2, extensible: true }, DrmIoctl{ cmd: 9 }]
	}
	device := DrmDevice{ driver: &driver }
	assert (ioctl_layout(&device, 0x41, 32, 3, 1) or { panic('legacy layout') }).driver_index == 0
	assert (ioctl_layout(&device, 0x41, 16, 3, 0) or { panic('new layout') }).driver_index == 1
	assert (ioctl_layout(&device, 0x41, 32, 3, 2) or { panic('extended layout') }).driver_index == 1
	assert (ioctl_layout(&device, 9, 24, 3, 0) or { panic('metadata fallback') }).driver_index == -1
	if _ := ioctl_layout(&device, 0x41, 16, 3, 1) {
		assert false
	}
	if _ := ioctl_layout(&device, 0x41, 32, 0, 0) {
		assert false
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
	assert copy_ioctl_input(unsafe { &buffer[0] }, 12, unsafe { u64(&input[0]) }, 160) == 0
	input[159] = 1
	assert copy_ioctl_input(unsafe { &buffer[0] }, 12, unsafe { u64(&input[0]) }, 160) == -22
	input[159] = 0
	usercopy.fail_at(unsafe { u64(&input[12]) })
	assert copy_ioctl_input(unsafe { &buffer[0] }, 12, unsafe { u64(&input[0]) }, 160) == -14
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
	println('DRM wire: ABI dispatch, legacy metadata fallback, zero extension, unknown tails, bounds and copy faults passed')
}
