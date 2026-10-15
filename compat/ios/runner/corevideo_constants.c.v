// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn corevideo_constant_symbol(symbol string) ?u64 {
	index := match symbol {
		'_kCVImageBufferColorPrimariesKey' { 0 }
		'_kCVImageBufferGammaLevelKey' { 1 }
		'_kCVImageBufferTransferFunctionKey' { 2 }
		'_kCVImageBufferTransferFunction_ITU_R_709_2' { 3 }
		'_kCVImageBufferTransferFunction_SMPTE_240M_1995' { 4 }
		'_kCVImageBufferTransferFunction_UseGamma' { 5 }
		'_kCVImageBufferYCbCrMatrixKey' { 6 }
		'_kCVPixelBufferBytesPerRowAlignmentKey' { 7 }
		'_kCVPixelBufferMetalCompatibilityKey' { 8 }
		'_kCVPixelBufferOpenGLESCompatibilityKey' { 9 }
		'_kCVImageBufferColorPrimaries_ITU_R_709_2' { 10 }
		'_kCVImageBufferColorPrimaries_SMPTE_C' { 11 }
		'_kCVImageBufferColorPrimaries_EBU_3213' { 12 }
		'_kCVImageBufferYCbCrMatrix_ITU_R_709_2' { 13 }
		'_kCVImageBufferYCbCrMatrix_SMPTE_240M_1995' { 14 }
		'_kCVImageBufferYCbCrMatrix_ITU_R_601_4' { 15 }
		'_kCVPixelBufferPixelFormatTypeKey' { 16 }
		'_kCVPixelBufferPlaneAlignmentKey' { 17 }
		'_kCVPixelBufferIOSurfacePropertiesKey' { 18 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.corevideo_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate CoreVideo globals') }
		texts := ['CVImageBufferColorPrimaries', 'CVImageBufferGammaLevel', 'CVImageBufferTransferFunction',
			'ITU_R_709_2', 'SMPTE_240M_1995', 'UseGamma', 'CVImageBufferYCbCrMatrix',
			'BytesPerRowAlignment', 'MetalCompatibility', 'OpenGLESCompatibility', 'ITU_R_709_2',
			'SMPTE_C', 'EBU_3213', 'ITU_R_709_2', 'SMPTE_240M_1995', 'ITU_R_601_4', 'PixelFormatType',
			'PlaneAlignment', 'IOSurfaceProperties']!
		mut cursor := u64(768) // 19 cells, alignment padding, then 19 possible CFSTR records.
		for i, text in texts {
			mut object := u64(0)
			for j in 0 .. i { if texts[j] == text { object = read64(u64(arena) + u64(j * 8)); break } }
			if object == 0 {
				object = u64(arena) + 160 + u64(i * 32)
				if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: CoreVideo globals exceed their page') }
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
			// Native 709/240M globals have separate cells sharing their CFString.
			unsafe { *(&u64(u64(arena) + u64(i * 8))) = object }
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal CoreVideo globals') }
		ios_runtime.corevideo_constants_arena = u64(arena)
	}
	return ios_runtime.corevideo_constants_arena + u64(index * 8)
}

fn corevideo_constants_stop() {
	arena := ios_runtime.corevideo_constants_arena
	if arena == 0 { return }
	for i in 0 .. 19 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire CoreVideo globals') }
	ios_runtime.corevideo_constants_arena = 0
}
