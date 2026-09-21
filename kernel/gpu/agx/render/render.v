// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module render

// Generation-neutral render input shared by the native and fake AGX
// backends. Mesa's unstable Asahi UAPI is copied and validated here once;
// backend code never follows userspace pointers or reparses attachments.

import drm.ioctl
import gpu.agx.command as agxcommand

pub const max_dimension = u32(16384)
pub const max_layers = u32(2048)
pub const no_clear_pipeline_textures = u64(1) << 0
pub const set_when_reloading_z_or_s = u64(1) << 1
pub const vertex_spills = u64(1) << 2
pub const process_empty_tiles = u64(1) << 3
pub const no_vertex_clustering = u64(1) << 4
pub const msaa_zs = u64(1) << 5
pub const no_preemption = u64(1) << 6
pub const supported_flags = no_clear_pipeline_textures | set_when_reloading_z_or_s | vertex_spills | process_empty_tiles | no_vertex_clustering | msaa_zs | no_preemption

pub struct Command {
pub:
	flags                              u64
	encoder_ptr                        u64
	vertex_usc_base                    u64
	fragment_usc_base                  u64
	vertex_helper_program              u32
	fragment_helper_program            u32
	vertex_helper_cfg                  u32
	fragment_helper_cfg                u32
	vertex_helper_arg                  u64
	fragment_helper_arg                u64
	depth_buffer_load                  u64
	depth_buffer_load_stride           u64
	depth_buffer_store                 u64
	depth_buffer_store_stride          u64
	depth_buffer_partial               u64
	depth_buffer_partial_stride        u64
	depth_meta_buffer_load             u64
	depth_meta_buffer_load_stride      u64
	depth_meta_buffer_store            u64
	depth_meta_buffer_store_stride     u64
	depth_meta_buffer_partial          u64
	depth_meta_buffer_partial_stride   u64
	stencil_buffer_load                u64
	stencil_buffer_load_stride         u64
	stencil_buffer_store               u64
	stencil_buffer_store_stride        u64
	stencil_buffer_partial             u64
	stencil_buffer_partial_stride      u64
	stencil_meta_buffer_load           u64
	stencil_meta_buffer_load_stride    u64
	stencil_meta_buffer_store          u64
	stencil_meta_buffer_store_stride   u64
	stencil_meta_buffer_partial        u64
	stencil_meta_buffer_partial_stride u64
	scissor_array                      u64
	depth_bias_array                   u64
	visibility_result_buffer           u64
	vertex_sampler_array               u64
	vertex_sampler_count               u32
	vertex_sampler_max                 u32
	fragment_sampler_array             u64
	fragment_sampler_count             u32
	fragment_sampler_max               u32
	zls_control                        u64
	ppp_multisamplectl                 u64
	ppp_control                        u32
	framebuffer_width                  u32
	framebuffer_height                 u32
	utile_width                        u32
	utile_height                       u32
	samples                            u32
	layers                             u32
	encoder_id                         u32
	vertex_command_id                  u32
	fragment_command_id                u32
	sample_size                        u32
	tib_blocks                         u32
	iogpu_unk_214                      u32
	merge_upper_x                      u32
	merge_upper_y                      u32
	load_pipeline                      u32
	load_pipeline_bind                 u32
	store_pipeline                     u32
	store_pipeline_bind                u32
	partial_reload_pipeline            u32
	partial_reload_pipeline_bind       u32
	partial_store_pipeline             u32
	partial_store_pipeline_bind        u32
	depth_dimensions                   u32
	isp_bgobjdepth                     u32
	isp_bgobjvals                      u32
	vertex_attachment_count            u32
	fragment_attachment_count          u32
	vertex_attachments                 [16]agxcommand.Attachment
	fragment_attachments               [16]agxcommand.Attachment
	has_result                         bool
	flush_stamps                       bool
}

pub fn valid_uapi(command &ioctl.DrmAsahiCmdRender) bool {
	if command.extensions != 0 || command.flags & ~supported_flags != 0
		|| command.fb_width == 0 || command.fb_width > max_dimension
		|| command.fb_height == 0 || command.fb_height > max_dimension
		|| command.layers == 0 || command.layers > max_layers {
		return false
	}
	if !((command.utile_width == 32 && command.utile_height == 32)
		|| (command.utile_width == 32 && command.utile_height == 16)
		|| (command.utile_width == 16 && command.utile_height == 16)) {
		return false
	}
	if command.samples != 1 && command.samples != 2 && command.samples != 4 {
		return false
	}
	return command.vertex_attachment_count <= agxcommand.max_attachments
		&& command.fragment_attachment_count <= agxcommand.max_attachments
		&& (command.vertex_attachment_count == 0 || command.vertex_attachments != 0)
		&& (command.fragment_attachment_count == 0 || command.fragment_attachments != 0)
}

