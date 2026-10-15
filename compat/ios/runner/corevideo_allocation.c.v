// SPDX-License-Identifier: GPL-2.0-or-later
module main

// These are CPU allocations. Accepting a GPU/surface request here would make
// callers believe that an otherwise unmappable buffer can be imported by Metal.
fn cv_allocation_attributes(attributes u64) (u64, u64, i32) {
	mut row := u64(64)
	mut plane := u64(64)
	if attributes == 0 { return row, plane, 0 }
	if !objc_is_kind(attributes, ios_runtime.names['NSDictionary']) { return 0, 0, -6682 }
	header := obj_header(attributes)
	for i, key in header.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) { return 0, 0, -6682 }
		name := string_text(key)
		value := header.items[i]
		if name == 'IOSurfaceProperties' { return 0, 0, -6663 }
		if !objc_is_kind(value, ios_runtime.names['NSNumber']) { return 0, 0, -6682 }
		number := obj_header(value)
		if number.is_real || number.unsigned_number || number.number < 0 { return 0, 0, -6682 }
		match name {
			'BytesPerRowAlignment', 'PlaneAlignment' {
				if number.cf_boolean || number.number == 0 { return 0, 0, -6682 }
				alignment := cv_alignment_multiple(64, u64(number.number)) or { return 0, 0, -6681 }
				if name == 'BytesPerRowAlignment' { row = alignment } else { plane = alignment }
			}
			'MetalCompatibility' { if number.number != 0 { return 0, 0, -6684 } }
			'OpenGLESCompatibility' { if number.number != 0 { return 0, 0, -6683 } }
			else { return 0, 0, -6682 }
		}
	}
	return row, plane, 0
}

fn cv_alignment_multiple(a u64, b u64) ?u64 {
	if a == 0 || b == 0 { return none }
	mut x := a
	mut y := b
	for y != 0 { remainder := x % y; x = y; y = remainder }
	if a / x > ~u64(0) / b { return none }
	return a / x * b
}

fn cv_allocation_round(value u64, alignment u64) ?u64 {
	if alignment == 0 { return none }
	remainder := value % alignment
	if remainder == 0 { return value }
	padding := alignment - remainder
	if value > ~u64(0) - padding { return none }
	return value + padding
}

fn cv_descriptor_word(address u64, value u64) {
	// CVPlanarComponentInfo uses big-endian 32-bit offsets and row sizes on
	// every architecture. Never write a host-endian pointer into this header.
	unsafe {
		*(&u8(address)) = u8(value >> 24)
		*(&u8(address + 1)) = u8(value >> 16)
		*(&u8(address + 2)) = u8(value >> 8)
		*(&u8(address + 3)) = u8(value)
	}
}

fn cv_pixel_create(allocator u64, width u64, height u64, format u32, attributes u64, output &u64) i32 {
	if output == unsafe { nil } || width == 0 || height == 0 { return -6661 }
	cf_allocator_check(allocator)
	// Native leaves the output untouched for invalid dimensions, but clears it
	// before format/allocation failures. Publish a +1 object only after success.
	unsafe { *output = 0 }
	if format !in [u32(0x42475241), 0x34323076, 0x34323066]! { return -6680 }
	row_alignment, plane_alignment, status := cv_allocation_attributes(attributes)
	if status != 0 { return status }
	packed := format == 0x42475241
	// Besides preventing arithmetic overflow, this bounds the signed 32-bit
	// planar descriptor offsets. Larger CPU buffers are outside this profile.
	limit := u64(0x7fffffff)
	if width > limit / 4 || height > limit { return -6681 }
	chroma_width := width / 2 + width % 2
	chroma_height := height / 2 + height % 2
	row := cv_allocation_round(if packed { width * 4 } else { width }, row_alignment) or { return -6681 }
	if row > limit / height { return -6681 }
	mut size := row * height
	mut luma_offset := u64(0)
	mut chroma_offset := u64(0)
	mut chroma_row := u64(0)
	if !packed {
		chroma_row = cv_allocation_round(chroma_width * 2, row_alignment) or { return -6681 }
		luma_offset = cv_allocation_round(16, plane_alignment) or { return -6681 }
		if luma_offset > limit || size > limit - luma_offset { return -6681 }
		chroma_offset = cv_allocation_round(luma_offset + size, plane_alignment) or { return -6681 }
		if chroma_offset > limit || chroma_row > (limit - chroma_offset) / chroma_height { return -6681 }
		size = cv_allocation_round(chroma_offset + chroma_row * chroma_height, height) or { return -6681 }
	}
	if size > limit { return -6681 }
	mut state := unsafe { &CVPixelState(C.calloc(1, sizeof(CVPixelState))) }
	if state == unsafe { nil } { return -6662 }
	mut allocation := u64(0)
	if C.posix_memalign(unsafe { voidptr(&allocation) }, 64, usize(size)) != 0 { C.free(state); return -6662 }
	C.memset(unsafe { voidptr(allocation) }, 0, usize(size))
	state.allocation = allocation
	state.width = width; state.height = height; state.format = format
	state.base = allocation; state.size = size; state.stride = size / height
	if !packed {
		state.planes = 2
		state.addresses = [allocation + luma_offset, allocation + chroma_offset]!
		state.widths = [width, chroma_width]!
		state.heights = [height, chroma_height]!
		state.strides = [row, chroma_row]!
		cv_descriptor_word(allocation, luma_offset)
		cv_descriptor_word(allocation + 4, row)
		cv_descriptor_word(allocation + 8, chroma_offset)
		cv_descriptor_word(allocation + 12, chroma_row)
	}
	object := objc_allocate(cv_pixel_type_id())
	obj_header(object).cv_pixel = state
	unsafe { *output = object }
	return 0
}
