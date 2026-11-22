@[has_globals]
module drm

import drm.ioctl
import usercopy
import memory
import errno
import klock

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
	name string
	desc string
	date string = default_driver_date
	major int
	minor int
	patchlevel int
	features  u32
	ioctls    []DrmIoctl
	ioctl_abi fn (&DrmDevice, voidptr) u32 = unsafe { nil }
	file_close fn (&DrmDevice, voidptr) = unsafe { nil }
	mmap voidptr = unsafe { nil }
	mmap_admit fn (&DrmDevice, voidptr, u64, u64, bool) int = unsafe { nil }
	mmap_retain fn (&DrmDevice, voidptr, u64, u64) bool = unsafe { nil }
	mmap_release fn (&DrmDevice, voidptr, u64, u64) = unsafe { nil }
	mmap_no_expand bool
}

struct DrmDevice {
	driver_data voidptr
	dev_id u32
	driver     &DrmDriver = unsafe { nil }
mut:
	registered bool       = true
	node &DrmNode = unsafe { nil }
	render_node &DrmNode = unsafe { nil }
	clients_lock klock.Lock
	clients_first &NodeHandle = unsafe { nil }
	clients_last &NodeHandle = unsafe { nil }
	clients_count int
}

struct NodeStat {
mut:
	size i64
	blocks i64
	blksize i64
	rdev u64
	mode u32
	nlink u64
}

fn update_client_process(_ voidptr) {}

struct DrmNode {
	dev &DrmDevice
mut:
	stat NodeStat
	render bool
	can_mmap bool
	box &NodeBox = unsafe { nil }
	refcount int
}

__global handler_status = 0
__global handler_calls = 0
__global activity_calls = 0
__global handler_input = u32(0)

fn account_activity(_ &DrmDevice, _ u32) { activity_calls++ }

fn drm_ioctl(dev &DrmDevice, cmd u32, data voidptr, _ voidptr) int {
	return match cmd {
		ioctl.drm_ioctl_version { ioctl_version(dev, data) }
		ioctl.drm_ioctl_get_cap { ioctl_get_cap(dev, data) }
		ioctl.drm_ioctl_syncobj_wait, ioctl.drm_ioctl_syncobj_timeline_wait { handle_wait(cmd, data) }
		ioctl.drm_ioctl_syncobj_handle_to_fd, ioctl.drm_ioctl_syncobj_fd_to_handle { handle_descriptor(cmd, data) }
		else { -95 }
	}
}

fn modern_abi(_ &DrmDevice, _ voidptr) u32 { return 2 }

fn handle(_ &DrmDevice, _ voidptr, data voidptr) int {
	mut word := unsafe { &u32(data) }
	handler_input = *word
	unsafe { *word += 0x100 }
	handler_calls++
	return handler_status
}

pub fn run_checks() {
	check_registration()
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
	assert (ioctl_layout(&device, 9, 8, ioctl_write, 0) or { panic('metadata fallback') }).driver_index == -1
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
	check_wait_transport()
	check_descriptor_transport()
	check_device_capabilities()
	check_agx_version()
	check_core_query_transport()
}

fn check_device_capabilities() {
	assert ioctl.drm_cap_syncobj_timeline == 0x14 && sizeof(ioctl.DrmGetCap) == 16
	assert ioctl.drm_cap_timestamp_monotonic == 0x6
	compute := driver_gem | driver_render | driver_compute
	memory.fail_next(true)
	for index, features in [compute, driver_gem | driver_dumb_buffer, compute | driver_syncobj_timeline]! {
		driver := DrmDriver{features: features}
		dev := DrmDevice{driver: unsafe { &driver }}
		mut node := DrmNode{dev: unsafe { &dev }}
		mut cap := ioctl.DrmGetCap{capability: ioctl.drm_cap_syncobj_timeline, value: ~u64(0)}
		assert (node.ioctl(voidptr(1), u64(0xc010640c), unsafe { &cap }) or { panic('GET_CAP timeline probe') }) == 0
		assert cap.capability == 0x14 && cap.value == if index == 2 { u64(1) } else { u64(0) }
		cap = ioctl.DrmGetCap{capability: ioctl.drm_cap_syncobj}
		assert (node.ioctl(voidptr(1), u64(0xc010640c), unsafe { &cap }) or { panic('GET_CAP binary probe') }) == 0
		assert cap.value == 1
		cap = ioctl.DrmGetCap{capability: ioctl.drm_cap_timestamp_monotonic, value: ~u64(0)}
		assert (node.ioctl(voidptr(1), u64(0xc010640c), unsafe { &cap }) or {
			panic('GET_CAP monotonic timestamp probe')
		}) == 0
		assert cap.capability == ioctl.drm_cap_timestamp_monotonic && cap.value == 1
	}
	memory.fail_next(false)
	assert memory.outstanding() == 0
	println('DRM GET_CAP: timeline discovery, binary syncobjs and monotonic timestamps passed')
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
	foreign := (base & ~u64(0xff00)) | (u64(`x`) << 8)
	unknown := (base & ~u64(0xff)) | u64(0xff)
	expect_error(mut node, foreign, unsafe { nil }, errno.enotty)
	expect_error(mut node, unknown, unsafe { nil }, errno.einval)
	inactive := DrmDevice{driver: &driver, registered: false}
	mut detached := DrmNode{dev: &inactive}
	expect_error(mut detached, foreign, unsafe { nil }, errno.enodev)
	expect_error(mut detached, unknown, unsafe { nil }, errno.enodev)
	check_ioctl_handler_selection()
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

fn check_ioctl_handler_selection() {
	// A shared legacy layout exists for this number, even on a driver
	// without the VirtIO handler.
	request := u64(0xc0106441)
	mut data := [16]u8{}
	buffer := unsafe { &data[0] }
	usercopy.fail_at(u64(buffer))
	driver := DrmDriver{}
	device := DrmDevice{driver: &driver}
	mut node := DrmNode{dev: &device}
	expect_error(mut node, request, buffer, errno.einval)

	legacy_driver := DrmDriver{ioctls: [
		DrmIoctl{cmd: ioctl.drm_virtgpu_map, handler: handle},
		DrmIoctl{cmd: ioctl.drm_ioctl_version, size: 16, direction: 3, handler: handle},
	]}
	legacy_device := DrmDevice{driver: &legacy_driver}
	mut legacy := DrmNode{dev: &legacy_device}
	expect_error(mut legacy, request, buffer, errno.efault)
	usercopy.fail_at(0)
	layout := ioctl_layout(&legacy_device, ioctl.drm_ioctl_version, 16, 3, 0) or {
		panic('core VERSION layout')
	}
	assert layout.size == sizeof(ioctl.DrmVersion) && layout.driver_index == -1
}
