// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SoftwareMetalOrigin { x u64 y u64 z u64 }
struct SoftwareMetalSize { width u64 height u64 depth u64 }
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
	if source == destination && origin.x < target.x + size.width && target.x < origin.x + size.width && origin.y < target.y + size.height && target.y < origin.y + size.height { panic('iOS: overlapping Metal texture blit regions') }
	if state.ops.len >= 65536 { panic('iOS: software Metal command limit') }
	pixel := sm_pixel_size(a.format)
	// Texture allocation bounds guarantee all row offsets remain within 64 MiB.
	state.ops << SoftwareMetalCopy{source: objc_retain(source), destination: objc_retain(destination), source_offset: (origin.y * a.width + origin.x) * pixel, destination_offset: (target.y * b.width + target.x) * pixel, size: size.width * pixel, rows: size.height, source_stride: a.width * pixel, destination_stride: b.width * pixel}
}
fn sm_texture_blit_start(encoder u64) {
	sm_method(encoder, c'copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:', u64(unsafe { voidptr(sm_copy_texture) }), c'v136@0:8@16Q24Q32{MTLOrigin=QQQ}40{MTLSize=QQQ}64@88Q96Q104{MTLOrigin=QQQ}112')
}
