@[has_globals]
module drm

// Minimal DRM (Direct Rendering Manager) subsystem for Vinix
// Implements only what Asahi GPU and DCP display drivers need.
// Skips legacy mode setting, DRM leases, writeback connectors.
import klock
import katomic
import fs
import file
import stat
import resource
import errno
import event.eventstruct
import drm.gem
import drm.ioctl
import drm.syncobj
import sched
import proc
import memory
import memory.mmap
import usercopy
import lib

// DRM driver feature flags
pub const driver_gem = u32(0x1)
pub const driver_dumb_buffer = u32(0x2)
pub const driver_render = u32(0x8)
pub const driver_compute = u32(0x10)

pub struct DrmIoctl {
pub:
	cmd       u32
	size      u32
	direction u32
	handler   fn (&DrmDevice, voidptr, voidptr) int = unsafe { nil }
	flags     u32
	abi       u32 // zero: shared; otherwise selected by the driver's file ABI
	extensible bool // Linux DRM size/direction intersections and zero extension
}

pub struct DrmDriver {
pub mut:
	name           string
	desc           string
	major          int
	minor          int
	patchlevel     int
	features       u32
	ioctls         []DrmIoctl
	ioctl_abi      fn (&DrmDevice, voidptr) u32 = unsafe { nil }
	file_close     fn (&DrmDevice, voidptr) = unsafe { nil }
	gem_close      fn (&DrmDevice, voidptr, u32) int = unsafe { nil }
	gem_export     fn (&DrmDevice, voidptr, u32) ?&gem.GemObject = unsafe { nil }
	gem_export_put fn (&DrmDevice, &gem.GemObject) = unsafe { nil }
	gem_import     fn (&DrmDevice, voidptr, &gem.GemObject) ?u32 = unsafe { nil }
	mmap_attributes fn (&DrmDevice, voidptr, u64) u64 = unsafe { nil }
	mmap           fn (&DrmDevice, voidptr, u64, int) voidptr = unsafe { nil }
	mmap_retain    fn (&DrmDevice, voidptr, u64, u64) bool = unsafe { nil }
	mmap_release   fn (&DrmDevice, voidptr, u64, u64) = unsafe { nil }
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

// A sync-file fd is a stable reference to one DMA fence. Mesa uses this to
// snapshot the last submitted batch fence and, when necessary, import that
// snapshot into another binary syncobj. The fence allocations are retained by
// the syncobj subsystem, while this small wrapper follows ordinary fd lifetime.
struct SyncFileResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	fence    &syncobj.DmaFence = unsafe { nil }
	poll_event syncobj.FenceEvent
	box &resource.Resource = unsafe { nil }
}

// A PRIME fd keeps one GEM object alive while it is passed to another DRM
// file through SCM_RIGHTS.  The receiving file imports its own handle/ref;
// closing the dma-buf-style fd then releases this transport reference.
struct GemPrimeResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	dev      &DrmDevice = unsafe { nil }
	obj      &gem.GemObject = unsafe { nil }
	box &resource.Resource = unsafe { nil }
}

// Preserve this asynchronous object's existing status rather than treating
// its regular-file metadata as ordinary filesystem readiness. Fence-driven
// DMA-BUF readiness remains a separate implementation.
fn (mut this GemPrimeResource) poll_status(_access int) int {
	return this.status
}

fn (mut this GemPrimeResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	if this.obj == unsafe { nil } || page > u64(-1) / page_size
		|| (this.obj.external && (this.obj.phys_addr == 0 || flags & mmap.map_shared == 0)) {
		return unsafe { nil }
	}
	offset := page * page_size
	if offset >= this.obj.size {
		return unsafe { nil }
	}
	return voidptr(this.obj.phys_addr + offset)
}

fn (mut this GemPrimeResource) mapping_attributes(_handle voidptr, _offset u64) u64 {
	return if this.obj != unsafe { nil } { this.obj.pte_extra } else { 0 }
}

fn (mut this GemPrimeResource) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this GemPrimeResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this GemPrimeResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this GemPrimeResource) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	if this.obj != unsafe { nil } {
		if this.dev != unsafe { nil } && this.dev.driver != unsafe { nil }
			&& this.dev.driver.gem_export_put != unsafe { nil } {
			this.dev.driver.gem_export_put(this.dev, this.obj)
		} else {
			gem.unref(this.obj)
		}
	}
	unsafe {
		free(voidptr(this.box))
		free(voidptr(this))
	}
}