// Snapshot the nested attachment arrays before any driver lock is acquired.
// A successful result contains no userspace pointers except GPU virtual
// addresses, so every backend observes exactly the command that was checked.
pub fn stage_uapi(command &ioctl.DrmAsahiCmdRender, has_result bool) (int, Command) {
	mut staged := Command{}
	if !valid_uapi(command) {
		return -22, staged
	}
	vertex_result, vertex_attachments := agxcommand.stage_attachments(command.vertex_attachments, command.vertex_attachment_count)
	if vertex_result != 0 {
		return vertex_result, staged
	}
	fragment_result, fragment_attachments := agxcommand.stage_attachments(command.fragment_attachments, command.fragment_attachment_count)
	if fragment_result != 0 {
		return fragment_result, staged
	}
	staged = Command{
		flags: command.flags
		encoder_ptr: command.encoder_ptr
		vertex_usc_base: command.vertex_usc_base
		fragment_usc_base: command.fragment_usc_base
		vertex_helper_program: command.vertex_helper_program
		fragment_helper_program: command.fragment_helper_program
		vertex_helper_cfg: command.vertex_helper_cfg
		fragment_helper_cfg: command.fragment_helper_cfg
		vertex_helper_arg: command.vertex_helper_arg
		fragment_helper_arg: command.fragment_helper_arg
		depth_buffer_load: command.depth_buffer_load
		depth_buffer_load_stride: command.depth_buffer_load_stride
		depth_buffer_store: command.depth_buffer_store
		depth_buffer_store_stride: command.depth_buffer_store_stride
		depth_buffer_partial: command.depth_buffer_partial
		depth_buffer_partial_stride: command.depth_buffer_partial_stride
		depth_meta_buffer_load: command.depth_meta_buffer_load
		depth_meta_buffer_load_stride: command.depth_meta_buffer_load_stride
		depth_meta_buffer_store: command.depth_meta_buffer_store
		depth_meta_buffer_store_stride: command.depth_meta_buffer_store_stride
		depth_meta_buffer_partial: command.depth_meta_buffer_partial
		depth_meta_buffer_partial_stride: command.depth_meta_buffer_partial_stride
		stencil_buffer_load: command.stencil_buffer_load
		stencil_buffer_load_stride: command.stencil_buffer_load_stride
		stencil_buffer_store: command.stencil_buffer_store
		stencil_buffer_store_stride: command.stencil_buffer_store_stride
		stencil_buffer_partial: command.stencil_buffer_partial
		stencil_buffer_partial_stride: command.stencil_buffer_partial_stride
		stencil_meta_buffer_load: command.stencil_meta_buffer_load
		stencil_meta_buffer_load_stride: command.stencil_meta_buffer_load_stride
		stencil_meta_buffer_store: command.stencil_meta_buffer_store
		stencil_meta_buffer_store_stride: command.stencil_meta_buffer_store_stride
		stencil_meta_buffer_partial: command.stencil_meta_buffer_partial
		stencil_meta_buffer_partial_stride: command.stencil_meta_buffer_partial_stride
		scissor_array: command.scissor_array
		depth_bias_array: command.depth_bias_array
		visibility_result_buffer: command.visibility_result_buffer
		vertex_sampler_array: command.vertex_sampler_array
		vertex_sampler_count: command.vertex_sampler_count
		vertex_sampler_max: command.vertex_sampler_max
		fragment_sampler_array: command.fragment_sampler_array
		fragment_sampler_count: command.fragment_sampler_count
		fragment_sampler_max: command.fragment_sampler_max
		zls_control: command.zls_ctrl
		ppp_multisamplectl: command.ppp_multisamplectl
		ppp_control: command.ppp_ctrl
		framebuffer_width: command.fb_width
		framebuffer_height: command.fb_height
		utile_width: command.utile_width
		utile_height: command.utile_height
		samples: command.samples
		layers: command.layers
		encoder_id: command.encoder_id
		vertex_command_id: command.cmd_ta_id
		fragment_command_id: command.cmd_3d_id
		sample_size: command.sample_size
		tib_blocks: command.tib_blocks
		iogpu_unk_214: command.iogpu_unk_214
		merge_upper_x: command.merge_upper_x
		merge_upper_y: command.merge_upper_y
		load_pipeline: command.load_pipeline
		load_pipeline_bind: command.load_pipeline_bind
		store_pipeline: command.store_pipeline
		store_pipeline_bind: command.store_pipeline_bind
		partial_reload_pipeline: command.partial_reload_pipeline
		partial_reload_pipeline_bind: command.partial_reload_pipeline_bind
		partial_store_pipeline: command.partial_store_pipeline
		partial_store_pipeline_bind: command.partial_store_pipeline_bind
		depth_dimensions: command.depth_dimensions
		isp_bgobjdepth: command.isp_bgobjdepth
		isp_bgobjvals: command.isp_bgobjvals
		vertex_attachment_count: command.vertex_attachment_count
		fragment_attachment_count: command.fragment_attachment_count
		vertex_attachments: vertex_attachments
		fragment_attachments: fragment_attachments
		has_result: has_result
		flush_stamps: true
	}
	return 0, staged
}
