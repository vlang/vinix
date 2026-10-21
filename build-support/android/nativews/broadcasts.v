// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsSameObject = fn (voidptr, voidptr, voidptr) u8

fn ws_broadcast_list(e voidptr) voidptr {
 return static_obj(e, c'android/atl/VinixBroadcast', c'getRegistrations', c'()Ljava/util/concurrent/CopyOnWriteArrayList;', unsafe { nil })
}

fn ws_broadcast_get(e voidptr, entry voidptr, name &char, signature &char) voidptr {
 return get_object(e, entry, c'android/atl/VinixBroadcast', name, signature)
}

fn ws_broadcast_put(e voidptr, entry voidptr, name &char, signature &char, value voidptr) {
 put_object(e, entry, c'android/atl/VinixBroadcast', name, signature, value)
}

fn ws_broadcast_register(e voidptr, context voidptr, receiver voidptr, filter voidptr, handler voidptr, flags i32) voidptr {
 unsafe {
  if flags & 6 == 6 {
   throw(e, c'java/lang/IllegalArgumentException', c'RECEIVER_EXPORTED and RECEIVER_NOT_EXPORTED conflict')
   return nil
  }
  if filter == nil { throw(e, c'java/lang/NullPointerException', c'filter'); return nil }
  // There are no sticky broadcasts from a native system service yet.
  if receiver == nil { return nil }
  mut target := handler
  if target == nil {
   looper := static_obj(e, c'android/os/Looper', c'getMainLooper', c'()Landroid/os/Looper;', nil)
   args := [Value{l: looper}]!
   target = new_object(e, c'android/os/Handler', c'(Landroid/os/Looper;)V', &args[0])
  }
  entry := new_object(e, c'android/atl/VinixBroadcast', c'()V', nil)
  ws_broadcast_put(e, entry, c'receiver', c'Landroid/content/BroadcastReceiver;', receiver)
  ws_broadcast_put(e, entry, c'context', c'Landroid/content/Context;', context)
  ws_broadcast_put(e, entry, c'filter', c'Landroid/content/IntentFilter;', filter)
  ws_broadcast_put(e, entry, c'handler', c'Landroid/os/Handler;', target)
  args := [Value{l: entry}]!
  boolean(e, ws_broadcast_list(e), c'java/util/concurrent/CopyOnWriteArrayList', c'add', c'(Ljava/lang/Object;)Z', &args[0])
  return nil
 }
}

fn ws_broadcast_unregister(e voidptr, receiver voidptr) {
 unsafe {
  list := ws_broadcast_list(e)
  snapshot := obj(e, list, c'java/util/concurrent/CopyOnWriteArrayList', c'toArray', c'()[Ljava/lang/Object;', nil)
  mut removed := false
  for i := i32(0); i < ws_array_len(e, snapshot); i++ {
   entry := WsArrayGet(slot(e, 173))(e, snapshot, i)
   registered := ws_broadcast_get(e, entry, c'receiver', c'Landroid/content/BroadcastReceiver;')
   if WsSameObject(slot(e, 24))(e, receiver, registered) != 0 {
    args := [Value{l: entry}]!
    removed = boolean(e, list, c'java/util/concurrent/CopyOnWriteArrayList', c'remove', c'(Ljava/lang/Object;)Z', &args[0]) != 0 || removed
   }
  }
  if !removed { throw(e, c'java/lang/IllegalArgumentException', c'receiver is not registered') }
 }
}

fn ws_broadcast_send(e voidptr, context voidptr, intent voidptr) {
 unsafe {
  if intent == nil { throw(e, c'java/lang/NullPointerException', c'intent'); return }
  list := ws_broadcast_list(e)
  snapshot := obj(e, list, c'java/util/concurrent/CopyOnWriteArrayList', c'toArray', c'()[Ljava/lang/Object;', nil)
  action := obj(e, intent, c'android/content/Intent', c'getAction', c'()Ljava/lang/String;', nil)
  package := obj(e, intent, c'android/content/Intent', c'getPackage', c'()Ljava/lang/String;', nil)
  if package != nil {
   own := obj(e, context, c'android/content/Context', c'getPackageName', c'()Ljava/lang/String;', nil)
   args := [Value{l: own}]!
   if boolean(e, package, c'java/lang/String', c'equals', c'(Ljava/lang/Object;)Z', &args[0]) == 0 { return }
  }
  for i := i32(0); i < ws_array_len(e, snapshot); i++ {
   entry := WsArrayGet(slot(e, 173))(e, snapshot, i)
   filter := ws_broadcast_get(e, entry, c'filter', c'Landroid/content/IntentFilter;')
   match_args := [Value{l: action}]!
   if boolean(e, filter, c'android/content/IntentFilter', c'matchAction', c'(Ljava/lang/String;)Z', &match_args[0]) == 0 { continue }
   task := new_object(e, c'android/atl/VinixBroadcast', c'()V', nil)
   ws_broadcast_put(e, task, c'receiver', c'Landroid/content/BroadcastReceiver;', ws_broadcast_get(e, entry, c'receiver', c'Landroid/content/BroadcastReceiver;'))
   ws_broadcast_put(e, task, c'context', c'Landroid/content/Context;', ws_broadcast_get(e, entry, c'context', c'Landroid/content/Context;'))
   args := [Value{l: intent}]!
   copy := new_object(e, c'android/content/Intent', c'(Landroid/content/Intent;)V', &args[0])
   ws_broadcast_put(e, task, c'intent', c'Landroid/content/Intent;', copy)
   post := [Value{l: task}]!
   handler := ws_broadcast_get(e, entry, c'handler', c'Landroid/os/Handler;')
   boolean(e, handler, c'android/os/Handler', c'post', c'(Ljava/lang/Runnable;)Z', &post[0])
  }
  app := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
  args := [Value{l: context}, Value{l: intent}]!
  call(e, app, c'android/atl/ATLLoadedApp', c'receiveBroadcast', c'(Landroid/content/Context;Landroid/content/Intent;)V', &args[0])
 }
}

fn ws_broadcast_run(e voidptr, task voidptr) {
 receiver := ws_broadcast_get(e, task, c'receiver', c'Landroid/content/BroadcastReceiver;')
 args := [Value{l: ws_broadcast_get(e, task, c'context', c'Landroid/content/Context;')}, Value{l: ws_broadcast_get(e, task, c'intent', c'Landroid/content/Intent;')}]!
 unsafe { call(e, receiver, c'android/content/BroadcastReceiver', c'onReceive', c'(Landroid/content/Context;Landroid/content/Intent;)V', &args[0]) }
}