fn (mut this GemPrimeResource) link(_handle voidptr) ? {
}

fn (mut this GemPrimeResource) unlink(_handle voidptr) ? {
}

fn (mut this GemPrimeResource) grow(_handle voidptr, _new_size u64) ? {
}

fn (mut this SyncFileResource) poll_status(_access int) int {
	return if syncobj.poll_fence(this.fence, unsafe { &this.poll_event }, unsafe { &this.event }) { file.pollin } else { 0 }
}

fn (mut this SyncFileResource) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this SyncFileResource) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this SyncFileResource) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.einval)
	return none
}

fn (mut this SyncFileResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	if u32(request) == ioctl.sync_ioc_file_info {
		result := sync_file_info_ioctl(this.fence, u64(argp))
		if result < 0 { errno.set(u64(-result)); return none }
		return result
	}
	if u32(request) == ioctl.sync_ioc_set_deadline {
		result := sync_file_deadline_ioctl(u64(argp))
		if result < 0 { errno.set(u64(-result)); return none }
		return result
	}
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this SyncFileResource) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	syncobj.cancel_fence_event(this.fence, unsafe { &this.poll_event })
	unsafe {
		memory.free(voidptr(this.box))
		memory.free(voidptr(this))
	}
}

fn (mut this SyncFileResource) link(_handle voidptr) ? {
}

fn (mut this SyncFileResource) unlink(_handle voidptr) ? {
}

fn (mut this SyncFileResource) grow(_handle voidptr, _new_size u64) ? {
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
	driver_index int = -1
	extensible bool
	flags u32
}

// Linux ioctl direction bits describe userspace's view: WRITE copies the
// request into the kernel and READ copies the result back to userspace.
pub const ioctl_write = u32(1)
pub const ioctl_read = u32(2)
pub const ioctl_no_activity = u32(1) << 31
const ioctl_size_shift = u32(16)
const ioctl_size_mask = u32(0x3fff)
const ioctl_direction_shift = u32(30)
const ioctl_direction_mask = u32(0x3)

fn common_ioctl_layout(cmd u32) ?DrmIoctlLayout {
	return match cmd {
		ioctl.drm_ioctl_version {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVersion))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_get_cap {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmGetCap))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_gem_close {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmGemClose))
				direction: ioctl_write
			}
		}
		ioctl.drm_ioctl_prime_handle_to_fd, ioctl.drm_ioctl_prime_fd_to_handle {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmPrimeHandle))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_syncobj_create {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjCreate))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_syncobj_destroy {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjDestroy))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_syncobj_handle_to_fd, ioctl.drm_ioctl_syncobj_fd_to_handle {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjHandle))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_syncobj_wait {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjWait)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_syncobj_reset {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjArray)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_syncobj_signal {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjArray)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_syncobj_query {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjTimelineArray)), direction: ioctl_write | ioctl_read }
		}
		ioctl.drm_ioctl_mode_create_dumb {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmModeCreateDumb))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_mode_map_dumb {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmModeMapDumb))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_ioctl_mode_destroy_dumb {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmModeDestroyDumb))
				direction: ioctl_write
			}
		}
		ioctl.drm_virtgpu_map {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuMap))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_execbuffer {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuExecbuffer))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_getparam {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuGetparam))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_resource_create {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuResourceCreate))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_resource_info {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuResourceInfo))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_transfer_from_host, ioctl.drm_virtgpu_transfer_to_host {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuTransfer))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_wait {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuWait))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_get_caps {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuGetCaps))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_resource_create_blob {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuResourceCreateBlob))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_virtgpu_context_init {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmVirtgpuContextInit))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_get_params {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiGetParams))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_vm_create {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiVmCreate))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_vm_destroy {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiVmDestroy))
				direction: ioctl_write
			}
		}
		ioctl.drm_asahi_gem_create {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiGemCreate))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_gem_mmap_offset {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiGemMmapOffset))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_gem_bind {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiGemBind))
				direction: ioctl_write
			}
		}
		ioctl.drm_asahi_queue_create {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiQueueCreate))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_queue_destroy {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiQueueDestroy))
				direction: ioctl_write
			}
		}
		ioctl.drm_asahi_submit {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiSubmit))
				direction: ioctl_write
			}
		}
		ioctl.drm_asahi_get_time {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiGetTime))
				direction: ioctl_write | ioctl_read
			}
		}
		ioctl.drm_asahi_gem_bind_object {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmAsahiGemBindObject))
				direction: ioctl_write | ioctl_read
			}
		}
		else {
			return none
		}
	}
}

