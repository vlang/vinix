// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsGlNio {
mut:
 data voidptr
 allocated voidptr
 array voidptr
 offset i32
 size i64
}

// JNI references remain local to the calling native method. Mesa only sees
// stable direct storage or an owned copy, never a pinned ART heap allocation.
fn ws_gl_nio_open(e voidptr, source voidptr, size i64, output bool, storage &WsGlNio) bool {
 unsafe {
  C.memset(storage, 0, sizeof(WsGlNio))
  if source == nil || size < 0 || size > 0x7fffffff {
   ws_egl_java_error(e, c'invalid GL buffer storage'); return false
  }
  position := integer(e, source, c'java/nio/Buffer', c'position', c'()I', nil)
  remaining := integer(e, source, c'java/nio/Buffer', c'remaining', c'()I', nil)
  shift := get_int(e, source, c'java/nio/Buffer', c'_elementSizeShift')
  if pending(e) { return false }
  if shift < 0 || shift > 3 || size > (i64(remaining) << shift) {
   ws_egl_java_error(e, c'GL transfer exceeds buffer remaining'); return false
  }
  if output && boolean(e, source, c'java/nio/Buffer', c'isReadOnly', c'()Z', nil) != 0 {
   exception := new_object(e, c'java/nio/ReadOnlyBufferException', c'()V', nil)
   if exception != nil { ExceptionThrow(slot(e, 13))(e, exception) }
   return false
  }
  if pending(e) { return false }
  storage.size = size
  direct := WsGlesDirectAddress(slot(e, 230))(e, source)
  if direct != nil {
   storage.data = &u8(direct) + (i64(position) << shift)
   return true
  }
  args := &Value(C.alloca(sizeof(Value)))
  args[0] = Value{ l: source }
  storage.array = static_obj(e, c'java/nio/NIOAccess', c'getBaseArray', c'(Ljava/nio/Buffer;)Ljava/lang/Object;', args)
  if storage.array == nil {
   if !pending(e) { ws_egl_java_error(e, c'GL transfer needs accessible buffer storage') }
   return false
  }
  nio := cls(e, c'java/nio/NIOAccess')
  if nio == nil { return false }
  member := Member(slot(e, 113))(e, nio, c'getBaseArrayOffset', c'(Ljava/nio/Buffer;)I')
  if member == nil { Drop(slot(e, 23))(e, nio); return false }
  storage.offset = IntCall(slot(e, 131))(e, nio, member, args)
  Drop(slot(e, 23))(e, nio)
  if pending(e) { return false }
  if storage.offset < 0 { ws_egl_java_error(e, c'invalid GL buffer offset'); return false }
  storage.allocated = C.malloc(usize(if size == 0 { i64(1) } else { size }))
  if storage.allocated == nil { throw(e, c'java/lang/OutOfMemoryError', c'GL transfer'); return false }
  pinned := WsGlesCritical(slot(e, 222))(e, storage.array, nil)
  if pinned == nil { return false }
  C.memcpy(storage.allocated, &u8(pinned) + storage.offset, usize(size))
  WsGlesReleaseCritical(slot(e, 223))(e, storage.array, pinned, 2)
  storage.data = storage.allocated
  return true
 }
}

fn ws_gl_nio_close(e voidptr, storage &WsGlNio, output bool) {
 unsafe {
  if output && storage.data != nil && storage.array != nil && !pending(e) {
   pinned := WsGlesCritical(slot(e, 222))(e, storage.array, nil)
   if pinned != nil {
    C.memcpy(&u8(pinned) + storage.offset, storage.data, usize(storage.size))
    WsGlesReleaseCritical(slot(e, 223))(e, storage.array, pinned, 0)
   }
  }
  if storage.array != nil { Drop(slot(e, 23))(e, storage.array) }
  C.free(storage.allocated)
 }
}
