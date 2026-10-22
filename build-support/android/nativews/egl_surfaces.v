// SPDX-License-Identifier: GPL-2.0-or-later
// An EGL window uses a Mesa pbuffer and posts its pixels to the WS compositor.
@[translated]
module atlframework

struct WsEglWindow {
mut:
	next &WsEglWindow
	display voidptr
	surface voidptr
	window &WsNativeWindow
	bindings i32
	destroyed bool
	width i32
	height i32
	pixels &u8
}
struct WsEglBinding {
mut:
	draw &WsEglWindow
	read &WsEglWindow
}
__global ws_egl_windows &WsEglWindow

// All registry access is serialized. Bound surfaces retain both their native
// window and readback storage until every current thread has released them.
fn ws_egl_find(surface voidptr) &WsEglWindow {
	unsafe {
		mut item := ws_egl_windows
		for item != nil {
			if item.surface == surface { return item }
			item = item.next
		}
		return nil
	}
}
fn ws_egl_window_drop(item &WsEglWindow) {
	unsafe {
		if item == nil { return }
		item.bindings--
		if item.bindings != 0 || !item.destroyed { return }
		mut link := &ws_egl_windows
		for *link != nil && *link != item { link = &(*link).next }
		if *link == item { *link = item.next }
		C.pthread_mutex_lock(&item.window.mutex)
		item.window.egl_connected = false
		C.pthread_mutex_unlock(&item.window.mutex)
		ws_window_release(item.window)
		C.free(item.pixels)
		C.free(item)
	}
}
fn ws_egl_binding_release(pointer voidptr) {
	unsafe {
		if pointer == nil { return }
		WsEglNoArgs(ws_egl_symbol(c'eglReleaseThread'))()
		binding := &WsEglBinding(pointer)
		C.pthread_mutex_lock(&ws_egl_mutex)
		ws_egl_window_drop(binding.draw)
		ws_egl_window_drop(binding.read)
		C.pthread_mutex_unlock(&ws_egl_mutex)
		C.free(binding)
	}
}

