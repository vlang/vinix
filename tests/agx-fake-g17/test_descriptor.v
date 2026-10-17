// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import gpu.agx.fw

fn C.kprintf(format &char, ...) i32

fn read_le_u64(bytes []u8, offset u32) u64 {
	mut value := u64(0)
	for index := u32(0); index < 8; index++ {
		value |= u64(bytes[int(offset + index)]) << (index * 8)
	}
	return value
}

fn main() {
	mut descriptor := []u8{len: int(fw.g17_3d_descriptor_size)}
	fields := fw.G17RenderDescriptorFields{
		encoder: 0x1111_1111_1111_1111
		load_pipeline_bind: 0x2222_2222_2222_2222
		load_pipeline: 0x3333_3333_3333_3333
		store_pipeline_bind: 0x4444_4444_4444_4444
		store_pipeline: 0x5555_5555_5555_5555
		depth_buffer_load: 0x6666_6666_6666_6666
		depth_buffer_store: 0x7777_7777_7777_7777
		depth_meta_load: 0x8888_8888_8888_8888
		depth_meta_store: 0x9999_9999_9999_9999
		stencil_buffer_load: 0xaaaa_aaaa_aaaa_aaaa
		stencil_buffer_store: 0xbbbb_bbbb_bbbb_bbbb
		stencil_meta_load: 0xcccc_cccc_cccc_cccc
		stencil_meta_store: 0xdddd_dddd_dddd_dddd
		visibility_result_buffer: 0xeeee_eeee_eeee_eee0
	}

	assert fw.initialize_g17_3d_descriptor(descriptor.data, u64(descriptor.len))
	assert fw.populate_g17_render_resource_fields(descriptor.data, u64(descriptor.len), fields)
	assert read_le_u64(descriptor, fw.g17_render_encoder_member) == fields.encoder
	assert read_le_u64(descriptor, fw.g17_render_load_pipeline_bind_member) == fields.load_pipeline_bind
	assert read_le_u64(descriptor, fw.g17_render_load_pipeline_member) == fields.load_pipeline
	assert read_le_u64(descriptor, fw.g17_render_store_pipeline_bind_member) == fields.store_pipeline_bind
	assert read_le_u64(descriptor, fw.g17_render_store_pipeline_member) == fields.store_pipeline
	assert read_le_u64(descriptor, fw.g17_render_depth_buffer_load_member) == fields.depth_buffer_load
	assert read_le_u64(descriptor, fw.g17_render_depth_buffer_store_member) == fields.depth_buffer_store
	assert read_le_u64(descriptor, fw.g17_render_depth_meta_buffer_load_member) == fields.depth_meta_load
	assert read_le_u64(descriptor, fw.g17_render_depth_meta_buffer_store_member) == fields.depth_meta_store
	assert read_le_u64(descriptor, fw.g17_render_stencil_buffer_load_member) == fields.stencil_buffer_load
	assert read_le_u64(descriptor, fw.g17_render_stencil_buffer_store_member) == fields.stencil_buffer_store
	assert read_le_u64(descriptor, fw.g17_render_stencil_meta_buffer_load_member) == fields.stencil_meta_load
	assert read_le_u64(descriptor, fw.g17_render_stencil_meta_buffer_store_member) == fields.stencil_meta_store
	// An independent raw Apple payload must reach the same native member as
	// the Mesa bridge. Do not use the bridge's member constant as this oracle.
	assert read_le_u64(descriptor, 0x4c0) == fields.visibility_result_buffer
	mut payload := []u8{len: int(fw.g17_render_payload_size)}
	for index in 0 .. 8 {
		payload[0x6c0 + index] = u8(fields.visibility_result_buffer >> (index * 8))
	}
	mut apple_descriptor := []u8{len: int(fw.g17_3d_descriptor_size)}
	assert fw.initialize_g17_3d_descriptor(apple_descriptor.data, u64(apple_descriptor.len))
	assert fw.populate_g17_ta_render_passthrough(apple_descriptor.data,
		u64(apple_descriptor.len), payload.data, u64(payload.len))
	assert read_le_u64(apple_descriptor, 0x4c0) == read_le_u64(descriptor, 0x4c0)
	assert !fw.populate_g17_render_resource_fields(descriptor.data, fw.g17_3d_descriptor_size - 1, fields)

	println('G17 render descriptor bridge tests passed')
}
