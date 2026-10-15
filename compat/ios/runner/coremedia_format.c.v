// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Descriptions own format metadata, not an encoder or decoder.
struct CMVideoDimensions {
	width i32
	height i32
}
struct CMFormatState {
	media u32
	subtype u32
	dimensions CMVideoDimensions
	audio AudioFormat
}
fn cm_format_id() u64 { return ios_runtime.names['VinixCMFormatDescription'] }
fn cm_format_state(object u64) &CMFormatState {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[object] or { panic('iOS: expected a live CMFormatDescription') }
	if header.cls != cm_format_id() || header.cm_format == unsafe { nil } { panic('iOS: expected a live CMFormatDescription') }
	return header.cm_format
}
fn cm_format_dispose(mut header ObjHeader) {
	if header.cm_format == unsafe { nil } { return }
	C.free(header.cm_format)
	header.cm_format = unsafe { nil }
	// ObjHeader.fields[0] owns the deep extension snapshot.
}

struct CMPropertyBudget {
mut:
	remaining int = 65536
}
fn cm_property_snapshot(object u64, depth int, mut budget CMPropertyBudget) ?u64 {
	if depth > 64 || budget.remaining <= 0 || object == 0 { return none }
	budget.remaining--
	if objc_is_kind(object, ios_runtime.names['NSString']) { return owned_string(string_text(object)) }
	if objc_is_kind(object, ios_runtime.names['NSNumber']) { return objc_retain(object) }
	if ns_date_is_date(object) { return cf_date_create(0, cf_date_absolute(object)) }
	if objc_is_kind(object, ios_runtime.names['NSData']) {
		if data_length(object) > 16777216 { return none }
		return cf_data_create(0, data_pointer(object), i64(data_length(object)))
	}
	dictionary := objc_is_kind(object, ios_runtime.names['NSDictionary'])
	if !dictionary && !objc_is_kind(object, ios_runtime.names['NSArray']) { return none }
	source := obj_header(object)
	if source.cf_raw_keys || source.cf_raw_values || source.items.len > budget.remaining { return none }
	result := objc_allocate(ios_runtime.names[if dictionary { 'NSDictionary' } else { 'NSArray' }])
	mut target := obj_header(result)
	for i, item in source.items {
		if dictionary {
			if !objc_is_kind(source.keys[i], ios_runtime.names['NSString']) { objc_release(result); return none }
			target.keys << owned_string(string_text(source.keys[i]))
		}
		child := cm_property_snapshot(item, depth + 1, mut budget) or { objc_release(result); return none }
		target.items << child
	}
	return result
}
fn cm_format_new(allocator u64, initial CMFormatState, extensions u64, output &u64) i32 {
	if output == unsafe { nil } || initial.media == 0 { return -12710 }
	cf_allocator_check(allocator)
	mut snapshot := u64(0)
	if extensions != 0 {
		if !objc_is_kind(extensions, ios_runtime.names['NSDictionary']) { return -12710 }
		mut budget := CMPropertyBudget{}
		snapshot = cm_property_snapshot(extensions, 0, mut budget) or { return -12710 }
	}
	state := unsafe { &CMFormatState(C.calloc(1, sizeof(CMFormatState))) }
	if state == unsafe { nil } { objc_release(snapshot); return -12711 }
	unsafe { *state = initial }
	object := objc_allocate(cm_format_id())
	mut header := obj_header(object)
	header.cm_format = state
	header.fields[0] = snapshot
	unsafe { *output = object }
	return 0
}
fn cm_format_create(allocator u64, media u32, subtype u32, extensions u64, output &u64) i32 {
	return cm_format_new(allocator, CMFormatState{media:media, subtype:subtype}, extensions, output)
}
fn cm_audio_create(allocator u64, asbd &AudioFormat, layout_size u64, layout u64, cookie_size u64, cookie u64, extensions u64, output &u64) i32 {
	if output == unsafe { nil } { return -12710 }
	unsafe { *output = 0 }
	if asbd == unsafe { nil } || asbd.rate == 0 { return -12710 }
	// Layout/cookie interpretation is codec-specific and outside this profile.
	if layout_size != 0 || layout != 0 || cookie_size != 0 || cookie != 0 { return -12718 }
	return cm_format_new(allocator, CMFormatState{media:0x736f756e, subtype:asbd.id, audio:*asbd}, extensions, output)
}
fn cm_video_create(allocator u64, codec u32, width i32, height i32, extensions u64, output &u64) i32 {
	// Native preserves signed dimensions, including zero and negative values.
	return cm_format_new(allocator, CMFormatState{media:0x76696465, subtype:codec, dimensions:CMVideoDimensions{width,height}}, extensions, output)
}
fn cm_format_media(object u64) u32 { return cm_format_state(object).media }
fn cm_format_subtype(object u64) u32 { return cm_format_state(object).subtype }
fn cm_format_extensions(object u64) u64 { cm_format_state(object); return obj_header(object).fields[0] }
fn cm_format_extension(object u64, key u64) u64 {
	extensions := cm_format_extensions(object)
	return if extensions == 0 { u64(0) } else { cf_dictionary_value(extensions, key) }
}
fn cm_audio_asbd(object u64) u64 {
	if object == 0 { return 0 }
	state := cm_format_state(object)
	return if state.media == 0x736f756e { u64(unsafe { &state.audio }) } else { u64(0) }
}
fn cm_video_dimensions(object u64) CMVideoDimensions { return cm_format_state(object).dimensions }
fn cm_format_equal(left u64, right u64) bool {
	if left == right { return true }
	if left == 0 || right == 0 { return false }
	a := cm_format_state(left)
	C.ios_objc_initialize_lock()
	header := ios_runtime.objects[right] or { C.ios_objc_initialize_unlock(); return false }
	valid := header.cls == cm_format_id() && header.cm_format != unsafe { nil }
	C.ios_objc_initialize_unlock()
	if !valid { return false }
	b := cm_format_state(right)
	return a.media == b.media && a.subtype == b.subtype && a.dimensions == b.dimensions
		// Native copies mReserved but ignores it when comparing ASBDs.
		&& C.memcmp(unsafe { &a.audio }, unsafe { &b.audio }, sizeof(AudioFormat) - sizeof(u32)) == 0
		&& object_equal(cm_format_extensions(left), cm_format_extensions(right))
}
fn coremedia_format_symbol(symbol string) ?u64 {
	return match symbol {
		'_CMFormatDescriptionCreate' { u64(unsafe { voidptr(cm_format_create) }) }
		'_CMAudioFormatDescriptionCreate' { u64(unsafe { voidptr(cm_audio_create) }) }
		'_CMVideoFormatDescriptionCreate' { u64(unsafe { voidptr(cm_video_create) }) }
		'_CMFormatDescriptionGetTypeID' { u64(unsafe { voidptr(cm_format_id) }) }
		'_CMFormatDescriptionGetMediaType' { u64(unsafe { voidptr(cm_format_media) }) }
		'_CMFormatDescriptionGetMediaSubType' { u64(unsafe { voidptr(cm_format_subtype) }) }
		'_CMFormatDescriptionGetExtensions' { u64(unsafe { voidptr(cm_format_extensions) }) }
		'_CMFormatDescriptionGetExtension' { u64(unsafe { voidptr(cm_format_extension) }) }
		'_CMAudioFormatDescriptionGetStreamBasicDescription' { u64(unsafe { voidptr(cm_audio_asbd) }) }
		'_CMVideoFormatDescriptionGetDimensions' { u64(unsafe { voidptr(cm_video_dimensions) }) }
		'_CMFormatDescriptionEqual' { u64(unsafe { voidptr(cm_format_equal) }) }
		else { none }
	}
}