@[export: 'eglCreateWindowSurface']
pub fn ws_egl_window(display voidptr, config voidptr, window &WsNativeWindow, attributes &i32) voidptr {
	unsafe {
		if window == nil { ws_egl_error(0x300b); return nil }
		width, height := ws_window_width(window), ws_window_height(window)
		if width <= 0 || height <= 0 || width > 8192 || height > 8192 { ws_egl_error(0x300b); return nil }
		translated := &i32(C.alloca(4096 * sizeof(i32)))
		translated[0] = 0x3057; translated[1] = width
		translated[2] = 0x3056; translated[3] = height
		mut at := 0
		mut out := 4
		if attributes != nil {
			for attributes[at] != 0x3038 {
				if at >= 4088 { ws_egl_error(0x3004); return nil }
				attribute, value := attributes[at], attributes[at + 1]
				if attribute == 0x3086 {
					if value != 0x3084 { ws_egl_error(0x3009); return nil }
				} else if attribute == 0x309d {
					translated[out] = attribute; translated[out + 1] = value; out += 2
				} else { ws_egl_error(0x3004); return nil }
				at += 2
			}
		}
		translated[out] = 0x3038
		C.pthread_mutex_lock(&window.mutex)
		if window.egl_connected || window.locked {
			C.pthread_mutex_unlock(&window.mutex)
			ws_egl_error(0x3002); return nil
		}
		window.egl_connected = true
		C.pthread_mutex_unlock(&window.mutex)
		surface := ws_egl_pbuffer(display, config, translated)
		item := &WsEglWindow(C.calloc(1, sizeof(WsEglWindow)))
		pixels := &u8(C.malloc(usize(width) * usize(height) * 4))
		if surface == nil || item == nil || pixels == nil {
			if surface != nil { WsEglPair(ws_egl_symbol(c'eglDestroySurface'))(display, surface) }
			C.free(item); C.free(pixels)
			C.pthread_mutex_lock(&window.mutex)
			window.egl_connected = false
			C.pthread_mutex_unlock(&window.mutex)
			if surface != nil { ws_egl_error(0x3003) }
			return nil
		}
		ws_window_acquire(window)
		C.pthread_mutex_lock(&ws_egl_mutex)
		*item = WsEglWindow{ next: ws_egl_windows, display: display, surface: surface,
			window: window, width: width, height: height, pixels: pixels }
		ws_egl_windows = item
		C.pthread_mutex_unlock(&ws_egl_mutex)
		return surface
	}
}
@[export: 'eglDestroySurface']
pub fn ws_egl_destroy_surface(display voidptr, surface voidptr) u32 {
	unsafe {
		C.pthread_mutex_lock(&ws_egl_mutex)
		defer { C.pthread_mutex_unlock(&ws_egl_mutex) }
		result := WsEglPair(ws_egl_symbol(c'eglDestroySurface'))(display, surface)
		item := ws_egl_find(surface)
		if result != 0 && item != nil {
			item.destroyed = true
			item.bindings++; ws_egl_window_drop(item)
		}
		return result
	}
}
@[export: 'eglMakeCurrent']
pub fn ws_egl_make_current(display voidptr, draw voidptr, read voidptr, context voidptr) u32 {
	unsafe {
		mut binding := &WsEglBinding(C.pthread_getspecific(ws_egl_binding_key))
		if binding == nil {
			binding = &WsEglBinding(C.calloc(1, sizeof(WsEglBinding)))
			if binding == nil { ws_egl_error(0x3003); return 0 }
			if C.pthread_setspecific(ws_egl_binding_key, binding) != 0 {
				C.free(binding); ws_egl_error(0x3003); return 0
			}
		}
		C.pthread_mutex_lock(&ws_egl_mutex)
		defer { C.pthread_mutex_unlock(&ws_egl_mutex) }
		result := WsEglMakeCurrent(ws_egl_symbol(c'eglMakeCurrent'))(display, draw, read, context)
		if result == 0 { return 0 }
		new_draw, new_read := ws_egl_find(draw), ws_egl_find(read)
		if new_draw != nil { new_draw.bindings++ }
		if new_read != nil { new_read.bindings++ }
		ws_egl_window_drop(binding.draw)
		ws_egl_window_drop(binding.read)
		binding.draw = new_draw; binding.read = new_read
		return result
	}
}
@[export: 'eglTerminate']
pub fn ws_egl_terminate(display voidptr) u32 {
	unsafe {
		C.pthread_mutex_lock(&ws_egl_mutex)
		defer { C.pthread_mutex_unlock(&ws_egl_mutex) }
		result := WsEglDisplayCall(ws_egl_symbol(c'eglTerminate'))(display)
		if result != 0 {
			mut item := ws_egl_windows
			for item != nil {
				next := item.next
				if item.display == display {
					item.destroyed = true
					item.bindings++; ws_egl_window_drop(item)
				}
				item = next
			}
		}
		return result
	}
}
@[export: 'eglReleaseThread']
pub fn ws_egl_release_thread() u32 {
	unsafe {
		result := WsEglNoArgs(ws_egl_symbol(c'eglReleaseThread'))()
		if result != 0 {
			binding := C.pthread_getspecific(ws_egl_binding_key)
			C.pthread_setspecific(ws_egl_binding_key, nil)
			ws_egl_binding_release(binding)
			C.pthread_setspecific(ws_egl_error_key, nil)
		}
		return result
	}
}

type WsGlGetString = fn (u32) &char
type WsGlGetInteger = fn (u32, &i32)
type WsGlBind = fn (u32, u32)
type WsGlStore = fn (u32, i32)
type WsGlRead = fn (i32, i32, i32, i32, u32, u32, voidptr)
type WsGlReadBuffer = fn (u32)

