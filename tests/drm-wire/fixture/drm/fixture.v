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
	gem_close fn (&DrmDevice, voidptr, u32) int = unsafe { nil }
	gem_close_request fn (&DrmDevice, voidptr, &ioctl.DrmGemClose) int = unsafe { nil }
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
const page_size = u64(4096)

fn account_activity(_ &DrmDevice, _ u32) { activity_calls++ }

fn drm_ioctl(dev &DrmDevice, cmd u32, data voidptr, client voidptr) int {
	return match cmd {
		ioctl.drm_ioctl_version { ioctl_version(dev, data) }
		ioctl.drm_ioctl_get_cap { ioctl_get_cap(dev, data) }
		ioctl.drm_ioctl_gem_close { ioctl_gem_close(dev, client, data) }
		ioctl.drm_ioctl_mode_create_dumb, ioctl.drm_ioctl_mode_map_dumb, ioctl.drm_ioctl_mode_destroy_dumb {
			ioctl_dumb_buffer(dev, cmd, client, data)
		}
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
	for direction := u32(0); direction < 4; direction++ {
		close_layout := ioctl_layout(&device, ioctl.drm_ioctl_gem_close, 4, direction, 0) or {
			panic('GEM_CLOSE layout')
		}
		assert close_layout.extensible && close_layout.direction == (direction & ioctl_write)
		assert ioctl_buffer_size(&close_layout, 4) == 8
		assert ioctl_buffer_size(&close_layout, 16) == if close_layout.direction == 0 { u32(8) } else { u32(16) }
	}
	for cmd, size in {
		ioctl.drm_ioctl_prime_handle_to_fd: u32(12)
		ioctl.drm_ioctl_prime_fd_to_handle: 12
		ioctl.drm_ioctl_mode_create_dumb: 32
		ioctl.drm_ioctl_mode_map_dumb: 16
		ioctl.drm_ioctl_mode_destroy_dumb: 4
		ioctl.drm_ioctl_syncobj_create: 8
		ioctl.drm_ioctl_syncobj_destroy: 8
		ioctl.drm_ioctl_syncobj_reset: 16
		ioctl.drm_ioctl_syncobj_signal: 16
		ioctl.drm_ioctl_syncobj_query: 24
		ioctl.drm_ioctl_syncobj_transfer: 32
		ioctl.drm_ioctl_syncobj_timeline_signal: 24
	} {
		for direction := u32(0); direction < 4; direction++ {
			layout := ioctl_layout(&device, cmd, size - 4, direction, 0) or { panic('core read/write layout') }
			assert layout.extensible && layout.direction == direction && layout.size == size
			assert ioctl_buffer_size(&layout, size - 4) == size
			assert ioctl_buffer_size(&layout, size + 8) == if direction == 0 { size } else { size + 8 }
		}
	}
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
	check_dumb_node_access()
	check_dumb_create_geometry()
	check_gem_close_dispatch()
}

fn close_fixture_gem(_ &DrmDevice, client voidptr, name u32) int {
	if client != voidptr(4) { return -int(errno.enodev) }
	return if name == 7 { 0 } else { -int(errno.enoent) }
}

fn check_gem_close_dispatch() {
	unsupported_driver := DrmDriver{gem_close: close_fixture_gem}
	unsupported_device := DrmDevice{driver: &unsupported_driver}
	mut unsupported := DrmNode{dev: &unsupported_device}
	no_owner_driver := DrmDriver{features: driver_gem}
	no_owner_device := DrmDevice{driver: &no_owner_driver}
	mut no_owner := DrmNode{dev: &no_owner_device}
	driver := DrmDriver{features: driver_gem, gem_close: close_fixture_gem}
	device := DrmDevice{driver: &driver}
	mut node := DrmNode{dev: &device}
	command := u64(0x40086409)
	mut request := ioctl.DrmGemClose{handle: 7, pad: 0xffffffff}
	expect_error(mut unsupported, command, unsafe { &request }, errno.eopnotsupp)
	expect_error(mut no_owner, command, unsafe { &request }, errno.einval)
	expect_error(mut node, command, unsafe { &request }, errno.enodev)
	assert (node.ioctl(voidptr(4), command, unsafe { &request }) or { panic('GEM close') }) == 0
	request.handle = 8
	if _ := node.ioctl(voidptr(4), command, unsafe { &request }) { panic('expected missing GEM handle') }
	assert errno.get() == errno.einval
	println('DRM GEM_CLOSE: feature gate, client lookup, padding and errno passed')
}

fn observe_dumb_create(_ &DrmDevice, _ voidptr, data voidptr) int {
	mut request := unsafe { &ioctl.DrmModeCreateDumb(data) }
	assert request.handle == 0 && request.pitch == 0 && request.size == 0
	request.handle = 1
	return 0
}

fn check_dumb_create_geometry() {
	driver := DrmDriver{ioctls: [DrmIoctl{cmd: ioctl.drm_ioctl_mode_create_dumb, handler: observe_dumb_create}]}
	device := DrmDevice{driver: &driver}
	mut node := DrmNode{dev: &device}
	command := u64(0xc02064b2)
	max_aligned := ~u32(0) & ~u32(page_size - 1)
	for geometry in [ioctl.DrmModeCreateDumb{width: 1, height: 1, bpp: ~u32(0) - 7},
		ioctl.DrmModeCreateDumb{width: 1 << 30, height: 1, bpp: 32},
		ioctl.DrmModeCreateDumb{width: 1 << 20, height: 1 << 10, bpp: 32},
		ioctl.DrmModeCreateDumb{width: max_aligned + 1, height: 1, bpp: 8}]! {
		mut request := ioctl.DrmModeCreateDumb{...geometry, handle: 9, pitch: 9, size: 9}
		expect_error(mut node, command, unsafe { &request }, errno.einval)
		assert request.handle == 0 && request.pitch == 0 && request.size == 0
	}
	mut valid := ioctl.DrmModeCreateDumb{width: max_aligned, height: 1, bpp: 8, handle: 9, pitch: 9, size: 9}
	assert (node.ioctl(unsafe { nil }, command, unsafe { &valid }) or { panic('largest aligned size') }) == 0
	assert valid.handle == 1
	println('DRM dumb-buffer geometry: stride, size, page rounding and zeroed driver outputs passed')
}

fn check_dumb_node_access() {
	driver := DrmDriver{}
	device := DrmDevice{driver: &driver}
	mut render := DrmNode{dev: &device, render: true}
	mut primary := DrmNode{dev: &device}
	mut request := [32]u8{init: 0xab}
	for encoded in [u64(0xc02064b2), 0xc01064b3, 0xc00464b4]! {
		expect_error(mut primary, encoded, &request[0], errno.enosys)
		expect_error(mut render, encoded, &request[0], errno.eacces)
		assert request[0] == 0xab
		expect_error(mut render, encoded, unsafe { nil }, errno.efault)
	}
	mut create := ioctl.DrmModeCreateDumb{width: 1, height: 2, bpp: 32, handle: 9, pitch: 9, size: 9}
	expect_error(mut primary, u64(0xc02064b2), unsafe { &create }, errno.enosys)
	assert create.handle == 0 && create.pitch == 0 && create.size == 0
	assert create.width == 1 && create.height == 2 && create.bpp == 32
	mut mapping := ioctl.DrmModeMapDumb{handle: 9, offset: 9}
	expect_error(mut primary, u64(0xc01064b3), unsafe { &mapping }, errno.enosys)
	assert mapping.handle == 9 && mapping.offset == 0
	expect_error(mut render, u64(0x802064b3), unsafe { nil }, errno.efault)
	expect_error(mut render, u64(0x802064b3), &request[0], errno.eacces)
	assert request[0] == 0 && request[31] == 0
	println('DRM dumb-buffer permissions: render denial, copy faults and primary dispatch passed')
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
		cap = ioctl.DrmGetCap{capability: ioctl.drm_cap_prime}
		assert (node.ioctl(voidptr(1), u64(0xc010640c), unsafe { &cap }) or { panic('GET_CAP PRIME probe') }) == 0
		assert cap.value == ioctl.drm_prime_cap_import | ioctl.drm_prime_cap_export
		for capability, value in {
			ioctl.drm_cap_dumb_buffer: u64(1)
			ioctl.drm_cap_dumb_preferred_depth: 32
			ioctl.drm_cap_dumb_prefer_shadow: 0
		} {
			cap = ioctl.DrmGetCap{capability: capability, value: ~u64(0)}
			if features & driver_dumb_buffer != 0 {
				assert (node.ioctl(voidptr(1), u64(0xc010640c), unsafe { &cap }) or { panic('GET_CAP display probe') }) == 0
				assert cap.value == value
			} else {
				expect_error(mut node, u64(0xc010640c), unsafe { &cap }, errno.eopnotsupp)
				assert cap.capability == capability && cap.value == 0
			}
		}
		cap = ioctl.DrmGetCap{capability: ~u64(0), value: ~u64(0)}
		expect_error(mut node, u64(0xc010640c), unsafe { &cap }, if features & driver_dumb_buffer != 0 {
			errno.einval
		} else {
			errno.eopnotsupp
		})
		assert cap.capability == ~u64(0) && cap.value == 0
	}
	memory.fail_next(false)
	assert memory.outstanding() == 0
	println('DRM GET_CAP: render and display capability replies and errors passed')
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
