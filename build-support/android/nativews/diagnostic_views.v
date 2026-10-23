// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

__global ws_view_add_traces i32

// Opt-in, bounded caller stacks locate the controller that inserts a selected
// view type. Inspect the Java children after insertion without modifying them.
fn ws_trace_view_additions(e voidptr, parent voidptr, widget i64) {
 unsafe {
  selected := C.getenv(c'VINIX_ANDROID_TRACE_VIEW_ADDS')
  if selected == nil || ws_view_add_traces >= 16 || pending(e) { return }
  push_frame(e)
  defer { pop_frame(e) }
  count := integer(e, parent, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
  for i := i32(0); i < count && i < 4096 && !pending(e); i++ {
   push_frame(e)
   args := [Value{ i: i }]!
   child := obj(e, parent, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', &args[0])
   if child == nil || pending(e) { pop_frame(e); break }
   if get_long(e, child, c'android/view/View', c'widget') != widget {
    pop_frame(e)
    continue
   }
   cls := WsObjectClass(slot(e, 31))(e, child)
   name := obj(e, cls, c'java/lang/Class', c'getName', c'()Ljava/lang/String;', nil)
   if name == nil || pending(e) { pop_frame(e); break }
   chars := ws_utf(e, name)
   matches := chars != nil && !pending(e) && C.strcmp(chars, selected) == 0
   if chars != nil { ws_release(e, name, chars) }
   if matches {
    ws_view_add_traces++
    C.printf(c'ANDROID-WS-VIEW-ADD class=%.256s index=%d trace=%d\n', selected, i, ws_view_add_traces)
    worker := static_obj(e, c'java/lang/Thread', c'currentThread', c'()Ljava/lang/Thread;', nil)
    stack := obj(e, worker, c'java/lang/Thread', c'getStackTrace', c'()[Ljava/lang/StackTraceElement;', nil)
    length := if pending(e) { i32(0) } else { ws_array_len(e, stack) }
    for n := i32(0); n < length && n < 40 && !pending(e); n++ {
     push_frame(e)
     frame := WsArrayGet(slot(e, 173))(e, stack, n)
     line := obj(e, frame, c'java/lang/StackTraceElement', c'toString', c'()Ljava/lang/String;', nil)
     text := ws_utf(e, line)
     if text != nil && !pending(e) { C.printf(c'ANDROID-WS-VIEW-CALLER %.1024s\n', text) }
     if text != nil { ws_release(e, line, text) }
     pop_frame(e)
    }
   }
   pop_frame(e)
   break
  }
  // An optional diagnostic must not leave an exception in the application.
  if pending(e) {
   C.puts(c'ANDROID-WS-VIEW-ADD unavailable')
   ExceptionClear(slot(e, 17))(e)
  }
 }
}
