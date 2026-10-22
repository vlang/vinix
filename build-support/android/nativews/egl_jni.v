// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsEglObjectArraySet = fn (voidptr, voidptr, i32, voidptr)

fn static_object(e voidptr, class_name &char, name &char, signature &char) voidptr {
	unsafe {
		c := cls(e, class_name)
		if c == nil { return nil }
		defer { Drop(slot(e, 23))(e, c) }
		f := Member(slot(e, 144))(e, c, name, signature)
		return if f == nil { nil } else { ObjectField(slot(e, 145))(e, c, f) }
	}
}

fn ws_egl_java_string(e voidptr, object voidptr, name i32) voidptr {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		if pending(e) { return nil }
		text := ws_egl_query_string(display, name)
		return if text == nil { nil } else { WsNewUtf(slot(e, 167))(e, text) }
	}
}

fn ws_egl_java_terminate(e voidptr, object voidptr) u8 {
	display := ws_egl_handle(e, object, 0)
	if pending(e) { return 0 }
	return u8(ws_egl_terminate(display))
}

fn ws_gl_java_string(e voidptr, name i32) voidptr {
	unsafe {
		text := WsGlGetString(ws_egl_proc(c'glGetString'))(u32(name))
		return if text == nil { nil } else { WsNewUtf(slot(e, 167))(e, text) }
	}
}

