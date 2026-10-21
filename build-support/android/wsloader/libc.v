// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module wsloader

#include <dlfcn.h>

type PropertyGet = fn (&char, &char) i32
fn C.dlopen(&char, i32) voidptr
fn C.dlclose(voidptr) i32

// libc_bio may be a local host dependency. Resolve through its own handle,
// rather than assuming its property entrypoint is in RTLD_DEFAULT's scope.
@[export: 'bionic___system_property_get']
pub fn property_get(name &char, value &char) i32 {
	unsafe {
		if name == nil || value == nil { return 0 }
		value[0] = 0
		provider := C.dlopen(c'libc_bio.so.0', 1)
		if provider == nil { return 0 }
		defer { C.dlclose(provider) }
		get := PropertyGet(C.dlsym(provider, c'__system_property_get'))
		return if voidptr(get) == nil { 0 } else { get(name, value) }
	}
}

// Query the same system property as Bionic's android_get_device_api_level.
// Do not claim a newer Android level than the installed compatibility provider.
@[export: 'bionic_android_get_device_api_level']
pub fn device_api_level() i32 {
	unsafe {
		mut value := [92]char{}
		if property_get(c'ro.build.version.sdk', &value[0]) <= 0 { return -1 }
		mut result := i32(0)
		for i := 0; i < 91 && value[i] != 0; i++ {
			if value[i] < `0` || value[i] > `9` { return -1 }
			digit := i32(value[i] - `0`)
			if result > (2147483647 - digit) / 10 { return -1 }
			result = result * 10 + digit
		}
		return if result > 0 { result } else { i32(-1) }
	}
}

// musl exposes no allocator tuning knobs. Bionic documents zero for an
// unrecognized/unsupported option; leave the allocator's policy unchanged.
@[export: 'bionic_mallopt']
pub fn allocator_option(option i32, value i32) i32 {
	return 0
}
