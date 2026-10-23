// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// WS bitmaps have stable, tightly packed RGBA_8888 CPU storage. Upload that
// storage to the calling thread's real GLES context, preserving GL errors and
// pixel-store state. Other bitmap formats are rejected by the bitmap backend.
fn ws_gl_bitmap_image(e voidptr, target i32, level i32, internal i32, object voidptr, kind i32, border i32) i32 {
	unsafe {
		if object == nil { throw(e, c'java/lang/NullPointerException', c'bitmap is null'); return -1 }
		if Monitor(slot(e, 217))(e, object) != 0 { return -1 }
		defer { Monitor(slot(e, 218))(e, object) }
		pointer := ws_bitmap_snapshot(e, object)
		if pointer == 0 || pending(e) { return -1 }
		bitmap := &WsBitmap(pointer)
		format := if internal < 0 { i32(0x1908) } else { internal }
		pixel_type := if kind < 0 { i32(0x1401) } else { kind }
		if format !in [0x1908, 0x8c43] || pixel_type != 0x1401 { return -1 }
		// Validate unpack state before handing CPU memory to Mesa. In particular,
		// a bound PBO must never interpret this host pointer as a buffer offset.
		size := ws_gl_pixel_bytes(e, bitmap.width, bitmap.height, 0x1908, pixel_type, false)
		if size < 0 { return -1 }
		if size > i64(bitmap.width) * bitmap.height * 4 {
			ws_egl_java_error(e, c'GL unpack state exceeds bitmap storage'); return -1
		}
		ws_bitmap_ref(pointer)
		defer { ws_bitmap_unref(pointer) }
		WsGlTexImage(ws_egl_proc(c'glTexImage2D'))(u32(target), level, format, bitmap.width,
			bitmap.height, border, 0x1908, u32(pixel_type), bitmap.rgba)
		return 0
	}
}