// Driver-private commands all start at DRM_COMMAND_BASE and intentionally
// reuse the same numbers across drivers. Prefer layout metadata from the
// device's own table so, for example, Asahi 0x41 is never decoded as VirtIO's
// unrelated 0x41 request.
fn ioctl_layout(dev &DrmDevice, cmd u32, request_size u32, direction u32, abi u32) ?DrmIoctlLayout {
	if dev.driver != unsafe { nil } {
		mut private_command := false
		for index, entry in dev.driver.ioctls {
			if entry.cmd != cmd { continue }
			if entry.size == 0 || entry.direction == 0 { continue }
			private_command = true
			if entry.size != 0 && (entry.extensible || entry.direction == direction)
				&& (abi == 0 || entry.abi == 0 || entry.abi == abi)
				&& (entry.extensible || entry.size == request_size) {
				return DrmIoctlLayout{
					size: entry.size
					direction: if entry.extensible { entry.direction & direction } else { entry.direction }
					driver_index: index
					extensible: entry.extensible
					flags: entry.flags
				}
			}
		}
		if private_command { return none }
	}
	return common_ioctl_layout(cmd)
}

// Linux DRM allocates max(in_size, out_size, driver_size). Unknown input
// bytes are preserved, including their output echo for read/write requests;
// only bytes omitted by the caller are zero extended. Nested Asahi command
// payloads have their own stricter Reader::read_supported validation.
fn ioctl_buffer_size(layout &DrmIoctlLayout, user_size u32) u32 {
	return if layout.extensible && layout.direction != 0 && user_size > layout.size { user_size } else { layout.size }
}

fn copy_ioctl_input(buffer voidptr, size u32, user u64, user_size u32) int {
	unsafe { C.memset(buffer, 0, size) }
	if user_size != 0 && u64(user_size - 1) > ~user { return -14 }
	copy_size := if user_size < size { user_size } else { size }
	if copy_size != 0 && !usercopy.copy_from_user(buffer, user, u64(copy_size)) { return -14 }
	return 0
}

fn copy_ioctl_output(user u64, buffer voidptr, size u32, user_size u32) bool {
	if user_size != 0 && u64(user_size - 1) > ~user { return false }
	copy_size := if user_size < size { user_size } else { size }
	if copy_size != 0 && !usercopy.copy_to_user(user, buffer, u64(copy_size)) { return false }
	mut zeros := [64]u8{}
	mut offset := size
	for offset < user_size {
		count := if user_size - offset < 64 { user_size - offset } else { u32(64) }
		if !usercopy.copy_to_user(user + offset, unsafe { &zeros[0] }, u64(count)) { return false }
		offset += count
	}
	return true
}

// The node is /dev/dri/<prefix><number>.
fn create_device_node(dev &DrmDevice, prefix string, number u64, render bool) ?&DrmNode {
	fs.create(vfs_root, '/dev/dri', stat.ifdir | 0o755) or {}

	mut node := &DrmNode{
		dev: unsafe { dev }
		render: render
	}
	node.stat.size = 0
	node.stat.blocks = 0
	node.stat.blksize = 4096
	// libdrm identifies primary and render nodes from Linux's DRM major and
	// minor ranges before scanning /dev/dri for the matching pathname.
	minor := if render { 128 + int(dev.dev_id) } else { int(dev.dev_id) }
	node.stat.rdev = u64((226 << 8) | minor)
	node.stat.mode = stat.ifchr | 0o666
	node.can_mmap = voidptr(dev.driver) != unsafe { nil } && dev.driver.mmap != unsafe { nil }

	mut path := lib.new_text(32)
	path.add('dri/')
	path.add(prefix)
	path.add_unsigned(number)
	name := path.str() @[freed]
	// devtmpfs keeps its own copy of the last path component.
	fs.devtmpfs_add_device(node, name)
	unsafe { name.free() }
	return node
}

