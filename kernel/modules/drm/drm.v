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
}

pub struct DrmDevice {
pub mut:
	dev_id      u32
	driver      &DrmDriver = unsafe { nil }
	gem_objects []&GemObjectRef
	lock        klock.Lock
	registered  bool
	node        &DrmNode = unsafe { nil }
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
	dev      &DrmDevice = unsafe { nil }
}

__global (
	registered_devices [64]&DrmDevice
	next_dev_id        = u32(0)
	drm_devices_lock   klock.Lock
)

fn decode_ioctl_cmd(request u64) ?u32 {
	raw := u32(request & 0xffffffff)
	if raw <= 0xff {
		return raw
	}

	typ := (raw >> 8) & 0xff
	nr := raw & 0xff
	if typ == u32(`d`) {
		return nr
	}
	return none
}

fn create_device_node(dev &DrmDevice) ?&DrmNode {
	fs.create(vfs_root, '/dev/dri', stat.ifdir | 0o755) or {}

	mut node := &DrmNode{
		dev: unsafe { dev }
	}
	node.stat.size = 0
	node.stat.blocks = 0
	node.stat.blksize = 4096
	node.stat.rdev = resource.create_dev_id()
	node.stat.mode = stat.ifchr | 0o666

	fs.devtmpfs_add_device(node, 'dri/card${dev.dev_id}')
	return node
}

fn (mut this DrmNode) mmap(_page u64, _flags int) voidptr {
	return unsafe { nil }
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

	ret := drm_ioctl(this.dev, cmd, argp, handle)
	if ret < 0 {
		errno.set(u64(-ret))
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
		dev_id:     id
		driver:     unsafe { driver }
		registered: true
	}

	dev.node = create_device_node(dev) or {
		return none
	}
	registered_devices[id] = dev

	println('drm: Registered driver ${driver.name} as card${id}')
	println('drm: created device node /dev/dri/card${id}')
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

// Dispatch a DRM ioctl to the appropriate handler registered by the driver.
// Returns 0 on success, negative errno on failure.
pub fn drm_ioctl(dev &DrmDevice, cmd u32, data voidptr, handle voidptr) int {
	if dev.driver == unsafe { nil } {
		return -1
	}

	if !dev.registered {
		return -19 // ENODEV
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
