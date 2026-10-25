// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Measured on macOS ARM64: NSObject followed by three float ivars, size 24.
// Keep the native bits in object storage, including NaNs and signed zero.
fn gc_color_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GCColor' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic GCColor superclass chain')
}

fn gc_color_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['GCColor']] or { panic('iOS: missing GCColor') }
	for i, name in ['_red', '_green', '_blue']! {
		info.ivars[name] = &ObjIvar{name: name.clone(), types: 'f'.clone(), offset: i64(8 + 4 * i), size: 4}
	}
}

fn gc_color_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'initWithColorPreset:']!
}

fn gc_color_types(name string, meta bool, selector string) ?string {
	if name != 'GCColor' || meta { return none }
	return match selector {
		'initWithRed:green:blue:' { '@28@0:8f16f20f24' }
		'red', 'green', 'blue' { 'f16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'description' { '@16@0:8' }
		else { none }
	}
}

fn gc_color_require_storage(object u64) {
	header := obj_header(object)
	if header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.native_size < 24 || header.cls != header.allocation_cls
		|| read64(object) != header.allocation_cls || !gc_color_family(header.allocation_cls) {
		panic('iOS: GCColor requires live owned color storage')
	}
}

fn gc_color_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !gc_color_family(cls) { return false }
	if gc_color_unsupported(selector) { panic('iOS: unsupported GCColor method: ' + selector) }
	if meta { return false }
	if selector !in ['init', 'initWithRed:green:blue:', 'red', 'green', 'blue', 'copy', 'copyWithZone:', 'description']! { return false }
	gc_color_require_storage(object)
	match selector {
		'init' { frame.x[0] = object }
		'initWithRed:green:blue:' {
			for i in 0 .. 3 { unsafe { *(&u32(object + 8 + u64(4 * i))) = u32(frame.q[2 * i]) } }
			frame.x[0] = object
		}
		'red', 'green', 'blue' {
			index := if selector == 'red' { 0 } else if selector == 'green' { 1 } else { 2 }
			frame.q[0] = u64(read32(object + 8 + u64(4 * index)))
			frame.q[1] = 0
		}
		'copy', 'copyWithZone:' {
			values := [read32(object + 8), read32(object + 12), read32(object + 16)]!
			duplicate := objc_allocate(read64(object))
			if duplicate != 0 { unsafe { C.memcpy(voidptr(duplicate + 8), &values[0], 12) } }
			frame.x[0] = duplicate
		}
		'description' {
			mut bytes := [256]u8{}
			values := unsafe { &f32(object + 8) }
			length := unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'<GCColor r=%f g=%f b=%f>', f64(values[0]), f64(values[1]), f64(values[2])) }
			if length < 0 || length >= bytes.len { panic('iOS: GCColor description formatting failed') }
			frame.x[0] = objc_autorelease(owned_string(unsafe { tos(&bytes[0], length) }))
		}
		else {}
	}
	return true
}