fn (mut this DrmNode) mapping_attributes(handle voidptr, offset u64) u64 {
	if this.dev == unsafe { nil } || this.dev.driver == unsafe { nil }
		|| this.dev.driver.mmap_attributes == unsafe { nil } { return 0 }
	return this.dev.driver.mmap_attributes(this.dev, handle, offset)
}

fn (mut this DrmNode) mmap(handle voidptr, page u64, flags int) voidptr {
	if handle == unsafe { nil } || voidptr(this.dev) == unsafe { nil }
		|| voidptr(this.dev.driver) == unsafe { nil } || this.dev.driver.mmap == unsafe { nil } {
		return unsafe { nil }
	}
	return this.dev.driver.mmap(this.dev, handle, page, flags)
}

fn (mut this DrmNode) retain_mapping_range(handle voidptr, offset u64, length u64, _flags int) bool {
	if handle == unsafe { nil } || this.dev == unsafe { nil }
		|| this.dev.driver == unsafe { nil } {
		return false
	}
	if this.dev.driver.mmap_retain == unsafe { nil } {
		return true
	}
	return this.dev.driver.mmap_retain(this.dev, handle, offset, length)
}

fn (mut this DrmNode) release_mapping_range(handle voidptr, offset u64, length u64, _flags int) {
	if handle != unsafe { nil } && this.dev != unsafe { nil }
		&& this.dev.driver != unsafe { nil }
		&& this.dev.driver.mmap_release != unsafe { nil } {
		this.dev.driver.mmap_release(this.dev, handle, offset, length)
	}
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
	request_size := (raw >> ioctl_size_shift) & ioctl_size_mask
	request_direction := (raw >> ioctl_direction_shift) & ioctl_direction_mask
	if this.dev == unsafe { nil } || this.dev.driver == unsafe { nil } || !this.dev.registered {
		errno.set(errno.enodev)
		return none
	}
	abi := if this.dev.driver.ioctl_abi != unsafe { nil } { this.dev.driver.ioctl_abi(this.dev, handle) } else { u32(0) }
	layout := ioctl_layout(this.dev, cmd, request_size, request_direction, abi) or {
		errno.set(errno.einval)
		return none
	}
	if !layout.extensible && (request_size != layout.size || request_direction != layout.direction
		|| argp == unsafe { nil }) {
		errno.set(errno.einval)
		return none
	}
	if layout.driver_index >= 0 && this.dev.driver.ioctls[layout.driver_index].handler == unsafe { nil } {
		errno.set(errno.einval)
		return none
	}
	buffer_size := ioctl_buffer_size(&layout, request_size)
	mut stack_buffer := [128]u8{}
	mut buffer := unsafe { voidptr(&stack_buffer[0]) }
	heap_buffer := buffer_size > sizeof(stack_buffer)
	if heap_buffer {
		buffer = memory.malloc_packed_fallible(u64(buffer_size))
		if buffer == unsafe { nil } {
			errno.set(errno.enomem)
			return none
		}
	}
	defer {
		if heap_buffer { memory.free(buffer) }
	}
	if layout.direction & ioctl_write != 0 {
		copy_result := copy_ioctl_input(buffer, buffer_size, u64(argp), request_size)
		if copy_result < 0 {
			errno.set(u64(-copy_result))
			return none
		}
	} else {
		unsafe { C.memset(buffer, 0, buffer_size) }
	}

	ret := if layout.driver_index >= 0 {
		entry := this.dev.driver.ioctls[layout.driver_index]
		if entry.handler == unsafe { nil } { -22 } else { entry.handler(this.dev, handle, buffer) }
	} else { drm_ioctl(this.dev, cmd, buffer, handle) }
	if ret < 0 && !layout.extensible {
		errno.set(u64(-ret))
		return none
	}
	if ret >= 0 && layout.flags & ioctl_no_activity == 0 { account_activity(this.dev, cmd) }
	if layout.direction & ioctl_read != 0
		&& !copy_ioctl_output(u64(argp), buffer, buffer_size, request_size) {
		errno.set(errno.efault)
		return none
	}
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

	dev.node = create_device_node(dev, 'card', u64(id), false) or { return none }
	if driver.features & driver_render != 0 {
		dev.render_node = create_device_node(dev, 'renderD', u64(128 + id), true) or {
			return none
		}
	}
	registered_devices[id] = dev

	C.kprintf(c'drm: Registered driver %.*s as card%llu\n', i32(driver.name.len), driver.name.str,
		u64(id))
	C.kprintf(c'drm: created device node /dev/dri/card%llu\n', u64(id))
	if dev.render_node != unsafe { nil } {
		C.kprintf(c'drm: created device node /dev/dri/renderD%llu\n', u64(128 + id))
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
		C.kprintf(c'drm: Unregistered card%llu\n', u64(dev.dev_id))
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
	version.version_major = i32(dev.driver.major)
	version.version_minor = i32(dev.driver.minor)
	version.version_patchlevel = i32(dev.driver.patchlevel)
	version.name_len = u64(dev.driver.name.len)
	version.date_len = 8
	version.desc_len = u64(dev.driver.desc.len)
	return 0
}

fn ioctl_get_cap(dev &DrmDevice, data voidptr) int {
	if data == unsafe { nil } {
		return -14
	}
	mut cap := unsafe { &ioctl.DrmGetCap(data) }
	match cap.capability {
		ioctl.drm_cap_dumb_buffer {
			cap.value = if dev.driver.features & driver_dumb_buffer != 0 { u64(1) } else { u64(0) }
			return 0
		}
		ioctl.drm_cap_dumb_preferred_depth {
			cap.value = 32
			return 0
		}
		ioctl.drm_cap_dumb_prefer_shadow {
			cap.value = 0
			return 0
		}
		ioctl.drm_cap_prime {
			cap.value = ioctl.drm_prime_cap_import | ioctl.drm_prime_cap_export
			return 0
		}
		ioctl.drm_cap_syncobj {
			cap.value = 1
			return 0
		}
		ioctl.drm_cap_syncobj_timeline {
			// Submission chains and QUERY exist; timeline wait/signal/transfer
			// must be complete before advertising the generic timeline feature.
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
	obj := syncobj.new_syncobj_with_flags(u64(handle),
		request.flags & ioctl.drm_syncobj_create_signaled != 0) or { return -12 }
	request.handle = obj.handle
	return 0
}

fn create_prime_fd(dev &DrmDevice, obj &gem.GemObject, flags u32) ?int {
	if dev == unsafe { nil } || obj == unsafe { nil } {
		return none
	}
	mut wrapper := &GemPrimeResource{
		stat: stat.Stat{
			mode: stat.ifreg | 0o600
			size: i64(obj.size)
			blksize: i64(4096)
			blocks: i64(obj.size / 512)
		}
		dev: unsafe { dev }
		obj: unsafe { obj }
		can_mmap: true
	}
	mut fd_flags := 0
	if flags & ioctl.drm_cloexec != 0 {
		fd_flags |= resource.o_cloexec
	}
	if flags & ioctl.drm_rdwr != 0 {
		fd_flags |= resource.o_rdwr
	}
	wrapper.box = &resource.Resource(unsafe { wrapper }) @[freed]
	mut res := wrapper.box
	mut fd := file.fd_create_from_resource(mut res, fd_flags) or {
		if dev.driver.gem_export_put != unsafe { nil } {
			dev.driver.gem_export_put(dev, obj)
		} else {
			gem.unref(obj)
		}
		unsafe {
			free(voidptr(wrapper.box))
			free(voidptr(wrapper))
		}
		return none
	}
	fdnum := file.fdnum_create_from_fd(unsafe { nil }, fd, 0, false) or {
		fd.unref()
		return none
	}
	return fdnum
}

// Return an owned object reference: the descriptor can be closed concurrently
// after its open-file-description reference is released below.
fn prime_object_from_fd(dev &DrmDevice, fdnum int) ?&gem.GemObject {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return none }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res is GemPrimeResource {
		if res.dev != dev || res.obj == unsafe { nil } {
			return none
		}
		obj := unsafe { res.obj }
		gem.ref_obj(obj)
		return obj
	}
	return none
}

fn ioctl_prime_handle_to_fd(dev &DrmDevice, handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } || dev.driver.gem_export == unsafe { nil } {
		return -22
	}
	mut request := unsafe { &ioctl.DrmPrimeHandle(data) }
	if request.handle == 0 || request.flags & ~(ioctl.drm_cloexec | ioctl.drm_rdwr) != 0 {
		return -22
	}
	obj := dev.driver.gem_export(dev, handle, request.handle) or { return -2 }
	if obj.vm_private_identity != 0 {
		// The exporter returned an owned reference. Refuse private reservation
		// domains before creating an fd, using the exporter's matching put.
		if dev.driver.gem_export_put != unsafe { nil } {
			dev.driver.gem_export_put(dev, obj)
		} else { gem.unref(obj) }
		return -22 // EINVAL, as in Asahi's non-exportable object policy
	}
	fdnum := create_prime_fd(dev, obj, request.flags) or { return -24 }
	request.fd = i32(fdnum)
	return 0
}

fn ioctl_prime_fd_to_handle(dev &DrmDevice, handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } || dev.driver.gem_import == unsafe { nil } {
		return -22
	}
	mut request := unsafe { &ioctl.DrmPrimeHandle(data) }
	if request.fd < 0 || request.flags != 0 {
		return -22
	}
	obj := prime_object_from_fd(dev, request.fd) or { return -9 }
	defer {
		gem.unref(obj)
	}
	request.handle = dev.driver.gem_import(dev, handle, obj) or { return -12 }
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

pub fn create_sync_file_fd(fence &syncobj.DmaFence) ?int {
	return create_sync_file_fd_at(fence, unsafe { nil })
}

fn create_sync_file_fd_at(fence &syncobj.DmaFence, reservation &file.FdReservation) ?int {
	if fence == unsafe { nil } {
		return none
	}
	allocation := memory.malloc_packed_fallible(sizeof(SyncFileResource))
	if allocation == unsafe { nil } { errno.set(errno.enomem); return none }
	mut wrapper := unsafe { &SyncFileResource(allocation) }
	unsafe { *wrapper = SyncFileResource{
		fence: fence
		status: if syncobj.is_signaled(fence) { file.pollin } else { 0 }
	} }
	box := memory.malloc_packed_fallible(sizeof(resource.Resource))
	if box == unsafe { nil } {
		memory.free(allocation)
		errno.set(errno.enomem)
		return none
	}
	// A direct &Resource(voidptr) conversion boxes the pointer in V. Reinterpret
	// the pointer slot to adopt this already allocated interface storage.
	unsafe { *(&voidptr(&wrapper.box)) = box }
	unsafe { *wrapper.box = resource.Resource(wrapper) }
	mut res := wrapper.box
	if reservation != unsafe { nil } {
		return file.fdnum_create_from_reserved_resource(reservation, mut res, resource.o_cloexec)
	}
	return file.fdnum_create_from_resource(unsafe { nil }, mut res, resource.o_cloexec, 0, false)
}

// Resolve only fds created by create_sync_file_fd. The interface type check
// rejects arbitrary user-provided descriptors before accessing fence state.
pub fn sync_file_fence_from_fd(fdnum int) ?&syncobj.DmaFence {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return none }
	defer {
		fd.unref()
	}
	mut res := fd.handle.resource
	if mut res is SyncFileResource {
		if res.fence == unsafe { nil } {
			return none
		}
		return unsafe { res.fence }
	}
	return none
}

