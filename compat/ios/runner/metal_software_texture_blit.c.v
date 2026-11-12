// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SoftwareMetalOrigin { x u64 y u64 z u64 }
struct SoftwareMetalSize { width u64 height u64 depth u64 }
fn sm_spans_overlap(a u64, an u64, b u64, bn u64) bool { return if a <= b { b - a < an } else { a - b < bn } }
fn sm_copy_texture(encoder u64, selector &char, source u64, source_slice u64, source_level u64, origin SoftwareMetalOrigin, size SoftwareMetalSize, destination u64, destination_slice u64, destination_level u64, target SoftwareMetalOrigin) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(encoder, 'VinixSoftwareMTLBlitCommandEncoder')
	mut state := obj_header(h.fields[0]).software_metal
	if !h.valid || !state.active || state.status != 0 { panic('iOS: Metal encoding has ended') }
	src := sm_check(source, 'VinixSoftwareMTLTexture'); dst := sm_check(destination, 'VinixSoftwareMTLTexture')
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	if src.fields[0] != device || dst.fields[0] != device { panic('iOS: Metal texture blit resources belong to another device') }
	a := src.cv_metal; b := dst.cv_metal
	if source_slice != 0 || destination_slice != 0 || source_level != 0 || destination_level != 0 || origin.z != 0 || target.z != 0 || size.depth != 1 || size.width == 0 || size.height == 0 || a.format != b.format { panic('iOS: unsupported Metal texture blit layout/format') }
	if !sm_range(a.width, origin.x, size.width) || !sm_range(a.height, origin.y, size.height) || !sm_range(b.width, target.x, size.width) || !sm_range(b.height, target.y, size.height) { panic('iOS: Metal texture blit region exceeds texture') }
	if sm_storage_base(src) == sm_storage_base(dst) && origin.x < target.x + size.width && target.x < origin.x + size.width && origin.y < target.y + size.height && target.y < origin.y + size.height { panic('iOS: overlapping Metal texture blit regions') }
	if sm_storage_base(src) != sm_storage_base(dst) || sm_texture_stride(src) != sm_texture_stride(dst) {
		pixel := sm_pixel_size(a.format)
		if sm_spans_overlap(sm_storage_base(src) + origin.y * sm_texture_stride(src) + origin.x * pixel, (size.height - 1) * sm_texture_stride(src) + size.width * pixel, sm_storage_base(dst) + target.y * sm_texture_stride(dst) + target.x * pixel, (size.height - 1) * sm_texture_stride(dst) + size.width * pixel) { panic('iOS: overlapping Metal texture storage spans') }
	}
	if state.ops.len >= 65536 { panic('iOS: software Metal command limit') }
	pixel := sm_pixel_size(a.format)
	// Owned allocations and imported spans are both bounded to 64 MiB.
	state.ops << SoftwareMetalCopy{source: objc_retain(source), destination: objc_retain(destination), source_offset: origin.y * sm_texture_stride(src) + origin.x * pixel, destination_offset: target.y * sm_texture_stride(dst) + target.x * pixel, size: size.width * pixel, rows: size.height, source_stride: sm_texture_stride(src), destination_stride: sm_texture_stride(dst)}
}
fn sm_texture_blit_start(encoder u64) {
	sm_method(encoder, c'copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:', u64(unsafe { voidptr(sm_copy_texture) }), c'v136@0:8@16Q24Q32{MTLOrigin=QQQ}40{MTLSize=QQQ}64@88Q96Q104{MTLOrigin=QQQ}112')
	sm_method(encoder, c'copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:', u64(unsafe { voidptr(sm_buffer_to_texture) }), c'v120@0:8@16Q24Q32Q40{MTLSize=QQQ}48@72Q80Q88{MTLOrigin=QQQ}96')
	sm_method(encoder, c'copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:', u64(unsafe { voidptr(sm_texture_to_buffer) }), c'v120@0:8@16Q24Q32{MTLOrigin=QQQ}40{MTLSize=QQQ}64@88Q96Q104Q112')
}
fn sm_buffer_texture_copy(encoder u64, buffer u64, offset u64, row u64, image u64, size SoftwareMetalSize, texture u64, slice u64, level u64, origin SoftwareMetalOrigin, upload bool) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(encoder, 'VinixSoftwareMTLBlitCommandEncoder')
	mut state := obj_header(h.fields[0]).software_metal
	if !h.valid || !state.active || state.status != 0 { panic('iOS: Metal encoding has ended') }
	b := sm_check(buffer, 'VinixSoftwareMTLBuffer'); t := sm_check(texture, 'VinixSoftwareMTLTexture')
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	if b.fields[0] != device || t.fields[0] != device { panic('iOS: Metal transfer resources belong to another device') }
	a := t.cv_metal
	if slice != 0 || level != 0 || origin.z != 0 || size.depth != 1 || size.width == 0 || size.height == 0 || image != 0 { panic('iOS: unsupported Metal buffer/texture layout') }
	if !sm_range(a.width, origin.x, size.width) || !sm_range(a.height, origin.y, size.height) { panic('iOS: Metal transfer region exceeds texture') }
	pixel := sm_pixel_size(a.format); width := size.width * pixel
	if offset % pixel != 0 || row % pixel != 0 || row < width || row > 16384 * pixel { panic('iOS: Metal transfer offset/row alignment or size') }
	// Dimensions and row pitch are bounded before this multiplication.
	span := (size.height - 1) * row + width
	if !sm_range(sm_buffer_length(b), offset, span) { panic('iOS: Metal transfer span exceeds buffer') }
	if state.ops.len >= 65536 { panic('iOS: software Metal command limit') }
	texture_offset := origin.y * sm_texture_stride(t) + origin.x * pixel
	if sm_spans_overlap(sm_storage_base(b) + offset, span, sm_storage_base(t) + texture_offset, (size.height - 1) * sm_texture_stride(t) + width) { panic('iOS: overlapping Metal buffer/texture storage spans') }
	state.ops << SoftwareMetalCopy{source: objc_retain(if upload { buffer } else { texture }), destination: objc_retain(if upload { texture } else { buffer }), source_offset: if upload { offset } else { texture_offset }, destination_offset: if upload { texture_offset } else { offset }, size: width, rows: size.height, source_stride: if upload { row } else { sm_texture_stride(t) }, destination_stride: if upload { sm_texture_stride(t) } else { row }}
}
fn sm_buffer_to_texture(encoder u64, selector &char, source u64, offset u64, row u64, image u64, size SoftwareMetalSize, destination u64, slice u64, level u64, origin SoftwareMetalOrigin) { sm_buffer_texture_copy(encoder, source, offset, row, image, size, destination, slice, level, origin, true) }
fn sm_texture_to_buffer(encoder u64, selector &char, source u64, slice u64, level u64, origin SoftwareMetalOrigin, size SoftwareMetalSize, destination u64, offset u64, row u64, image u64) { sm_buffer_texture_copy(encoder, destination, offset, row, image, size, source, slice, level, origin, false) }