fn ws_egl_present(item &WsEglWindow) bool {
	unsafe {
		get_integer := WsGlGetInteger(ws_egl_proc(c'glGetIntegerv'))
		bind_framebuffer := WsGlBind(ws_egl_proc(c'glBindFramebuffer'))
		bind_buffer := WsGlBind(ws_egl_proc(c'glBindBuffer'))
		store := WsGlStore(ws_egl_proc(c'glPixelStorei'))
		version := WsGlGetString(ws_egl_proc(c'glGetString'))(0x1f02)
		es3 := version != nil && C.strncmp(version, c'OpenGL ES 3.', 12) == 0
		mut framebuffer, mut alignment := i32(0), i32(4)
		mut pack_buffer, mut row_length, mut skip_rows, mut skip_pixels := i32(0), i32(0), i32(0), i32(0)
		mut read_buffer := i32(0x405)
		get_integer(if es3 { u32(0x8caa) } else { u32(0x8ca6) }, &framebuffer)
		bind_framebuffer(if es3 { u32(0x8ca8) } else { u32(0x8d40) }, 0)
		get_integer(0x0d05, &alignment); store(0x0d05, 1)
		if es3 {
			get_integer(0x0c02, &read_buffer)
			WsGlReadBuffer(ws_egl_proc(c'glReadBuffer'))(0x405)
			get_integer(0x88ed, &pack_buffer); bind_buffer(0x88eb, 0)
			get_integer(0x0d02, &row_length); store(0x0d02, 0)
			get_integer(0x0d03, &skip_rows); store(0x0d03, 0)
			get_integer(0x0d04, &skip_pixels); store(0x0d04, 0)
		}
		WsGlRead(ws_egl_proc(c'glReadPixels'))(0, 0, item.width, item.height, 0x1908, 0x1401, item.pixels)
		store(0x0d05, alignment)
		if es3 {
			store(0x0d02, row_length); store(0x0d03, skip_rows); store(0x0d04, skip_pixels)
			bind_buffer(0x88eb, u32(pack_buffer))
			WsGlReadBuffer(ws_egl_proc(c'glReadBuffer'))(u32(read_buffer))
		}
		bind_framebuffer(if es3 { u32(0x8ca8) } else { u32(0x8d40) }, u32(framebuffer))
		buffer := &WsNativeBuffer(C.alloca(sizeof(WsNativeBuffer)))
		C.memset(buffer, 0, sizeof(WsNativeBuffer))
		if ws_window_lock_pixels(item.window, buffer, nil, true) != 0 { ws_egl_error(0x3003); return false }
		// GL has a bottom-left origin. A resized WS view scales this backing
		// surface until the app recreates EGLSurface for its new dimensions.
		for y in 0 .. buffer.height {
			src_y := item.height - 1 - i32(i64(y) * item.height / buffer.height)
			dest := &u8(buffer.bits) + usize(y) * usize(buffer.stride) * 4
			row := item.pixels + usize(src_y) * usize(item.width) * 4
			if buffer.width == item.width { C.memcpy(dest, row, usize(item.width) * 4) }
			else {
				for x in 0 .. buffer.width {
					C.memcpy(dest + x * 4, row + usize(i64(x) * item.width / buffer.width) * 4, 4)
				}
			}
		}
		return ws_window_post(item.window) == 0
	}
}
@[export: 'eglSwapBuffers']
pub fn ws_egl_swap(display voidptr, surface voidptr) u32 {
	unsafe {
		C.pthread_mutex_lock(&ws_egl_mutex)
		defer { C.pthread_mutex_unlock(&ws_egl_mutex) }
		item := ws_egl_find(surface)
		if item != nil && (ws_egl_current_display() != display || ws_egl_current_surface(0x3059) != surface) {
			ws_egl_error(0x300d); return 0
		}
		result := WsEglPair(ws_egl_symbol(c'eglSwapBuffers'))(display, surface)
		if result != 0 && item != nil { return u32(ws_egl_present(item)) }
		return result
	}
}
