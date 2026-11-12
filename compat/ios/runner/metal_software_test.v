// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/wait.h>
fn C.waitpid(int, &int, int) int
type SMGet = fn (u64, &char) u64
type SMCreate = fn () u64
type SMBuffer = fn (u64, &char, u64, u64) u64
type SMBytes = fn (u64, &char, u64, u64, u64) u64
type SMCopy = fn (u64, &char, u64, u64, u64, u64, u64)
type SMVoid = fn (u64, &char)
type SMDescriptor = fn (u64, &char, u64, u64, u64, u8) u64
type SMTexture = fn (u64, &char, u64) u64
type SMSet = fn (u64, &char, u64)
type SMPut = fn (u64, &char, SoftwareMetalRegion, u64, u64, u64)
type SMRead = fn (u64, &char, u64, u64, SoftwareMetalRegion, u64)
type SMTextureCopy = fn (u64, &char, u64, u64, u64, SoftwareMetalOrigin, SoftwareMetalSize, u64, u64, u64, SoftwareMetalOrigin)
fn sm_test_texture_copy(encoder u64, source u64, slice u64, level u64, origin SoftwareMetalOrigin, size SoftwareMetalSize, destination u64, target_slice u64, target_level u64, target SoftwareMetalOrigin) {
	unsafe { SMTextureCopy(voidptr(C.ios_objc_msgsend))(encoder, c'copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:', source, slice, level, origin, size, destination, target_slice, target_level, target) }
}
fn test_software_metal_deferred_texture_blits() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format in [u64(10), 30, 80, 81]! {
			pool := objc_pool_push(); device := metal_create_system_default_device(); pixel := sm_pixel_size(format)
			a := sm_test_texture(device, sm_test_descriptor(format, 7, 5, 0)); b := sm_test_texture(device, sm_test_descriptor(format, 9, 6, 0)); c := sm_test_texture(device, sm_test_descriptor(format, 5, 4, 0))
			mut input := [160]u8{}; mut output := [256]u8{}
			for i in 0 .. 160 { input[i] = u8(i * 13 + 7) }
			sm_test_put(a, SoftwareMetalRegion{width: 7, height: 5, depth: 1}, 0, u64(&input[0]), 7 * pixel)
			queue := sm_send(device, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
			origin := SoftwareMetalOrigin{x: 1, y: 1}; target := SoftwareMetalOrigin{x: 3, y: 2}; size := SoftwareMetalSize{width: 3, height: 2, depth: 1}
			sm_test_texture_copy(encoder, a, 0, 0, origin, size, b, 0, 0, target)
			sm_test_texture_copy(encoder, b, 0, 0, target, size, c, 0, 0, origin)
			sm_test_read(b, SoftwareMetalRegion{width: 9, height: 6, depth: 1}, 0, u64(&output[0]), 9 * pixel)
			for i in 0 .. int(54 * pixel) { assert output[i] == 0 }
			// Recording retains resources, but reads their bytes when committed.
			input[0] = 0xff
			sm_test_put(a, SoftwareMetalRegion{x: 1, y: 1, width: 1, height: 1, depth: 1}, 0, u64(&input[0]), 0)
			sm_call(encoder, c'endEncoding'); second := sm_send(command, c'blitCommandEncoder')
			sm_test_texture_copy(second, c, 0, 0, origin, SoftwareMetalSize{width: 3, height: 1, depth: 1}, c, 0, 0, SoftwareMetalOrigin{y: 3})
			sm_call(second, c'endEncoding'); objc_release(a); objc_release(queue); objc_release(device)
			sm_call(command, c'commit'); sm_call(command, c'waitUntilCompleted')
			sm_test_read(b, SoftwareMetalRegion{width: 9, height: 6, depth: 1}, 0, u64(&output[0]), 9 * pixel)
			for y in 0 .. 6 { for x in 0 .. 9 { for byte in 0 .. int(pixel) {
				expected := if y == 2 && x == 3 { input[byte] } else if y >= 2 && y < 4 && x >= 3 && x < 6 { input[((y - 1) * 7 + x - 2) * int(pixel) + byte] } else { u8(0) }
				assert output[(y * 9 + x) * int(pixel) + byte] == expected
			} } }
			sm_test_read(c, SoftwareMetalRegion{width: 5, height: 4, depth: 1}, 0, u64(&output[0]), 5 * pixel)
			for y in 0 .. 4 { for x in 0 .. 5 { for byte in 0 .. int(pixel) {
				copied := (y >= 1 && y < 3 && x >= 1 && x < 4) || (y == 3 && x < 3)
				sx := if y == 3 { x + 1 } else { x }; sy := if y == 3 { 1 } else { y }
				expected := if copied { if sx == 1 && sy == 1 { input[byte] } else { input[(sy * 7 + sx) * int(pixel) + byte] } } else { u8(0) }
				assert output[(y * 5 + x) * int(pixel) + byte] == expected
			} } }
			for mode in 0 .. 10 {
				child := C.fork(); assert child >= 0
				if child == 0 {
					C.close(1); C.close(2)
					d := metal_create_system_default_device(); q := sm_send(d, c'newCommandQueue'); cmd := sm_send(q, c'commandBuffer'); enc := sm_send(cmd, c'blitCommandEncoder')
					src := sm_test_texture(d, sm_test_descriptor(format, 7, 5, 0))
					dst := if mode == 8 { src } else { sm_test_texture(if mode == 7 { metal_create_system_default_device() } else { d }, sm_test_descriptor(if mode == 6 { if format == 10 { u64(30) } else { u64(10) } } else { format }, 7, 5, 0)) }
					if mode == 9 { sm_call(enc, c'endEncoding') }
					sm_test_texture_copy(enc, src, if mode == 0 { u64(1) } else { 0 }, if mode == 1 { u64(1) } else { 0 }, if mode == 2 { SoftwareMetalOrigin{x: ~u64(0)} } else { origin }, if mode == 3 { SoftwareMetalSize{...size, width: 0} } else { size }, dst, if mode == 4 { u64(1) } else { 0 }, if mode == 5 { u64(1) } else { 0 }, origin)
					C._exit(0)
				}
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			}
			objc_release(b); objc_release(c); objc_pool_pop(pool)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-TEXTURE-BLITS: four formats, aggregate/stack argument ABI, deferred dependent copies, different strides, same-texture disjoint copies, retained resources, ten rejection modes and two drained runtimes PASS')
}
fn sm_test_descriptor(format u64, width u64, height u64, mipmapped u8) u64 { return unsafe { SMDescriptor(voidptr(C.ios_objc_msgsend))(ios_runtime.names['MTLTextureDescriptor'], c'texture2DDescriptorWithPixelFormat:width:height:mipmapped:', format, width, height, mipmapped) } }
fn sm_test_texture(device u64, descriptor u64) u64 { return unsafe { SMTexture(voidptr(C.ios_objc_msgsend))(device, c'newTextureWithDescriptor:', descriptor) } }
fn sm_test_set(object u64, selector &char, value u64) { unsafe { SMSet(voidptr(C.ios_objc_msgsend))(object, selector, value) } }
fn sm_test_put(texture u64, region SoftwareMetalRegion, level u64, bytes u64, row u64) { unsafe { SMPut(voidptr(C.ios_objc_msgsend))(texture, c'replaceRegion:mipmapLevel:withBytes:bytesPerRow:', region, level, bytes, row) } }
fn sm_test_read(texture u64, region SoftwareMetalRegion, level u64, bytes u64, row u64) { unsafe { SMRead(voidptr(C.ios_objc_msgsend))(texture, c'getBytes:bytesPerRow:fromRegion:mipmapLevel:', bytes, row, region, level) } }

fn test_software_metal_texture_storage_region_abi_and_lifetimes() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		for format in [u64(10), 30, 80, 81]! {
			pool := objc_pool_push(); device := metal_create_system_default_device()
			assert sm_test_descriptor(format, 7, 5, 1) == 0
			descriptor := sm_test_descriptor(format, 7, 5, 0)
			assert descriptor != 0 && sm_send(descriptor, c'width') == 7
			texture := sm_test_texture(device, descriptor)
			assert texture != 0 && sm_send(texture, c'width') == 7 && sm_send(texture, c'height') == 5 && sm_send(texture, c'pixelFormat') == format && sm_send(texture, c'device') == device
			assert sm_send(texture, c'mipmapLevelCount') == 1 && sm_send(texture, c'textureType') == 2 && sm_send(texture, c'storageMode') == 0
			for selector in [c'setWidth:', c'setStorageMode:', c'setPixelFormat:', c'setUsage:']! {
				key := ctext(u64(selector))
				original := sm_send(descriptor, if key == 'setWidth:' { c'width' } else if key == 'setStorageMode:' { c'storageMode' } else if key == 'setPixelFormat:' { c'pixelFormat' } else { c'usage' })
				sm_test_set(descriptor, selector, if key == 'setWidth:' { u64(0) } else { ~u64(0) })
				assert sm_test_texture(device, descriptor) == 0
				sm_test_set(descriptor, selector, original)
			}
			sm_test_set(descriptor, c'setWidth:', 16385); assert sm_test_texture(device, descriptor) == 0
			sm_test_set(descriptor, c'setWidth:', 16384); sm_test_set(descriptor, c'setHeight:', 16384); assert sm_test_texture(device, descriptor) == 0
			assert sm_send(texture, c'width') == 7 && sm_send(texture, c'height') == 5
			objc_release(device); objc_pool_pop(pool) // Texture owns its snapshot and device.
			pixel := sm_pixel_size(format); row := 7 * pixel + 4
			mut input := [64]u8{}; mut output := [256]u8{}
			for i in 0 .. 64 { input[i] = u8(i * 7 + 3) }
			for i in 0 .. 256 { output[i] = 0xcc }
			full := SoftwareMetalRegion{width: 7, height: 5, depth: 1}
			sm_test_read(texture, full, 0, u64(&output[4]), row)
			for y in 0 .. 5 { for x in 0 .. int(row) { assert output[4 + y * int(row) + x] == if x < int(7 * pixel) { u8(0) } else { u8(0xcc) } } }
			region := SoftwareMetalRegion{x: 2, y: 1, width: 3, height: 2, depth: 1}
			sm_test_put(texture, region, 0, u64(&input[0]), 3 * pixel + 4)
			sm_test_read(texture, full, 0, u64(&output[4]), row)
			for y in 0 .. 5 { for x in 0 .. int(row) {
				expected := if x >= int(7 * pixel) { u8(0xcc) } else if y >= 1 && y < 3 && x >= int(2 * pixel) && x < int(5 * pixel) { input[(y - 1) * int(3 * pixel + 4) + x - int(2 * pixel)] } else { u8(0) }
				assert output[4 + y * int(row) + x] == expected
			} }
			for i in 0 .. 4 { assert output[i] == 0xcc && output[4 + int(row) * 5 + i] == 0xcc }
			one := SoftwareMetalRegion{width: 1, height: 1, depth: 1}
			sm_test_put(texture, one, 0, u64(&input[0]), 0)
			sm_test_read(texture, one, 0, u64(&output[240]), 0)
			for i in 0 .. int(pixel) { assert output[240 + i] == input[i] }
			for mode in 0 .. 9 {
				child := C.fork(); assert child >= 0
				if child == 0 {
					C.close(1); C.close(2)
					bad := match mode { 0 { SoftwareMetalRegion{...region, x: 7} } 1 { SoftwareMetalRegion{...region, y: ~u64(0)} } 2 { SoftwareMetalRegion{...region, depth: 2} } else { region } }
					sm_test_put(texture, bad, if mode == 3 { u64(1) } else { 0 }, if mode == 4 { u64(0) } else if mode == 6 { ~u64(0) } else { u64(unsafe { &input[0] }) }, if mode == 5 { ~u64(0) } else if mode == 7 { u64(1) } else if mode == 8 { if pixel == 1 { u64(0) } else { 3 * pixel + 1 } } else { 3 * pixel + 4 })
					C._exit(0)
				}
				mut status := 0; assert C.waitpid(child, &status, 0) == child && status == 256
			}
			objc_release(texture)
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL-TEXTURES: four formats, 48-byte region ABI, padded subregion uploads/readback, guards, descriptor snapshots, device lifetimes and two drained runtimes PASS')
}
fn sm_send(object u64, selector &char) u64 { return unsafe { SMGet(voidptr(C.ios_objc_msgsend))(object, selector) } }
fn sm_call(object u64, selector &char) { unsafe { SMVoid(voidptr(C.ios_objc_msgsend))(object, selector) } }
fn sm_test_buffer(device u64, length u64, options u64) u64 { return unsafe { SMBuffer(voidptr(C.ios_objc_msgsend))(device, c'newBufferWithLength:options:', length, options) } }
fn sm_test_copy(encoder u64, src u64, a u64, dst u64, b u64, size u64) { unsafe { SMCopy(voidptr(C.ios_objc_msgsend))(encoder, c'copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:', src, a, dst, b, size) } }
fn sm_test_reject(mode int) {
	child := C.fork(); assert child >= 0
	if child == 0 {
		C.close(1); C.close(2)
		device := metal_create_system_default_device(); queue := sm_send(device, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
		a := sm_test_buffer(device, 64, 0); b := sm_test_buffer(device, 64, 0)
		match mode {
			0 { sm_call(command, c'commit') }
			1 { sm_call(command, c'waitUntilCompleted') }
			2 { sm_test_copy(encoder, a, 63, b, 0, 2) }
			3 { sm_test_copy(encoder, a, ~u64(0), b, 0, 1) }
			4 { sm_test_copy(encoder, a, 0, a, 4, 8) }
			5 { sm_call(encoder, c'endEncoding'); sm_test_copy(encoder, a, 0, b, 0, 1) }
			6 { sm_call(encoder, c'endEncoding'); sm_call(encoder, c'endEncoding') }
			7 { sm_call(encoder, c'endEncoding'); sm_call(command, c'commit'); sm_call(command, c'commit') }
			8 { other := metal_create_system_default_device(); x := sm_test_buffer(other, 64, 0); sm_test_copy(encoder, a, 0, x, 0, 1) }
			else { sm_send(command, c'blitCommandEncoder') }
		}
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, &status, 0) == child && status == 256, 'invalid Metal state/range did not reject cleanly'
}
fn sm_test_worker() {
	pool := objc_pool_push()
	device := metal_create_system_default_device(); queue := sm_send(device, c'newCommandQueue')
	a := sm_test_buffer(device, 16, 0); b := sm_test_buffer(device, 16, 0)
	unsafe { *(&u64(sm_send(a, c'contents'))) = 0x123456789abcdef0 }
	command := sm_send(queue, c'commandBuffer'); encoder := sm_send(command, c'blitCommandEncoder')
	sm_test_copy(encoder, a, 0, b, 8, 8); sm_call(encoder, c'endEncoding'); sm_call(command, c'commit')
	assert unsafe { *(&u64(sm_send(b, c'contents') + 8)) } == u64(0x123456789abcdef0)
	objc_release(a); objc_release(b); objc_release(queue); objc_release(device); objc_pool_pop(pool)
}
fn test_software_metal_deferred_blit_abi_lifetimes_and_threads() {
	$if !ios_metal_software ? { return }
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		address := runtime_symbol('/System/Library/Frameworks/Metal.framework/Metal', '_MTLCreateSystemDefaultDevice') or { panic(err) }
		device := unsafe { SMCreate(voidptr(address))() }
		assert device != 0 && sm_send(device, c'maxBufferLength') == software_metal_max_buffer
		assert !objc_responds(device, c'newLibraryWithData:error:') && !objc_responds(device, c'newRenderPipelineStateWithDescriptor:error:')
		assert sm_test_buffer(device, 0, 0) == 0 && sm_test_buffer(device, software_metal_max_buffer + 1, 0) == 0 && sm_test_buffer(device, 16, 16) == 0
		mut bytes := [64]u8{}
		for i in 0 .. 64 { bytes[i] = u8(i ^ 0xa5) }
		a := unsafe { SMBytes(voidptr(C.ios_objc_msgsend))(device, c'newBufferWithBytes:length:options:', u64(&bytes[0]), 64, 0) }
		b := sm_test_buffer(device, 64, 0); c := sm_test_buffer(device, 64, 0)
		queue := sm_send(device, c'newCommandQueue'); command := sm_send(queue, c'commandBuffer')
		assert sm_send(a, c'length') == 64 && sm_send(a, c'device') == device && sm_send(queue, c'device') == device && sm_send(command, c'device') == device && sm_send(command, c'commandQueue') == queue
		assert sm_send(command, c'status') == 0
		encoder := sm_send(command, c'blitCommandEncoder')
		sm_test_copy(encoder, a, 8, b, 16, 32)
		sm_test_copy(encoder, b, 16, c, 0, 32) // Must observe preceding deferred command.
		sm_test_copy(encoder, c, 64, b, 64, 0)
		assert unsafe { *(&u8(sm_send(b, c'contents') + 16)) } == 0
		// Encoding retains resources; the device/queue outlive caller references.
		objc_release(a); objc_release(queue); objc_release(device)
		sm_call(encoder, c'endEncoding')
		second := sm_send(command, c'blitCommandEncoder'); sm_test_copy(second, c, 0, b, 0, 16); sm_call(second, c'endEncoding')
		sm_call(command, c'commit'); sm_call(command, c'waitUntilCompleted')
		assert sm_send(command, c'status') == 4 && sm_send(command, c'error') == 0
		for i in 0 .. 64 {
			actual := unsafe { *(&u8(sm_send(b, c'contents') + u64(i))) }
			expected := if i < 16 { bytes[i + 8] } else if i < 48 { bytes[i - 8] } else { u8(0) }
			assert actual == expected
		}
		for i in 0 .. 32 { assert unsafe { *(&u8(sm_send(c, c'contents') + u64(i))) } == bytes[i + 8] }
		objc_release(b); objc_release(c); objc_pool_pop(pool)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		for mode in 0 .. 10 { sm_test_reject(mode) }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn sm_test_worker() }; workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-SOFTWARE-METAL: Objective-C buffer/queue/command/blit ABI, deferred ordered copies, bounds, retained resources, completion, 10 rejected states, eight workers and two drained runtimes PASS')
}
