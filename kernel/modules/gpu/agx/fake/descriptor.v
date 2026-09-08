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

pub const g17_command_bytes = u64(0x2240)
pub const g17_descriptor_bytes = u64(0x15b0)
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
}

pub struct G17DescriptorScalar {
pub:
	member     u32
	bytes      u32
	value      u64
	provenance G17DescriptorProvenance
}

// 17 unique nonzero defaults recovered from the selected derived initializer.
// This manifest is the source of the writes below, not descriptive metadata
// maintained beside an independent list of stores.
const g17_render_descriptor_scalars = [
	G17DescriptorScalar{ member: 0x144, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x1c1, bytes: 2, value: 0x101, provenance: .constant },
	G17DescriptorScalar{ member: 0x2d4, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x400, bytes: 4, value: 1, provenance: .constant },
	G17DescriptorScalar{ member: 0x410, bytes: 4, value: 2, provenance: .constant },
	G17DescriptorScalar{ member: 0x900, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x968, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0xaa0, bytes: 8, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0xb60, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0xc30, bytes: 4, value: 1, provenance: .constant },
	G17DescriptorScalar{ member: 0xe18, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0xf60, bytes: 4, value: 2, provenance: .constant },
	G17DescriptorScalar{ member: 0x1208, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x1264, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x126c, bytes: 4, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x13a8, bytes: 8, value: 0xffff_ffff, provenance: .constant },
	G17DescriptorScalar{ member: 0x13e8, bytes: 4, value: 0xffff_ffff, provenance: .constant },
]

fn write_descriptor_value(destination &u8, offset u64, bytes u64, value u64) {
	unsafe {
		C.memcpy(voidptr(destination + offset), &value, bytes)
	}
}

fn render_descriptor_scalar_manifest_valid() bool {
	for index, field in g17_render_descriptor_scalars {
		if field.provenance != .constant
			|| (field.bytes != 1 && field.bytes != 2 && field.bytes != 4
				&& field.bytes != 8)
			|| u64(field.member) > g17_descriptor_bytes
			|| u64(field.bytes) > g17_descriptor_bytes - u64(field.member) {
			return false
		}
		for previous := 0; previous < index; previous++ {
			other := g17_render_descriptor_scalars[previous]
			if field.member < other.member + other.bytes
				&& other.member < field.member + field.bytes {
				return false
			}
		}
	}
	return true
}

pub fn initialize_render_descriptor(descriptor voidptr, descriptor_bytes u64) bool {
	if descriptor == unsafe { nil } || descriptor_bytes < g17_descriptor_bytes {
		return false
	}
	if !render_descriptor_scalar_manifest_valid() {
		return false
	}
	unsafe {
		C.memset(descriptor, 0, g17_descriptor_bytes)
		destination := &u8(descriptor)
		for field in g17_render_descriptor_scalars {
			write_descriptor_value(destination, field.member, field.bytes, field.value)
		}
	}
	return true
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
	append_render_resource(mut resources, .vertex_sampler_array, .gpu_va, command.vertex_sampler_array, if command.vertex_sampler_count == 0 {
		u64(1)
	} else {
		u64(command.vertex_sampler_count)
	}, fake_g17_vm_read)
	append_render_resource(mut resources, .fragment_sampler_array, .gpu_va, command.fragment_sampler_array, if command.fragment_sampler_count == 0 {
		u64(1)
	} else {
		u64(command.fragment_sampler_count)
	}, fake_g17_vm_read)
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
