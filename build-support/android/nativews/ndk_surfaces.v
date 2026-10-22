// SPDX-License-Identifier: GPL-2.0-or-later
// NDK CPU surface producer, composed by the native WS Canvas.
@[translated]
module atlframework

struct C.pthread_mutex_t {}
fn C.pthread_mutex_init(&C.pthread_mutex_t, voidptr) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.__atomic_exchange_n(&u32, u32, i32) u32

__global ws_window_pending u32

fn ws_window_bitmap(width i32, height i32) i64 {
	unsafe {
		if width <= 0 || height <= 0 || width > 8192 || height > 8192 { return 0 }
		bitmap := &WsBitmap(C.calloc(1, sizeof(WsBitmap)))
		if bitmap == nil { return 0 }
		pixels := &u8(C.calloc(usize(width) * usize(height), 4))
		if pixels == nil { C.free(bitmap); return 0 }
		*bitmap = WsBitmap{ width: width, height: height, references: 1, rgba: pixels }
		return i64(bitmap)
	}
}

struct WsNativeWindow {
mut:
	mutex      C.pthread_mutex_t
	references i32
	width      i32
	height     i32
	buffer_width i32
	buffer_height i32
	locked     bool
	egl_connected bool
	front      i64
	back       i64
}

struct WsNativeBuffer {
mut:
	width    i32
	height   i32
	stride   i32
	format   i32
	bits     voidptr
	reserved [6]u32
}

struct WsNativeRect {
mut:
	left i32
	top i32
	right i32
	bottom i32
}

fn ws_window_new() &WsNativeWindow {
	unsafe {
		window := &WsNativeWindow(C.calloc(1, sizeof(WsNativeWindow)))
		if window == nil { return nil }
		if C.pthread_mutex_init(&window.mutex, nil) != 0 { C.free(window); return nil }
		window.references = 1
		return window
	}
}

@[export: 'ANativeWindow_acquire']
pub fn ws_window_acquire(window &WsNativeWindow) {
	if window != unsafe { nil } { C.__atomic_add_fetch(&window.references, 1, 5) }
}

@[export: 'ANativeWindow_release']
pub fn ws_window_release(window &WsNativeWindow) {
	unsafe {
		if window == nil || C.__atomic_sub_fetch(&window.references, 1, 5) != 0 { return }
		ws_bitmap_unref(window.front)
		ws_bitmap_unref(window.back)
		C.pthread_mutex_destroy(&window.mutex)
		C.free(window)
	}
}

@[export: 'ANativeWindow_fromSurface']
pub fn ws_window_from_surface(e voidptr, surface voidptr) &WsNativeWindow {
	unsafe {
		if e == nil || surface == nil || pending(e) { return nil }
		if !instance_of(e, surface, c'android/view/Surface') { return nil }
		view := &WsView(get_long(e, surface, c'android/view/Surface', c'widget'))
		if pending(e) || view == nil || view.kind != 10 { return nil }
		ws_window_acquire(view.window)
		return view.window
	}
}

@[export: 'ANativeWindow_getWidth']
pub fn ws_window_width(window &WsNativeWindow) i32 {
	if window == unsafe { nil } { return -22 }
	C.pthread_mutex_lock(&window.mutex)
	defer { C.pthread_mutex_unlock(&window.mutex) }
	return if window.buffer_width > 0 { window.buffer_width } else { window.width }
}

@[export: 'ANativeWindow_getHeight']
pub fn ws_window_height(window &WsNativeWindow) i32 {
	if window == unsafe { nil } { return -22 }
	C.pthread_mutex_lock(&window.mutex)
	defer { C.pthread_mutex_unlock(&window.mutex) }
	return if window.buffer_height > 0 { window.buffer_height } else { window.height }
}

@[export: 'ANativeWindow_getFormat']
pub fn ws_window_format(window &WsNativeWindow) i32 {
	return if window == unsafe { nil } { i32(-22) } else { i32(1) }
}

@[export: 'ANativeWindow_getBuffersDataSpace']
pub fn ws_window_dataspace(window &WsNativeWindow) i32 {
	return if window == unsafe { nil } { i32(-22) } else { i32(0) }
}

