// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.__atomic_load_n(&u64, int) u64
fn C.__atomic_store_n(&u64, u64, int)
struct VDAPI { native bool handles [4]u64 }
type VDQuery = fn (u64) u64
type VDDrop = fn (u64)
type VDString = fn (u64, &char, u32) u64
type VDDict = fn (u64, i64, u64, u64) u64
type VDSet = fn (u64, u64, u64)
type VDNumber = fn (u64, i64, u64) u64
type VDH264 = fn (u64, u64, &u64, &u64, i32, &u64) i32
type VDHEVC = fn (u64, u64, &u64, &u64, i32, u64, &u64) i32
type VDCreate = fn (u64, u64, u64, u64, u64, &u64) i32
type VDAccept = fn (u64, u64) u8
type VDStatus = fn (u64) i32
type VDDecode = fn (u64, u64, u32, u64, &u32) i32
type VDBlock = fn (u64, u64, u64, u64, u64, u64, u64, u32, &u64) i32
type VDReplace = fn (u64, u64, u64, u64) i32
type VDSample = fn (u64, u64, u8, u64, u64, u64, i64, i64, &CMSampleTiming, i64, &u64, &u64) i32
type VDLock = fn (u64, u64) i32
type VDPlane = fn (u64, u64) u64
struct VDContext {
	api VDAPI
mut:
	calls int
	image u64
	session u64
	reentrant bool
	entered u64
	leave u64
	joining u64
	joined u64
	gate bool
}
fn vd_symbol(api VDAPI, group int, name string) u64 {
	if api.native { p := u64(C.dlsym(unsafe { voidptr(api.handles[group]) }, unsafe { &char(name.str + 1) })); assert p != 0, name; return p }
	return runtime_symbol('/System/Library/Frameworks/' + ['CoreFoundation', 'CoreMedia', 'CoreVideo', 'VideoToolbox']![group] + '.framework/' + ['CoreFoundation', 'CoreMedia', 'CoreVideo', 'VideoToolbox']![group], name) or { panic(err) }
}
fn vd_query(api VDAPI, group int, name string, object u64) u64 { return unsafe { VDQuery(voidptr(vd_symbol(api, group, name)))(object) } }
fn vd_drop(api VDAPI, object u64) { unsafe { VDDrop(voidptr(vd_symbol(api, 0, '_CFRelease')))(object) } }
fn vd_dict(api VDAPI) u64 { return unsafe { VDDict(voidptr(vd_symbol(api, 0, '_CFDictionaryCreateMutable')))(0, 0, vd_symbol(api, 0, '_kCFTypeDictionaryKeyCallBacks'), vd_symbol(api, 0, '_kCFTypeDictionaryValueCallBacks')) } }
fn vd_put(api VDAPI, object u64, name string, number i64) {
	key := unsafe { VDString(voidptr(vd_symbol(api, 0, '_CFStringCreateWithCString')))(0, &char(name.str), 0x08000100) }
	value := unsafe { VDNumber(voidptr(vd_symbol(api, 0, '_CFNumberCreate')))(0, 4, u64(&number)) }
	unsafe { VDSet(voidptr(vd_symbol(api, 0, '_CFDictionarySetValue')))(object, key, value) }; vd_drop(api, key); vd_drop(api, value)
}
fn vd_output(context u64, source u64, status i32, info u32, image u64, pts CMTime, duration CMTime) {
	mut c := unsafe { &VDContext(context) }
	assert source == 0x1234 && status == 0 && info == 0 && image != 0, 'callback native=${c.api.native} source=${source.hex()} status=${status} info=${info} image=${image.hex()}'
	assert pts == CMTime{17, 5, 1, 0} && duration == CMTime{1, 5, 1, 0}
	c.calls++
	assert c.image == 0
	c.image = vd_query(c.api, 0, '_CFRetain', image)
	if c.gate {
		C.__atomic_store_n(unsafe { &c.entered }, 1, 5)
		for C.__atomic_load_n(unsafe { &c.leave }, 5) == 0 { C.usleep(1000) }
	}
	if c.reentrant {
		// The active decode owns its session, including when a callback drops
		// the caller's last reference after invalidating that session.
		unsafe { VDDrop(voidptr(vd_symbol(c.api, 3, '_VTDecompressionSessionInvalidate')))(c.session) }
		vd_drop(c.api, c.session)
	}
}
fn vd_format(api VDAPI, hevc bool) u64 {
	texts := if hevc { ['40010c01ffff01600000030090000003000003001e928090', '42010101600000030090000003000003001ea0208105964a924caf016801', '4401c172b42240'] } else { ['6742c00ad90426c044000003000400000300283c489920', '68cb83cb20'] }
	mut units := [][]u8{}; mut pointers := []u64{}; mut sizes := []u64{}
	for text in texts { bytes := hex.decode(text) or { panic(err) }; units << bytes; pointers << u64(bytes.data); sizes << u64(bytes.len) }
	mut format := u64(0)
	status := if hevc { unsafe { VDHEVC(voidptr(vd_symbol(api, 1, '_CMVideoFormatDescriptionCreateFromHEVCParameterSets')))(0, 3, &pointers[0], &sizes[0], 4, 0, &format) } } else { unsafe { VDH264(voidptr(vd_symbol(api, 1, '_CMVideoFormatDescriptionCreateFromH264ParameterSets')))(0, 2, &pointers[0], &sizes[0], 4, &format) } }
	assert status == 0, 'format status ${status}'
	for bytes in units { unsafe { bytes.free() } }; unsafe { units.free(); pointers.free(); sizes.free() }
	return format
}
fn vd_sample(api VDAPI, format u64, hevc bool, blue bool) u64 {
	text := if hevc { if blue { '000000132801af26fa5503fff70f7a0ee6bffb73d29f9e' } else { '000000132801af26fa5503ffeee97ff39321d6d0529f9e' } } else { if blue { '0000001f6588840ff118a0002d231c00055ca38000860c9c9c9d75d75d75d75d75d75e' } else { '0000001f6588840ff118a00026fb1c000470638000ab949c9c9d75d75d75d75d75d75e' } }
	bytes := hex.decode(text) or { panic(err) }; defer { unsafe { bytes.free() } }
	mut block := u64(0); size := u64(bytes.len)
	assert unsafe { VDBlock(voidptr(vd_symbol(api, 1, '_CMBlockBufferCreateWithMemoryBlock')))(0, 0, size, 0, 0, 0, size, 0, &block) } == 0
	assert unsafe { VDReplace(voidptr(vd_symbol(api, 1, '_CMBlockBufferReplaceDataBytes')))(u64(bytes.data), block, 0, size) } == 0
	timing := CMSampleTiming{CMTime{1, 5, 1, 0}, CMTime{17, 5, 1, 0}, CMTime{}}
	mut sample := u64(0)
	assert unsafe { VDSample(voidptr(vd_symbol(api, 1, '_CMSampleBufferCreate')))(0, block, 1, 0, 0, format, 1, 1, &timing, 1, &size, &sample) } == 0
	vd_drop(api, block); return sample
}
fn vd_pixels(api VDAPI, image u64, pixel u32, blue bool) {
	assert vd_query(api, 2, '_CVPixelBufferGetWidth', image) == 64 && vd_query(api, 2, '_CVPixelBufferGetHeight', image) == 64
	assert unsafe { VDLock(voidptr(vd_symbol(api, 2, '_CVPixelBufferLockBaseAddress')))(image, 1) } == 0
	defer { assert unsafe { VDLock(voidptr(vd_symbol(api, 2, '_CVPixelBufferUnlockBaseAddress')))(image, 1) } == 0 }
	if pixel == 0x42475241 {
		base := vd_query(api, 2, '_CVPixelBufferGetBaseAddress', image); stride := vd_query(api, 2, '_CVPixelBufferGetBytesPerRow', image)
		for y in 0 .. 64 { for x in 0 .. 64 { unsafe { p := &u8(base + u64(y) * stride + u64(x) * 4); assert p[3] == 255; assert p[1] < 4; assert p[if blue { 0 } else { 2 }] > 250; assert p[if blue { 2 } else { 0 }] < 4 } } }
	} else {
		plane := unsafe { VDPlane(voidptr(vd_symbol(api, 2, '_CVPixelBufferGetBaseAddressOfPlane'))) }; stride := unsafe { VDPlane(voidptr(vd_symbol(api, 2, '_CVPixelBufferGetBytesPerRowOfPlane'))) }
		assert vd_query(api, 2, '_CVPixelBufferGetPlaneCount', image) == 2
		expected_y := if pixel == 0x34323066 { if blue { 29 } else { 76 } } else { if blue { 41 } else { 81 } }
		for y in 0 .. 64 { for x in 0 .. 64 { value := int(unsafe { *(&u8(plane(image, 0) + u64(y) * stride(image, 0) + u64(x))) }); assert value >= expected_y - 2 && value <= expected_y + 2 } }
		for y in 0 .. 32 { for x in 0 .. 32 { unsafe { p := &u8(plane(image, 1) + u64(y) * stride(image, 1) + u64(x) * 2); assert p[if blue { 0 } else { 1 }] >= 238; assert p[if blue { 1 } else { 0 }] < 115 } } }
	}
}
fn vd_cases(api VDAPI) {
	create := unsafe { VDCreate(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionCreate'))) }
	accept := unsafe { VDAccept(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionCanAcceptFormatDescription'))) }
	decode := unsafe { VDDecode(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionDecodeFrame'))) }
	wait := unsafe { VDStatus(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionWaitForAsynchronousFrames'))) }
	invalidate := unsafe { VDDrop(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionInvalidate'))) }
	assert accept(0, 0) == 0
	for hevc in [false, true]! { for pixel in [u32(0x42475241), 0x34323076, 0x34323066]! { for reentrant in [false, true]! {
		format := vd_format(api, hevc); attrs := vd_dict(api); vd_put(api, attrs, 'PixelFormatType', i64(pixel)); spec := vd_dict(api); vd_put(api, spec, 'EnableHardwareAcceleratedVideoDecoder', 0)
		mut context := VDContext{api: api, reentrant: reentrant}; wire := [u64(unsafe { voidptr(vd_output) }), u64(&context)]!
		mut session := u64(0xfeed); result := create(0, format, spec, attrs, u64(unsafe { &wire[0] }), &session)
		assert result == 0 && session != 0, 'create native=${api.native} hevc=${hevc} pixel=${pixel.hex()} status=${result}'
		context.session = session; vd_drop(api, attrs); vd_drop(api, spec)
		assert accept(session, format) == 1 && accept(session, 0) == 0
		assert wait(session) == 0
		for blue in [false, true]! {
			sample := vd_sample(api, format, hevc, blue); mut info := u32(0xfeed)
			status := decode(session, sample, 0, 0x1234, &info)
			assert status == 0 && info == 0 && context.image != 0, 'decode native=${api.native} hevc=${hevc} status=${status} info=${info}'
			vd_drop(api, sample)
			vd_pixels(api, context.image, pixel, blue); vd_drop(api, context.image); context.image = 0
			if reentrant { break }
		}
		assert context.calls == if reentrant { 1 } else { 2 }
		if !reentrant { assert wait(session) == 0; invalidate(session); assert accept(session, format) == 0; vd_drop(api, session) }
		vd_drop(api, format)
	} } }
}
fn vd_decode_worker(api VDAPI, session u64, sample u64) {
	mut info := u32(0xfeed)
	assert unsafe { VDDecode(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionDecodeFrame')))(session, sample, 0, 0x1234, &info) } == 0
	assert info == 0
}
fn vd_invalidate_worker(mut context VDContext) {
	C.__atomic_store_n(unsafe { &context.joining }, 1, 5)
	unsafe { VDDrop(voidptr(vd_symbol(context.api, 3, '_VTDecompressionSessionInvalidate')))(context.session) }
	C.__atomic_store_n(unsafe { &context.joined }, 1, 5)
}
fn vd_join(api VDAPI) {
	format := vd_format(api, false); sample := vd_sample(api, format, false, false)
	mut context := VDContext{api: api, gate: true}; wire := [u64(unsafe { voidptr(vd_output) }), u64(&context)]!
	mut session := u64(0)
	assert unsafe { VDCreate(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionCreate')))(0, format, 0, 0, u64(unsafe { &wire[0] }), &session) } == 0
	context.session = session
	worker := spawn vd_decode_worker(api, session, sample)
	for _ in 0 .. 5000 { if C.__atomic_load_n(unsafe { &context.entered }, 5) != 0 { break }; C.usleep(1000) }
	assert context.entered == 1
	joining := spawn vd_invalidate_worker(mut context)
	for _ in 0 .. 5000 { if C.__atomic_load_n(unsafe { &context.joining }, 5) != 0 { break }; C.usleep(1000) }
	assert context.joining == 1
	C.usleep(20000)
	assert C.__atomic_load_n(unsafe { &context.joined }, 5) == 0
	C.__atomic_store_n(unsafe { &context.leave }, 1, 5)
	worker.wait(); joining.wait()
	assert context.joined == 1 && context.calls == 1
	vd_drop(api, session); vd_drop(api, sample); vd_drop(api, format)
	vd_pixels(api, context.image, 0x34323076, false); vd_drop(api, context.image)
}
fn test_video_decode() {
	$if macos {
		mut api := VDAPI{native: true}
		for i, name in ['CoreFoundation', 'CoreMedia', 'CoreVideo', 'VideoToolbox']! { unsafe { api.handles[i] = u64(C.dlopen(&char(('/System/Library/Frameworks/' + name + '.framework/' + name).str), 2)) }; assert api.handles[i] != 0 }
		mut output := u64(0xfeed)
		result := unsafe { VDCreate(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionCreate')))(0, 0, 0, 0, 0, &output) }
		println('IOS-VIDEO-DECODE-NATIVE-ERRORS: null format create=${result} output=${output.hex()} wait-null=' + unsafe { VDStatus(voidptr(vd_symbol(api, 3, '_VTDecompressionSessionWaitForAsynchronousFrames')))(0) }.str())
		vd_cases(api); vd_join(api); println('IOS-VIDEO-DECODE-NATIVE: software H264/HEVC red/blue frames, BGRA/420v/420f, packed callback CMTime ABI, retained images, reentrant invalidation and joined callbacks')
	}
	for _ in 0 .. 2 {
		objc_start(); vd_cases(VDAPI{}); vd_join(VDAPI{})
		assert ios_runtime.live == ios_runtime.framework_objects.len && ios_runtime.objects.len == ios_runtime.framework_objects.len
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-VIDEO-DECODE: real software H264/HEVC frames, synchronous callbacks, timing/source identity, owned BGRA/NV12 output, invalidation and two drained runtimes')
}
