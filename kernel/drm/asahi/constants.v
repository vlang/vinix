// SPDX-License-Identifier: MIT
module asahi

// Linux-Aurora's extensible Asahi UAPI. Keep the older Mesa 25 ABI in
// drm.ioctl separate; overlapping request numbers carry different layouts.
pub const get_params = u32(0x40)
pub const get_time = u32(0x41)
pub const vm_create = u32(0x42)
pub const vm_destroy = u32(0x43)
pub const vm_bind = u32(0x44)
pub const gem_create = u32(0x45)
pub const gem_mmap_offset = u32(0x46)
pub const gem_bind_object = u32(0x47)
pub const queue_create = u32(0x48)
pub const queue_destroy = u32(0x49)
pub const submit = u32(0x4a)
pub const gem_madvise = u32(0x4b)
pub const max_commands = u32(64)
pub const max_attachments = u32(16)
pub const barrier_none = u16(0xffff)
pub const cmd_render = u16(0)
pub const cmd_compute = u16(1)
pub const set_vertex_attachments = u16(2)
pub const set_fragment_attachments = u16(3)
pub const set_compute_attachments = u16(4)
pub const bind_unbind = u32(1) << 0
pub const bind_read = u32(1) << 1
pub const bind_write = u32(1) << 2
pub const bind_single_page = u32(1) << 3
pub const gem_writeback = u32(1) << 0
pub const gem_vm_private = u32(1) << 1
pub const render_vertex_scratch = u32(1) << 0
pub const render_process_empty_tiles = u32(1) << 1
pub const render_no_vertex_clustering = u32(1) << 2
pub const render_dbias_is_int = u32(1) << 18
pub const render_supported = render_vertex_scratch | render_process_empty_tiles | render_no_vertex_clustering | render_dbias_is_int
