// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Configuration only: measured ARM64 Catalyst layout, not snapshot rendering.
fn snapshot_configuration_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'WKSnapshotConfiguration' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic WKSnapshotConfiguration superclass chain')
}

fn snapshot_configuration_require_class(cls u64) {
	if snapshot_configuration_family(cls) && cls != ios_runtime.names['WKSnapshotConfiguration'] {
		panic('iOS: WKSnapshotConfiguration subclass or metaclass construction is not implemented')
	}
}

fn snapshot_configuration_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['WKSnapshotConfiguration']] or { panic('iOS: missing WKSnapshotConfiguration') }
	for i, name in ['_usesTransparentBackground', '_afterScreenUpdates', '_snapshotWidth', '_rect']! {
		info.ivars[name] = &ObjIvar{name: name.clone(), types: ['B', 'B', '@"NSNumber"', '{CGRect="origin"{CGPoint="x"d"y"d}"size"{CGSize="width"d"height"d}}']![i].clone(), offset: [i64(8), 9, 16, 24]![i], size: [u64(1), 1, 8, 32]![i]}
	}
}

fn snapshot_configuration_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder', '_usesTransparentBackground', '_setUsesTransparentBackground:']!
}

fn snapshot_configuration_types(name string, meta bool, selector string) ?string {
	if name != 'WKSnapshotConfiguration' || meta { return none }
	return match selector {
		'init', 'copy', 'snapshotWidth' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'rect' { '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8' }
		'setRect:' { 'v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16' }
		'setSnapshotWidth:' { 'v24@0:8@16' }
		'afterScreenUpdates' { 'B16@0:8' }
		'setAfterScreenUpdates:' { 'v20@0:8B16' }
		else { none }
	}
}

fn snapshot_configuration_require_storage(object u64, initialized bool) {
	header := obj_header(object)
	if header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 56
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['WKSnapshotConfiguration'] {
		panic('iOS: WKSnapshotConfiguration requires live owned configuration storage')
	}
	if initialized && !header.snapshot_configuration_initialized {
		panic('iOS: WKSnapshotConfiguration requires initialization')
	}
}

fn snapshot_configuration_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	snapshot_configuration_require_storage(object, false)
	// Native repeated init resets rect/flag, preserving the copied width.
	unsafe {
		*(&u8(object + 9)) = 1
		*(&u64(object + 24)) = u64(0x7ff0000000000000)
		*(&u64(object + 32)) = u64(0x7ff0000000000000)
		*(&u64(object + 40)) = 0
		*(&u64(object + 48)) = 0
	}
	obj_header(object).snapshot_configuration_initialized = true
	return object
}

fn snapshot_configuration_set_width(object u64, width u64) {
	if width != 0 {
		header := obj_header(width)
		if header.destroying || header.destroyed || header.caller_storage
			|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
			|| header.cls != header.allocation_cls || read64(width) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSNumber'], ios_runtime.names['NSConstantIntegerNumber']]! {
			panic('iOS: WKSnapshotConfiguration snapshotWidth requires a live builtin NSNumber')
		}
	}
	// Copy before releasing the previous width makes self-assignment safe.
	value := if width == 0 { u64(0) } else { objc_copy_value(width, true) }
	mut header := obj_header(object)
	previous := header.fields[0]
	header.fields[0] = value
	unsafe { *(&u64(object + 16)) = value }
	objc_release(previous)
}

fn snapshot_configuration_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	snapshot_configuration_require_storage(object, true)
	duplicate := snapshot_configuration_initialize(objc_allocate(ios_runtime.names['WKSnapshotConfiguration']))
	snapshot_configuration_set_width(duplicate, read64(object + 16))
	unsafe { *(&u8(duplicate + 9)) = *(&u8(object + 9)) }
	for i in 0 .. 4 { unsafe { *(&u64(duplicate + 24 + u64(i * 8))) = read64(object + 24 + u64(i * 8)) } }
	return duplicate
}

fn snapshot_configuration_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !snapshot_configuration_family(cls) { return false }
	if snapshot_configuration_unsupported(selector) { panic('iOS: unsupported WKSnapshotConfiguration method: ' + selector) }
	if meta { return false }
	if snapshot_configuration_types('WKSnapshotConfiguration', false, selector) == none { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	snapshot_configuration_require_storage(object, selector != 'init')
	match selector {
		'init' { frame.x[0] = snapshot_configuration_initialize(object) }
		'copy', 'copyWithZone:' { frame.x[0] = snapshot_configuration_copy(object) }
		'snapshotWidth' { frame.x[0] = read64(object + 16) }
		'setSnapshotWidth:' { snapshot_configuration_set_width(object, frame.x[2]) }
		'afterScreenUpdates' { frame.x[0] = unsafe { u64(*(&u8(object + 9))) } }
		'setAfterScreenUpdates:' { unsafe { *(&u8(object + 9)) = u8(frame.x[2]) } }
		'rect' {
			// CGRect is an ARM64 HFA: one double in each of v0..v3.
			for i in 0 .. 4 { frame.q[i * 2] = read64(object + 24 + u64(i * 8)); frame.q[i * 2 + 1] = 0 }
		}
		'setRect:' { for i in 0 .. 4 { unsafe { *(&u64(object + 24 + u64(i * 8))) = frame.q[i * 2] } } }
		else {}
	}
	return true
}
