// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsGlesBufferData = fn (u32, isize, voidptr, u32)
type WsGlesBufferSubData = fn (u32, isize, isize, voidptr)
type WsGlesDirectAddress = fn (voidptr, voidptr) voidptr
type WsGlesCritical = fn (voidptr, voidptr, &u8) voidptr
type WsGlesReleaseCritical = fn (voidptr, voidptr, voidptr, i32)
type WsGlesDrawElements = fn (u32, i32, u32, voidptr)
type WsGlesVertexPointer = fn (u32, i32, u32, u8, i32, voidptr)

// Only synchronous uploads borrow NIO storage. Heap arrays are unpinned before
// the driver runs; direct buffers stay reachable through the JNI argument.
fn ws_gl_buffer_upload(e voidptr, target i32, offset i32, size i32, source voidptr, usage i32, subdata bool) {
 unsafe {
  storage := &WsGlNio(C.alloca(sizeof(WsGlNio)))
  C.memset(storage, 0, sizeof(WsGlNio))
  defer { ws_gl_nio_close(e, storage, false) }
  if source != nil && size >= 0 {
   if !ws_gl_nio_open(e, source, size, false, storage) { return }
  } else if source == nil && subdata && size > 0 {
   ws_egl_java_error(e, c'null GL subdata'); return
  }
  if subdata {
   WsGlesBufferSubData(ws_egl_proc(c'glBufferSubData'))(u32(target), isize(offset), isize(size), storage.data)
  } else {
   WsGlesBufferData(ws_egl_proc(c'glBufferData'))(u32(target), isize(size), storage.data, u32(usage))
  }
 }
}

// Integer offsets refer to an already bound GL buffer, never Java memory.
fn ws_gl_draw_elements_offset(mode i32, count i32, kind i32, offset i32) {
 unsafe { WsGlesDrawElements(ws_egl_proc(c'glDrawElements'))(u32(mode), count, u32(kind), voidptr(isize(offset))) }
}

fn ws_gl_vertex_pointer_offset(index i32, size i32, kind i32, normalized u8, stride i32, offset i32) {
 unsafe { WsGlesVertexPointer(ws_egl_proc(c'glVertexAttribPointer'))(u32(index), size, u32(kind), normalized, stride, voidptr(isize(offset))) }
}