fn ws_egl_java_error(e voidptr, message &char) {
	throw(e, c'java/lang/IllegalArgumentException', message)
}
fn ws_egl_handle(e voidptr, object voidptr, kind i32) voidptr {
	unsafe {
		if object == nil { ws_egl_java_error(e, c'null EGL handle'); return nil }
		return match kind {
			0 { voidptr(get_long(e, object, c'javax/microedition/khronos/egl/EGLDisplay', c'native_egl_display')) }
			1 { voidptr(get_long(e, object, c'javax/microedition/khronos/egl/EGLConfig', c'native_egl_config')) }
			2 { voidptr(get_long(e, object, c'javax/microedition/khronos/egl/EGLContext', c'native_egl_context')) }
			else { voidptr(get_long(e, object, c'com/google/android/gles_jni/EGLSurfaceImpl', c'mEGLSurface')) }
		}
	}
}
fn ws_egl_java_handle(e voidptr, pointer voidptr, kind i32) voidptr {
	unsafe {
		class_name := match kind {
			0 { &char(c'javax/microedition/khronos/egl/EGLDisplay') }
			1 { &char(c'javax/microedition/khronos/egl/EGLConfig') }
			2 { &char(c'javax/microedition/khronos/egl/EGLContext') }
			else { &char(c'com/google/android/gles_jni/EGLSurfaceImpl') }
		}
		if pointer == nil && kind != 1 {
			name := if kind == 0 { &char(c'EGL_NO_DISPLAY') } else if kind == 2 { &char(c'EGL_NO_CONTEXT') } else { &char(c'EGL_NO_SURFACE') }
			signature := if kind == 0 { &char(c'Ljavax/microedition/khronos/egl/EGLDisplay;') }
				else if kind == 2 { &char(c'Ljavax/microedition/khronos/egl/EGLContext;') } else { &char(c'Ljavax/microedition/khronos/egl/EGLSurface;') }
			return static_object(e, c'javax/microedition/khronos/egl/EGL10', name, signature)
		}
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{ j: i64(pointer) }
		return new_object(e, class_name, c'(J)V', args)
	}
}
fn ws_egl_java_display(e voidptr, object voidptr) voidptr {
	unsafe {
		default_display := static_object(e, c'javax/microedition/khronos/egl/EGL10', c'EGL_DEFAULT_DISPLAY', c'Ljava/lang/Object;')
		if Same(slot(e, 24))(e, object, default_display) == 0 {
			Drop(slot(e, 23))(e, default_display)
			ws_egl_java_error(e, c'expected EGL_DEFAULT_DISPLAY'); return nil
		}
		Drop(slot(e, 23))(e, default_display)
		return ws_egl_java_handle(e, ws_egl_display(nil), 0)
	}
}
// Own a terminated copy of attribute arrays: never let EGL scan past Java's
// array or hold a moving-GC pointer during rendering.
fn ws_egl_java_attributes(e voidptr, array voidptr) &i32 {
	unsafe {
		if array == nil { return nil }
		length := ArrayLength(slot(e, 171))(e, array)
		if length < 1 || length > 4096 { ws_egl_java_error(e, c'invalid EGL attribute list'); return nil }
		values := &i32(C.malloc(usize(length) * sizeof(i32)))
		if values == nil { throw(e, c'java/lang/OutOfMemoryError', c'EGL attributes'); return nil }
		IntRegion(slot(e, 203))(e, array, 0, length, values)
		for at := 0; at < length; at += 2 {
			if values[at] == 0x3038 { return values }
		}
		C.free(values); ws_egl_java_error(e, c'unterminated EGL attribute list'); return nil
	}
}
fn ws_egl_java_output(e voidptr, array voidptr, minimum i32) bool {
	unsafe {
		if array == nil || ArrayLength(slot(e, 171))(e, array) < minimum {
			ws_egl_java_error(e, c'EGL output array too short'); return false
		}
		return true
	}
}
fn ws_egl_java_initialize(e voidptr, object voidptr, version voidptr) u8 {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		if pending(e) || (version != nil && !ws_egl_java_output(e, version, 2)) { return 0 }
		mut major, mut minor := i32(0), i32(0)
		result := ws_egl_initialize(display, &major, &minor)
		if result != 0 && version != nil {
			values := [major, minor]!
			IntRegion(slot(e, 211))(e, version, 0, 2, &values[0])
		}
		return u8(result)
	}
}
fn ws_egl_java_configs(e voidptr, object voidptr, attributes voidptr, configs voidptr, capacity i32, count voidptr, choose bool) u8 {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		if pending(e) || !ws_egl_java_output(e, count, 1) { return 0 }
		if capacity < 0 || (configs != nil && ArrayLength(slot(e, 171))(e, configs) < capacity) {
			ws_egl_java_error(e, c'invalid EGL config capacity'); return 0
		}
		attrs := ws_egl_java_attributes(e, attributes)
		defer { C.free(attrs) }
		if pending(e) { return 0 }
		values := if configs == nil || capacity == 0 { &voidptr(nil) } else { &voidptr(C.calloc(usize(capacity), sizeof(voidptr))) }
		defer { C.free(values) }
		if configs != nil && capacity > 0 && values == nil { throw(e, c'java/lang/OutOfMemoryError', c'EGL configs'); return 0 }
		mut size := i32(0)
		result := if choose { ws_egl_choose(display, attrs, values, capacity, &size) }
			else { ws_egl_configs(display, values, capacity, &size) }
		if result != 0 {
			IntRegion(slot(e, 211))(e, count, 0, 1, &size)
			if configs != nil {
				for i in 0 .. if size < capacity { size } else { capacity } {
					value := ws_egl_java_handle(e, values[i], 1)
					WsEglObjectArraySet(slot(e, 174))(e, configs, i, value)
					Drop(slot(e, 23))(e, value)
					if pending(e) { return 0 }
				}
			}
		}
		return u8(result)
	}
}
fn ws_egl_java_query(e voidptr, object voidptr, target voidptr, attribute i32, output voidptr, kind i32) u8 {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		handle := ws_egl_handle(e, target, kind)
		if pending(e) || !ws_egl_java_output(e, output, 1) { return 0 }
		mut value := i32(0)
		result := match kind {
			1 { ws_egl_config_attrib(display, handle, attribute, &value) }
			2 { ws_egl_query_context(display, handle, attribute, &value) }
			else { ws_egl_query_surface(display, handle, attribute, &value) }
		}
		if result != 0 { IntRegion(slot(e, 211))(e, output, 0, 1, &value) }
		return u8(result)
	}
}
fn ws_egl_java_create(e voidptr, object voidptr, config_object voidptr, share_object voidptr, attributes voidptr, kind i32) voidptr {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		config := ws_egl_handle(e, config_object, 1)
		attrs := ws_egl_java_attributes(e, attributes)
		defer { C.free(attrs) }
		if pending(e) { return nil }
		if kind == 2 {
			share := ws_egl_handle(e, share_object, 2)
			if pending(e) { return nil }
			return ws_egl_java_handle(e, ws_egl_context(display, config, share, attrs), 2)
		}
		if kind == 0 { return ws_egl_java_handle(e, ws_egl_pbuffer(display, config, attrs), 3) }
		mut surface := share_object
		if instance_of(e, surface, c'android/view/SurfaceView') {
			holder := obj(e, surface, c'android/view/SurfaceView', c'getHolder', c'()Landroid/view/SurfaceHolder;', nil)
			surface = obj(e, holder, c'android/view/SurfaceHolder', c'getSurface', c'()Landroid/view/Surface;', nil)
		} else if instance_of(e, surface, c'android/view/SurfaceHolder') {
			surface = obj(e, surface, c'android/view/SurfaceHolder', c'getSurface', c'()Landroid/view/Surface;', nil)
		}
		if pending(e) { return nil }
		if surface == nil || !instance_of(e, surface, c'android/view/Surface') {
			ws_egl_java_error(e, c'expected Surface, SurfaceView or SurfaceHolder'); return nil
		}
		window := ws_window_from_surface(e, surface)
		result := ws_egl_window(display, config, window, attrs)
		ws_window_release(window)
		return ws_egl_java_handle(e, result, 3)
	}
}
fn ws_egl_java_pair(e voidptr, object voidptr, target voidptr, operation i32) u8 {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		handle := ws_egl_handle(e, target, if operation == 0 { i32(2) } else { i32(3) })
		if pending(e) { return 0 }
		return u8(match operation {
			0 { ws_egl_destroy_context(display, handle) }
			1 { ws_egl_destroy_surface(display, handle) }
			else { ws_egl_swap(display, handle) }
		})
	}
}
fn ws_egl_java_current(e voidptr, object voidptr, draw_object voidptr, read_object voidptr, context_object voidptr) u8 {
	unsafe {
		display := ws_egl_handle(e, object, 0)
		draw := ws_egl_handle(e, draw_object, 3)
		read := ws_egl_handle(e, read_object, 3)
		context := ws_egl_handle(e, context_object, 2)
		if pending(e) { return 0 }
		return u8(ws_egl_make_current(display, draw, read, context))
	}
}
