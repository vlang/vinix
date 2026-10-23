// Read-only bounded main-queue snapshot for the Maps transition investigation.
@[translated]
module atlframework

type MapsQueueLong = fn (voidptr, voidptr, voidptr) i64

fn ws_maps_queue_snapshot(e voidptr) {
 unsafe {
  if pending(e) { return }
  push_frame(e)
  defer { pop_frame(e) }
  activity_class := WsObjectClass(slot(e,31))(e,ws.activity)
  transitions_field := Member(slot(e,94))(e,activity_class,c'bB',c'Lnge;')
  transitions := if !pending(e) { ObjectField(slot(e,95))(e,ws.activity,transitions_field) } else { nil }
  transitions_class := if transitions != nil && !pending(e) { WsObjectClass(slot(e,31))(e,transitions) } else { nil }
  reference_field := if transitions_class != nil { Member(slot(e,94))(e,transitions_class,c'b',c'Ljava/util/concurrent/atomic/AtomicReference;') } else { nil }
  reference := if reference_field != nil && !pending(e) { ObjectField(slot(e,95))(e,transitions,reference_field) } else { nil }
  future := obj(e,reference,c'java/util/concurrent/atomic/AtomicReference',c'get',c'()Ljava/lang/Object;',nil)
  if !pending(e) && future != nil {
   done := boolean(e,future,c'java/util/concurrent/Future',c'isDone',c'()Z',nil)
   C.printf(c'ANDROID-WS-TRANSITION-FUTURE done=%d\n',done)
   if done != 0 && !pending(e) {
    obj(e,future,c'java/util/concurrent/Future',c'get',c'()Ljava/lang/Object;',nil)
    if pending(e) { C.puts(c'ANDROID-WS-TRANSITION-FUTURE-FAIL'); Check(slot(e,16))(e) }
   }
  }
  if pending(e) { C.puts(c'ANDROID-WS-TRANSITION-FUTURE-DIAGNOSTIC-FAIL'); Check(slot(e,16))(e); ExceptionClear(slot(e,17))(e) }
  looper := static_obj(e,c'android/os/Looper',c'getMainLooper',c'()Landroid/os/Looper;',nil)
  queue := get_object(e,looper,c'android/os/Looper',c'mQueue',c'Landroid/os/MessageQueue;')
  if pending(e) || queue == nil { return }
  if Monitor(slot(e,217))(e,queue) != 0 { return }
  defer { Monitor(slot(e,218))(e,queue) }
  mut message := get_object(e,queue,c'android/os/MessageQueue',c'mMessages',c'Landroid/os/Message;')
  C.printf(c'ANDROID-WS-QUEUE-BEGIN uptime=%ld\n',ws_millis())
  for i := i32(0); i < 64 && message != nil && !pending(e); i++ {
   when := MapsQueueLong(slot(e,101))(e,message,field(e,c'android/os/Message',c'when',c'J'))
   target := get_object(e,message,c'android/os/Message',c'target',c'Landroid/os/Handler;')
   callback := get_object(e,message,c'android/os/Message',c'callback',c'Ljava/lang/Runnable;')
   what := get_int(e,message,c'android/os/Message',c'what')
   C.printf(c'ANDROID-WS-QUEUE index=%d when=%ld what=%d barrier=%d\n',i,when,what,i32(target == nil))
   for entry in [target,callback]! {
    if entry == nil { continue }
    cls := WsObjectClass(slot(e,31))(e,entry)
    name := obj(e,cls,c'java/lang/Class',c'getName',c'()Ljava/lang/String;',nil)
    if pending(e) { break }
    chars := ws_utf(e,name)
    if chars != nil { C.printf(c'ANDROID-WS-QUEUE-CLASS %s\n',chars); ws_release(e,name,chars) }
   }
   message = get_object(e,message,c'android/os/Message',c'next',c'Landroid/os/Message;')
  }
  C.puts(c'ANDROID-WS-QUEUE-END')
  if pending(e) { ExceptionClear(slot(e,17))(e) }
 }
}
