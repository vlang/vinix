// SPDX-License-Identifier: GPL-2.0-or-later
// Mesa surfaceless EGL, with native WS window presentation in egl_surfaces.v.
@[translated]
module atlframework

#include <pthread.h>

fn C.pthread_key_create(&u32, voidptr) i32
fn C.pthread_getspecific(u32) voidptr
fn C.pthread_setspecific(u32, voidptr) i32
fn C.setenv(&char, &char, i32) i32
type WsGraphicsLookup = fn (&char) voidptr
type WsEglGetError = fn () i32
type WsEglGetHandle = fn () voidptr
type WsEglGetDisplay = fn (voidptr) voidptr
type WsEglInitialize = fn (voidptr, &i32, &i32) u32
type WsEglChoose = fn (voidptr, &i32, &voidptr, i32, &i32) u32
type WsEglConfigs = fn (voidptr, &voidptr, i32, &i32) u32
type WsEglAttrib = fn (voidptr, voidptr, i32, &i32) u32
type WsEglContext = fn (voidptr, voidptr, voidptr, &i32) voidptr
type WsEglPbuffer = fn (voidptr, voidptr, &i32) voidptr
type WsEglPair = fn (voidptr, voidptr) u32
type WsEglMakeCurrent = fn (voidptr, voidptr, voidptr, voidptr) u32
type WsEglCurrentSurface = fn (i32) voidptr
type WsEglSurfaceAttrib = fn (voidptr, voidptr, i32, i32) u32
type WsEglDisplayCall = fn (voidptr) u32
type WsEglApi = fn (u32) u32
type WsEglNoArgs = fn () u32
type WsEglString = fn (voidptr, i32) &char
type WsEglInterval = fn (voidptr, i32) u32
type WsEglWaitNative = fn (i32) u32

__global ws_egl_error_key u32
__global ws_egl_binding_key u32
__global ws_egl_provider voidptr
__global ws_egl_mutex C.pthread_mutex_t

fn ws_egl_symbol(name &char) voidptr {
	unsafe { return C.dlsym(ws_egl_provider, name) }
}

fn ws_egl_init(root &char) bool {
	unsafe {
		if C.pthread_key_create(&ws_egl_error_key, nil) != 0
			|| C.pthread_key_create(&ws_egl_binding_key, voidptr(ws_egl_binding_release)) != 0
			|| C.pthread_mutex_init(&ws_egl_mutex, nil) != 0 { return false }
		path := &char(C.alloca(8192))
		for name in [&char(c'libvinix-ws-GLESv1_CM.so'), &char(c'libvinix-ws-GLESv2.so')]! {
			C.snprintf(path, 8192, c'%s/usr/lib/art/native-ws/%s', root, name)
			if C.dlopen(path, 2 | 256) == nil { C.puts(C.dlerror()); return false }
		}
		C.snprintf(path, 8192, c'%s/usr/lib/art/native-ws/dri', root)
		C.setenv(c'LIBGL_DRIVERS_PATH', path, 1)
		C.setenv(c'LIBGL_ALWAYS_SOFTWARE', c'1', 1)
		C.setenv(c'GALLIUM_DRIVER', c'softpipe', 1)
		C.setenv(c'EGL_PLATFORM', c'surfaceless', 1)
		C.snprintf(path, 8192, c'%s/usr/lib/art/native-ws/libvinix-ws-mesa-EGL.so', root)
		ws_egl_provider = C.dlopen(path, 2)
		if ws_egl_provider == nil { C.puts(C.dlerror()); return false }
		return true
	}
}

fn ws_egl_error(code i32) {
	unsafe { C.pthread_setspecific(ws_egl_error_key, voidptr(usize(code))) }
}

@[export: 'eglGetError']
pub fn ws_egl_get_error() i32 {
	unsafe {
		code := i32(usize(C.pthread_getspecific(ws_egl_error_key)))
		C.pthread_setspecific(ws_egl_error_key, nil)
		provider_code := WsEglGetError(ws_egl_symbol(c'eglGetError'))()
		return if code != 0 { code } else { provider_code }
	}
}

@[export: 'eglGetProcAddress']
pub fn ws_egl_proc(name &char) voidptr {
	unsafe {
		if name == nil { return nil }
		// EGL entrypoints must go through the WS adapter, including when obtained
		// dynamically. Mesa's GL entrypoints use its thread-local dispatch table.
		if C.strncmp(name, c'egl', 3) == 0 { return C.dlsym(nil, name) }
		return WsGraphicsLookup(ws_egl_symbol(c'eglGetProcAddress'))(name)
	}
}

