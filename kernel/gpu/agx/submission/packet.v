// SPDX-License-Identifier: GPL-2.0-or-later
module submission

import drm.asahi
import drm.ioctl
import gpu.agx.command as agxcommand
import gpu.agx.compute as agxcompute
import gpu.agx.packet
import gpu.agx.render as agxrender

// Decoded modern input, before file-owned timestamp lookup and job creation.
// Timestamp names must be resolved and retained by a future modern submit
// handler before dispatch. The registered Mesa 25 path uses Command directly.
pub struct PacketCommand {
pub:
	command Command
	timestamps [3]asahi.Timestamps // vertex, fragment, compute
}

// Caller-owned scratch keeps mutable parser state out of V's implicit heap
// promotion. It is reset for each decode and never retained by the adapter.
pub struct PacketWorkspace {
mut:
	reader packet.Reader
	input packet.Command
}

pub fn (command &PacketCommand) needs_timestamp_objects() bool {
	for timestamps in command.timestamps {
		if timestamps.start.handle != 0 || timestamps.end.handle != 0 { return true }
	}
	return false
}

fn packet_barrier(value u16) u32 {
	return if value == asahi.barrier_none { ioctl.asahi_barrier_none } else { u32(value) }
}

// Asahi's modern attachments use a fixed exponent of one. Zero addresses
// and sizes retain the parser's semantics; legacy attachment validation is
// separate and still validates its explicit per-record exponent.
fn packet_attachments(count u32, input [16]packet.Attachment) [16]agxcommand.Attachment {
	mut attachments := [16]agxcommand.Attachment{}
	for index := u32(0); index < count; index++ {
		attachments[index] = agxcommand.Attachment{
			address: input[index].address
			size_bytes: input[index].size_bytes
			cache_lines: input[index].cache_lines
			order: 1
		}
	}
	return attachments
}

fn packet_compute(input &packet.Command, usc_base u64, flush_stamps bool) agxcompute.Command {
	return agxcompute.Command{
		encoder_ptr: input.compute.cdm_ctrl_stream_base
		encoder_end: input.compute.cdm_ctrl_stream_end
		usc_base: usc_base
		helper_program: input.compute.helper.binary
		helper_cfg: input.compute.helper.cfg
		helper_arg: input.compute.helper.data
		sampler_array: input.compute.sampler_heap
		sampler_count: input.compute.sampler_count
		sampler_max: input.compute.sampler_count + u32(1)
		unk_mask: ~u32(0)
		attachment_count: input.compute_count
		attachments: packet_attachments(input.compute_count, input.compute_attachments)
		flush_stamps: flush_stamps
	}
}

