// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct CVMetalState {
mut:
	width u64
	height u64
	format u64
	usage u64
	storage u64
}
fn cv_metal_cache_id() u64 { return ios_runtime.names['VinixCVMetalTextureCache'] }
fn cv_metal_texture_id() u64 { return ios_runtime.names['VinixCVMetalTexture'] }
fn cv_metal_state(object u64, cls u64) &CVMetalState {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: expected a live CoreVideo Metal object') }
	if header.cls != cls || header.cv_metal == unsafe { nil } { panic('iOS: expected a live CoreVideo Metal object') }
	return header.cv_metal
}
fn cv_metal_dispose(mut header ObjHeader) {
	if header.cv_metal == unsafe { nil } { return }
	C.free(header.cv_metal)
	header.cv_metal = unsafe { nil }
	// Ordinary ObjHeader fields release the device, texture and source owners.
}
fn cv_metal_options(attributes u64, initial_usage u64, initial_storage u64) (u64, u64, i32) {
	mut usage := initial_usage
	mut storage := initial_storage
	if attributes == 0 { return usage, storage, 0 }
	if !objc_is_kind(attributes, ios_runtime.names['NSDictionary']) { return 0, 0, -6661 }
	header := obj_header(attributes)
	for i, key in header.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) || !objc_is_kind(header.items[i], ios_runtime.names['NSNumber']) { return 0, 0, -6661 }
		value := obj_header(header.items[i])
		if value.is_real || value.number < 0 { return 0, 0, -6661 }
		match string_text(key) {
			'MetalTextureUsage' { usage = u64(value.number); if usage & ~u64(31) != 0 { return 0, 0, -6663 } }
			'MetalTextureStorageMode' { storage = u64(value.number); if storage != 0 { return 0, 0, -6663 } }
			else { return 0, 0, -6663 }
		}
	}
	return usage, storage, 0
}
fn cv_metal_cache_create(allocator u64, attributes u64, device u64, texture_attributes u64, output &u64) i32 {
	if device == 0 || output == unsafe { nil } { return -6661 }
	cf_allocator_check(allocator)
	if attributes != 0 {
		if !objc_is_kind(attributes, ios_runtime.names['NSDictionary']) { return -6661 }
		header := obj_header(attributes)
		for i, key in header.keys {
			if !objc_is_kind(key, ios_runtime.names['NSString']) || string_text(key) != 'MaximumMetalTextureAge' { return -6663 }
			if !objc_is_kind(header.items[i], ios_runtime.names['NSNumber']) { return -6661 }
			value := obj_header(header.items[i])
			if (value.is_real && !(value.real_number >= 0)) || (!value.is_real && value.number < 0) { return -6661 }
		}
	}
	usage, storage, status := cv_metal_options(texture_attributes, 23, 0)
	if status != 0 { return status }
	C.ios_objc_initialize_lock()
	live := device in ios_runtime.objects
	C.ios_objc_initialize_unlock()
	if !live { return -6661 }
	unsafe { *output = 0 }
	if !objc_responds(device, c'newTextureWithDescriptor:iosurface:plane:') { return -6663 }
	mut state := unsafe { &CVMetalState(C.calloc(1, sizeof(CVMetalState))) }
	if state == unsafe { nil } { return -6662 }
	state.usage = usage; state.storage = storage
	cache := objc_allocate(cv_metal_cache_id())
	mut header := obj_header(cache)
	header.cv_metal = state
	header.fields[0] = objc_retain(device)
	unsafe { *output = cache }
	return 0
}
type CVMetalFactory = fn (u64, u64, u64, u64, u64) u64
fn cv_metal_create_view(allocator u64, cache u64, image u64, attributes u64, format u64, width u64, height u64, plane u64, output &u64) i32 {
	if cache == 0 || image == 0 || output == unsafe { nil } { return -6661 }
	cf_allocator_check(allocator)
	settings := cv_metal_state(cache, cv_metal_cache_id())
	pixels := cv_pixel_state(image)
	index := plane
	count := if pixels.planes == 0 { u64(1) } else { pixels.planes }
	if index >= count || width == 0 || height == 0 { return -6661 }
	if width > cv_pixel_plane_width(image, index) || height > cv_pixel_plane_height(image, index) { return -6661 }
	unsafe { *output = 0 }
	if pixels.surface == 0 { return -6660 }
	expected := if pixels.planes == 0 { u64(80) } else if index == 0 { u64(10) } else { u64(30) }
	if format != expected && !(pixels.planes == 0 && format == 81) { return -6680 }
	usage, storage, status := cv_metal_options(attributes, settings.usage, settings.storage)
	if status != 0 { return status }
	mut state := unsafe { &CVMetalState(C.calloc(1, sizeof(CVMetalState))) }
	if state == unsafe { nil } { return -6662 }
	state.width = width; state.height = height; state.format = format
	state.usage = usage; state.storage = storage
	descriptor := objc_allocate(ios_runtime.names['VinixMetalTextureDescriptor'])
	obj_header(descriptor).cv_metal = state
	device := obj_header(cache).fields[0]
	texture := unsafe { CVMetalFactory(voidptr(C.ios_objc_msgsend))(device, u64(c'newTextureWithDescriptor:iosurface:plane:'), descriptor, pixels.surface, index) }
	objc_release(descriptor)
	if texture == 0 { return -6684 }
	view := objc_allocate(cv_metal_texture_id())
	mut header := obj_header(view)
	header.fields[0] = texture // newTexture transfers its +1 reference.
	header.fields[1] = objc_retain(image)
	unsafe { *output = view }
	return 0
}
fn cv_metal_view_check(view u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[view] or { panic('iOS: expected a live CVMetalTexture') }
	if header.cls != cv_metal_texture_id() { panic('iOS: expected a live CVMetalTexture') }
}
fn cv_metal_get_texture(view u64) u64 { if view == 0 { return 0 }; cv_metal_view_check(view); return obj_header(view).fields[0] }
fn cv_metal_flipped(view u64) u8 { cv_metal_view_check(view); return 1 }
fn cv_metal_coords(view u64, lower_left &f32, lower_right &f32, upper_right &f32, upper_left &f32) {
	cv_metal_view_check(view)
	if lower_left == unsafe { nil } || lower_right == unsafe { nil } || upper_right == unsafe { nil } || upper_left == unsafe { nil } { panic('iOS: null Metal texture coordinates') }
	unsafe { lower_left[0] = 0; lower_left[1] = 1; lower_right[0] = 1; lower_right[1] = 1; upper_right[0] = 1; upper_right[1] = 0; upper_left[0] = 0; upper_left[1] = 0 }
}
fn cv_metal_flush(cache u64, options u64) {
	_ = options
	cv_metal_state(cache, cv_metal_cache_id())
	// No idle views are retained. Flush cannot invalidate a client's live view.
}
fn cv_metal_descriptor_get(object u64, selector &char) u64 {
	state := cv_metal_state(object, ios_runtime.names['VinixMetalTextureDescriptor'])
	return match ctext(u64(selector)) {
		'width' { state.width }
		'height' { state.height }
		'pixelFormat' { state.format }
		'usage' { state.usage }
		'storageMode' { state.storage }
		'resourceOptions' { state.storage << 4 }
		'textureType' { u64(2) }
		'depth', 'arrayLength', 'sampleCount', 'mipmapLevelCount' { u64(1) }
		'cpuCacheMode', 'hazardTrackingMode' { u64(0) }
		else { panic('iOS: unsupported surface texture descriptor property') }
	}
}
fn cv_metal_start() {
	cls := ios_runtime.names['VinixMetalTextureDescriptor']
	for selector in [c'width', c'height', c'pixelFormat', c'usage', c'storageMode', c'resourceOptions', c'textureType', c'depth', c'arrayLength', c'sampleCount', c'mipmapLevelCount', c'cpuCacheMode', c'hazardTrackingMode']! {
		if !objc_add_method(cls, u64(selector), u64(unsafe { voidptr(cv_metal_descriptor_get) }), c'Q16@0:8') { panic('iOS: cannot register surface texture descriptor') }
	}
}
fn corevideo_metal_symbol(symbol string) ?u64 {
	return match symbol {
		'_CVMetalTextureCacheCreate' { u64(unsafe { voidptr(cv_metal_cache_create) }) }
		'_CVMetalTextureCacheCreateTextureFromImage' { u64(unsafe { voidptr(cv_metal_create_view) }) }
		'_CVMetalTextureGetTexture' { u64(unsafe { voidptr(cv_metal_get_texture) }) }
		'_CVMetalTextureCacheGetTypeID' { u64(unsafe { voidptr(cv_metal_cache_id) }) }
		'_CVMetalTextureGetTypeID' { u64(unsafe { voidptr(cv_metal_texture_id) }) }
		'_CVMetalTextureCacheFlush' { u64(unsafe { voidptr(cv_metal_flush) }) }
		'_CVMetalTextureIsFlipped' { u64(unsafe { voidptr(cv_metal_flipped) }) }
		'_CVMetalTextureGetCleanTexCoords' { u64(unsafe { voidptr(cv_metal_coords) }) }
		else { none }
	}
}
