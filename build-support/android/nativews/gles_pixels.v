// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlTexImage = fn (u32, i32, i32, i32, i32, i32, u32, u32, voidptr)
type WsGlTexSubImage = fn (u32, i32, i32, i32, i32, i32, u32, u32, voidptr)

// Compute the touched byte range, including pixel-store padding and ES3 skips.
// Reject an unbounded transfer before exposing any Java storage to the driver.
fn ws_gl_pixel_bytes(e voidptr, width i32, height i32, format i32, kind i32, pack bool) i64 {
 unsafe {
  if width <= 0 || height <= 0 { return 0 }
  channels := match format {
   0x1902, 0x1903, 0x1906, 0x1909, 0x8d94, 0x84f9 { i64(1) }
   0x190a, 0x8227, 0x8228 { i64(2) }
   0x1907, 0x8d98 { i64(3) }
   0x1908, 0x80e1, 0x8d99 { i64(4) }
   else { i64(0) }
  }
  bytes := match kind {
   0x1400, 0x1401 { channels }
   0x1402, 0x1403, 0x140b, 0x8d61 { channels * 2 }
   0x1404, 0x1405, 0x1406 { channels * 4 }
   0x8033, 0x8034, 0x8363 { i64(2) }
   0x8035, 0x8367, 0x8368, 0x8c3b, 0x8c3e, 0x84fa { i64(4) }
   0x8dad { i64(8) }
   else { i64(0) }
  }
  if channels == 0 || bytes == 0 { ws_egl_java_error(e, c'unsupported GL pixel storage'); return -1 }
  get_integer := WsGlGetInteger(ws_egl_proc(c'glGetIntegerv'))
  mut alignment := i32(4)
  get_integer(if pack { u32(0x0d05) } else { u32(0x0cf5) }, &alignment)
  mut row_length, mut skip_rows, mut skip_pixels, mut binding := i32(0), i32(0), i32(0), i32(0)
  version := WsGlGetString(ws_egl_proc(c'glGetString'))(0x1f02)
  if version != nil && C.strncmp(version, c'OpenGL ES 3.', 12) == 0 {
   get_integer(if pack { u32(0x0d02) } else { u32(0x0cf2) }, &row_length)
   get_integer(if pack { u32(0x0d03) } else { u32(0x0cf3) }, &skip_rows)
   get_integer(if pack { u32(0x0d04) } else { u32(0x0cf4) }, &skip_pixels)
   get_integer(if pack { u32(0x88ed) } else { u32(0x88ef) }, &binding)
  }
  if binding != 0 { ws_egl_java_error(e, c'Java pixel buffer requires pixel-buffer binding zero'); return -1 }
  if alignment !in [1, 2, 4, 8] || row_length < 0 || skip_rows < 0 || skip_pixels < 0 {
   ws_egl_java_error(e, c'invalid GL pixel-store state'); return -1
  }
  row := i64(if row_length > 0 { row_length } else { width }) * bytes
  stride := (row + alignment - 1) / alignment * alignment
  rows := i64(skip_rows) + height - 1
  // Limit the product before multiplying; dimensions can be arbitrary Java ints.
  if stride > 0x7fffffff || rows > 0x7fffffff / stride {
   ws_egl_java_error(e, c'GL pixel transfer too large'); return -1
  }
  size := rows * stride + (i64(skip_pixels) + width) * bytes
  if size > 0x7fffffff { ws_egl_java_error(e, c'GL pixel transfer too large'); return -1 }
  return size
 }
}

fn ws_gl_read_pixels(e voidptr, x i32, y i32, width i32, height i32, format i32, kind i32, pixels voidptr) {
 unsafe {
  size := ws_gl_pixel_bytes(e, width, height, format, kind, true)
  if size < 0 { return }
  storage := &WsGlNio(C.alloca(sizeof(WsGlNio)))
  opened := ws_gl_nio_open(e, pixels, size, true, storage)
  defer { ws_gl_nio_close(e, storage, opened) }
  if !opened { return }
  WsGlRead(ws_egl_proc(c'glReadPixels'))(x, y, width, height, u32(format), u32(kind), storage.data)
 }
}

fn ws_gl_tex_image(e voidptr, target i32, level i32, internal i32, x i32, y i32, width i32, height i32, border i32, format i32, kind i32, pixels voidptr, subdata bool) {
 unsafe {
  storage := &WsGlNio(C.alloca(sizeof(WsGlNio)))
  C.memset(storage, 0, sizeof(WsGlNio))
  defer { ws_gl_nio_close(e, storage, false) }
  if pixels != nil {
   size := ws_gl_pixel_bytes(e, width, height, format, kind, false)
   if size < 0 || !ws_gl_nio_open(e, pixels, size, false, storage) { return }
  } else if subdata && width > 0 && height > 0 {
   ws_egl_java_error(e, c'null GL texture subdata'); return
  }
  if subdata {
   WsGlTexSubImage(ws_egl_proc(c'glTexSubImage2D'))(u32(target), level, x, y, width, height, u32(format), u32(kind), storage.data)
  } else {
   WsGlTexImage(ws_egl_proc(c'glTexImage2D'))(u32(target), level, internal, width, height, border, u32(format), u32(kind), storage.data)
  }
 }
}
