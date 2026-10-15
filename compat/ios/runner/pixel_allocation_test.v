// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type PACreate = fn (u64, u64, u64, u32, u64, &u64) i32
type PAQuery = fn (u64) u64
type PAFormat = fn (u64) u32
type PAPlane = fn (u64, u64) u64
type PAFlag = fn (u64, u64) i32
type PADrop = fn (u64)
type PANumber = fn (u64, i64, u64) u64
type PADictionary = fn (u64, u64, u64, i64, u64, u64) u64
type PAText = fn (u64, &char, i64, u32) bool
type PAPoison = fn (voidptr) i32
struct PAApi { native bool cv u64 cf u64 }

fn pa_symbol(api PAApi, name string, core bool) u64 {
	if api.native { return u64(C.dlsym(unsafe { voidptr(if core { api.cf } else { api.cv }) }, unsafe { &char(name.str + 1) })) }
	return runtime_symbol(if core { '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' } else { '/System/Library/Frameworks/CoreVideo.framework/CoreVideo' }, name) or { panic(err) }
}
fn pa_global(api PAApi, name string) u64 { cell := pa_symbol(api, name, false); assert cell != 0; return read64(cell) }
fn pa_query(api PAApi, name string, object u64) u64 { return unsafe { PAQuery(voidptr(pa_symbol(api, name, false)))(object) } }
fn pa_plane(api PAApi, name string, object u64, index u64) u64 { return unsafe { PAPlane(voidptr(pa_symbol(api, name, false)))(object, index) } }
fn pa_flag(api PAApi, name string, object u64, flags u64) i32 { return unsafe { PAFlag(voidptr(pa_symbol(api, name, false)))(object, flags) } }
fn pa_drop(api PAApi, object u64) { unsafe { PADrop(voidptr(pa_symbol(api, '_CFRelease', true)))(object) } }
fn pa_number(api PAApi, value i64) u64 { return unsafe { PANumber(voidptr(pa_symbol(api, '_CFNumberCreate', true)))(0, 4, u64(&value)) } }
fn pa_dict(api PAApi, keys []u64, values []u64) u64 {
	assert keys.len == values.len
	return unsafe { PADictionary(voidptr(pa_symbol(api, '_CFDictionaryCreate', true)))(0, u64(keys.data), u64(values.data), i64(keys.len), pa_symbol(api, '_kCFTypeDictionaryKeyCallBacks', true), pa_symbol(api, '_kCFTypeDictionaryValueCallBacks', true)) }
}
fn pa_attributes(api PAApi, row i64, plane i64) u64 {
	if row == 0 && plane == 0 { return 0 }
	mut keys := []u64{}
	mut values := []u64{}
	if row != 0 { keys << pa_global(api, '_kCVPixelBufferBytesPerRowAlignmentKey'); values << pa_number(api, row) }
	if plane != 0 { keys << pa_global(api, '_kCVPixelBufferPlaneAlignmentKey'); values << pa_number(api, plane) }
	attributes := pa_dict(api, keys, values)
	for value in values { pa_drop(api, value) }
	unsafe { keys.free(); values.free() }
	return attributes
}
fn pa_be32(address u64) u64 {
	bytes := unsafe { &u8(address) }
	return unsafe { u64(bytes[0]) * 16777216 + u64(bytes[1]) * 65536 + u64(bytes[2]) * 256 + u64(bytes[3]) }
}

fn pa_verify(api PAApi, object u64, width u64, height u64, format u32, row_alignment u64, plane_alignment u64) {
	assert pa_query(api, '_CVPixelBufferGetWidth', object) == width
	assert pa_query(api, '_CVPixelBufferGetHeight', object) == height
	assert unsafe { PAFormat(voidptr(pa_symbol(api, '_CVPixelBufferGetPixelFormatType', false)))(object) } == format
	assert pa_flag(api, '_CVPixelBufferLockBaseAddress', object, 0) == 0
	base := pa_query(api, '_CVPixelBufferGetBaseAddress', object)
	size := pa_query(api, '_CVPixelBufferGetDataSize', object)
	assert base != 0 && size > 0
	packed := format == 0x42475241
	assert pa_query(api, '_CVPixelBufferGetPlaneCount', object) == if packed { u64(0) } else { u64(2) }
	count := if packed { 1 } else { 2 }
	mut previous_end := if packed { base } else { base + 16 }
	for plane in 0 .. count {
		w := if plane == 0 { width } else { (width + 1) / 2 }
		h := if plane == 0 { height } else { (height + 1) / 2 }
		assert pa_plane(api, '_CVPixelBufferGetWidthOfPlane', object, u64(plane)) == w
		assert pa_plane(api, '_CVPixelBufferGetHeightOfPlane', object, u64(plane)) == h
		row := pa_plane(api, '_CVPixelBufferGetBytesPerRowOfPlane', object, u64(plane))
		address := pa_plane(api, '_CVPixelBufferGetBaseAddressOfPlane', object, u64(plane))
		pixel_bytes := if packed { u64(4) } else if plane == 0 { u64(1) } else { u64(2) }
		assert row >= w * pixel_bytes && row % row_alignment == 0
		assert address >= previous_end && address + row * h <= base + size
		if !packed {
			assert (address - base) % plane_alignment == 0
			assert pa_be32(base + u64(plane * 8)) == address - base
			assert pa_be32(base + u64(plane * 8 + 4)) == row
		}
		// Fill complete rows, including padding and the final byte of each plane.
		for y := u64(0); y < h; y++ { for x := u64(0); x < row; x++ { unsafe { *(&u8(address + y * row + x)) = u8((x + y + u64(plane * 31)) % 251) } } }
		previous_end = address + row * h
	}
	assert pa_flag(api, '_CVPixelBufferUnlockBaseAddress', object, 0) == 0
	assert pa_flag(api, '_CVPixelBufferLockBaseAddress', object, 1) == 0
	for plane in 0 .. count {
		h := if plane == 0 { height } else { (height + 1) / 2 }
		row := pa_plane(api, '_CVPixelBufferGetBytesPerRowOfPlane', object, u64(plane))
		address := pa_plane(api, '_CVPixelBufferGetBaseAddressOfPlane', object, u64(plane))
		for y := u64(0); y < h; y++ { for x := u64(0); x < row; x++ { assert unsafe { *(&u8(address + y * row + x)) } == u8((x + y + u64(plane * 31)) % 251) } }
	}
	assert pa_flag(api, '_CVPixelBufferUnlockBaseAddress', object, 1) == 0
}