fn packet_render(input &packet.Command, usc_base u64, flush_stamps bool) agxrender.Command {
	value := input.render
	mut flags := agxrender.no_clear_pipeline_textures
	if value.flags & asahi.render_vertex_scratch != 0 { flags |= agxrender.vertex_spills }
	if value.flags & asahi.render_process_empty_tiles != 0 { flags |= agxrender.process_empty_tiles }
	if value.flags & asahi.render_no_vertex_clustering != 0 { flags |= agxrender.no_vertex_clustering }
	return agxrender.Command{
		flags: flags
		encoder_ptr: value.vdm_ctrl_stream_base
		vertex_usc_base: usc_base
		fragment_usc_base: usc_base
		vertex_helper_program: value.vertex_helper.binary
		vertex_helper_cfg: value.vertex_helper.cfg
		vertex_helper_arg: value.vertex_helper.data
		fragment_helper_program: value.fragment_helper.binary
		fragment_helper_cfg: value.fragment_helper.cfg
		fragment_helper_arg: value.fragment_helper.data
		depth_buffer_load: value.depth.base
		depth_buffer_store: value.depth.base
		depth_buffer_partial: value.depth.base
		depth_buffer_load_stride: u64(value.depth.stride)
		depth_buffer_store_stride: u64(value.depth.stride)
		depth_buffer_partial_stride: u64(value.depth.stride)
		depth_meta_buffer_load: value.depth.comp_base
		depth_meta_buffer_store: value.depth.comp_base
		depth_meta_buffer_partial: value.depth.comp_base
		depth_meta_buffer_load_stride: u64(value.depth.comp_stride)
		depth_meta_buffer_store_stride: u64(value.depth.comp_stride)
		depth_meta_buffer_partial_stride: u64(value.depth.comp_stride)
		stencil_buffer_load: value.stencil.base
		stencil_buffer_store: value.stencil.base
		stencil_buffer_partial: value.stencil.base
		stencil_buffer_load_stride: u64(value.stencil.stride)
		stencil_buffer_store_stride: u64(value.stencil.stride)
		stencil_buffer_partial_stride: u64(value.stencil.stride)
		stencil_meta_buffer_load: value.stencil.comp_base
		stencil_meta_buffer_store: value.stencil.comp_base
		stencil_meta_buffer_partial: value.stencil.comp_base
		stencil_meta_buffer_load_stride: u64(value.stencil.comp_stride)
		stencil_meta_buffer_store_stride: u64(value.stencil.comp_stride)
		stencil_meta_buffer_partial_stride: u64(value.stencil.comp_stride)
		scissor_array: value.isp_scissor_base
		depth_bias_array: value.isp_dbias_base
		visibility_result_buffer: value.isp_oclqry_base
		vertex_sampler_array: value.sampler_heap
		fragment_sampler_array: value.sampler_heap
		vertex_sampler_count: u32(value.sampler_count)
		fragment_sampler_count: u32(value.sampler_count)
		vertex_sampler_max: u32(value.sampler_count) + 1
		fragment_sampler_max: u32(value.sampler_count) + 1
		zls_control: value.zls_ctrl
		ppp_multisamplectl: value.ppp_multisamplectl
		ppp_control: value.ppp_ctrl
		framebuffer_width: u32(value.width_px)
		framebuffer_height: u32(value.height_px)
		utile_width: u32(value.utile_width_px)
		utile_height: u32(value.utile_height_px)
		samples: u32(value.samples)
		layers: u32(value.layers)
		sample_size: u32(value.sample_size_b)
		iogpu_unk_214: u32(0xc000) | (value.flags & asahi.render_dbias_is_int)
		merge_upper_x: value.isp_merge_upper_x
		merge_upper_y: value.isp_merge_upper_y
		load_pipeline: value.bg.usc
		load_pipeline_bind: value.bg.rsrc_spec
		store_pipeline: value.eot.usc
		store_pipeline_bind: value.eot.rsrc_spec
		partial_reload_pipeline: value.partial_bg.usc
		partial_reload_pipeline_bind: value.partial_bg.rsrc_spec
		partial_store_pipeline: value.partial_eot.usc
		partial_store_pipeline_bind: value.partial_eot.rsrc_spec
		depth_dimensions: value.isp_zls_pixels
		isp_bgobjdepth: value.isp_bgobjdepth
		isp_bgobjvals: value.isp_bgobjvals
		vertex_attachment_count: input.vertex_count
		fragment_attachment_count: input.fragment_count
		vertex_attachments: packet_attachments(input.vertex_count, input.vertex_attachments)
		fragment_attachments: packet_attachments(input.fragment_count, input.fragment_attachments)
		flush_stamps: flush_stamps
	}
}

// Caller supplies immutable copied bytes, output storage and parser scratch.
// No allocation, userspace access, timestamp lookup or job publication occurs.
// A failure returns zero usable commands; the caller discards any staged prefix.
pub fn decode_packet(data voidptr, size u64, usc_base u64, flush_stamps bool,
	mut staged []PacketCommand, mut workspace PacketWorkspace) (int, u32) {
	if staged.len == 0 || staged.len > int(max_commands) { return -22, 0 }
	workspace.reader = packet.reader(data, size)
	input := unsafe { &workspace.input }
	mut count := u32(0)
	for {
		code := workspace.reader.next(mut workspace.input)
		if code < 0 { return code, 0 }
		if code == 1 { return if count == 0 { -22 } else { 0 }, count }
		if count >= u32(staged.len) { return -22, 0 }
		mut timestamps := [3]asahi.Timestamps{}
		barriers := [packet_barrier(input.header.vdm_barrier), packet_barrier(input.header.cdm_barrier)]!
		command := if input.header.cmd_type == asahi.cmd_render {
			timestamps[0] = input.render.ts_vtx
			timestamps[1] = input.render.ts_frag
			Command{descriptor: ioctl.DrmAsahiCommand{cmd_type: ioctl.asahi_cmd_render, barriers: barriers},
				render: packet_render(input, usc_base, flush_stamps)}
		} else {
			timestamps[2] = input.compute.ts
			Command{descriptor: ioctl.DrmAsahiCommand{cmd_type: ioctl.asahi_cmd_compute, barriers: barriers},
				compute: packet_compute(input, usc_base, flush_stamps)}
		}
		staged[count] = PacketCommand{command: command, timestamps: timestamps}
		count++
	}
	return -22, 0
}
