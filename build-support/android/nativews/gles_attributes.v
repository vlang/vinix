// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlesAttributeValues = fn (u32, voidptr)

fn ws_gl_attribute_values(e voidptr, function &char, width i32, index i32, values voidptr, offset i32, buffer bool) {
 unsafe {
  if values == nil { ws_egl_java_error(e, c'null vertex attribute storage'); return }
  if buffer {
   storage := &WsGlNio(C.alloca(sizeof(WsGlNio)))
   defer { ws_gl_nio_close(e, storage, false) }
   if !ws_gl_nio_open(e, values, i64(width) * 4, false, storage) { return }
   WsGlesAttributeValues(ws_egl_proc(function))(u32(index), storage.data)
   return
  }
  length := ArrayLength(slot(e, 171))(e, values)
  if offset < 0 || offset > length || width > length - offset {
   ws_egl_java_error(e, c'vertex attribute array too short'); return
  }
  data := &f32(C.alloca(4 * sizeof(f32)))
  WsFloatRegion(slot(e, 205))(e, values, offset, width, data)
  if !pending(e) { WsGlesAttributeValues(ws_egl_proc(function))(u32(index), data) }
 }
}
