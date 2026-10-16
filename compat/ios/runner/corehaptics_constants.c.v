// SPDX-License-Identifier: GPL-2.0-or-later
module main

// CoreHaptics exports NSString pointer cells. These values were measured from
// the installed framework; they are not the exported symbol spellings.
fn corehaptics_constant_symbol(symbol string) ?u64 {
	index := match symbol {
		'_CHHapticDynamicParameterIDHapticIntensityControl' { 0 }
		'_CHHapticDynamicParameterIDHapticSharpnessControl' { 1 }
		'_CHHapticEventParameterIDHapticIntensity' { 2 }
		'_CHHapticEventParameterIDHapticSharpness' { 3 }
		'_CHHapticEventTypeHapticContinuous' { 4 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.corehaptics_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
			C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate CoreHaptics globals') }
		// Five pointer cells followed by five 32-byte CFSTR records.
		mut cursor := u64(200)
		for i, text in ['HapticIntensityControl', 'HapticSharpnessControl',
			'HapticIntensity', 'HapticSharpness', 'HapticContinuous']! {
			object := u64(arena) + 40 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) {
				panic('iOS: CoreHaptics globals exceed their page')
			}
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
		if C.mprotect(arena, page, C.PROT_READ) != 0 {
			panic('iOS: cannot seal CoreHaptics globals')
		}
		ios_runtime.corehaptics_constants_arena = u64(arena)
	}
	return ios_runtime.corehaptics_constants_arena + u64(index * 8)
}

// Pool destructors, collections and Swift contexts may still borrow these
// immortal strings. Retire the registrations and page after those users drain.
fn corehaptics_constants_stop() {
	arena := ios_runtime.corehaptics_constants_arena
	if arena == 0 { return }
	for i in 0 .. 5 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 {
		panic('iOS: cannot retire CoreHaptics globals')
	}
	ios_runtime.corehaptics_constants_arena = 0
}
