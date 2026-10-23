// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlesUniformMatrix = fn (i32, i32, u8, voidptr)
type WsGlesUniformVector = fn (i32, i32, voidptr)

fn ws_gl_uniform_apply(function &char, location i32, count i32, transpose u8, data voidptr, matrix bool) {
 unsafe {
  if matrix { WsGlesUniformMatrix(ws_egl_proc(function))(location, count, transpose, data) }
  else { WsGlesUniformVector(ws_egl_proc(function))(location, count, data) }
 }
}

// Mesa consumes uniforms synchronously. Copy Java arrays out of the moving
// heap; NIO storage follows the same cursor and ownership rules as uploads.
fn ws_gl_uniform_matrix(e voidptr, function &char, dimension i32, location i32, count i32, transpose u8, value voidptr, offset i32, buffer bool) {
 ws_gl_uniform_values(e, function, dimension * dimension, location, count, transpose, value, offset, buffer, true, false)
}

fn ws_gl_uniform_vector(e voidptr, function &char, width i32, location i32, count i32, value voidptr, offset i32, buffer bool, integer bool) {
 ws_gl_uniform_values(e, function, width, location, count, 0, value, offset, buffer, false, integer)
}

fn ws_gl_uniform_values(e voidptr, function &char, width i32, location i32, count i32, transpose u8, value voidptr, offset i32, buffer bool, matrix bool, integer bool) {
 unsafe {
  if value == nil || count < 0 { ws_egl_java_error(e, c'invalid uniform storage'); return }
  elements := i64(count) * width
  if elements > 16 * 1024 * 1024 { ws_egl_java_error(e, c'uniform storage too large'); return }
  if buffer {
   mut storage := WsGlNio{}
   defer { ws_gl_nio_close(e, &storage, false) }
   if !ws_gl_nio_open(e, value, elements * 4, false, &storage) { return }
   ws_gl_uniform_apply(function, location, count, transpose, storage.data, matrix)
   return
  }
  length := ArrayLength(slot(e, 171))(e, value)
  if offset < 0 || offset > length || elements > i64(length - offset) {
   ws_egl_java_error(e, c'uniform array too short'); return
  }
  data := C.calloc(usize(if elements == 0 { i64(1) } else { elements }), sizeof(f32))
  if data == nil { throw(e, c'java/lang/OutOfMemoryError', c'uniform'); return }
  defer { C.free(data) }
  if elements != 0 {
   if integer { IntRegion(slot(e, 203))(e, value, offset, i32(elements), &i32(data)) }
   else { WsFloatRegion(slot(e, 205))(e, value, offset, i32(elements), &f32(data)) }
  }
  if pending(e) { return }
  ws_gl_uniform_apply(function, location, count, transpose, data, matrix)
 }
}
