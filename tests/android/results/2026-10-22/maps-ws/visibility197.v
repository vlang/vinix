@[translated]
module atlframework
__global visibility197_count i32
fn ws_trace_visibility(e voidptr, view voidptr, visibility i32) {
 unsafe {
  selected:=C.getenv(c'VINIX_ANDROID_TRACE_VISIBILITY')
  if selected==nil || visibility197_count>=24 || pending(e) { return }
  push_frame(e)
  defer {pop_frame(e)}
  owner:=WsObjectClass(slot(e,31))(e,view)
  name:=obj(e,owner,c'java/lang/Class',c'getName',c'()Ljava/lang/String;',nil)
  chars:=ws_utf(e,name)
  matches:=chars!=nil && C.strcmp(chars,selected)==0
  if chars!=nil {ws_release(e,name,chars)}
  if !matches {return}
  visibility197_count++
  C.printf(c'ANDROID-WS-VISIBILITY state=%d sample=%d\n',visibility,visibility197_count)
  worker:=static_obj(e,c'java/lang/Thread',c'currentThread',c'()Ljava/lang/Thread;',nil)
  stack:=obj(e,worker,c'java/lang/Thread',c'getStackTrace',c'()[Ljava/lang/StackTraceElement;',nil)
  length:=if pending(e) {i32(0)} else {ws_array_len(e,stack)}
  for n:=i32(0); n<length && n<32 && !pending(e); n++ {
   push_frame(e)
   frame:=WsArrayGet(slot(e,173))(e,stack,n)
   label:=obj(e,frame,c'java/lang/StackTraceElement',c'toString',c'()Ljava/lang/String;',nil)
   text:=ws_utf(e,label)
   if text!=nil {C.printf(c'ANDROID-WS-VISIBILITY-CALLER %.1024s\n',text);ws_release(e,label,text)}
   pop_frame(e)
  }
  if pending(e) {ExceptionClear(slot(e,17))(e)}
 }
}
fn ws_trace_view_label(e voidptr, view voidptr) {
 unsafe {
  native:=ws_view(e,view)
  C.printf(c'ANDROID-WS-VIEW-LABEL id=%x kind=%d text=%.256s\n',integer(e,view,c'android/view/View',c'getId',c'()I',nil),native.kind,native.text)
 }
}
