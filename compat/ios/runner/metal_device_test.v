// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <dlfcn.h>
	#include <objc/runtime.h>
	fn C.dlopen(&char, int) voidptr
	fn C.dlsym(voidptr, &char) voidptr
	fn C.dlclose(voidptr) int
	fn C.objc_getProtocol(&char) voidptr
	fn C.sel_registerName(&char) voidptr
}

type MetalDeviceCreate = fn () u64
type MetalDeviceRelease = fn (u64)
type MetalDeviceConforms = fn (u64, u64, u64) u8

fn metal_device_unavailable_worker(address u64) {
	for _ in 0 .. 256 {
		assert unsafe { MetalDeviceCreate(voidptr(address))() } == 0
	}
}

fn test_metal_device() {
	$if macos {
		metal := C.dlopen(c'/System/Library/Frameworks/Metal.framework/Metal', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert metal != unsafe { nil } && objc != unsafe { nil }
		create := C.dlsym(metal, c'MTLCreateSystemDefaultDevice')
		release := C.dlsym(objc, c'objc_release')
		send := C.dlsym(objc, c'objc_msgSend')
		assert create != unsafe { nil } && release != unsafe { nil } && send != unsafe { nil }
		device := unsafe { MetalDeviceCreate(create)() }
		println('IOS-METAL-DEVICE-NATIVE-DEVICE: available=${device != 0}')
		if device != 0 {
			assert unsafe { MetalDeviceConforms(send)(device,
				u64(C.sel_registerName(c'conformsToProtocol:')), u64(C.objc_getProtocol(c'MTLDevice'))) } != 0
			unsafe { MetalDeviceRelease(release)(device) }
		}
		assert C.dlclose(metal) == 0 && C.dlclose(objc) == 0
		println('IOS-METAL-DEVICE-NATIVE: nullable no-argument API, device protocol when available and owned result released PASS')
	}
	for _ in 0 .. 2 {
		objc_start()
		library := '/System/Library/Frameworks/Metal.framework/Metal'
		address := runtime_symbol(library, '_MTLCreateSystemDefaultDevice') or { panic(err) }
		assert address == u64(unsafe { voidptr(metal_create_system_default_device) })
		before := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn metal_device_unavailable_worker(address) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == before
		mut cache := u64(0xfeed)
		assert cv_metal_cache_create(0, 0, 0, 0, &cache) == -6661 && cache == 0xfeed
		for other in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libobjc.A.dylib',
			'/System/Library/Frameworks/Foundation.framework/Foundation',
			'/System/Library/Frameworks/CoreVideo.framework/CoreVideo',
			'/System/Library/Frameworks/OpenGLES.framework/OpenGLES']! {
			if _ := runtime_symbol(other, '_MTLCreateSystemDefaultDevice') { assert false }
		}
		for missing in ['_MTLCreateSystemDefaultDeviceUnknown', '_OBJC_CLASS_$_MTLDevice',
			'_MTLCreateSystemDefaultDeviceWithOptions']! {
			if _ := runtime_symbol(library, missing) { assert false }
		}
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-METAL-DEVICE: scoped no-argument import, nil without a Metal backend, eight workers, invalid cache device and two drained runtimes PASS')
}
