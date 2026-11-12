// SPDX-License-Identifier: GPL-2.0-or-later
module main

// POD snapshots live in ObjHeader.data; normal object cleanup frees that storage
// and the copied label in fields[1]. States additionally retain their device.
struct SoftwareMetalSampler {
mut:
	min_filter u64
	mag_filter u64
	mip_filter u64
	anisotropy u64 = 1
	s_address u64
	t_address u64
	r_address u64
	border u64
	compare u64
	normalized bool = true
	lod_average bool
	argument_buffers bool
	lod_min f32
	lod_max f32 = 3.4028234663852886e38
}
fn sm_sampler_data(h &ObjHeader) &SoftwareMetalSampler {
	if h.data.len != int(sizeof(SoftwareMetalSampler)) { panic('iOS: software Metal sampler requires initialization') }
	return unsafe { &SoftwareMetalSampler(h.data.data) }
}
fn sm_sampler_init(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_check(object, 'MTLSamplerDescriptor')
	if h.data.len != 0 { panic('iOS: software Metal sampler descriptor already initialized') }
	unsafe { h.data.free() }
	h.data = []u8{len: int(sizeof(SoftwareMetalSampler))}
	state := sm_sampler_data(h)
	unsafe { *state = SoftwareMetalSampler{} }
	return object
}
fn sm_sampler_copy(object u64, selector &char, zone u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(object, 'MTLSamplerDescriptor')
	sm_sampler_data(h)
	copy := objc_allocate(h.cls)
	mut target := obj_header(copy)
	unsafe { target.data.free() }
	target.data = h.data.clone()
	target.fields[1] = objc_retain(h.fields[1]) // Labels are already immutable copies.
	return copy
}
fn sm_sampler_copy_plain(object u64, selector &char) u64 { return sm_sampler_copy(object, selector, 0) }
fn sm_sampler_get(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	s := sm_sampler_data(sm_check(object, 'MTLSamplerDescriptor'))
	return match ctext(u64(selector)) {
		'minFilter' { s.min_filter } 'magFilter' { s.mag_filter } 'mipFilter' { s.mip_filter }
		'maxAnisotropy' { s.anisotropy }
		'sAddressMode' { s.s_address } 'tAddressMode' { s.t_address } 'rAddressMode' { s.r_address }
		'borderColor' { s.border } 'compareFunction' { s.compare }
		else { panic('iOS: unsupported software Metal sampler property') }
	}
}
fn sm_sampler_set(object u64, selector &char, value u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut s := sm_sampler_data(sm_check(object, 'MTLSamplerDescriptor'))
	// Descriptors can represent invalid values; creation validates the snapshot.
	match ctext(u64(selector)) {
		'setMinFilter:' { s.min_filter = value } 'setMagFilter:' { s.mag_filter = value } 'setMipFilter:' { s.mip_filter = value }
		'setMaxAnisotropy:' { s.anisotropy = value }
		'setSAddressMode:' { s.s_address = value } 'setTAddressMode:' { s.t_address = value } 'setRAddressMode:' { s.r_address = value }
		'setBorderColor:' { s.border = value } 'setCompareFunction:' { s.compare = value }
		else { panic('iOS: unsupported software Metal sampler setter') }
	}
}
fn sm_sampler_bool_get(object u64, selector &char) u8 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	s := sm_sampler_data(sm_check(object, 'MTLSamplerDescriptor'))
	return u8(match ctext(u64(selector)) {
		'normalizedCoordinates' { s.normalized } 'lodAverage' { s.lod_average } 'supportArgumentBuffers' { s.argument_buffers }
		else { panic('iOS: unsupported software Metal sampler bool') }
	})
}
fn sm_sampler_bool_set(object u64, selector &char, value u8) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut s := sm_sampler_data(sm_check(object, 'MTLSamplerDescriptor'))
	match ctext(u64(selector)) {
		'setNormalizedCoordinates:' { s.normalized = value != 0 } 'setLodAverage:' { s.lod_average = value != 0 } 'setSupportArgumentBuffers:' { s.argument_buffers = value != 0 }
		else { panic('iOS: unsupported software Metal sampler bool setter') }
	}
}
fn sm_sampler_float_get(object u64, selector &char) f32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	s := sm_sampler_data(sm_check(object, 'MTLSamplerDescriptor'))
	return if ctext(u64(selector)) == 'lodMinClamp' { s.lod_min } else { s.lod_max }
}
fn sm_sampler_float_set(object u64, selector &char, value f32) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut s := sm_sampler_data(sm_check(object, 'MTLSamplerDescriptor'))
	if ctext(u64(selector)) == 'setLodMinClamp:' { s.lod_min = value } else { s.lod_max = value }
}
fn sm_sampler_label(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return obj_header(object).fields[1]
}
fn sm_sampler_label_set(object u64, selector &char, value u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_check(object, 'MTLSamplerDescriptor')
	sm_sampler_data(h)
	if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: software Metal sampler label requires NSString') }
	copy := if value == 0 { u64(0) } else { owned_string(string_text(value)) }
	old := h.fields[1]; h.fields[1] = copy; objc_release(old)
}
fn sm_new_sampler(device u64, selector &char, descriptor u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(device, 'VinixSoftwareMTLDevice')
	h := ios_runtime.objects[descriptor] or { return 0 }
	if h.cls != ios_runtime.names['MTLSamplerDescriptor'] || h.data.len != int(sizeof(SoftwareMetalSampler)) { return 0 }
	s := sm_sampler_data(h)
	if s.min_filter > 1 || s.mag_filter > 1 || s.mip_filter > 2 || s.anisotropy < 1 || s.anisotropy > 16 || s.s_address > 5 || s.t_address > 5 || s.r_address > 5 || s.border > 2 || s.compare > 7 || s.argument_buffers { return 0 }
	// Ordered comparisons reject NaNs; FLT_MAX rejects infinities.
	if !(s.lod_min >= 0 && s.lod_max >= s.lod_min && s.lod_max <= f32(3.4028234663852886e38)) { return 0 }
	if !s.normalized && (s.s_address != 0 || s.t_address != 0 || s.r_address != 0 || s.mip_filter != 0 || s.anisotropy != 1) { return 0 }
	state := sm_new('VinixSoftwareMTLSamplerState', device)
	mut target := obj_header(state)
	unsafe { target.data.free() }
	target.data = h.data.clone()
	target.fields[1] = objc_retain(h.fields[1])
	return state
}
fn sm_sampler_device(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return sm_check(object, 'VinixSoftwareMTLSamplerState').fields[0]
}
fn sm_sampler_start(device u64) {
	for name in [c'MTLSamplerDescriptor', c'VinixSoftwareMTLSamplerState']! {
		cls := objc_allocate_class(ios_runtime.names['NSObject'], name, 0)
		objc_register_class(cls)
	}
	descriptor := ios_runtime.names['MTLSamplerDescriptor']; state := ios_runtime.names['VinixSoftwareMTLSamplerState']
	sm_method(device, c'newSamplerStateWithDescriptor:', u64(unsafe { voidptr(sm_new_sampler) }), c'@24@0:8@16')
	sm_method(descriptor, c'init', u64(unsafe { voidptr(sm_sampler_init) }), c'@16@0:8')
	sm_method(descriptor, c'copy', u64(unsafe { voidptr(sm_sampler_copy_plain) }), c'@16@0:8')
	sm_method(descriptor, c'copyWithZone:', u64(unsafe { voidptr(sm_sampler_copy) }), c'@24@0:8^{_NSZone=}16')
	for selector in [c'minFilter', c'magFilter', c'mipFilter', c'maxAnisotropy', c'sAddressMode', c'tAddressMode', c'rAddressMode', c'borderColor', c'compareFunction']! { sm_method(descriptor, selector, u64(unsafe { voidptr(sm_sampler_get) }), c'Q16@0:8') }
	for selector in [c'setMinFilter:', c'setMagFilter:', c'setMipFilter:', c'setMaxAnisotropy:', c'setSAddressMode:', c'setTAddressMode:', c'setRAddressMode:', c'setBorderColor:', c'setCompareFunction:']! { sm_method(descriptor, selector, u64(unsafe { voidptr(sm_sampler_set) }), c'v24@0:8Q16') }
	for selector in [c'normalizedCoordinates', c'lodAverage', c'supportArgumentBuffers']! { sm_method(descriptor, selector, u64(unsafe { voidptr(sm_sampler_bool_get) }), c'B16@0:8') }
	for selector in [c'setNormalizedCoordinates:', c'setLodAverage:', c'setSupportArgumentBuffers:']! { sm_method(descriptor, selector, u64(unsafe { voidptr(sm_sampler_bool_set) }), c'v20@0:8B16') }
	for selector in [c'lodMinClamp', c'lodMaxClamp']! { sm_method(descriptor, selector, u64(unsafe { voidptr(sm_sampler_float_get) }), c'f16@0:8') }
	for selector in [c'setLodMinClamp:', c'setLodMaxClamp:']! { sm_method(descriptor, selector, u64(unsafe { voidptr(sm_sampler_float_set) }), c'v20@0:8f16') }
	for cls in [descriptor, state]! { sm_method(cls, c'label', u64(unsafe { voidptr(sm_sampler_label) }), c'@16@0:8') }
	sm_method(descriptor, c'setLabel:', u64(unsafe { voidptr(sm_sampler_label_set) }), c'v24@0:8@16')
	sm_method(state, c'device', u64(unsafe { voidptr(sm_sampler_device) }), c'@16@0:8')
}
