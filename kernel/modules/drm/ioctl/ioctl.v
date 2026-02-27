module ioctl

// DRM ioctl definitions for standard DRM commands and Asahi custom ioctls.
// No imports needed -- this module contains only constants and data structures.

// ---- Standard DRM ioctl numbers ----
pub const drm_ioctl_version = u32(0x00)
pub const drm_ioctl_get_cap = u32(0x0C)
pub const drm_ioctl_gem_close = u32(0x09)
pub const drm_ioctl_gem_open = u32(0x0B)
pub const drm_ioctl_prime_handle_to_fd = u32(0x2D)
pub const drm_ioctl_prime_fd_to_handle = u32(0x2E)
pub const drm_ioctl_syncobj_create = u32(0xBF)
pub const drm_ioctl_syncobj_destroy = u32(0xC0)
pub const drm_ioctl_syncobj_handle_to_fd = u32(0xC1)
pub const drm_ioctl_syncobj_fd_to_handle = u32(0xC2)
pub const drm_ioctl_syncobj_wait = u32(0xC7)
pub const drm_ioctl_syncobj_timeline_wait = u32(0xCA)

// ---- Asahi custom ioctl numbers (driver-specific, base 0x40) ----
pub const drm_asahi_base = u32(0x40)

pub const drm_asahi_get_params = drm_asahi_base + u32(0x00)
pub const drm_asahi_vm_create = drm_asahi_base + u32(0x01)
pub const drm_asahi_vm_destroy = drm_asahi_base + u32(0x02)
pub const drm_asahi_gem_create = drm_asahi_base + u32(0x03)
pub const drm_asahi_gem_mmap_offset = drm_asahi_base + u32(0x04)
pub const drm_asahi_gem_bind = drm_asahi_base + u32(0x05)
pub const drm_asahi_queue_create = drm_asahi_base + u32(0x06)
pub const drm_asahi_queue_destroy = drm_asahi_base + u32(0x07)
pub const drm_asahi_submit = drm_asahi_base + u32(0x08)
pub const drm_asahi_get_time = drm_asahi_base + u32(0x09)

// ---- Asahi ioctl data structures ----

pub struct DrmAsahiGetParams {
pub mut:
	param u32
	pad   u32
	value u64
}

pub struct DrmAsahiVmCreate {
pub mut:
	vm_id u32
	pad   u32
}

pub struct DrmAsahiVmDestroy {
pub mut:
	vm_id u32
	pad   u32
}

pub struct DrmAsahiGemCreate {
pub mut:
	size   u64
	flags  u32
	handle u32
	offset u64
}

pub struct DrmAsahiGemMmapOffset {
pub mut:
	handle u32
	pad    u32
	offset u64
}

pub struct DrmAsahiGemBind {
pub mut:
	op     u32
	flags  u32
	handle u32
	vm_id  u32
	offset u64
	range  u64
	addr   u64
}

pub struct DrmAsahiQueueCreate {
pub mut:
	flags    u32
	vm_id    u32
	queue_id u32
	priority u32
}

pub struct DrmAsahiQueueDestroy {
pub mut:
	queue_id u32
	pad      u32
}

pub struct DrmAsahiSubmit {
pub mut:
	queue_id       u32
	result_handle  u32
	cmds           u64 // pointer to command array
	cmd_count      u32
	flags          u32
	in_syncs       u64
	in_sync_count  u32
	out_syncs      u64
	out_sync_count u32
	pad            u32
}

// Command types for DrmAsahiCmd
pub const asahi_cmd_render = u32(0)
pub const asahi_cmd_compute = u32(1)

// Per-command descriptor in the submit command array
pub struct DrmAsahiCmd {
pub mut:
	cmd_type u32
	flags    u32
	// Render parameters (used when cmd_type == asahi_cmd_render)
	result_buf     u64
	result_size    u32
	// Vertex buffer
	vertex_buf     u64
	vertex_size    u64
	vertex_count   u32
	instance_count u32
	// Fragment buffer
	frag_buf       u64
	frag_size      u64
	// Dimensions
	width          u32
	height         u32
	layers         u32
	samples        u32
	tile_width     u32
	tile_height    u32
	// Scene / TVB
	scene_addr     u64
	tvb_addr       u64
	// Compute parameters (used when cmd_type == asahi_cmd_compute)
	compute_buf    u64
	compute_size   u64
	wg_x           u32
	wg_y           u32
	wg_z           u32
	grid_x         u32
	grid_y         u32
	grid_z         u32
	shared_mem     u32
	pad2           u32
}

// Sync point reference for in/out sync arrays
pub struct DrmAsahiSyncItem {
pub mut:
	handle u32
	point  u32
}
