// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include <pthread.h>

fn C.pthread_key_create(&u32, voidptr) i32
fn C.pthread_getspecific(u32) voidptr
fn C.pthread_setspecific(u32, voidptr) i32
type WsGraphicsLookup = fn (&char) voidptr

__global ws_egl_error_key u32

fn ws_egl_init(root &char) bool {
	unsafe {
		if C.pthread_key_create(&ws_egl_error_key, nil) != 0 { return false }
		path := &char(C.alloca(8192))
		// These Mesa entrypoint/dispatch libraries depend only on musl. No EGL
		// vendor, X11, GTK, Gallium driver or window-system library is loaded.
		C.snprintf(path, 8192, c'%s/usr/lib/art/native-ws/libvinix-ws-GLESv1_CM.so', root)
		if C.dlopen(path, 2 | 256) == nil { C.puts(C.dlerror()); return false }
		C.snprintf(path, 8192, c'%s/usr/lib/art/native-ws/libvinix-ws-GLESv2.so', root)
		if C.dlopen(path, 2 | 256) == nil { C.puts(C.dlerror()); return false }
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
		return if code == 0 { i32(0x3000) } else { code }
	}
}

@[export: 'eglGetProcAddress']
pub fn ws_egl_proc(name &char) voidptr {
	if name == unsafe { nil } { return unsafe { nil } }
	unsafe {
		lookup := WsGraphicsLookup(C.dlsym(nil, c'vinix_ws_gl_symbol'))
		return if voidptr(lookup) == nil { nil } else { lookup(name) }
	}
}

// The software WS Canvas never makes an EGL context current. These queries
// report that state using the EGL_NO_DISPLAY / EGL_NO_CONTEXT sentinel; they
// neither create a display nor load a window-system graphics provider.
@[export: 'eglGetCurrentDisplay']
pub fn ws_egl_current_display() voidptr { return unsafe { nil } }

@[export: 'eglGetCurrentContext']
pub fn ws_egl_current_context() voidptr { return unsafe { nil } }

@[export: 'eglGetCurrentSurface']
pub fn ws_egl_current_surface(which i32) voidptr {
	if which != 0x3059 && which != 0x305a { ws_egl_error(0x300c) }
	return unsafe { nil }
}

// EGL's native display/context creation is unavailable for the software WS
// Canvas. Return standard failure results, with per-thread error state, rather
// than claiming a usable graphics context. Apps can query and handle this.
@[export: 'eglGetDisplay']
pub fn ws_egl_display(native_display voidptr) voidptr {
	ws_egl_error(0x300c)
	return unsafe { nil }
}

@[export: 'eglInitialize']
pub fn ws_egl_initialize(display voidptr, major &i32, minor &i32) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglChooseConfig']
pub fn ws_egl_choose(display voidptr, attributes &i32, configs &voidptr, capacity i32, count &i32) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglCreateContext']
pub fn ws_egl_context(display voidptr, config voidptr, share voidptr, attributes &i32) voidptr {
	ws_egl_error(0x3008)
	return unsafe { nil }
}

@[export: 'eglCreatePbufferSurface']
pub fn ws_egl_pbuffer(display voidptr, config voidptr, attributes &i32) voidptr {
	ws_egl_error(0x3008)
	return unsafe { nil }
}

@[export: 'eglCreateWindowSurface']
pub fn ws_egl_window(display voidptr, config voidptr, window voidptr, attributes &i32) voidptr {
	ws_egl_error(0x3008)
	return unsafe { nil }
}

@[export: 'eglDestroySurface']
pub fn ws_egl_destroy_surface(display voidptr, surface voidptr) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglDestroyContext']
pub fn ws_egl_destroy_context(display voidptr, context voidptr) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglMakeCurrent']
pub fn ws_egl_make_current(display voidptr, draw voidptr, read voidptr, context voidptr) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglSwapBuffers']
pub fn ws_egl_swap(display voidptr, surface voidptr) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglQuerySurface']
pub fn ws_egl_query_surface(display voidptr, surface voidptr, attribute i32, value &i32) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglSurfaceAttrib']
pub fn ws_egl_surface_attribute(display voidptr, surface voidptr, attribute i32, value i32) u32 {
	ws_egl_error(0x3008)
	return 0
}

@[export: 'eglQueryString']
pub fn ws_egl_query_string(display voidptr, name i32) &char {
	if display == unsafe { nil } && name == 0x3055 { return c'EGL_EXT_client_extensions' }
	ws_egl_error(0x3008)
	return unsafe { nil }
}