fn ioctl_syncobj_handle_to_fd(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmSyncobjHandle(data) }
	if request.flags & ~ioctl.drm_syncobj_handle_to_fd_export_sync_file != 0 || request.pad != 0 {
		return -22
	}
	if request.flags == 0 {
		obj := syncobj.lookup(u64(handle), request.handle) or { return -22 }
		request.fd = i32(create_syncobj_fd(obj) or { return -int(errno.get()) })
		return 0
	}
	// Linux reserves the number before sync-file source lookup. A full table
	// wins over missing handles/fences; private sync-file creation failure is
	// EINVAL. Opaque export instead resolves its object before reservation.
	mut reservation := file.FdReservation{}
	file.reserve_fd(unsafe { nil }, unsafe { &reservation }) or { return -int(errno.get()) }
	defer { file.cancel_fd_reservation(unsafe { &reservation }) }
	obj := syncobj.lookup(u64(handle), request.handle) or { return -2 }
	fence := syncobj.get_fence(obj) or { return -22 }
	fdnum := create_sync_file_fd_at(fence, unsafe { &reservation }) or { return -22 }
	request.fd = i32(fdnum)
	return 0
}

fn ioctl_syncobj_fd_to_handle(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmSyncobjHandle(data) }
	if request.flags & ~ioctl.drm_syncobj_fd_to_handle_import_sync_file != 0 || request.pad != 0
		|| request.fd < 0 {
		return -22
	}
	if request.flags == 0 {
		obj := syncobj_from_fd(request.fd) or { return -22 }
		request.handle = syncobj.import_syncobj(u64(handle), obj) or { return -12 }
		return 0
	}
	// Linux resolves the transport first. Even when both inputs are invalid,
	// an invalid sync-file is EINVAL; only a valid fence with no target is ENOENT.
	// Fence metadata remains retained after the descriptor lookup releases its
	// reference, including across destination destruction/reuse before lookup.
	fence := sync_file_fence_from_fd(request.fd) or { return -22 }
	obj := syncobj.lookup(u64(handle), request.handle) or { return -2 }
	syncobj.replace_fence(obj, fence)
	return 0
}

