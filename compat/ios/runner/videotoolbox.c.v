// SPDX-License-Identifier: GPL-2.0-or-later
module main

type VTOutput = fn (u64, u64, i32, u32, u64, CMTime, CMTime)
struct VTSessionState {
mut:
	backend VTBackend
	mutex voidptr
	condition voidptr
	callback u64
	context u64
	owner u64
	format u32
	width u64
	height u64
	valid bool
	busy bool
}
fn vt_session_id() u64 { return ios_runtime.names['VinixVTDecompressionSession'] }
fn vt_acquire(session u64) ?&VTSessionState {
	if session == 0 || ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[session] or { return none }
	if header.cls != vt_session_id() || header.external_data == 0 || header.destroying || header.destroyed { return none }
	objc_retain(session)
	return unsafe { &VTSessionState(header.external_data) }
}
fn vt_close_locked(mut state VTSessionState) {
	if !state.busy { vt_backend_close(mut state.backend) }
}
fn vt_invalidate(session u64) {
	mut state := vt_acquire(session) or { return }
	defer { objc_release(session) }
	C.pthread_mutex_lock(state.mutex)
	state.valid = false
	// Reentrant invalidation from the output callback retires the codec when
	// that operation returns. Other threads join it before invalidation returns.
	for state.busy && state.owner != u64(C.pthread_self()) { C.pthread_cond_wait(state.condition, state.mutex) }
	vt_close_locked(mut state)
	C.pthread_mutex_unlock(state.mutex)
}
fn vt_dispose(mut header ObjHeader) {
	if header.cls != vt_session_id() || header.external_data == 0 { return }
	mut state := unsafe { &VTSessionState(header.external_data) }
	assert !state.busy
	vt_backend_close(mut state.backend)
	C.pthread_cond_destroy(state.condition)
	C.pthread_mutex_destroy(state.mutex)
	C.free(state.condition)
	C.free(state.mutex)
	C.free(state)
	header.external_data = 0
}
fn vt_format_valid(format u64) bool {
	if format == 0 { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header := ios_runtime.objects[format] or { return false }
	return header.cls == cm_format_id() && header.cm_format != unsafe { nil }
}
fn vt_hardware(_codec u32) u8 { return 0 } // This backend provides software decoding.
fn vt_specification(specification u64) i32 {
	if specification == 0 { return 0 }
	if !objc_is_kind(specification, ios_runtime.names['NSDictionary']) { return -12902 }
	header := obj_header(specification)
	for i, key in header.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) { return -12902 }
		name := string_text(key)
		if name !in ['EnableHardwareAcceleratedVideoDecoder', 'RequireHardwareAcceleratedVideoDecoder']! { return -12900 }
		value := header.items[i]
		if !objc_is_kind(value, ios_runtime.names['NSNumber']) || obj_header(value).is_real { return -12902 }
		if name == 'RequireHardwareAcceleratedVideoDecoder' && obj_header(value).number != 0 { return -12906 }
	}
	return 0
}
fn vt_attributes(attributes u64, dimensions CMVideoDimensions) (u32, u64, i32) {
	mut pixel := u32(0x34323076)
	if attributes == 0 { return pixel, 0, 0 }
	if !objc_is_kind(attributes, ios_runtime.names['NSDictionary']) { return 0, 0, -12902 }
	source := obj_header(attributes)
	filtered := objc_allocate(ios_runtime.names['NSDictionary'])
	mut target := obj_header(filtered)
	for i, key in source.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) { objc_release(filtered); return 0, 0, -12902 }
		name := string_text(key)
		value := source.items[i]
		if name in ['PixelFormatType', 'Width', 'Height']! {
			if !objc_is_kind(value, ios_runtime.names['NSNumber']) || obj_header(value).is_real { objc_release(filtered); return 0, 0, -12902 }
			number := obj_header(value).number
			if name == 'PixelFormatType' { pixel = u32(number) }
			else if number != i64(if name == 'Width' { dimensions.width } else { dimensions.height }) { objc_release(filtered); return 0, 0, -12905 }
		} else {
			mut budget := CMPropertyBudget{}
			copy := cm_property_snapshot(value, 0, mut budget) or { objc_release(filtered); return 0, 0, -12902 }
			target.keys << owned_string(name)
			target.items << copy
		}
	}
	if pixel !in [u32(0x42475241), 0x34323076, 0x34323066]! { objc_release(filtered); return 0, 0, -12905 }
	_, _, _, status := cv_allocation_attributes(filtered)
	if status != 0 { objc_release(filtered); return 0, 0, -12905 }
	return pixel, filtered, 0
}
fn vt_create(allocator u64, format u64, specification u64, attributes u64, record u64, output &u64) i32 {
	if output == unsafe { nil } { return -12902 }
	unsafe { *output = 0 }
	if !vt_format_valid(format) { return -12902 }
	cf_allocator_check(allocator)
	description := cm_format_state(format)
	if description.media != 0x76696465 { return -12902 }
	if description.subtype !in [u32(0x61766331), 0x68766331, 0x68657631]! { return -12906 }
	dimensions := description.dimensions
	if dimensions.width <= 0 || dimensions.height <= 0 || dimensions.width > 8192 || dimensions.height > 8192 { return -12910 }
	status := vt_specification(specification)
	if status != 0 { return status }
	if record == 0 { return -12902 } // The block-output entry is outside this callback profile.
	callback := cm_block_wire_word(record, 8)
	if callback == 0 { return -12902 }
	pixel, filtered, result := vt_attributes(attributes, dimensions)
	if result != 0 { return result }
	defer { objc_release(filtered) }
	atoms := h264_named(cm_format_extensions(format), 'SampleDescriptionExtensionAtoms')
	config := h264_named(atoms, if description.subtype == 0x61766331 { 'avcC' } else { 'hvcC' })
	if config == 0 || !objc_is_kind(config, ios_runtime.names['NSData']) { return -12906 }
	size := data_length(config)
	if size == 0 || size > 1048576 { return -12909 }
	mut state := unsafe { &VTSessionState(C.calloc(1, sizeof(VTSessionState))) }
	if state == unsafe { nil } { return -12904 }
	opened := vt_backend_open(description.subtype, data_pointer(config), size, mut state.backend)
	if opened != 0 { C.free(state); return opened }
	state.mutex = C.calloc(1, C.ios_sizeof_mutex())
	state.condition = C.calloc(1, C.ios_sizeof_cond())
	if state.mutex == unsafe { nil } || state.condition == unsafe { nil } { vt_backend_close(mut state.backend); C.free(state.mutex); C.free(state.condition); C.free(state); return -12904 }
	if C.ios_mutex_create(state.mutex, 0) != 0 { vt_backend_close(mut state.backend); C.free(state.mutex); C.free(state.condition); C.free(state); return -12904 }
	if C.pthread_cond_init(state.condition, unsafe { nil }) != 0 { C.pthread_mutex_destroy(state.mutex); vt_backend_close(mut state.backend); C.free(state.mutex); C.free(state.condition); C.free(state); return -12904 }
	state.callback = callback
	state.context = cm_block_wire_word(record + 8, 8)
	state.format = pixel
	state.width = u64(dimensions.width)
	state.height = u64(dimensions.height)
	state.valid = true
	object := objc_allocate(vt_session_id())
	mut header := obj_header(object)
	header.external_data = u64(state)
	header.fields[0] = objc_retain(format)
	header.fields[1] = objc_retain(filtered)
	unsafe { *output = object }
	return 0
}
fn vt_can_accept(session u64, format u64) u8 {
	mut state := vt_acquire(session) or { return 0 }
	defer { objc_release(session) }
	C.pthread_mutex_lock(state.mutex)
	defer { C.pthread_mutex_unlock(state.mutex) }
	if !state.valid || !vt_format_valid(format) { return 0 }
	// A fixed configuration can be reused. Changes require a fresh decoder;
	// do not accept a new SPS/PPS while retaining the preceding extradata.
	return u8(cm_format_equal(obj_header(session).fields[0], format))
}
fn vt_wait(session u64) i32 {
	mut state := vt_acquire(session) or { return -12903 }
	defer { objc_release(session) }
	C.pthread_mutex_lock(state.mutex)
	for state.busy && state.owner != u64(C.pthread_self()) { C.pthread_cond_wait(state.condition, state.mutex) }
	result := if state.valid { i32(0) } else { i32(-12903) }
	C.pthread_mutex_unlock(state.mutex)
	return result
}
fn vt_decode(session u64, sample u64, flags u32, source u64, info &u32) i32 {
	mut state := vt_acquire(session) or { return -12903 }
	defer { objc_release(session) }
	if flags & ~u32(3) != 0 { return -12902 }
	C.pthread_mutex_lock(state.mutex)
	if state.busy && state.owner == u64(C.pthread_self()) { C.pthread_mutex_unlock(state.mutex); return -12902 }
	for state.busy && state.valid { C.pthread_cond_wait(state.condition, state.mutex) }
	if !state.valid { C.pthread_mutex_unlock(state.mutex); return -12903 }
	state.busy = true
	state.owner = u64(C.pthread_self())
	C.pthread_mutex_unlock(state.mutex)
	defer {
		C.pthread_mutex_lock(state.mutex)
		state.busy = false
		state.owner = 0
		if !state.valid { vt_close_locked(mut state) }
		C.pthread_cond_broadcast(state.condition)
		C.pthread_mutex_unlock(state.mutex)
	}
	if sample == 0 { return -12902 }
	C.ios_objc_initialize_lock()
	header := ios_runtime.objects[sample] or { C.ios_objc_initialize_unlock(); return -12902 }
	if header.cls != cm_sample_id() || header.cm_sample == unsafe { nil } { C.ios_objc_initialize_unlock(); return -12902 }
	objc_retain(sample)
	C.ios_objc_initialize_unlock()
	defer { objc_release(sample) }
	if cm_sample_ready(sample) == 0 || cm_sample_count(sample) != 1 { return -12902 }
	if !cm_format_equal(cm_sample_format(sample), obj_header(session).fields[0]) { return -12910 }
	data := cm_sample_data(sample)
	count := cm_sample_size(sample, 0)
	if data == 0 || count == 0 || count > 16777216 || count > cm_block_length(data) { return -12909 }
	mut pointer := u64(0)
	if cm_block_pointer(data, 0, unsafe { nil }, unsafe { nil }, &pointer) != 0 { return -12909 }
	mut image := u64(0)
	if cv_pixel_create(0, state.width, state.height, state.format, obj_header(session).fields[1], &image) != 0 { return -12904 }
	defer { objc_release(image) }
	result := vt_backend_decode(mut state.backend, pointer, count, image)
	if result != 0 { return result }
	C.pthread_mutex_lock(state.mutex)
	valid := state.valid
	C.pthread_mutex_unlock(state.mutex)
	if !valid { return -12903 }
	if info != unsafe { nil } { zero := u32(0); C.memcpy(info, unsafe { &zero }, 4) }
	unsafe { VTOutput(voidptr(state.callback))(state.context, source, 0, 0, image, cm_sample_pts(sample), cm_sample_duration(sample)) }
	return 0
}
fn videotoolbox_symbol(symbol string) ?u64 {
	return match symbol {
		'_VTDecompressionSessionCreate' { u64(unsafe { voidptr(vt_create) }) }
		'_VTDecompressionSessionCanAcceptFormatDescription' { u64(unsafe { voidptr(vt_can_accept) }) }
		'_VTDecompressionSessionDecodeFrame' { u64(unsafe { voidptr(vt_decode) }) }
		'_VTDecompressionSessionInvalidate' { u64(unsafe { voidptr(vt_invalidate) }) }
		'_VTDecompressionSessionWaitForAsynchronousFrames', '_VTDecompressionSessionFinishDelayedFrames' { u64(unsafe { voidptr(vt_wait) }) }
		'_VTDecompressionSessionGetTypeID' { u64(unsafe { voidptr(vt_session_id) }) }
		'_VTIsHardwareDecodeSupported' { u64(unsafe { voidptr(vt_hardware) }) }
		else { none }
	}
}
