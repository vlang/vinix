@[has_globals]
module drm

// Minimal DRM (Direct Rendering Manager) subsystem for Vinix
// Implements only what Asahi GPU and DCP display drivers need.
// Skips legacy mode setting, DRM leases, writeback connectors.

import klock
import katomic
import fs
import stat
import resource
import errno
import event.eventstruct
import drm.gem
import drm.ioctl
import drm.syncobj
import memory
import usercopy

// DRM driver feature flags
pub const driver_gem = u32(0x1)
pub const driver_render = u32(0x8)
pub const driver_compute = u32(0x10)

pub struct DrmIoctl {
pub:
	cmd     u32
	handler fn (&DrmDevice, voidptr, voidptr) int = unsafe { nil }
	flags   u32
}

pub struct DrmDriver {
pub mut:
	name       string
	desc       string
	major      int
	minor      int
	patchlevel int
	features   u32
	ioctls     []DrmIoctl
	file_close fn (&DrmDevice, voidptr) = unsafe { nil }
	gem_close  fn (&DrmDevice, voidptr, u32) int = unsafe { nil }
	mmap       fn (&DrmDevice, voidptr, u64, int) voidptr = unsafe { nil }
}

pub struct DrmDevice {
pub mut:
	dev_id      u32
	driver      &DrmDriver = unsafe { nil }
	gem_objects []&GemObjectRef
	lock        klock.Lock
	registered  bool
	node        &DrmNode = unsafe { nil }
	render_node &DrmNode = unsafe { nil }
}

// Forward-reference placeholder for GEM objects stored at device level.
// The actual GEM object type lives in drm.gem; this is a thin handle
// kept per-device so the core can track which objects belong to a card.
pub struct GemObjectRef {
pub mut:
	handle u32
}

pub struct DrmNode {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	render   bool
	dev      &DrmDevice = unsafe { nil }
}

__global (
	registered_devices [64]&DrmDevice
	next_dev_id        = u32(0)
	drm_devices_lock   klock.Lock
)

fn decode_ioctl_cmd(request u64) ?u32 {
	raw := u32(request & 0xffffffff)
	typ := (raw >> 8) & 0xff
	nr := raw & 0xff
	if typ == u32(`d`) {
		return nr
	}
	return none
}

struct DrmIoctlLayout {
pub:
	size      u32
	direction u32
}

// Linux ioctl direction bits describe userspace's view: WRITE copies the
// request into the kernel and READ copies the result back to userspace.
const ioctl_write = u32(1)
const ioctl_read = u32(2)
const ioctl_size_shift = u32(16)
const ioctl_size_mask = u32(0x3fff)
const ioctl_direction_shift = u32(30)
const ioctl_direction_mask = u32(0x3)

fn ioctl_layout(cmd u32) ?DrmIoctlLayout {
	return match cmd {
		ioctl.drm_ioctl_version {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmVersion)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_get_cap {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmGetCap)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_gem_close {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmGemClose)), direction: ioctl_write }
		}
		ioctl.drm_ioctl_syncobj_create {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjCreate)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_syncobj_destroy {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjDestroy)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_syncobj_wait {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjWait)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_get_params {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiGetParams)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_vm_create {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiVmCreate)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_vm_destroy {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiVmDestroy)), direction: ioctl_write }
		}
		ioctl.drm_asahi_gem_create {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiGemCreate)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_gem_mmap_offset {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiGemMmapOffset)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_gem_bind {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiGemBind)), direction: ioctl_write }
		}
		ioctl.drm_asahi_queue_create {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiQueueCreate)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_queue_destroy {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiQueueDestroy)), direction: ioctl_write }
		}
		ioctl.drm_asahi_submit {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiSubmit)), direction: ioctl_write }
		}
		ioctl.drm_asahi_get_time {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiGetTime)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_asahi_gem_bind_object {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmAsahiGemBindObject)), direction: ioctl_write | ioctl_read }
		}
		else {
			return none
		}
	}
}

fn create_device_node(dev &DrmDevice, name string, render bool) ?&DrmNode {
	fs.create(vfs_root, '/dev/dri', stat.ifdir | 0o755) or {}

	mut node := &DrmNode{
		dev: unsafe { dev }
		render: render
	}
	node.stat.size = 0
	node.stat.blocks = 0
	node.stat.blksize = 4096
	node.stat.rdev = resource.create_dev_id()
	node.stat.mode = stat.ifchr | 0o666
	node.can_mmap = voidptr(dev.driver) != unsafe { nil } && dev.driver.mmap != unsafe { nil }

	fs.devtmpfs_add_device(node, 'dri/${name}')
	return node
}

fn (mut this DrmNode) mmap(handle voidptr, page u64, flags int) voidptr {
	if handle == unsafe { nil } || voidptr(this.dev) == unsafe { nil }
		|| voidptr(this.dev.driver) == unsafe { nil }
		|| this.dev.driver.mmap == unsafe { nil } {
		return unsafe { nil }
	}
	return this.dev.driver.mmap(this.dev, handle, page, flags)
}

fn (mut this DrmNode) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	return 0
}