fn ioctl_syncobj_wait(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmSyncobjWait(data) }
	known_flags := ioctl.drm_syncobj_wait_all | ioctl.drm_syncobj_wait_for_submit | ioctl.drm_syncobj_wait_deadline
	if request.flags & ~known_flags != 0 {
		return -22
	}
	if request.count_handles == 0 { return 0 }
	mut handles := [64]u32{}
	// Retained syncobj/fence metadata keeps these synchronous snapshots valid
	// even if another thread replaces a fence or destroys/reuses its handle.
	mut objects := unsafe { [64]voidptr{} }
	mut captures := [64]syncobj.FenceCapture{}
	mut buffer := SyncobjWaitBuffer{
		handles: unsafe { &handles[0] }
		objects: unsafe { &objects[0] }
		captures: unsafe { &captures[0] }
	}
	if request.count_handles > 64 {
		buffer = new_syncobj_wait_buffer(request.count_handles) or { return -12 }
	}
	// Defer order is intentional: the later capture detachment runs first.
	defer { buffer.free_owned() }
	if !usercopy.copy_from_user(buffer.handles, request.handles,
		u64(request.count_handles) * sizeof(u32)) { return -14 }
	for i := u32(0); i < request.count_handles; i++ {
		object := syncobj.lookup(u64(handle), unsafe { buffer.handles[i] }) or { return -2 }
		unsafe { buffer.objects[i] = voidptr(object) }
	}
	// Every prepared entry is detached before this synchronous ioctl unwinds,
	// including validation failures, timeout, signal interruption and success.
	defer {
		// Registrations prepend to each object's list. Reverse retirement
		// removes duplicate-handle registrations without repeated tail scans.
		mut remaining := request.count_handles
		for remaining > 0 {
			remaining--
			syncobj.release_capture(unsafe { &buffer.captures[remaining] })
		}
	}
	for i := u32(0); i < request.count_handles; i++ {
		if !syncobj.prepare_capture(unsafe { &syncobj.SyncObj(buffer.objects[i]) }, unsafe { &buffer.captures[i] },
			request.flags & ioctl.drm_syncobj_wait_for_submit != 0) { return -22 }
	}
	wait_all := request.flags & ioctl.drm_syncobj_wait_all != 0
	for {
		mut ready_count := u32(0)
		mut first := u32(0)
		for i := u32(0); i < request.count_handles; i++ {
			fence := syncobj.captured_fence(unsafe { &buffer.captures[i] }) or { continue }
			if syncobj.is_signaled(fence) {
				if ready_count == 0 { first = i }
				ready_count++
			}
		}
		ready := if wait_all { ready_count == request.count_handles } else { ready_count != 0 }
		if ready {
			request.first_signaled = first
			return 0
		}
		now := syncobj.now_ns()
		if request.timeout_nsec <= 0 || u64(request.timeout_nsec) <= now {
			return -62 // ETIME
		}
		waiting_thread := proc.current_thread()
		if katomic.load(&waiting_thread.must_exit) || proc.pending_signals(waiting_thread) & ~waiting_thread.masked_signals != 0 {
			return -proc.interrupted_errno
		}
		// Also yield while waiting for submission into an empty object.
		sched.reschedule()
	}
	return -62
}