fn pa_reader(api PAApi, object u64) {
	for _ in 0 .. 64 {
		assert unsafe { PAQuery(voidptr(pa_symbol(api, '_CFRetain', true)))(object) } == object
		assert pa_flag(api, '_CVPixelBufferLockBaseAddress', object, 1) == 0
		assert pa_query(api, '_CVPixelBufferGetWidth', object) == 8
		base := pa_plane(api, '_CVPixelBufferGetBaseAddressOfPlane', object, 1)
		assert unsafe { *(&u8(base)) } == 31
		assert pa_flag(api, '_CVPixelBufferUnlockBaseAddress', object, 1) == 0
		pa_drop(api, object)
	}
}

fn pa_cases(api PAApi) {
	create := unsafe { PACreate(voidptr(pa_symbol(api, '_CVPixelBufferCreate', false))) }
	for alignments in [[i64(0), 0]!, [i64(1), 1]!, [i64(3), 24]!, [i64(128), 256]!]! {
		for dimensions in [[u64(7), 3]!, [u64(8), 4]!, [u64(1), 1]!]! {
			for format in [u32(0x42475241), 0x34323076, 0x34323066]! {
				attributes := pa_attributes(api, alignments[0], alignments[1])
				mut output := [u64(0xcafe), 0, 0xbeef]!
				assert create(0, dimensions[0], dimensions[1], format, attributes, unsafe { &output[1] }) == 0
				if attributes != 0 { pa_drop(api, attributes) } // Buffer must own no dictionary/number references.
				assert output[0] == 0xcafe && output[1] != 0 && output[2] == 0xbeef
				object := output[1]
				pa_verify(api, object, dimensions[0], dimensions[1], format, if alignments[0] == 0 { u64(1) } else { u64(alignments[0]) }, if alignments[1] == 0 { u64(1) } else { u64(alignments[1]) })
				assert pa_query(api, '_CVPixelBufferRetain', object) == object
				unsafe { PADrop(voidptr(pa_symbol(api, '_CVPixelBufferRelease', false)))(object) }
				assert pa_query(api, '_CVPixelBufferGetWidth', object) == dimensions[0]
				pa_drop(api, object)
			}
		}
	}
	mut shared := u64(0)
	assert create(0, 8, 4, 0x34323076, 0, &shared) == 0
	pa_verify(api, shared, 8, 4, 0x34323076, 1, 1)
	mut readers := []thread{}
	for _ in 0 .. 8 { readers << spawn pa_reader(api, shared) }
	readers.wait()
	unsafe { readers.free() }
	pa_drop(api, shared)
	for dimensions in [[u64(0), 3]!, [u64(7), 0]!]! {
		mut output := u64(0xfeed)
		assert create(0, dimensions[0], dimensions[1], 0x42475241, 0, &output) == -6661 && output == 0xfeed
	}
	mut output := u64(0xfeed)
	assert create(0, 8, 4, 0xdeadbeef, 0, &output) == -6680 && output == 0
	for name in ['_kCVPixelBufferPlaneAlignmentKey', '_kCVPixelBufferIOSurfacePropertiesKey']! {
		value := pa_global(api, name)
		expected := name.all_after('_kCVPixelBuffer').trim_string_right('Key')
		if api.native { mut text := [128]u8{}; assert unsafe { PAText(voidptr(pa_symbol(api, '_CFStringGetCString', true)))(value, &char(&text[0]), 128, 0x08000100) }; assert unsafe { (&char(&text[0])).vstring() } == expected }
		else { assert string_text(value) == expected }
	}
}

