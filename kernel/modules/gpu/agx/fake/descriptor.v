// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fake

// Pure software staging for the recovered G17 3D descriptor. Provenance is
// kept next to every value admitted to the fake native path: recovered scalar
// defaults are written here, while Mesa resource VAs are carried as an
// independently verified sidecar until their native descriptor members are
// proven. A proprietary Apple payload offset is never treated as a Mesa UAPI
// offset.

import gpu.agx.render as agxrender
import gpu.agx.fw

pub const g17_command_bytes = u64(fw.g17_command_3d_size)
pub const g17_descriptor_bytes = fw.g17_3d_descriptor_size
pub const g17_descriptor_member_pending = ~u32(0)

pub enum G17DescriptorProvenance as u32 {
	constant
	mesa_command
	bo_resource
	gpu_va
	format_stride
	external_hardware
}

// Stable identifiers make verifier failures actionable without embedding
// strings in the kernel ABI. Attachment identifiers describe an indexed
// family; the resource-reference order supplies the attachment index.
pub enum G17RenderResourceField as u32 {
	encoder
	vertex_helper_argument
	fragment_helper_argument
	depth_buffer_load
	depth_buffer_store
	depth_buffer_partial
	depth_meta_buffer_load
	depth_meta_buffer_store
	depth_meta_buffer_partial
	stencil_buffer_load
	stencil_buffer_store
	stencil_buffer_partial
	stencil_meta_buffer_load
	stencil_meta_buffer_store
	stencil_meta_buffer_partial
	scissor_array
	depth_bias_array
	visibility_result_buffer
	vertex_sampler_array
	fragment_sampler_array
	vertex_attachment
	fragment_attachment
	vertex_helper_program
	fragment_helper_program
	load_pipeline
	store_pipeline
	partial_reload_pipeline
	partial_store_pipeline
}

pub fn initialize_render_descriptor(descriptor voidptr, descriptor_bytes u64) bool {
	return fw.initialize_g17_3d_descriptor(descriptor, descriptor_bytes)
}

fn append_render_resource(mut resources []FakeG17ResourceReference,
	field G17RenderResourceField, provenance G17DescriptorProvenance,
	address u64, size u64, access u32) {
	if address == 0 {
		return
	}
	resources << FakeG17ResourceReference{
		address: address
		size: if size == 0 { u64(1) } else { size }
		field: u32(field)
		provenance: u32(provenance)
		descriptor_member: g17_descriptor_member_pending
		descriptor_bytes: 0
		access: access
	}
}

// Mesa's helper and clear/store pipeline fields are USC-heap-relative u32
// offsets. Their low bits are flags rather than address bits: helper programs
// reserve bit zero, while render pipelines reserve the low three bits. Keep
// this UAPI translation separate from native descriptor-member recovery.
fn append_usc_resource(mut resources []FakeG17ResourceReference,
	field G17RenderResourceField, base u64, encoded_offset u32,
	flag_mask u32) {
	if encoded_offset == 0 {
		return
	}
	offset := u64(encoded_offset & ~flag_mask)
	append_render_resource(mut resources, field, .gpu_va, base + offset, 1,
		fake_g17_vm_read)
}

fn sampler_array_bytes(count u32) u64 {
	// AGX sampler descriptors are eight bytes each. A non-null zero-count
	// array still validates its base byte without claiming an element exists.
	return if count == 0 { u64(1) } else { u64(count) * u64(8) }
}

// Build the Mesa-resource portion of the native G17 descriptor provenance
// graph. These records already have real lifetime and VM semantics even
// though their G17 member offsets are intentionally PENDING. Once recovery
// assigns a member, the C verifier will additionally require that exact VA at
// that member before it allows synthetic completion.
pub fn stage_render_resource_references(command &agxrender.Command) []FakeG17ResourceReference {
	mut resources := []FakeG17ResourceReference{cap: 64}
	append_render_resource(mut resources, .encoder, .gpu_va, command.encoder_ptr, 4, fake_g17_vm_read)
	append_render_resource(mut resources, .vertex_helper_argument, .gpu_va, command.vertex_helper_arg, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .fragment_helper_argument, .gpu_va, command.fragment_helper_arg, 8, fake_g17_vm_read)
	append_usc_resource(mut resources, .vertex_helper_program,
		command.vertex_usc_base, command.vertex_helper_program, u32(1))
	append_usc_resource(mut resources, .fragment_helper_program,
		command.fragment_usc_base, command.fragment_helper_program, u32(1))
	append_usc_resource(mut resources, .load_pipeline, command.fragment_usc_base,
		command.load_pipeline, u32(7))
	append_usc_resource(mut resources, .store_pipeline, command.fragment_usc_base,
		command.store_pipeline, u32(7))
	append_usc_resource(mut resources, .partial_reload_pipeline,
		command.fragment_usc_base, command.partial_reload_pipeline, u32(7))
	append_usc_resource(mut resources, .partial_store_pipeline,
		command.fragment_usc_base, command.partial_store_pipeline, u32(7))
	append_render_resource(mut resources, .depth_buffer_load, .gpu_va, command.depth_buffer_load, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .depth_buffer_store, .gpu_va, command.depth_buffer_store, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .depth_buffer_partial, .gpu_va, command.depth_buffer_partial, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .depth_meta_buffer_load, .gpu_va, command.depth_meta_buffer_load, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .depth_meta_buffer_store, .gpu_va, command.depth_meta_buffer_store, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .depth_meta_buffer_partial, .gpu_va, command.depth_meta_buffer_partial, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .stencil_buffer_load, .gpu_va, command.stencil_buffer_load, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .stencil_buffer_store, .gpu_va, command.stencil_buffer_store, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .stencil_buffer_partial, .gpu_va, command.stencil_buffer_partial, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .stencil_meta_buffer_load, .gpu_va, command.stencil_meta_buffer_load, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .stencil_meta_buffer_store, .gpu_va, command.stencil_meta_buffer_store, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .stencil_meta_buffer_partial, .gpu_va, command.stencil_meta_buffer_partial, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .scissor_array, .gpu_va, command.scissor_array, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .depth_bias_array, .gpu_va, command.depth_bias_array, 8, fake_g17_vm_read)
	append_render_resource(mut resources, .visibility_result_buffer, .gpu_va, command.visibility_result_buffer, 8, fake_g17_vm_write)
	append_render_resource(mut resources, .vertex_sampler_array, .gpu_va,
		command.vertex_sampler_array, sampler_array_bytes(command.vertex_sampler_count),
		fake_g17_vm_read)
	append_render_resource(mut resources, .fragment_sampler_array, .gpu_va,
		command.fragment_sampler_array, sampler_array_bytes(command.fragment_sampler_count),
		fake_g17_vm_read)
	for index := u32(0); index < command.vertex_attachment_count; index++ {
		attachment := command.vertex_attachments[index]
		append_render_resource(mut resources, .vertex_attachment, .bo_resource, attachment.address, attachment.size_bytes, fake_g17_vm_read)
	}
	for index := u32(0); index < command.fragment_attachment_count; index++ {
		attachment := command.fragment_attachments[index]
		append_render_resource(mut resources, .fragment_attachment, .bo_resource, attachment.address, attachment.size_bytes, fake_g17_vm_read)
	}
	return resources
}
