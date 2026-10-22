// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlesShaderSource = fn (u32, i32, &&char, &i32)
type WsGlesBindLocation = fn (u32, u32, &char)
type WsGlesGetLocation = fn (u32, &char) i32
type WsGlesObjectInteger = fn (u32, u32, &i32)
type WsGlesInfoLog = fn (u32, i32, &i32, &char)

fn ws_gl_shader_source(e voidptr, shader i32, source voidptr) {
	unsafe {
		if source == nil { ws_egl_java_error(e, c'null shader source'); return }
		text := ws_utf(e, source)
		if pending(e) { return }
		WsGlesShaderSource(ws_egl_proc(c'glShaderSource'))(u32(shader), 1, &text, nil)
		ws_release(e, source, text)
	}
}

fn ws_gl_location(e voidptr, program i32, index i32, name voidptr, operation i32) i32 {
	unsafe {
		if name == nil { ws_egl_java_error(e, c'null shader name'); return -1 }
		text := ws_utf(e, name)
		if pending(e) { return -1 }
		defer { ws_release(e, name, text) }
		if operation == 0 {
			WsGlesBindLocation(ws_egl_proc(c'glBindAttribLocation'))(u32(program), u32(index), text)
			return 0
		}
		function := if operation == 1 { &char(c'glGetAttribLocation') } else { &char(c'glGetUniformLocation') }
		return WsGlesGetLocation(ws_egl_proc(function))(u32(program), text)
	}
}

fn ws_gl_object_integer(e voidptr, function &char, object i32, name i32, output voidptr, offset i32) {
	unsafe {
		if output == nil { ws_egl_java_error(e, c'null shader output'); return }
		length := ArrayLength(slot(e, 171))(e, output)
		if offset < 0 || offset >= length { ws_egl_java_error(e, c'shader output too short'); return }
		mut value := i32(0)
		IntRegion(slot(e, 203))(e, output, offset, 1, &value)
		if pending(e) { return }
		WsGlesObjectInteger(ws_egl_proc(function))(u32(object), u32(name), &value)
		IntRegion(slot(e, 211))(e, output, offset, 1, &value)
	}
}

fn ws_gl_info_log(e voidptr, object i32, shader bool) voidptr {
	unsafe {
		query := if shader { &char(c'glGetShaderiv') } else { &char(c'glGetProgramiv') }
		function := if shader { &char(c'glGetShaderInfoLog') } else { &char(c'glGetProgramInfoLog') }
		mut length := i32(0)
		WsGlesObjectInteger(ws_egl_proc(query))(u32(object), 0x8b84, &length)
		if length < 1 { return WsNewUtf(slot(e, 167))(e, c'') }
		if length > 16 * 1024 * 1024 { throw(e, c'java/lang/OutOfMemoryError', c'shader log too large'); return nil }
		text := &char(C.calloc(usize(length), 1))
		if text == nil { throw(e, c'java/lang/OutOfMemoryError', c'shader log'); return nil }
		defer { C.free(text) }
		WsGlesInfoLog(ws_egl_proc(function))(u32(object), length, nil, text)
		return WsNewUtf(slot(e, 167))(e, text)
	}
}
