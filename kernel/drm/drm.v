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

// DRM driver feature flags
pub const driver_gem = u32(0x1)
pub const driver_dumb_buffer = u32(0x2)
pub const driver_render = u32(0x8)
pub const driver_compute = u32(0x10)
pub const driver_syncobj_timeline = u32(0x20)

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

pub const default_driver_date = '20260905'

pub struct DrmDriver {
pub mut:
	name           string
	desc           string
	date           string = default_driver_date
	major          int
	minor          int
	patchlevel     int
	features       u32
	ioctls         []DrmIoctl
	ioctl_abi      fn (&DrmDevice, voidptr) u32 = unsafe { nil }
	file_close     fn (&DrmDevice, voidptr) = unsafe { nil }
	gem_close      fn (&DrmDevice, voidptr, u32) int = unsafe { nil }
	gem_close_request fn (&DrmDevice, voidptr, &ioctl.DrmGemClose) int = unsafe { nil }
	gem_export     fn (&DrmDevice, voidptr, u32) ?&gem.GemObject = unsafe { nil }
	gem_export_put fn (&DrmDevice, &gem.GemObject) = unsafe { nil }
	gem_import     fn (&DrmDevice, voidptr, &gem.GemObject) ?u32 = unsafe { nil }
	mmap_attributes fn (&DrmDevice, voidptr, u64) u64 = unsafe { nil }
	mmap           fn (&DrmDevice, voidptr, u64, int) voidptr = unsafe { nil }
	mmap_admit     fn (&DrmDevice, voidptr, u64, u64, bool) int = unsafe { nil }
	mmap_no_expand bool
	mmap_retain    fn (&DrmDevice, voidptr, u64, u64) bool = unsafe { nil }
	mmap_release   fn (&DrmDevice, voidptr, u64, u64) = unsafe { nil }
	// The client's memory for its fdinfo; nil prints no memory lines.
	memory_stats   fn (&DrmDevice, voidptr) ?MemoryStats = unsafe { nil }
	// The /sys path of the device the minors belong to, such as
	// devices/platform/soc/206400000.gpu; empty for devices/virtual.
	sysfs_parent   string
}

pub struct DrmDevice {
pub:
	driver_data voidptr // Immutable for this device's lifetime.
	dev_id      u32
pub mut:
	driver      &DrmDriver = unsafe { nil }
	gem_objects []&GemObjectRef
	lock        klock.Lock
	node        &DrmNode = unsafe { nil }
	render_node &DrmNode = unsafe { nil }
mut:
	registered  bool
	sysfs_parent string // owned copy, for removal after the driver is gone
	primary_sysfs DrmMinorSysfs
	render_sysfs DrmMinorSysfs
	debugfs_dir  string // owned; empty for a device with no parent
	debugfs_primary_link bool
	debugfs_render_link bool
	clients_lock klock.Lock
	clients_first &file.Handle = unsafe { nil }
	clients_last &file.Handle = unsafe { nil }
	clients_count int
}

pub fn (dev &DrmDevice) is_registered() bool {
	return katomic.load(&dev.registered)
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
mut:
	box      &resource.Resource = unsafe { nil }
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
	name [32]u8
	owns_snapshot bool
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
	poll_read PrimePoll
	poll_write PrimePoll
	box &resource.Resource = unsafe { nil }
}

fn (mut this GemPrimeResource) poll_status(_access int) int {
	return this.poll_requested(file.pollin | file.pollout).status
}

fn (this &GemPrimeResource) seek_offset(offset i64, whence int) ?u64 {
	if offset == 0 {
		if whence == fs.seek_set { return u64(0) }
		if whence == fs.seek_end { return u64(this.stat.size) }
	}
	errno.set(errno.einval)
	return none
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
	if this.obj.external { return voidptr(this.obj.phys_addr + offset) }
	return voidptr(this.obj.page_phys(offset) or { return unsafe { nil } })
}

fn (mut this GemPrimeResource) mapping_attributes(_handle voidptr, _offset u64) u64 {
	return if this.obj != unsafe { nil } { this.obj.pte_extra } else { 0 }
}

