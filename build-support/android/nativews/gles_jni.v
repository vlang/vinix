// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlViewport = fn (i32, i32, i32, i32)

// Fixed-size GLES state queries, plus the format lists whose sizes the
// renderer supplies. Do not pin a moving Java array across a driver call.
fn ws_gl_integer_count(name i32) i32 {
	match name {
		0x0b70, 0x0d3a, 0x846d, 0x846e, 0x825d { return 2 }
		0x0b00, 0x0b66, 0x0ba2, 0x0c10, 0x0c22, 0x0c23, 0x8005 { return 4 }
		0x0ba6, 0x0ba7, 0x0ba8 { return 16 }
		0x92be { return 8 }
		0x86a3, 0x8df8, 0x87ff {
			count_name := if name == 0x86a3 { u32(0x86a2) } else if name == 0x8df8 { u32(0x8df9) } else { u32(0x87fe) }
			mut count := i32(0)
			unsafe { WsGlGetInteger(ws_egl_proc(c'glGetIntegerv'))(count_name, &count) }
			return count
		}
		else { return 1 }
	}
}

fn ws_gl_integer_query(e voidptr, name i32, output voidptr, offset i32, buffer bool) {
	unsafe {
		if output == nil { ws_egl_java_error(e, c'null GL output'); return }
		count := ws_gl_integer_count(name)
		if count < 0 || count > 4096 { ws_egl_java_error(e, c'GL state query too large'); return }
		mut start := offset
		if buffer {
			start = integer(e, output, c'java/nio/Buffer', c'position', c'()I', nil)
			remaining := integer(e, output, c'java/nio/Buffer', c'remaining', c'()I', nil)
			if pending(e) { return }
			if remaining < count { ws_egl_java_error(e, c'GL buffer too short'); return }
			if boolean(e, output, c'java/nio/Buffer', c'isReadOnly', c'()Z', nil) != 0 {
				exception := new_object(e, c'java/nio/ReadOnlyBufferException', c'()V', nil)
				if exception != nil { ExceptionThrow(slot(e, 13))(e, exception) }
				return
			}
			if pending(e) { return }
		} else {
			length := ArrayLength(slot(e, 171))(e, output)
			if start < 0 || start > length || count > length - start {
				ws_egl_java_error(e, c'GL output array too short'); return
			}
		}
		// Reserve at least a matrix for extension state. Known variable lists
		// use the renderer's count; Java only receives the query's own elements.
		values := &i32(C.calloc(usize(if count < 16 { i32(16) } else { count }), sizeof(i32)))
		if values == nil { throw(e, c'java/lang/OutOfMemoryError', c'GL state query'); return }
		defer { C.free(values) }
		args := &Value(C.alloca(2 * sizeof(Value)))
		if buffer {
			for i in 0 .. count {
				args[0] = Value{ i: start + i }
				values[i] = integer(e, output, c'java/nio/IntBuffer', c'get', c'(I)I', args)
				if pending(e) { return }
			}
		} else if count != 0 {
			IntRegion(slot(e, 203))(e, output, start, count, values)
		}
		if pending(e) { return }
		WsGlGetInteger(ws_egl_proc(c'glGetIntegerv'))(u32(name), values)
		if buffer {
			for i in 0 .. count {
				args[0] = Value{ i: start + i }; args[1] = Value{ i: values[i] }
				result := obj(e, output, c'java/nio/IntBuffer', c'put', c'(II)Ljava/nio/IntBuffer;', args)
				Drop(slot(e, 23))(e, result)
				if pending(e) { return }
			}
		} else if count != 0 {
			IntRegion(slot(e, 211))(e, output, start, count, values)
		}
	}
}
