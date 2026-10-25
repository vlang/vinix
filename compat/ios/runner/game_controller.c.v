// SPDX-License-Identifier: GPL-2.0-or-later
module main

// No physical controller transport exists in the desktop input protocol.
// Discovery is accurate for that environment; creating profiles is unsupported.
fn game_controller_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'GCController' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic controller superclass chain')
}

fn game_controller_unsupported(selector string) bool {
	return selector in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:',
		'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding']!
}

fn game_controller_require_discovery(cls u64) {
	if game_controller_family(cls) {
		panic('iOS: GCController construction requires an implemented physical input profile')
	}
}

fn game_controller_types(name string, meta bool, selector string) ?string {
	if name != 'GCController' || !meta { return none }
	return match selector {
		'controllers', 'current' { '@16@0:8' }
		'shouldMonitorBackgroundEvents' { 'B16@0:8' }
		'setShouldMonitorBackgroundEvents:' { 'v20@0:8B16' }
		else { none }
	}
}

fn game_controller_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !game_controller_family(if meta { object } else { read64(object) }) { return false }
	if game_controller_unsupported(selector) {
		panic('iOS: GCController construction requires an implemented physical input profile')
	}
	if !meta { return false }
	match selector {
		'controllers' {
			frame.x[0] = ns_empty_array_symbol('___NSArray0__struct') or { panic('iOS: controller discovery after shutdown') }
		}
		'current' { frame.x[0] = 0 }
		'shouldMonitorBackgroundEvents' {
			C.ios_objc_initialize_lock()
			frame.x[0] = u64(ios_runtime.controller_background_events)
			C.ios_objc_initialize_unlock()
		}
		'setShouldMonitorBackgroundEvents:' {
			C.ios_objc_initialize_lock()
			ios_runtime.controller_background_events = u8(frame.x[2]) != 0
			C.ios_objc_initialize_unlock()
			frame.x[0] = 0
		}
		else { return false }
	}
	return true
}

fn game_controller_constant_index(symbol string) ?int {
	return match symbol {
		'_GCControllerDidBecomeCurrentNotification' { 0 }
		'_GCControllerDidConnectNotification' { 1 }
		'_GCControllerDidDisconnectNotification' { 2 }
		else { none }
	}
}

fn game_controller_symbol(symbol string) ?u64 {
	cls := ios_runtime.names['GCController']
	if symbol == '_OBJC_CLASS_$_GCController' { return cls }
	if symbol == '_OBJC_METACLASS_$_GCController' { return read64(cls) }
	index := game_controller_constant_index(symbol) or { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.controller_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate controller globals') }
		mut cursor := u64(120)
		for i, text in ['GCControllerDidBecomeCurrentNotification',
			'GCControllerDidConnectNotification', 'GCControllerDidDisconnectNotification']! {
			object := u64(arena) + 24 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: controller globals exceed their page') }
			unsafe {
				*(&u64(u64(arena) + u64(i * 8))) = object
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal controller globals') }
		ios_runtime.controller_constants_arena = u64(arena)
	}
	return ios_runtime.controller_constants_arena + u64(index * 8)
}

// Borrowed by notification observers and collections until ordinary owners drain.
fn game_controller_stop() {
	arena := ios_runtime.controller_constants_arena
	if arena == 0 { return }
	for i in 0 .. 3 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire controller globals')
	}
	ios_runtime.controller_constants_arena = 0
}