fn (mut this DrmNode) write(_handle voidptr, _buf voidptr, _loc u64, count u64) ?i64 {
	return i64(count)
}

fn (mut this DrmNode) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	cmd := decode_ioctl_cmd(request) or {
		errno.set(errno.einval)
		return none
	}

	raw := u32(request & 0xffffffff)
	layout := ioctl_layout(cmd) or {
		errno.set(errno.einval)
		return none
	}
	request_size := (raw >> ioctl_size_shift) & ioctl_size_mask
	request_direction := (raw >> ioctl_direction_shift) & ioctl_direction_mask
	if request_size != layout.size || request_direction != layout.direction
		|| argp == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	buffer := memory.malloc(u64(layout.size))
	if buffer == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	defer {
		memory.free(buffer)
	}
	if layout.direction & ioctl_write != 0 {
		if !usercopy.copy_from_user(buffer, u64(argp), u64(layout.size)) {
			errno.set(errno.efault)
			return none
		}
	} else {
		unsafe { C.memset(buffer, 0, layout.size) }
	}

	ret := drm_ioctl(this.dev, cmd, buffer, handle)
	if ret < 0 {
		errno.set(u64(-ret))
		return none
	}
	if layout.direction & ioctl_read != 0
		&& !usercopy.copy_to_user(u64(argp), buffer, u64(layout.size)) {
		errno.set(errno.efault)
		return none
	}
	return ret
}

fn (mut this DrmNode) unref(handle voidptr) ? {
	if handle != unsafe { nil } && this.dev != unsafe { nil } && this.dev.driver != unsafe { nil } {
		if this.dev.driver.file_close != unsafe { nil } {
			this.dev.driver.file_close(this.dev, handle)
		}
	}
	if handle != unsafe { nil } {
		syncobj.destroy_owner(u64(handle))
	}
	katomic.dec(mut &this.refcount)
}

fn (mut this DrmNode) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this DrmNode) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this DrmNode) grow(_handle voidptr, _new_size u64) ? {
}

// Register a new DRM device backed by the given driver.
// Returns a reference to the newly created device or none on failure.
pub fn register_driver(driver &DrmDriver) ?&DrmDevice {
	drm_devices_lock.acquire()
	defer {
		drm_devices_lock.release()
	}

	if next_dev_id >= 64 {
		return none
	}

	id := next_dev_id
	next_dev_id++

	mut dev := &DrmDevice{
		dev_id: id
		driver: unsafe { driver }
		registered: true
	}

	dev.node = create_device_node(dev, 'card${id}', false) or {
		return none
	}
	if driver.features & driver_render != 0 {
		dev.render_node = create_device_node(dev, 'renderD${128 + id}', true) or {
			return none
		}
	}
	registered_devices[id] = dev

	println('drm: Registered driver ${driver.name} as card${id}')
	println('drm: created device node /dev/dri/card${id}')
	if dev.render_node != unsafe { nil } {
		println('drm: created device node /dev/dri/renderD${128 + id}')
	}
	return dev
}

// Unregister a DRM device and mark it as inactive.
pub fn unregister_device(dev &DrmDevice) {
	drm_devices_lock.acquire()
	defer {
		drm_devices_lock.release()
	}

	if dev.dev_id < 64 {
		mut d := unsafe { dev }
		d.registered = false
		registered_devices[dev.dev_id] = unsafe { nil }
		println('drm: Unregistered card${dev.dev_id}')
	}
}

fn copy_version_field(address u64, capacity u64, value string) bool {
	if capacity == 0 {
		return true
	}
	if address == 0 {
		return false
	}
	copy_size := if capacity < u64(value.len) { capacity } else { u64(value.len) }
	return usercopy.copy_to_user(address, voidptr(value.str), copy_size)
}

fn ioctl_version(dev &DrmDevice, data voidptr) int {
	if data == unsafe { nil } {
		return -14 // EFAULT
	}
	mut version := unsafe { &ioctl.DrmVersion(data) }
	name_capacity := version.name_len
	date_capacity := version.date_len
	desc_capacity := version.desc_len
	if !copy_version_field(version.name, name_capacity, dev.driver.name)
		|| !copy_version_field(version.date, date_capacity, '20260905')
		|| !copy_version_field(version.desc, desc_capacity, dev.driver.desc) {
		return -14
	}
	version.version_major = dev.driver.major
	version.version_minor = dev.driver.minor
	version.version_patchlevel = dev.driver.patchlevel
	version.name_len = u64(dev.driver.name.len)
	version.date_len = 8
	version.desc_len = u64(dev.driver.desc.len)
	return 0
}

fn ioctl_get_cap(data voidptr) int {
	if data == unsafe { nil } {
		return -14
	}
	mut cap := unsafe { &ioctl.DrmGetCap(data) }
	match cap.capability {
		ioctl.drm_cap_syncobj {
			cap.value = 1
			return 0
		}
		ioctl.drm_cap_syncobj_timeline {
			// Vinix currently exposes binary syncobjs only.
			cap.value = 0
			return 0
		}
		else {
			cap.value = 0
			return -22
		}
	}
}

