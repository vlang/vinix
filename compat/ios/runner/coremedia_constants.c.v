// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn coremedia_constant_symbol(symbol string) ?u64 {
	index := match symbol {
		'_kCMFormatDescriptionExtension_FullRangeVideo' { 0 }
		'_kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms' { 1 }
		'_kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG' { 2 }
		'_kCMFormatDescriptionTransferFunction_Linear' { 3 }
		'_kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ' { 4 }
		'_kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1' { 5 }
		'_kCMFormatDescriptionTransferFunction_sRGB' { 6 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.coremedia_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate CoreMedia globals') }
		texts := ['FullRangeVideo', 'SampleDescriptionExtensionAtoms', 'ITU_R_2100_HLG', 'Linear', 'SMPTE_ST_2084_PQ', 'SMPTE_ST_428_1', 'IEC_sRGB']!
		mut cursor := u64(280) // Seven cells and seven 32-byte CFSTR records.
		for i, text in texts {
			object := u64(arena) + 56 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: CoreMedia globals exceed their page') }
			unsafe {
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
				*(&u64(u64(arena) + u64(i * 8))) = object
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal CoreMedia globals') }
		ios_runtime.coremedia_constants_arena = u64(arena)
	}
	return ios_runtime.coremedia_constants_arena + u64(index * 8)
}
fn coremedia_constants_stop() {
	arena := ios_runtime.coremedia_constants_arena
	if arena == 0 { return }
	for i in 0 .. 7 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire CoreMedia globals') }
	ios_runtime.coremedia_constants_arena = 0
}
