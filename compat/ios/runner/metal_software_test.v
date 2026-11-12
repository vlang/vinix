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
