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
		'_kCMFormatDescriptionColorPrimaries_P3_D65' { 7 }
		'_kCMFormatDescriptionColorPrimaries_DCI_P3' { 8 }
		'_kCMFormatDescriptionColorPrimaries_ITU_R_2020' { 9 }
		'_kCMFormatDescriptionYCbCrMatrix_ITU_R_2020' { 10 }
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
		texts := ['FullRangeVideo', 'SampleDescriptionExtensionAtoms', 'ITU_R_2100_HLG', 'Linear', 'SMPTE_ST_2084_PQ', 'SMPTE_ST_428_1', 'IEC_sRGB', 'P3_D65', 'DCI_P3', 'ITU_R_2020', 'ITU_R_2020']!
		mut cursor := u64(440) // Eleven cells and eleven possible 32-byte CFSTR records.
		for i, text in texts {
			mut object := u64(0)
			for j in 0 .. i { if texts[j] == text { object = read64(u64(arena) + u64(j * 8)); break } }
			if object == 0 {
				object = u64(arena) + 88 + u64(i * 32)
				if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: CoreMedia globals exceed their page') }
				unsafe {
					*(&u64(object)) = ios_runtime.names['NSString']
					*(&u64(object + 8)) = 0x7c8
					*(&u64(object + 16)) = u64(arena) + cursor
					*(&u64(object + 24)) = u64(text.len)
					C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
				}
				cursor += u64(text.len) + 1
				ios_runtime.constants[object] = true
			}
			// Native 2020 globals have distinct cells sharing one CFString.
			unsafe { *(&u64(u64(arena) + u64(i * 8))) = object }
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal CoreMedia globals') }
		ios_runtime.coremedia_constants_arena = u64(arena)
	}
	return ios_runtime.coremedia_constants_arena + u64(index * 8)
}
fn coremedia_constants_stop() {
	arena := ios_runtime.coremedia_constants_arena
	if arena == 0 { return }
	for i in 0 .. 11 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire CoreMedia globals') }
	ios_runtime.coremedia_constants_arena = 0
}