fn pa_private_failures() {
	for dimensions in [[~u64(0), 4]!, [u64(8), ~u64(0)]!, [u64(0x40000000), 4]!]! {
		mut output := u64(0xfeed)
		assert cv_pixel_create(0, dimensions[0], dimensions[1], 0x34323076, 0, &output) == -6681 && output == 0
	}
	for pair in [['_kCVPixelBufferMetalCompatibilityKey', '-6684']!, ['_kCVPixelBufferOpenGLESCompatibilityKey', '-6683']!, ['_kCVPixelBufferIOSurfacePropertiesKey', '-6663']!]! {
		value := pa_number(PAApi{}, 1)
		attributes := pa_dict(PAApi{}, [pa_global(PAApi{}, pair[0])], [value])
		mut output := u64(0xfeed)
		assert cv_pixel_create(0, 8, 4, 0x42475241, attributes, &output) == pair[1].int() && output == 0
		pa_drop(PAApi{}, attributes); pa_drop(PAApi{}, value)
	}
	for alignment in [i64(-1), 0, 0x7fffffffffffffff]! {
		value := pa_number(PAApi{}, alignment)
		attributes := pa_dict(PAApi{}, [pa_global(PAApi{}, '_kCVPixelBufferBytesPerRowAlignmentKey')], [value])
		mut output := u64(0xfeed)
		assert cv_pixel_create(0, 8, 4, 0x42475241, attributes, &output) == if alignment > 0 { -6681 } else { -6682 }
		assert output == 0
		pa_drop(PAApi{}, attributes); pa_drop(PAApi{}, value)
	}
	for key in ['_kCVImageBufferGammaLevelKey', '_kCVPixelBufferBytesPerRowAlignmentKey']! {
		// Unsupported keys and values of the wrong type must never silently
		// create a buffer whose advertised allocation requirements were ignored.
		attributes := pa_dict(PAApi{}, [pa_global(PAApi{}, key)], [pa_global(PAApi{}, '_kCVImageBufferGammaLevelKey')])
		mut output := u64(0xfeed)
		assert cv_pixel_create(0, 8, 4, 0x42475241, attributes, &output) == -6682 && output == 0
		pa_drop(PAApi{}, attributes)
	}
	false_value := pa_number(PAApi{}, 0)
	false_attributes := pa_dict(PAApi{}, [pa_global(PAApi{}, '_kCVPixelBufferMetalCompatibilityKey'), pa_global(PAApi{}, '_kCVPixelBufferOpenGLESCompatibilityKey')], [false_value, false_value])
	mut cpu_only := u64(0)
	assert cv_pixel_create(0, 8, 4, 0x42475241, false_attributes, &cpu_only) == 0
	pa_drop(PAApi{}, false_attributes); pa_drop(PAApi{}, false_value); pa_drop(PAApi{}, cpu_only)
	assert cv_pixel_create(0, 8, 4, 0x42475241, 0, unsafe { nil }) == -6661
	for _ in 0 .. 256 {
		mut output := u64(0)
		assert cv_pixel_create(0, 8, 4, 0x34323076, 0, &output) == 0
		allocation := cv_pixel_state(output).allocation
		objc_release(output)
		$if macos {
			// When this fixture runs under ASan, verify that final CF/ObjC
			// release really freed the backing bytes, beyond object-count checks.
			check := C.dlsym(unsafe { voidptr(-2) }, c'__asan_address_is_poisoned')
			if check != unsafe { nil } { assert unsafe { PAPoison(check)(voidptr(allocation)) } != 0 }
		}
	}
}

fn test_pixel_allocation() {
	$if macos {
		api := PAApi{true, u64(C.dlopen(c'/System/Library/Frameworks/CoreVideo.framework/CoreVideo', 2)), u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2))}
		assert api.cv != 0 && api.cf != 0
		pa_cases(api)
		println('IOS-PIXEL-ALLOCATION-NATIVE: owned BGRA and 420v/420f,odd dimensions,alignment attributes,plane descriptors,bounded full-row writes/readback,CF ownership,eight concurrent readers and native error output semantics')
	}
	for _ in 0 .. 2 {
		objc_start()
		pa_cases(PAApi{})
		pa_private_failures()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		for symbol in ['_kCVPixelBufferPlaneAlignmentKey', '_kCVPixelBufferIOSurfacePropertiesKey', '_CVPixelBufferCreate']! {
			if _ := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', symbol) { assert false }
		}
		objc_stop()
		assert ios_runtime.corevideo_constants_arena == 0 && ios_runtime.live == 0
	}
	println('IOS-PIXEL-ALLOCATION: owned aligned CPU BGRA/YUV,checked arithmetic,big-endian plane descriptors,CF lifetime/churn,invalid attributes and sizes,explicit GPU/surface failures,two drained runtimes')
}