fn ioctl_syncobj_reset(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjArray(data) }
	if request.pad != 0 || request.count_handles == 0 { return -22 }
	mut handles := [64]u32{}
	mut objects := unsafe { [64]voidptr{} }
	mut buffer := SyncobjWaitBuffer{ handles: unsafe { &handles[0] }, objects: unsafe { &objects[0] } }
	if request.count_handles > 64 {
		buffer = new_syncobj_handle_buffer(request.count_handles) or { return -12 }
	}
	defer { buffer.free_owned() }
	if !usercopy.copy_from_user(buffer.handles, request.handles,
		u64(request.count_handles) * sizeof(u32)) { return -14 }
	// Resolve every handle before changing any object. Retained metadata keeps
	// these object identities valid across concurrent destroy/handle reuse.
	for i := u32(0); i < request.count_handles; i++ {
		object := syncobj.lookup(u64(handle), unsafe { buffer.handles[i] }) or { return -2 }
		unsafe { buffer.objects[i] = voidptr(object) }
	}
	for i := u32(0); i < request.count_handles; i++ {
		syncobj.replace_fence(unsafe { &syncobj.SyncObj(buffer.objects[i]) }, unsafe { nil })
	}
	return 0
}

fn ioctl_syncobj_signal(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -14 }
	request := unsafe { &ioctl.DrmSyncobjArray(data) }
	if request.pad != 0 || request.count_handles == 0 { return -22 }
	mut handles := [64]u32{}
	mut objects := unsafe { [64]voidptr{} }
	mut buffer := SyncobjWaitBuffer{ handles: unsafe { &handles[0] }, objects: unsafe { &objects[0] } }
	if request.count_handles > 64 {
		buffer = new_syncobj_handle_buffer(request.count_handles) or { return -12 }
	}
	defer { buffer.free_owned() }
	if !usercopy.copy_from_user(buffer.handles, request.handles,
		u64(request.count_handles) * sizeof(u32)) { return -14 }
	for i := u32(0); i < request.count_handles; i++ {
		object := syncobj.lookup(u64(handle), unsafe { buffer.handles[i] }) or { return -2 }
		unsafe { buffer.objects[i] = voidptr(object) }
	}
	// Linux allocates one private completion per array entry, including
	// duplicates. OOM preserves the already-replaced prefix, then stops.
	for i := u32(0); i < request.count_handles; i++ {
		fence := syncobj.new_private_stub(syncobj.now_ns()) or { return -12 }
		syncobj.replace_fence(unsafe { &syncobj.SyncObj(buffer.objects[i]) }, fence)
	}
	return 0
}