@[export: 'ANativeWindow_setBuffersGeometry']
pub fn ws_window_geometry(window &WsNativeWindow, width i32, height i32, format i32) i32 {
	if window == unsafe { nil } || width < 0 || height < 0 || width > 8192 || height > 8192
		|| (width == 0) != (height == 0) || (format != 0 && format != 1) { return -22 }
	C.pthread_mutex_lock(&window.mutex)
	defer { C.pthread_mutex_unlock(&window.mutex) }
	if window.locked { return -16 }
	unsafe { window.buffer_width = width; window.buffer_height = height }
	return 0
}

@[export: 'ANativeWindow_lock']
pub fn ws_window_lock(window &WsNativeWindow, buffer &WsNativeBuffer, dirty &WsNativeRect) i32 {
	return ws_window_lock_pixels(window, buffer, dirty, false)
}

fn ws_window_lock_pixels(window &WsNativeWindow, buffer &WsNativeBuffer, dirty &WsNativeRect, egl bool) i32 {
	if window == unsafe { nil } || buffer == unsafe { nil } { return -22 }
	C.pthread_mutex_lock(&window.mutex)
	defer { C.pthread_mutex_unlock(&window.mutex) }
	unsafe {
		if window.locked || (window.egl_connected && !egl) { return -16 }
		width := if window.buffer_width > 0 { window.buffer_width } else { window.width }
		height := if window.buffer_height > 0 { window.buffer_height } else { window.height }
		if width <= 0 || height <= 0 { return -22 }
		if window.back == 0 || (&WsBitmap(window.back)).width != width || (&WsBitmap(window.back)).height != height {
			ws_bitmap_unref(window.back)
			window.back = ws_window_bitmap(width, height)
			if window.back == 0 { return -12 }
		}
		window.locked = true
		bitmap := &WsBitmap(window.back)
		*buffer = WsNativeBuffer{ width: width, height: height, stride: width, format: 1, bits: bitmap.rgba }
		// Always invalidate the full buffer: the caller must repaint all pixels.
		if dirty != nil { *dirty = WsNativeRect{ right: width, bottom: height } }
		return 0
	}
}

@[export: 'ANativeWindow_unlockAndPost']
pub fn ws_window_post(window &WsNativeWindow) i32 {
	if window == unsafe { nil } { return -22 }
	C.pthread_mutex_lock(&window.mutex)
	defer { C.pthread_mutex_unlock(&window.mutex) }
	unsafe {
		if !window.locked { return -22 }
		previous := window.front
		window.front = window.back
		window.back = previous
		window.locked = false
	}
	C.__atomic_store_n(&ws_window_pending, 1, 5)
	return 0
}

fn ws_surface_new() i64 {
	unsafe {
		pointer := ws_view_new(10)
		view := &WsView(pointer)
		view.window = ws_window_new()
		return pointer
	}
}

fn ws_surface_layout(e voidptr, object voidptr, width i32, height i32) {
	unsafe {
		window := ws_view(e, object).window
		if window == nil { return }
		C.pthread_mutex_lock(&window.mutex)
		created := window.width == 0 || window.height == 0
		changed := window.width != width || window.height != height
		window.width = width
		window.height = height
		C.pthread_mutex_unlock(&window.mutex)
		if width <= 0 || height <= 0 { return }
		if C.getenv(c'VINIX_ANDROID_TRACE_TREE') != nil && (created || changed) {
			callbacks := get_object(e, object, c'android/view/SurfaceView', c'mCallbacks', c'Ljava/util/ArrayList;')
			count := integer(e, callbacks, c'java/util/ArrayList', c'size', c'()I', nil)
			C.printf(c'ANDROID-WS-SURFACE created=%d changed=%d size=%dx%d callbacks=%d\n', i32(created), i32(changed), width, height, count)
		}
		if created { call(e, object, c'android/view/SurfaceView', c'surfaceCreated', c'()V', nil) }
		if changed && !pending(e) {
			args := [Value{ i: 1 }, Value{ i: width }, Value{ i: height }]!
			call(e, object, c'android/view/SurfaceView', c'surfaceChanged', c'(III)V', &args[0])
		}
	}
}

fn ws_surface_draw(e voidptr, object voidptr) {
	unsafe {
		window := ws_view(e, object).window
		if window == nil { return }
		C.pthread_mutex_lock(&window.mutex)
		defer { C.pthread_mutex_unlock(&window.mutex) }
		if window.front == 0 { return }
		ws_draw_bitmap(window.front, 0, 0, window.width, window.height)
	}
}