fn (mut this GemPrimeResource) admit_mapping_range(_handle voidptr, offset u64, length u64, flags int) bool {
	if this.obj == unsafe { nil } || !this.obj.file_scoped { return true }
	return flags & mmap.map_shared != 0 && length != 0 && offset <= this.obj.size
		&& length <= this.obj.size - offset
}

fn (mut this GemPrimeResource) mapping_can_grow() bool {
	return this.obj == unsafe { nil } || !this.obj.file_scoped
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
	if this.obj == unsafe { nil } || !this.obj.file_scoped {
		return resource.default_ioctl(handle, request, argp)
	}
	result := match u32(request) {
		ioctl.dma_buf_ioctl_sync { prime_cpu_access(this.obj, u64(argp)) }
		ioctl.dma_buf_ioctl_export_sync_file { prime_export_sync_file(this.obj, u64(argp)) }
		ioctl.dma_buf_ioctl_import_sync_file { prime_import_sync_file(this.obj, u64(argp)) }
		else { return resource.default_ioctl(handle, request, argp) }
	}
	if result < 0 { errno.set(u64(-result)); return none }
	return result
}

fn (mut this GemPrimeResource) unref(_handle voidptr) ? {
	if katomic.dec(mut &this.refcount) {
		return
	}
	syncobj.cancel_fence_event(this.poll_read.fence, unsafe { &this.poll_read.event })
	syncobj.cancel_fence_event(this.poll_write.fence, unsafe { &this.poll_write.event })
	if this.obj != unsafe { nil } { put_prime_object(this.dev, this.obj) }
	unsafe {
		memory.free(voidptr(this.box))
		memory.free(voidptr(this))
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
	if u32(request) == ioctl.sync_ioc_merge {
		result := sync_file_merge_ioctl(this.fence, u64(argp))
		if result < 0 { errno.set(u64(-result)); return none }
		return result
	}
	if u32(request) == ioctl.sync_ioc_file_info {
		result := sync_file_info_ioctl(this.fence, u64(argp), unsafe { &this.name[0] })
		if result < 0 { errno.set(u64(-result)); return none }
		return result
	}
	if u32(request) == ioctl.sync_ioc_set_deadline {
		result := sync_file_deadline_ioctl(this.fence, u64(argp))
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
	if this.owns_snapshot { syncobj.release_sync_file_snapshot(this.fence) }
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
	drm_devices_lock   klock.Lock
	prime_stat_dev_id  u64
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
				extensible: true
			}
		}
		ioctl.drm_ioctl_get_cap {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmGetCap))
				direction: ioctl_write | ioctl_read
				extensible: true
			}
		}
		ioctl.drm_ioctl_set_client_name {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSetClientName))
				direction: ioctl_write | ioctl_read
				extensible: true
				flags: ioctl_no_activity
			}
		}
		ioctl.drm_ioctl_gem_close {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmGemClose))
				direction: ioctl_write
				extensible: true
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
				extensible: true
			}
		}
		ioctl.drm_ioctl_syncobj_destroy {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjDestroy))
				direction: ioctl_write | ioctl_read
				extensible: true
			}
		}
		ioctl.drm_ioctl_syncobj_handle_to_fd, ioctl.drm_ioctl_syncobj_fd_to_handle {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjHandle))
				direction: ioctl_write | ioctl_read
				extensible: true
			}
		}
		ioctl.drm_ioctl_syncobj_wait {
			// Older userspace omits the trailing deadline_nsec field.
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjWait))
				direction: ioctl_write | ioctl_read
				extensible: true
			}
		}
		ioctl.drm_ioctl_syncobj_timeline_wait {
			DrmIoctlLayout{
				size: u32(sizeof(ioctl.DrmSyncobjTimelineWait))
				direction: ioctl_write | ioctl_read
				extensible: true
			}
		}
		ioctl.drm_ioctl_syncobj_transfer {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjTransfer)), direction: ioctl_write | ioctl_read, extensible: true }
		}
		ioctl.drm_ioctl_syncobj_reset, ioctl.drm_ioctl_syncobj_signal {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjArray)), direction: ioctl_write | ioctl_read, extensible: true }
		}
		ioctl.drm_ioctl_syncobj_query, ioctl.drm_ioctl_syncobj_timeline_signal {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjTimelineArray)), direction: ioctl_write | ioctl_read, extensible: true }
		}
		ioctl.drm_ioctl_syncobj_eventfd {
			DrmIoctlLayout{ size: u32(sizeof(ioctl.DrmSyncobjEventfd)), direction: ioctl_write | ioctl_read, extensible: true }
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

fn ioctl_layout(dev &DrmDevice, cmd u32, request_size u32, direction u32, abi u32) ?DrmIoctlLayout {
	if cmd >= ioctl.drm_command_base && cmd < ioctl.drm_command_end {
		return private_ioctl_layout(dev, cmd, request_size, direction, abi)
	}
	layout := common_ioctl_layout(cmd) or { return none }
	if layout.extensible {
		return DrmIoctlLayout{
			...layout
			direction: layout.direction & direction
		}
	}
	return layout
}

// A private request needs an entry in this driver's table. A handler-only
// entry can use the shared legacy layout, as the VirtIO GPU table does.
fn private_ioctl_layout(dev &DrmDevice, cmd u32, request_size u32, direction u32, abi u32) ?DrmIoctlLayout {
	if dev.driver == unsafe { nil } { return none }
	mut has_layout := false
	mut legacy_index := -1
	for index, entry in dev.driver.ioctls {
		if entry.cmd != cmd { continue }
		if entry.size == 0 || entry.direction == 0 {
			if legacy_index < 0 { legacy_index = index }
			continue
		}
		has_layout = true
		if (entry.extensible || entry.direction == direction)
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
	if has_layout || legacy_index < 0 || dev.driver.ioctls[legacy_index].handler == unsafe { nil } {
		return none
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
fn create_device_node(dev &DrmDevice, render bool) ?&DrmNode {
	storage := memory.malloc_packed_fallible(sizeof(DrmNode))
	if storage == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	box := memory.malloc_packed_fallible(sizeof(resource.Resource))
	if box == unsafe { nil } {
		memory.free(storage)
		errno.set(errno.enomem)
		return none
	}
	mut node := unsafe { &DrmNode(storage) }
	unsafe {
		*node = DrmNode{
			dev: dev
			render: render
			refcount: 1 // The devtmpfs name owns the initial reference.
		}
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

	// Adopt the separately allocated box without an implicit V allocation.
	unsafe { *(&voidptr(&node.box)) = box }
	unsafe { *node.box = resource.Resource(node) }
	return node
}

// The name borrows a 32-byte caller buffer. The fixed prefixes and a u64
// decimal suffix fit, including the terminating zero.
fn drm_node_name(buffer &u8, prefix string, number u64) string {
	unsafe { C.memcpy(buffer, prefix.str, prefix.len) }
	mut length := prefix.len
	mut scale := u64(1)
	for number / scale >= 10 { scale *= 10 }
	for scale != 0 {
		unsafe { buffer[length] = u8(`0`) + u8(number / scale % 10) }
		length++
		scale /= 10
	}
	unsafe {
		buffer[length] = 0
		return tos(buffer, length)
	}
}

fn publish_device_nodes(dev &DrmDevice) ? {
	// The borrowed names are used synchronously. An explicit stack slot
	// keeps V from promoting their buffers on this optional-return path.
	card_path := unsafe { &u8(C.vinix_stack_alloc(32)) }
	card_name := drm_node_name(card_path, 'card', u64(dev.dev_id))
	if dev.render_node == unsafe { nil } {
		return fs.devtmpfs_add_dri_devices(dev.node.box, card_name, unsafe { nil }, '')
	}
	render_path := unsafe { &u8(C.vinix_stack_alloc(32)) }
	render_name := drm_node_name(render_path, 'renderD', u64(128 + dev.dev_id))
	return fs.devtmpfs_add_dri_devices(dev.node.box, card_name, dev.render_node.box, render_name)
}

fn remove_device_nodes(dev &DrmDevice) {
	card_path := unsafe { &u8(C.vinix_stack_alloc(32)) }
	card_name := drm_node_name(card_path, 'card', u64(dev.dev_id))
	if dev.render_node == unsafe { nil } {
		fs.devtmpfs_remove_dri_devices(dev.node.box, card_name, unsafe { nil }, '')
		return
	}
	render_path := unsafe { &u8(C.vinix_stack_alloc(32)) }
	render_name := drm_node_name(render_path, 'renderD', u64(128 + dev.dev_id))
	fs.devtmpfs_remove_dri_devices(dev.node.box, card_name, dev.render_node.box, render_name)
}

fn (mut this DrmNode) open(flags int) ?&resource.Resource {
	// O_PATH pins the node for metadata. Only a device open needs registration.
	if flags & resource.o_path == 0 && (this.dev == unsafe { nil } || !this.dev.is_registered()) {
		errno.set(errno.enodev)
		return none
	}
	return this.box
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

fn (mut this DrmNode) admit_mapping_range(handle voidptr, offset u64, length u64, flags int) bool {
	if this.dev == unsafe { nil } || !this.dev.is_registered() {
		errno.set(errno.enodev)
		return false
	}
	if handle != unsafe { nil } && this.dev.driver != unsafe { nil }
		&& this.dev.driver.mmap_admit != unsafe { nil } {
		code := this.dev.driver.mmap_admit(this.dev, handle, offset, length, flags & mmap.map_shared != 0)
		if code == 0 { return true }
		errno.set(u64(-code))
		return false
	}
	return this.retain_mapping_range(handle, offset, length, flags)
}

fn (mut this DrmNode) mapping_can_grow() bool {
	return this.dev != unsafe { nil } && this.dev.is_registered()
		&& (this.dev.driver == unsafe { nil } || !this.dev.driver.mmap_no_expand)
}

// Existing VMAs can still retain and release backing through their own device.
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
	if this.dev == unsafe { nil } || this.dev.driver == unsafe { nil } || !this.dev.is_registered() {
		errno.set(errno.enodev)
		return none
	}
	cmd := decode_ioctl_cmd(request) or {
		errno.set(errno.enotty)
		return none
	}

	raw := u32(request & 0xffffffff)
	request_size := (raw >> ioctl_size_shift) & ioctl_size_mask
	request_direction := (raw >> ioctl_direction_shift) & ioctl_direction_mask
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

	update_client_process(handle)
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
	if handle != unsafe { nil } && unsafe { (&file.Handle(handle)).flags & resource.o_path == 0 } {
		mut description := unsafe { &file.Handle(handle) }
		if description.drm_client_id != 0 {
			mut dev := unsafe { this.dev }
			dev.remove_client(mut description)
		}
		if this.dev != unsafe { nil } && this.dev.driver != unsafe { nil }
			&& this.dev.driver.file_close != unsafe { nil } {
			this.dev.driver.file_close(this.dev, handle)
		}
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
	return register_driver_with_data(driver, unsafe { nil })
}

// Borrow a fixed ioctl table that outlives every registration using it.
@[unsafe]
pub fn static_ioctl_table(entries &DrmIoctl, count int) []DrmIoctl {
	mut view := []DrmIoctl{}
	unsafe {
		view.data = voidptr(entries)
		view.len = count
		view.cap = count
		view.flags = .nofree
	}
	return view
}

// Store a driver definition for the lifetime of its registered device.
// The definition transfers any owned ioctl table, including on failure.
pub fn register_driver_definition(definition DrmDriver, driver_data voidptr) ?&DrmDevice {
	storage := memory.malloc_packed_fallible(sizeof(DrmDriver))
	if storage == unsafe { nil } {
		unsafe { definition.ioctls.free() }
		errno.set(errno.enomem)
		return none
	}
	mut driver := unsafe { &DrmDriver(storage) }
	unsafe { *driver = definition }
	return register_owned_driver(driver, driver_data)
}

// Consume a heap driver descriptor and any owned ioctl table. On success
// the device keeps them for open files that can survive unregister.
pub fn register_owned_driver(driver &DrmDriver, driver_data voidptr) ?&DrmDevice {
	return register_driver_with_data(driver, driver_data) or {
		unsafe {
			driver.ioctls.free()
			free(driver)
		}
		return none
	}
}

fn discard_unpublished_device(dev &DrmDevice) {
	for node in [dev.node, dev.render_node]! {
		if node == unsafe { nil } { continue }
		memory.free(voidptr(node.box))
		memory.free(voidptr(node))
	}
	memory.free(voidptr(dev))
}

// Install driver-private context before publishing either device node.
// The caller keeps the context alive until every reference to the device and
// its open files is gone, including references that survive unregister.
pub fn register_driver_with_data(driver &DrmDriver, driver_data voidptr) ?&DrmDevice {
	mut dev := register_device_nodes(driver, driver_data)?
	publish_drm_sysfs(mut dev)
	// The slot and both device names are already reserved. Admit data opens
	// and registry lookups once the sysfs publisher has finished. Serialize
	// the transition with the registry's activity report.
	drm_devices_lock.acquire()
	katomic.store(mut dev.registered, true)
	drm_devices_lock.release()
	id := dev.dev_id
	C.kprintf(c'drm: Registered driver %.*s as card%llu\n', i32(driver.name.len), driver.name.str,
		u64(id))
	C.kprintf(c'drm: created device node /dev/dri/card%llu\n', u64(id))
	if dev.render_node != unsafe { nil } {
		C.kprintf(c'drm: created device node /dev/dri/renderD%llu\n', u64(128 + id))
	}
	return dev
}

fn register_device_nodes(driver &DrmDriver, driver_data voidptr) ?&DrmDevice {
	// Establish the permanent completion's timestamp during DRM startup.
	syncobj.shared_timeline_stub()
	drm_devices_lock.acquire()
	defer {
		drm_devices_lock.release()
	}

	mut id := u32(0)
	for id < u32(registered_devices.len) && registered_devices[id] != unsafe { nil } {
		id++
	}
	if id == u32(registered_devices.len) {
		errno.set(errno.ebusy)
		return none
	}

	storage := memory.malloc_packed_fallible(sizeof(DrmDevice))
	if storage == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	mut dev := unsafe { &DrmDevice(storage) }
	unsafe {
		*dev = DrmDevice{
			driver_data: driver_data
			dev_id: id
			driver: driver
			registered: false
		}
	}
	mut published := false
	defer {
		if !published { discard_unpublished_device(dev) }
	}

	dev.node = create_device_node(dev, false)?
	if driver.features & driver_render != 0 {
		dev.render_node = create_device_node(dev, true)?
	}
	// Devtmpfs checks both names before either node can become reachable.
	publish_device_nodes(dev)?
	published = true
	registered_devices[id] = dev
	return dev
}

// Unregister a DRM device and mark it as inactive. Its card number stays taken
// until its sysfs entries are gone, so a device registering meanwhile cannot
// get the same names and lose them to this removal.
pub fn unregister_device(dev &DrmDevice) {
	if !unregister_device_nodes(dev) { return }
	mut device := unsafe { dev }
	remove_drm_sysfs(mut device)
	release_device_slot(dev)
}

fn unregister_device_nodes(dev &DrmDevice) bool {
	drm_devices_lock.acquire()
	defer {
		drm_devices_lock.release()
	}

	// A retiring device keeps its slot but is no longer registered; a second
	// unregister finds it so and does nothing.
	if dev == unsafe { nil } || dev.dev_id >= u32(registered_devices.len)
		|| registered_devices[dev.dev_id] != dev || !dev.is_registered() { return false }
	mut d := unsafe { dev }
	katomic.store(mut d.registered, false)
	remove_device_nodes(dev)
	C.kprintf(c'drm: Unregistered card%llu\n', u64(dev.dev_id))
	return true
}

fn release_device_slot(dev &DrmDevice) {
	drm_devices_lock.acquire()
	if registered_devices[dev.dev_id] == dev {
		registered_devices[dev.dev_id] = unsafe { nil }
	}
	drm_devices_lock.release()
}

fn copy_version_field(address u64, capacity &u64, value string) bool {
	length := u64(value.len)
	copy_size := if *capacity < length { *capacity } else { length }
	unsafe { *capacity = length }
	return address == 0 || copy_size == 0 || usercopy.copy_to_user(address, voidptr(value.str), copy_size)
}

fn ioctl_version(dev &DrmDevice, data voidptr) int {
	if data == unsafe { nil } {
		return -14 // EFAULT
	}
	mut version := unsafe { &ioctl.DrmVersion(data) }
	version.version_major = i32(dev.driver.major)
	version.version_minor = i32(dev.driver.minor)
	version.version_patchlevel = i32(dev.driver.patchlevel)
	if !copy_version_field(version.name, unsafe { &version.name_len }, dev.driver.name)
		|| !copy_version_field(version.date, unsafe { &version.date_len }, dev.driver.date)
		|| !copy_version_field(version.desc, unsafe { &version.desc_len }, dev.driver.desc) {
		return -14
	}
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
		ioctl.drm_cap_syncobj, ioctl.drm_cap_timestamp_monotonic {
			cap.value = 1
			return 0
		}
		ioctl.drm_cap_syncobj_timeline {
			cap.value = u64(dev.driver.features & driver_syncobj_timeline != 0)
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
	if dev.driver.gem_close_request != unsafe { nil } {
		return dev.driver.gem_close_request(dev, handle, request)
	}
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

fn prime_stat_device() u64 {
	drm_devices_lock.acquire()
	defer { drm_devices_lock.release() }
	if prime_stat_dev_id == 0 {
		prime_stat_dev_id = resource.create_dev_id()
	}
	return prime_stat_dev_id
}

fn put_prime_object(dev &DrmDevice, obj &gem.GemObject) {
	if dev != unsafe { nil } && dev.driver != unsafe { nil }
		&& dev.driver.gem_export_put != unsafe { nil } {
		dev.driver.gem_export_put(dev, obj)
	} else {
		gem.unref(obj)
	}
}

// Consume the export reference on success and failure.
fn create_prime_fd(dev &DrmDevice, obj &gem.GemObject, flags u32, reservation &file.FdReservation) ?int {
	allocation := memory.malloc_packed_fallible(sizeof(GemPrimeResource))
	if allocation == unsafe { nil } {
		put_prime_object(dev, obj)
		errno.set(errno.enomem)
		return none
	}
	box := memory.malloc_packed_fallible(sizeof(resource.Resource))
	if box == unsafe { nil } {
		memory.free(allocation)
		put_prime_object(dev, obj)
		errno.set(errno.enomem)
		return none
	}
	mut wrapper := unsafe { &GemPrimeResource(allocation) }
	unsafe { *wrapper = GemPrimeResource{
		stat: stat.Stat{
			dev: prime_stat_device()
			// GEM offsets are globally unique and never reused, even if a handle is.
			ino: gem.create_mmap_offset(obj) / page_size
			mode: stat.ifreg | 0o600
			size: i64(obj.size)
			blksize: i64(4096)
			blocks: i64(obj.size / 512)
		}
		dev: dev
		obj: obj
		can_mmap: true
	} }
	// Adopt the separately allocated interface as in create_sync_file_fd_at.
	unsafe { *(&voidptr(&wrapper.box)) = box }
	unsafe { *wrapper.box = resource.Resource(wrapper) }
	mut fd_flags := 0
	if flags & ioctl.drm_cloexec != 0 {
		fd_flags |= resource.o_cloexec
	}
	if flags & ioctl.drm_rdwr != 0 {
		fd_flags |= resource.o_rdwr
	}
	mut res := wrapper.box
	return file.fdnum_create_from_reserved_resource(reservation, mut res, fd_flags)
}

fn ioctl_prime_handle_to_fd(dev &DrmDevice, handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } || dev.driver.gem_export == unsafe { nil } {
		return -22
	}
	mut request := unsafe { &ioctl.DrmPrimeHandle(data) }
	if request.flags & ~(ioctl.drm_cloexec | ioctl.drm_rdwr) != 0 {
		return -22
	}
	mut reservation := file.FdReservation{}
	file.reserve_fd(unsafe { nil }, unsafe { &reservation }) or { return -int(errno.get()) }
	defer { file.cancel_fd_reservation(unsafe { &reservation }) }
	obj := dev.driver.gem_export(dev, handle, request.handle) or { return -2 }
	if obj.vm_private_identity != 0 {
		put_prime_object(dev, obj)
		return -22
	}
	fdnum := create_prime_fd(dev, obj, request.flags, unsafe { &reservation }) or { return -int(errno.get()) }
	request.fd = i32(fdnum)
	return 0
}

fn ioctl_prime_fd_to_handle(dev &DrmDevice, handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } || dev.driver.gem_import == unsafe { nil } {
		return -22
	}
	mut request := unsafe { &ioctl.DrmPrimeHandle(data) }
	// Keep the DMA-BUF and its exporter reference live through handle import.
	mut fd := file.fd_from_fdnum(unsafe { nil }, request.fd) or { return -int(errno.get()) }
	defer { fd.unref() }
	if fd.handle.flags & resource.o_path != 0 { return -9 }
	mut res := fd.handle.resource
	if mut res is GemPrimeResource {
		if voidptr(res.dev) != voidptr(dev) || res.obj == unsafe { nil } { return -9 }
		request.handle = dev.driver.gem_import(dev, handle, res.obj) or { return -12 }
		return 0
	}
	return -22
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
	mut fd := new_sync_file_fd(fence, false, unsafe { nil }) or { return none }
	if reservation != unsafe { nil } {
		return file.fdnum_install_reserved_fd(reservation, fd) or { fd.unref(); return none }
	}
	return file.fdnum_create_from_fd(unsafe { nil }, fd, 0, false) or { fd.unref(); return none }
}

// If owns_snapshot is set, construction consumes the snapshot on every path.
fn new_sync_file_fd(fence &syncobj.DmaFence, owns_snapshot bool, name &u8) ?&file.FD {
	if fence == unsafe { nil } {
		return none
	}
	allocation := memory.malloc_packed_fallible(sizeof(SyncFileResource))
	if allocation == unsafe { nil } {
		if owns_snapshot { syncobj.release_sync_file_snapshot(fence) }
		errno.set(errno.enomem)
		return none
	}
	mut wrapper := unsafe { &SyncFileResource(allocation) }
	unsafe { *wrapper = SyncFileResource{
		fence: fence
		owns_snapshot: owns_snapshot
		status: if syncobj.is_signaled(fence) { file.pollin } else { 0 }
	} }
	if name != unsafe { nil } {
		unsafe { C.memcpy(&wrapper.name[0], name, sizeof(wrapper.name)) }
	}
	box := memory.malloc_packed_fallible(sizeof(resource.Resource))
	if box == unsafe { nil } {
		memory.free(allocation)
		if owns_snapshot { syncobj.release_sync_file_snapshot(fence) }
		errno.set(errno.enomem)
		return none
	}
	// A direct &Resource(voidptr) conversion boxes the pointer in V. Reinterpret
	// the pointer slot to adopt this already allocated interface storage.
	unsafe { *(&voidptr(&wrapper.box)) = box }
	unsafe { *wrapper.box = resource.Resource(wrapper) }
	mut res := wrapper.box
	return file.fd_create_from_resource(mut res, resource.o_cloexec)
}

// The caller holds an FD reference while using the borrowed fence.
pub fn sync_file_fence(fd &file.FD) ?&syncobj.DmaFence {
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
	known_flags := ioctl.drm_syncobj_handle_to_fd_export_sync_file | ioctl.drm_syncobj_handle_to_fd_timeline
	if request.flags & ~known_flags != 0 || request.pad != 0 {
		return -22
	}
	if request.flags & ioctl.drm_syncobj_handle_to_fd_export_sync_file == 0 {
		if request.point != 0 { return -22 }
		obj := syncobj.lookup_referenced(u64(handle), request.handle) or { return -22 }
		defer { syncobj.release_syncobj(obj) }
		request.fd = i32(create_syncobj_fd(obj) or { return -int(errno.get()) })
		return 0
	}
	// Linux reserves the number before sync-file source lookup. A full table
	// wins over missing handles/fences; private sync-file creation failure is
	// EINVAL. Opaque export instead resolves its object before reservation.
	mut reservation := file.FdReservation{}
	file.reserve_fd(unsafe { nil }, unsafe { &reservation }) or { return -int(errno.get()) }
	defer { file.cancel_fd_reservation(unsafe { &reservation }) }
	point := if request.flags & ioctl.drm_syncobj_handle_to_fd_timeline != 0 { request.point } else { u64(0) }
	source := find_syncobj_fence(u64(handle), request.handle, point, 0)
	if source.code != 0 { return source.code }
	fdnum := create_sync_file_fd_at(source.fence, unsafe { &reservation }) or { return -22 }
	request.fd = i32(fdnum)
	return 0
}

fn ioctl_syncobj_fd_to_handle(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } {
		return -14
	}
	mut request := unsafe { &ioctl.DrmSyncobjHandle(data) }
	known_flags := ioctl.drm_syncobj_fd_to_handle_import_sync_file | ioctl.drm_syncobj_fd_to_handle_timeline
	if request.flags & ~known_flags != 0 || request.pad != 0 || request.fd < 0 {
		return -22
	}
	if request.flags & ioctl.drm_syncobj_fd_to_handle_import_sync_file == 0 {
		if request.point != 0 { return -22 }
		obj := syncobj_from_fd(request.fd) or { return -22 }
		defer { syncobj.release_syncobj(obj) }
		request.handle = syncobj.import_syncobj(u64(handle), obj) or { return -12 }
		return 0
	}
	// Linux resolves the transport first. Even when both inputs are invalid,
	// an invalid sync-file is EINVAL; only a valid fence with no target is ENOENT.
	mut fd := file.fd_from_fdnum(unsafe { nil }, request.fd) or { return -22 }
	defer { fd.unref() }
	fence := sync_file_fence(fd) or { return -22 }
	obj := syncobj.lookup_referenced(u64(handle), request.handle) or { return -2 }
	defer { syncobj.release_syncobj(obj) }
	if request.flags & ioctl.drm_syncobj_fd_to_handle_timeline != 0 && request.point != 0 {
		chain := syncobj.reserve_chain() or { return -12 }
		defer { syncobj.release_chain_reservation(chain) }
		syncobj.retain_sync_file_snapshot(fence)
		if !syncobj.add_chain_point(obj, chain, fence, request.point) { return -22 }
	} else {
		syncobj.retain_sync_file_snapshot(fence)
		syncobj.replace_fence(obj, fence)
	}
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
	allow_future := request.flags & ioctl.drm_syncobj_wait_for_submit != 0
	wait_all := request.flags & ioctl.drm_syncobj_wait_all != 0
	mut ready_count := u32(0)
	mut first := ~u32(0)
	for i := u32(0); i < request.count_handles; i++ {
		fence := syncobj.prepare_capture(unsafe { &syncobj.SyncObj(buffer.objects[i]) },
			unsafe { &buffer.captures[i] }, allow_future) or { return -22 }
		if fence != unsafe { nil } && syncobj.is_signaled(fence) {
			if ready_count == 0 { first = i }
			ready_count++
		}
	}
	if ready_count == request.count_handles || (!wait_all && ready_count != 0) {
		request.first_signaled = first
		return 0
	}
	if allow_future {
		for i := u32(0); i < request.count_handles; i++ {
			syncobj.arm_capture(unsafe { &buffer.captures[i] })
		}
	}
	if request.flags & ioctl.drm_syncobj_wait_deadline != 0 {
		for i := u32(0); i < request.count_handles; i++ {
			if fence := syncobj.captured_fence(unsafe { &buffer.captures[i] }) {
				syncobj.set_deadline(fence, i64(request.deadline_nsec))
			}
		}
	}
	for {
		ready_count = 0
		for i := u32(0); i < request.count_handles; i++ {
			fence := syncobj.captured_fence(unsafe { &buffer.captures[i] }) or { continue }
			if syncobj.is_signaled(fence) {
				if !wait_all { request.first_signaled = i; return 0 }
				ready_count++
			}
		}
		if ready_count == request.count_handles {
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
	defer { buffer.release_object_references(request.count_handles) }
	for i := u32(0); i < request.count_handles; i++ {
		object := syncobj.lookup_referenced(u64(handle), unsafe { buffer.handles[i] }) or { return -2 }
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
		ioctl.drm_ioctl_set_client_name {
			return ioctl_set_client_name(handle, data)
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
		ioctl.drm_ioctl_syncobj_timeline_wait {
			return ioctl_syncobj_timeline_wait(handle, data)
		}
		ioctl.drm_ioctl_syncobj_transfer {
			return ioctl_syncobj_transfer(handle, data)
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
		ioctl.drm_ioctl_syncobj_timeline_signal {
			return ioctl_syncobj_timeline_signal(handle, data)
		}
		ioctl.drm_ioctl_syncobj_eventfd {
			return ioctl_syncobj_eventfd(handle, data)
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

	if !dev.is_registered() {
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

	if dev == unsafe { nil } || !dev.is_registered() {
		return none
	}
	return dev
}