@[export: 'eglGetCurrentDisplay']
pub fn ws_egl_current_display() voidptr {
	unsafe { return WsEglGetHandle(ws_egl_symbol(c'eglGetCurrentDisplay'))() }
}
@[export: 'eglGetCurrentContext']
pub fn ws_egl_current_context() voidptr {
	unsafe { return WsEglGetHandle(ws_egl_symbol(c'eglGetCurrentContext'))() }
}
@[export: 'eglGetCurrentSurface']
pub fn ws_egl_current_surface(which i32) voidptr {
	if which != 0x3059 && which != 0x305a { ws_egl_error(0x300c); return unsafe { nil } }
	unsafe { return WsEglCurrentSurface(ws_egl_symbol(c'eglGetCurrentSurface'))(which) }
}
@[export: 'eglGetDisplay']
pub fn ws_egl_display(native_display voidptr) voidptr {
	if native_display != unsafe { nil } { ws_egl_error(0x300c); return unsafe { nil } }
	unsafe { return WsEglGetDisplay(ws_egl_symbol(c'eglGetDisplay'))(native_display) }
}
@[export: 'eglInitialize']
pub fn ws_egl_initialize(display voidptr, major &i32, minor &i32) u32 {
	unsafe { return WsEglInitialize(ws_egl_symbol(c'eglInitialize'))(display, major, minor) }
}
@[export: 'eglChooseConfig']
pub fn ws_egl_choose(display voidptr, attributes &i32, configs &voidptr, capacity i32, count &i32) u32 {
	unsafe {
		translated := &i32(C.alloca(4096 * sizeof(i32)))
		mut at := 0
		mut surface_type := false
		if attributes != nil {
			for attributes[at] != 0x3038 {
				if at >= 4090 { ws_egl_error(0x3004); return 0 }
				translated[at] = attributes[at]
				mut value := attributes[at + 1]
				if attributes[at] == 0x3033 { surface_type = true }
				if attributes[at] == 0x3033 && value != -1 && value & 4 != 0 { value = (value & ~4) | 1 }
				translated[at + 1] = value
				at += 2
			}
		}
		if !surface_type { translated[at] = 0x3033; translated[at + 1] = 1; at += 2 }
		translated[at] = 0x3038
		return WsEglChoose(ws_egl_symbol(c'eglChooseConfig'))(display, translated, configs, capacity, count)
	}
}
@[export: 'eglGetConfigs']
pub fn ws_egl_configs(display voidptr, configs &voidptr, capacity i32, count &i32) u32 {
	unsafe { return WsEglConfigs(ws_egl_symbol(c'eglGetConfigs'))(display, configs, capacity, count) }
}
@[export: 'eglGetConfigAttrib']
pub fn ws_egl_config_attrib(display voidptr, config voidptr, attribute i32, value &i32) u32 {
	unsafe {
		result := WsEglAttrib(ws_egl_symbol(c'eglGetConfigAttrib'))(display, config, attribute, value)
		if result != 0 && attribute == 0x3033 && value != nil && *value & 1 != 0 { *value |= 4 }
		return result
	}
}
@[export: 'eglCreateContext']
pub fn ws_egl_context(display voidptr, config voidptr, share voidptr, attributes &i32) voidptr {
	unsafe { return WsEglContext(ws_egl_symbol(c'eglCreateContext'))(display, config, share, attributes) }
}
@[export: 'eglCreatePbufferSurface']
pub fn ws_egl_pbuffer(display voidptr, config voidptr, attributes &i32) voidptr {
	unsafe { return WsEglPbuffer(ws_egl_symbol(c'eglCreatePbufferSurface'))(display, config, attributes) }
}
@[export: 'eglDestroyContext']
pub fn ws_egl_destroy_context(display voidptr, context voidptr) u32 {
	unsafe { return WsEglPair(ws_egl_symbol(c'eglDestroyContext'))(display, context) }
}
@[export: 'eglQueryContext']
pub fn ws_egl_query_context(display voidptr, context voidptr, attribute i32, value &i32) u32 {
	unsafe { return WsEglAttrib(ws_egl_symbol(c'eglQueryContext'))(display, context, attribute, value) }
}
@[export: 'eglQuerySurface']
pub fn ws_egl_query_surface(display voidptr, surface voidptr, attribute i32, value &i32) u32 {
	unsafe {
		result := WsEglAttrib(ws_egl_symbol(c'eglQuerySurface'))(display, surface, attribute, value)
		C.pthread_mutex_lock(&ws_egl_mutex)
		if result != 0 && attribute == 0x3086 && ws_egl_find(surface) != nil { *value = 0x3084 }
		C.pthread_mutex_unlock(&ws_egl_mutex)
		return result
	}
}
@[export: 'eglSurfaceAttrib']
pub fn ws_egl_surface_attribute(display voidptr, surface voidptr, attribute i32, value i32) u32 {
	unsafe { return WsEglSurfaceAttrib(ws_egl_symbol(c'eglSurfaceAttrib'))(display, surface, attribute, value) }
}
@[export: 'eglBindAPI']
pub fn ws_egl_bind(api u32) u32 {
	if api != 0x30a0 { ws_egl_error(0x300c); return 0 }
	unsafe { return WsEglApi(ws_egl_symbol(c'eglBindAPI'))(api) }
}
@[export: 'eglQueryAPI']
pub fn ws_egl_api() u32 {
	unsafe { return WsEglNoArgs(ws_egl_symbol(c'eglQueryAPI'))() }
}
@[export: 'eglQueryString']
pub fn ws_egl_query_string(display voidptr, name i32) &char {
	unsafe {
		if display == nil && name == 0x3055 { return c'EGL_EXT_client_extensions' }
		result := WsEglString(ws_egl_symbol(c'eglQueryString'))(display, name)
		if result != nil && name == 0x3055 {
			return c'EGL_KHR_create_context EGL_KHR_surfaceless_context EGL_KHR_gl_colorspace'
		}
		return result
	}
}
@[export: 'eglSwapInterval']
pub fn ws_egl_interval(display voidptr, interval i32) u32 {
	unsafe { return WsEglInterval(ws_egl_symbol(c'eglSwapInterval'))(display, interval) }
}
@[export: 'eglWaitGL']
pub fn ws_egl_wait_gl() u32 {
	unsafe { return WsEglNoArgs(ws_egl_symbol(c'eglWaitGL'))() }
}
@[export: 'eglWaitNative']
pub fn ws_egl_wait_native(engine i32) u32 {
	unsafe { return WsEglWaitNative(ws_egl_symbol(c'eglWaitNative'))(engine) }
}
