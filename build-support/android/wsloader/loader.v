// SPDX-License-Identifier: GPL-2.0-or-later
// ART's host JNI loader for the native WS runtime. The packaged Bionic bridge
// links Mesa EGL (and consequently X11) at process startup. Java APKs and ART's
// Linux JNI providers use musl directly and do not need that bridge.
// Bionic NDK libraries are outside this backend's current supported ABI.
@[translated]
module wsloader

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlerror() &char
fn C.dlclose(voidptr) i32
fn C.dladdr(voidptr, voidptr) i32

@[export:'bionic_dlopen']
pub fn open(path &char, flags i32) voidptr { return C.dlopen(path, flags) }

@[export:'bionic_dlsym']
pub fn symbol(handle voidptr, name &char) voidptr { return C.dlsym(handle, name) }

@[export:'bionic_dlerror']
pub fn last_error() &char { return C.dlerror() }

@[export:'bionic_dlclose']
pub fn close(handle voidptr) i32 { return C.dlclose(handle) }

@[export:'bionic_dladdr']
pub fn address(pointer voidptr, info voidptr) i32 { return C.dladdr(pointer, info) }
