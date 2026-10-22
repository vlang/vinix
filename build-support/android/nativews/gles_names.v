// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlesNames = fn (i32, &u32)

// GL names are copied before entering Mesa: the driver must never retain a
// pointer into ART's moving heap. Absolute NIO access preserves buffer cursors.
fn ws_gl_names(e voidptr, function &char, count i32, names voidptr, offset i32, buffer bool, generate bool) {
 unsafe {
  if names == nil { ws_egl_java_error(e, c'null GL names'); return }
  if count < 0 || count > 16 * 1024 * 1024 { ws_egl_java_error(e, c'invalid GL name count'); return }
  mut start := offset
  if buffer {
   start = integer(e, names, c'java/nio/Buffer', c'position', c'()I', nil)
   remaining := integer(e, names, c'java/nio/Buffer', c'remaining', c'()I', nil)
   if pending(e) { return }
   if remaining < count { ws_egl_java_error(e, c'GL names buffer too short'); return }
   if generate && boolean(e, names, c'java/nio/Buffer', c'isReadOnly', c'()Z', nil) != 0 {
    exception := new_object(e, c'java/nio/ReadOnlyBufferException', c'()V', nil)
    if exception != nil { ExceptionThrow(slot(e, 13))(e, exception) }
    return
   }
  } else {
   length := ArrayLength(slot(e, 171))(e, names)
   if start < 0 || start > length || count > length - start { ws_egl_java_error(e, c'GL names array too short'); return }
  }
  if pending(e) { return }
  values := &i32(C.calloc(usize(if count == 0 { i32(1) } else { count }), sizeof(i32)))
  if values == nil { throw(e, c'java/lang/OutOfMemoryError', c'GL names'); return }
  defer { C.free(values) }
  args := &Value(C.alloca(2 * sizeof(Value)))
  if buffer {
   for i in 0 .. count {
    args[0] = Value{ i: start + i }
    values[i] = integer(e, names, c'java/nio/IntBuffer', c'get', c'(I)I', args)
    if pending(e) { return }
   }
  } else if count != 0 { IntRegion(slot(e, 203))(e, names, start, count, values) }
  if pending(e) { return }
  WsGlesNames(ws_egl_proc(function))(count, &u32(values))
  if !generate { return }
  if buffer {
   for i in 0 .. count {
    args[0] = Value{ i: start + i }; args[1] = Value{ i: values[i] }
    result := obj(e, names, c'java/nio/IntBuffer', c'put', c'(II)Ljava/nio/IntBuffer;', args)
    Drop(slot(e, 23))(e, result)
    if pending(e) { return }
   }
  } else if count != 0 { IntRegion(slot(e, 211))(e, names, start, count, values) }
 }
}