fn ioctl_gem_close(dev &DrmDevice, handle voidptr, data voidptr) int {
	if data == unsafe { nil } {
		return -14
	}
	request := unsafe { &ioctl.DrmGemClose(data) }
	if request.pad != 0 {
		return -22
	}
	if dev.driver.gem_close != unsafe { nil } {
		return dev.driver.gem_close(dev, handle, request.handle)
	}
	obj := gem.get_by_handle(request.handle) or { return -2 }
	gem.unref(obj)
	return 0
}

fn ioctl_syncobj_create(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmSyncobjCreate(data) }
	if request.flags & ~ioctl.drm_syncobj_create_signaled != 0 {
		return -22
	}
	obj := syncobj.new_syncobj(u64(handle)) or { return -12 }
	fence := syncobj.new_fence(0, 0)
	syncobj.replace_fence(obj, fence)
	if request.flags & ioctl.drm_syncobj_create_signaled != 0 {
		syncobj.signal(fence)
	}
	request.handle = obj.handle
	return 0
}

fn ioctl_syncobj_destroy(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	request := unsafe { &ioctl.DrmSyncobjDestroy(data) }
	if request.pad != 0 {
		return -22
	}
	return if syncobj.destroy(u64(handle), request.handle) { 0 } else { -22 }
}

fn syncobj_wait_ready(owner u64, request &ioctl.DrmSyncobjWait, wait_all bool) (bool, u32) {
	mut ready_count := u32(0)
	mut first := u32(0)
	for i := u32(0); i < request.count_handles; i++ {
		handle := usercopy.read_u32(request.handles + u64(i) * sizeof(u32)) or {
			return false, u32(0xffffffff)
		}
		obj := syncobj.lookup(owner, handle) or { return false, u32(0xffffffff) }
		if obj.fence != unsafe { nil } && syncobj.is_signaled(obj.fence) {
			if ready_count == 0 {
				first = i
			}
			ready_count++
		}
	}
	return if wait_all { ready_count == request.count_handles } else { ready_count != 0 }, first
}

fn ioctl_syncobj_wait(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmSyncobjWait(data) }
	known_flags := ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit | ioctl.drm_syncobj_wait_available | ioctl.drm_syncobj_wait_deadline
	if request.handles == 0 || request.count_handles == 0 || request.count_handles > 64
		|| request.flags & ~known_flags != 0 || request.pad != 0 {
		return -22
	}
	wait_all := request.flags & ioctl.drm_syncobj_wait_all != 0
	owner := u64(handle)
	for {
		ready, first := syncobj_wait_ready(owner, request, wait_all)
		if first == u32(0xffffffff) {
			return -22
		}
		if ready {
			request.first_signaled = first
			return 0
		}
		now := syncobj.now_ns()
		if request.timeout_nsec <= 0 || u64(request.timeout_nsec) <= now {
			return -62 // ETIME
		}
		// Poll in bounded slices so WAIT_ANY observes every fence.
		remaining := u64(request.timeout_nsec) - now
		slice := if remaining < 100_000 { remaining } else { u64(100_000) }
		first_handle := usercopy.read_u32(request.handles) or { return -14 }
		first_obj := syncobj.lookup(owner, first_handle) or { return -22 }
		if first_obj.fence != unsafe { nil } {
			syncobj.wait(first_obj.fence, slice)
		}
	}
	return -62
}

fn core_ioctl(dev &DrmDevice, cmd u32, data voidptr, handle voidptr) ?int {
	match cmd {
		ioctl.drm_ioctl_version {
			return ioctl_version(dev, data)
		}
		ioctl.drm_ioctl_get_cap {
			return ioctl_get_cap(data)
		}
		ioctl.drm_ioctl_gem_close {
			return ioctl_gem_close(dev, handle, data)
		}
		ioctl.drm_ioctl_syncobj_create {
			return ioctl_syncobj_create(handle, data)
		}
		ioctl.drm_ioctl_syncobj_destroy {
			return ioctl_syncobj_destroy(handle, data)
		}
		ioctl.drm_ioctl_syncobj_wait {
			return ioctl_syncobj_wait(handle, data)
		}
		else {
			return none
		}
	}
}

// Dispatch a DRM ioctl to the appropriate handler registered by the driver.
// Returns 0 on success, negative errno on failure.
pub fn drm_ioctl(dev &DrmDevice, cmd u32, data voidptr, handle voidptr) int {
	if dev.driver == unsafe { nil } {
		return -1
	}

	if !dev.registered {
		return -19 // ENODEV
	}
	if ret := core_ioctl(dev, cmd, data, handle) {
		return ret
	}

	for ioctl in dev.driver.ioctls {
		if ioctl.cmd == cmd {
			return ioctl.handler(dev, handle, data)
		}
	}

	return -22 // EINVAL
}

// Look up a registered DRM device by its id.
pub fn get_device(id u32) ?&DrmDevice {
	if id >= 64 {
		return none
	}

	drm_devices_lock.acquire()
	dev := registered_devices[id]
	drm_devices_lock.release()

	if dev == unsafe { nil } || !dev.registered {
		return none
	}
	return dev
}
