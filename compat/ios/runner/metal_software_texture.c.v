// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SoftwareMetalRegion { x u64 y u64 z u64 width u64 height u64 depth u64 }
fn sm_pixel_size(format u64) u64 {
	return match format { 10 { u64(1) } 25, 30 { u64(2) } 55, 65, 70, 71, 80, 81 { u64(4) } 105, 115 { u64(8) } 125 { u64(16) } else { u64(0) } }
}
fn sm_linear_alignment(format u64) u64 { return if sm_pixel_size(format) == 0 { u64(0) } else { u64(256) } }
fn sm_device_linear_alignment(device u64, selector &char, format u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(device, 'VinixSoftwareMTLDevice')
	alignment := sm_linear_alignment(format)
	if alignment == 0 { panic('iOS: unsupported software Metal linear texture pixel format') }
	return alignment
}
// Imported textures borrow a plane address and retain its IOSurface in fields[1].
// mutation stores the immutable plane index; ordinary textures own data instead.
fn sm_storage_base(h &ObjHeader) u64 { return if h.external_data != 0 { h.external_data } else { u64(h.data.data) } }
fn sm_texture_stride(h &ObjHeader) u64 { return if h.fields[3] != 0 { u64(h.deadline) } else if h.fields[1] != 0 { cv_surface_plane_row(h.fields[1], h.mutation) } else { h.cv_metal.width * sm_pixel_size(h.cv_metal.format) } }
fn sm_buffer_texture(buffer u64, selector &char, descriptor u64, offset u64, row u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	b := sm_check(buffer, 'VinixSoftwareMTLBuffer')
	h := ios_runtime.objects[descriptor] or { return 0 }
	if h.cls != ios_runtime.names['VinixMetalTextureDescriptor'] || h.cv_metal == unsafe { nil } { return 0 }
	a := h.cv_metal; pixel := sm_pixel_size(a.format)
	if pixel == 0 || a.storage != 0 || a.usage & ~u64(31) != 0 || a.width == 0 || a.height == 0 || a.width > 16384 || a.height > 16384 { return 0 }
	// A conservative 256-byte layout works for every current format. Bound row
	// before span arithmetic, and use subtraction for the buffer extent check.
	alignment := sm_linear_alignment(a.format)
	if offset % alignment != 0 || row % alignment != 0 || row < a.width * pixel || row > software_metal_max_buffer { return 0 }
	span := (a.height - 1) * row + a.width * pixel
	if !sm_range(sm_buffer_length(b), offset, span) { return 0 }
	mut state := unsafe { &CVMetalState(C.malloc(sizeof(CVMetalState))) }
	if state == unsafe { nil } { return 0 }; unsafe { *state = *a }
	texture := sm_new('VinixSoftwareMTLTexture', b.fields[0]); mut target := obj_header(texture)
	target.cv_metal = state; target.external_data = sm_storage_base(b) + offset
	target.fields[3] = objc_retain(buffer); target.number = i64(offset); target.deadline = i64(row)
	return texture
}
fn sm_surface_texture(device u64, selector &char, descriptor u64, surface u64, plane u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(device, 'VinixSoftwareMTLDevice')
	h := ios_runtime.objects[descriptor] or { return 0 }
	s := ios_runtime.objects[surface] or { return 0 }
	if h.cls != ios_runtime.names['VinixMetalTextureDescriptor'] || h.cv_metal == unsafe { nil } || s.cls != cv_surface_type_id() || s.cv_pixel == unsafe { nil } { return 0 }
	input := h.cv_metal; pixels := s.cv_pixel
	count := if pixels.planes == 0 { u64(1) } else { pixels.planes }
	if plane >= count { return 0 }
	expected := if pixels.planes == 0 { u64(80) } else if plane == 0 { u64(10) } else { u64(30) }
	if input.format != expected && !(expected == 80 && input.format == 81) { return 0 }
	if input.storage != 0 || input.usage & ~u64(31) != 0 || input.width == 0 || input.height == 0 || input.width > 16384 || input.height > 16384 || input.width > cv_surface_plane_width(surface, plane) || input.height > cv_surface_plane_height(surface, plane) { return 0 }
	pixel := sm_pixel_size(input.format); row := cv_surface_plane_row(surface, plane)
	if row < input.width * pixel || row > software_metal_max_buffer || input.height - 1 > (software_metal_max_buffer - input.width * pixel) / row { return 0 }
	mut state := unsafe { &CVMetalState(C.calloc(1, sizeof(CVMetalState))) }
	if state == unsafe { nil } { return 0 }
	unsafe { *state = *input }
	texture := sm_new('VinixSoftwareMTLTexture', device)
	mut target := obj_header(texture)
	target.cv_metal = state
	target.fields[1] = objc_retain(surface)
	target.mutation = plane
	target.external_data = cv_surface_plane_base(surface, plane)
	return texture
}
fn sm_descriptor(cls u64, selector &char, format u64, width u64, height u64, mipmapped u8) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if mipmapped != 0 { return 0 }
	mut state := unsafe { &CVMetalState(C.calloc(1, sizeof(CVMetalState))) }
	if state == unsafe { nil } { return 0 }
	state.width = width; state.height = height; state.format = format; state.usage = 1
	descriptor := objc_allocate(ios_runtime.names['VinixMetalTextureDescriptor'])
	obj_header(descriptor).cv_metal = state
	return objc_autorelease(descriptor)
}
fn sm_descriptor_set(object u64, selector &char, value u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := cv_metal_state(object, ios_runtime.names['VinixMetalTextureDescriptor'])
	match ctext(u64(selector)) {
		'setWidth:' { state.width = value }
		'setHeight:' { state.height = value }
		'setPixelFormat:' { state.format = value }
		'setUsage:' { state.usage = value }
		'setStorageMode:' { state.storage = value }
		else { panic('iOS: unsupported software Metal descriptor setter') }
	}
}
fn sm_descriptor_copy(object u64, selector &char, zone u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	input := cv_metal_state(object, ios_runtime.names['VinixMetalTextureDescriptor'])
	state := unsafe { &CVMetalState(C.malloc(sizeof(CVMetalState))) }
	if state == unsafe { nil } { return 0 }
	unsafe { *state = *input }
	copy := objc_allocate(ios_runtime.names['VinixMetalTextureDescriptor'])
	obj_header(copy).cv_metal = state
	return copy // NSCopying returns a +1 descriptor with independent metadata.
}
fn sm_descriptor_copy_plain(object u64, selector &char) u64 { return sm_descriptor_copy(object, selector, 0) }
fn sm_new_texture(device u64, selector &char, descriptor u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(device, 'VinixSoftwareMTLDevice')
	if descriptor == 0 { return 0 }
	h := ios_runtime.objects[descriptor] or { return 0 }
	if h.cls != ios_runtime.names['VinixMetalTextureDescriptor'] || h.cv_metal == unsafe { nil } { return 0 }
	input := h.cv_metal; pixel := sm_pixel_size(input.format)
	if pixel == 0 || input.storage != 0 || input.usage & ~u64(31) != 0 || input.width == 0 || input.height == 0 || input.width > 16384 || input.height > 16384 { return 0 }
	length := input.width * input.height * pixel
	if length > software_metal_max_buffer { return 0 }
	mut state := unsafe { &CVMetalState(C.calloc(1, sizeof(CVMetalState))) }
	if state == unsafe { nil } { return 0 }
	unsafe { *state = *input } // Snapshot; subsequent descriptor changes are independent.
	texture := sm_new('VinixSoftwareMTLTexture', device)
	mut target := obj_header(texture)
	target.cv_metal = state
	target.data = []u8{len: int(length)}
	return texture
}
fn sm_texture_get(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(object, 'VinixSoftwareMTLTexture'); state := h.cv_metal
	return match ctext(u64(selector)) {
		'width' { state.width } 'height' { state.height } 'pixelFormat' { state.format }
		'usage' { state.usage } 'device' { h.fields[0] }
		'parentTexture' { h.fields[2] }
		'buffer' { h.fields[3] } 'bufferOffset' { u64(h.number) } 'bufferBytesPerRow' { if h.fields[3] != 0 { u64(h.deadline) } else { u64(0) } }
		'parentRelativeLevel', 'parentRelativeSlice' { u64(0) }
		'iosurface' { h.fields[1] } 'iosurfacePlane' { h.mutation }
		'textureType' { u64(2) }
		'depth', 'arrayLength', 'mipmapLevelCount', 'sampleCount' { u64(1) }
		'storageMode', 'cpuCacheMode', 'resourceOptions', 'hazardTrackingMode' { u64(0) }
		else { panic('iOS: unsupported software Metal texture property') }
	}
}
// Full single-level 2D views borrow the parent's bytes and retain that parent.
// fields[1]/mutation preserve IOSurface plane identity and padded row stride.
fn sm_texture_view(texture u64, selector &char, format u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(texture, 'VinixSoftwareMTLTexture')
	input := h.cv_metal
	compatible := (format in [u64(70), 71]! && input.format in [u64(70), 71]!) || (format in [u64(80), 81]! && input.format in [u64(80), 81]!)
	if format != input.format && (!compatible || input.usage & 16 == 0) { return 0 }
	mut state := unsafe { &CVMetalState(C.malloc(sizeof(CVMetalState))) }
	if state == unsafe { nil } { return 0 }
	unsafe { *state = *input }; state.format = format
	view := sm_new('VinixSoftwareMTLTexture', h.fields[0])
	mut target := obj_header(view)
	target.cv_metal = state
	target.external_data = sm_storage_base(h)
	target.fields[1] = objc_retain(h.fields[1]); target.mutation = h.mutation
	target.fields[2] = objc_retain(texture)
	target.fields[3] = objc_retain(h.fields[3]); target.number = h.number; target.deadline = h.deadline
	return view
}
fn sm_texture_view_ranges(texture u64, selector &char, format u64, kind u64, levels SoftwareMetalRange, slices SoftwareMetalRange) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(texture, 'VinixSoftwareMTLTexture')
	// Current storage has exactly one 2D mip and one slice. Test fields directly
	// instead of adding range endpoints, including for hostile NSUInteger values.
	if kind != 2 || levels.location != 0 || levels.length != 1 || slices.location != 0 || slices.length != 1 { return 0 }
	return sm_texture_view(texture, selector, format)
}
fn sm_texture_transfer(object u64, region SoftwareMetalRegion, level u64, bytes u64, row u64, write bool) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(object, 'VinixSoftwareMTLTexture'); state := h.cv_metal
	if level != 0 || region.z != 0 || region.depth != 1 || region.width == 0 || region.height == 0 || !sm_range(state.width, region.x, region.width) || !sm_range(state.height, region.y, region.height) { panic('iOS: software Metal texture region/level') }
	pixel := sm_pixel_size(state.format); width := region.width * pixel
	pitch := if row == 0 && region.height == 1 { width } else { row }
	if bytes == 0 || pitch < width || pitch % pixel != 0 || (region.height > 1 && pitch > (~u64(0) - width) / (region.height - 1)) { panic('iOS: software Metal texture row/pointer') }
	extent := pitch * (region.height - 1) + width
	if bytes > ~u64(0) - extent { panic('iOS: software Metal texture pointer overflow') }
	for y in u64(0) .. region.height {
		texture := sm_storage_base(h) + (region.y + y) * sm_texture_stride(h) + region.x * pixel
		client := bytes + y * pitch
		if write { C.memcpy(unsafe { voidptr(texture) }, unsafe { voidptr(client) }, usize(width)) }
		else { C.memcpy(unsafe { voidptr(client) }, unsafe { voidptr(texture) }, usize(width)) }
	}
}
fn sm_texture_put(object u64, selector &char, region SoftwareMetalRegion, level u64, bytes u64, row u64) { sm_texture_transfer(object, region, level, bytes, row, true) }
fn sm_texture_read(object u64, selector &char, bytes u64, row u64, region SoftwareMetalRegion, level u64) { sm_texture_transfer(object, region, level, bytes, row, false) }
fn sm_texture_put_slice(object u64, selector &char, region SoftwareMetalRegion, level u64, slice u64, bytes u64, row u64, image u64) {
	if slice != 0 || image != 0 { panic('iOS: software Metal CPU transfer requires slice zero and bytesPerImage zero') }
	sm_texture_transfer(object, region, level, bytes, row, true)
}
fn sm_texture_read_slice(object u64, selector &char, bytes u64, row u64, image u64, region SoftwareMetalRegion, level u64, slice u64) {
	if slice != 0 || image != 0 { panic('iOS: software Metal CPU transfer requires slice zero and bytesPerImage zero') }
	sm_texture_transfer(object, region, level, bytes, row, false)
}
fn sm_texture_start(device u64) {
	texture := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSoftwareMTLTexture', 0)
	objc_register_class(texture)
	sm_method(device, c'minimumLinearTextureAlignmentForPixelFormat:', u64(unsafe { voidptr(sm_device_linear_alignment) }), c'Q24@0:8Q16')
	sm_method(ios_runtime.names['VinixSoftwareMTLBuffer'], c'newTextureWithDescriptor:offset:bytesPerRow:', u64(unsafe { voidptr(sm_buffer_texture) }), c'@40@0:8@16Q24Q32')
	sm_method(texture, c'buffer', u64(unsafe { voidptr(sm_texture_get) }), c'@16@0:8')
	for selector in [c'bufferOffset', c'bufferBytesPerRow']! { sm_method(texture, selector, u64(unsafe { voidptr(sm_texture_get) }), c'Q16@0:8') }
	sm_method(texture, c'newTextureViewWithPixelFormat:', u64(unsafe { voidptr(sm_texture_view) }), c'@24@0:8Q16')
	sm_method(texture, c'newTextureViewWithPixelFormat:textureType:levels:slices:', u64(unsafe { voidptr(sm_texture_view_ranges) }), c'@64@0:8Q16Q24{_NSRange=QQ}32{_NSRange=QQ}48')
	sm_method(texture, c'parentTexture', u64(unsafe { voidptr(sm_texture_get) }), c'@16@0:8')
	for selector in [c'parentRelativeLevel', c'parentRelativeSlice']! { sm_method(texture, selector, u64(unsafe { voidptr(sm_texture_get) }), c'Q16@0:8') }
	sm_method(device, c'newTextureWithDescriptor:', u64(unsafe { voidptr(sm_new_texture) }), c'@24@0:8@16')
	sm_method(device, c'newTextureWithDescriptor:iosurface:plane:', u64(unsafe { voidptr(sm_surface_texture) }), c'@40@0:8@16^{__IOSurface=}24Q32')
	sm_method(texture, c'iosurface', u64(unsafe { voidptr(sm_texture_get) }), c'^{__IOSurface=}16@0:8')
	sm_method(texture, c'iosurfacePlane', u64(unsafe { voidptr(sm_texture_get) }), c'Q16@0:8')
	sm_method(read64(ios_runtime.names['MTLTextureDescriptor']), c'texture2DDescriptorWithPixelFormat:width:height:mipmapped:', u64(unsafe { voidptr(sm_descriptor) }), c'@48@0:8Q16Q24Q32B40')
	for selector in [c'setWidth:', c'setHeight:', c'setPixelFormat:', c'setUsage:', c'setStorageMode:']! { sm_method(ios_runtime.names['VinixMetalTextureDescriptor'], selector, u64(unsafe { voidptr(sm_descriptor_set) }), c'v24@0:8Q16') }
	sm_method(ios_runtime.names['VinixMetalTextureDescriptor'], c'copy', u64(unsafe { voidptr(sm_descriptor_copy_plain) }), c'@16@0:8')
	sm_method(ios_runtime.names['VinixMetalTextureDescriptor'], c'copyWithZone:', u64(unsafe { voidptr(sm_descriptor_copy) }), c'@24@0:8^{_NSZone=}16')
	for selector in [c'width', c'height', c'pixelFormat', c'usage', c'textureType', c'depth', c'arrayLength', c'mipmapLevelCount', c'sampleCount', c'storageMode', c'cpuCacheMode', c'resourceOptions', c'hazardTrackingMode']! { sm_method(texture, selector, u64(unsafe { voidptr(sm_texture_get) }), c'Q16@0:8') }
	sm_method(texture, c'device', u64(unsafe { voidptr(sm_texture_get) }), c'@16@0:8')
	sm_method(texture, c'replaceRegion:mipmapLevel:withBytes:bytesPerRow:', u64(unsafe { voidptr(sm_texture_put) }), c'v88@0:8{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}16Q64r^v72Q80')
	sm_method(texture, c'getBytes:bytesPerRow:fromRegion:mipmapLevel:', u64(unsafe { voidptr(sm_texture_read) }), c'v88@0:8^v16Q24{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}32Q80')
	sm_method(texture, c'replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:', u64(unsafe { voidptr(sm_texture_put_slice) }), c'v104@0:8{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}16Q64Q72r^v80Q88Q96')
	sm_method(texture, c'getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:', u64(unsafe { voidptr(sm_texture_read_slice) }), c'v104@0:8^v16Q24Q32{MTLRegion={MTLOrigin=QQQ}{MTLSize=QQQ}}40Q88Q96')
}