fn core_ioctl(dev &DrmDevice, cmd u32, data voidptr, handle voidptr) ?int {
	match cmd {
		ioctl.drm_ioctl_version {
			return ioctl_version(dev, data)
		}
		ioctl.drm_ioctl_get_cap {
			return ioctl_get_cap(dev, data)
		}
		ioctl.drm_ioctl_gem_close {
			return ioctl_gem_close(dev, handle, data)
		}
		ioctl.drm_ioctl_prime_handle_to_fd {
			return ioctl_prime_handle_to_fd(dev, handle, data)
		}
		ioctl.drm_ioctl_prime_fd_to_handle {
			return ioctl_prime_fd_to_handle(dev, handle, data)
		}
		ioctl.drm_ioctl_syncobj_create {
			return ioctl_syncobj_create(handle, data)
		}
		ioctl.drm_ioctl_syncobj_destroy {
			return ioctl_syncobj_destroy(handle, data)
		}
		ioctl.drm_ioctl_syncobj_handle_to_fd {
			return ioctl_syncobj_handle_to_fd(handle, data)
		}
		ioctl.drm_ioctl_syncobj_fd_to_handle {
			return ioctl_syncobj_fd_to_handle(handle, data)
		}
		ioctl.drm_ioctl_syncobj_wait {
			return ioctl_syncobj_wait(handle, data)
		}
		ioctl.drm_ioctl_syncobj_reset {
			return ioctl_syncobj_reset(handle, data)
		}
		ioctl.drm_ioctl_syncobj_signal {
			return ioctl_syncobj_signal(handle, data)
		}
		ioctl.drm_ioctl_syncobj_query {
			return ioctl_syncobj_query(handle, data)
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
