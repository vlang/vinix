// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn C.getpid() i32

type WsStaticImportance = fn (voidptr, voidptr, voidptr, &Value) i32

fn ws_uid_state(e voidptr) voidptr {
 return static_obj(e, c'android/atl/VinixUidImportance', c'state', c'()Landroid/atl/VinixUidImportance;', unsafe { nil })
}

fn ws_uid_query(e voidptr, uid i32) i32 {
 if uid != i32(C.getuid()) { return 1000 }
 return get_int(e, ws_uid_state(e), c'android/atl/VinixUidImportance', c'importance')
}

fn ws_uid_importance(e voidptr, uid i32) i32 {
 args := [Value{ i: uid }]!
 c := cls(e, c'android/atl/VinixUidImportance')
 unsafe {
  m := Member(slot(e, 113))(e, c, c'query', c'(I)I')
  result := WsStaticImportance(slot(e, 131))(e, c, m, &args[0])
  Drop(slot(e, 23))(e, c)
  return result
 }
}

fn ws_memory_state(e voidptr, info voidptr) {
 unsafe {
  if info == nil { throw(e, c'java/lang/NullPointerException', c'process info is null'); return }
  put_int(e, info, c'android/app/ActivityManager$RunningAppProcessInfo', c'pid', i32(C.getpid()))
  put_int(e, info, c'android/app/ActivityManager$RunningAppProcessInfo', c'uid', i32(C.getuid()))
  put_int(e, info, c'android/app/ActivityManager$RunningAppProcessInfo', c'importance', ws_uid_importance(e, i32(C.getuid())))
  loaded := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
  pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
  app := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'applicationInfo', c'Landroid/content/pm/ApplicationInfo;')
  name := get_object(e, app, c'android/content/pm/ApplicationInfo', c'processName', c'Ljava/lang/String;')
  put_object(e, info, c'android/app/ActivityManager$RunningAppProcessInfo', c'processName', c'Ljava/lang/String;', name)
 }
}

fn ws_running_processes(e voidptr) voidptr {
 unsafe {
  if pending(e) { return nil }
  if FramePush(slot(e, 19))(e, 32) != 0 { return nil }
  mut popped := false
  defer { if !popped { FramePop(slot(e, 20))(e, nil) } }
  loaded := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
  if loaded == nil || pending(e) {
   if !pending(e) { throw(e, c'java/lang/IllegalStateException', c'primary application is unavailable') }
   return nil
  }
  pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
  if pkg == nil || pending(e) {
   if !pending(e) { throw(e, c'java/lang/IllegalStateException', c'primary package is unavailable') }
   return nil
  }
  name := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'packageName', c'Ljava/lang/String;')
  if name == nil || pending(e) {
   if !pending(e) { throw(e, c'java/lang/IllegalStateException', c'primary package name is unavailable') }
   return nil
  }
  string_class := cls(e, c'java/lang/String')
  if string_class == nil || pending(e) { return nil }
  // Only this process's loaded package is running. The String is immutable;
  // each query owns a new array, independent of processName and prior results.
  packages := ObjectArrayNew(slot(e, 172))(e, 1, string_class, name)
  if packages == nil || pending(e) { return nil }
  list := new_object(e, c'java/util/ArrayList', c'()V', nil)
  if list == nil || pending(e) { return nil }
  info := new_object(e, c'android/app/ActivityManager$RunningAppProcessInfo', c'()V', nil)
  if info == nil || pending(e) { return nil }
  ws_memory_state(e, info)
  if pending(e) { return nil }
  put_object(e, info, c'android/app/ActivityManager$RunningAppProcessInfo', c'pkgList', c'[Ljava/lang/String;', packages)
  if pending(e) { return nil }
  args := [Value{ l: info }]!
  boolean(e, list, c'java/util/ArrayList', c'add', c'(Ljava/lang/Object;)Z', &args[0])
  if pending(e) { return nil }
  // Pop releases every temporary JNI reference, including the existing
  // memory-state helper's references; the returned list owns info and pkgList.
  popped = true
  return FramePop(slot(e, 20))(e, list)
 }
}

// Called with the VinixUidImportance class monitor held, including the native
// WS lifecycle path. Java references live in the registry and are GC managed.
fn ws_uid_listener(e voidptr, owner voidptr, listener voidptr, cutpoint i32, remove bool) {
 unsafe {
  if listener == nil { throw(e, c'java/lang/NullPointerException', c'listener is null'); return }
  state := ws_uid_state(e)
  list := get_object(e, state, c'android/atl/VinixUidImportance', c'listeners', c'Ljava/util/ArrayList;')
  count := integer(e, list, c'java/util/ArrayList', c'size', c'()I', nil)
  for i := i32(0); i < count; i++ {
   args := [Value{ i: i }]!
   entry := obj(e, list, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', &args[0])
   a := get_object(e, entry, c'android/atl/VinixUidObserver', c'owner', c'Landroid/app/ActivityManager;')
   b := get_object(e, entry, c'android/atl/VinixUidObserver', c'listener', c'Landroid/app/ActivityManager$OnUidImportanceListener;')
   same := Same(slot(e, 24))(e, a, owner) != 0 && Same(slot(e, 24))(e, b, listener) != 0
   Drop(slot(e, 23))(e, a); Drop(slot(e, 23))(e, b); Drop(slot(e, 23))(e, entry)
   if !same { continue }
   if remove { obj(e, list, c'java/util/ArrayList', c'remove', c'(I)Ljava/lang/Object;', &args[0]) }
   else { throw(e, c'java/lang/IllegalArgumentException', c'listener already registered') }
   return
  }
  if remove { throw(e, c'java/lang/IllegalArgumentException', c'listener not registered'); return }
  entry := new_object(e, c'android/atl/VinixUidObserver', c'()V', nil)
  put_object(e, entry, c'android/atl/VinixUidObserver', c'owner', c'Landroid/app/ActivityManager;', owner)
  put_object(e, entry, c'android/atl/VinixUidObserver', c'listener', c'Landroid/app/ActivityManager$OnUidImportanceListener;', listener)
  put_int(e, entry, c'android/atl/VinixUidObserver', c'cutpoint', cutpoint)
  args := [Value{ l: entry }]!
  boolean(e, list, c'java/util/ArrayList', c'add', c'(Ljava/lang/Object;)Z', &args[0])
 }
}

fn ws_uid_update(e voidptr, importance i32) {
 unsafe {
  state := ws_uid_state(e)
  previous := get_int(e, state, c'android/atl/VinixUidImportance', c'importance')
  if previous == importance { return }
  put_int(e, state, c'android/atl/VinixUidImportance', c'importance', importance)
  list := get_object(e, state, c'android/atl/VinixUidImportance', c'listeners', c'Ljava/util/ArrayList;')
  count := integer(e, list, c'java/util/ArrayList', c'size', c'()I', nil)
  for i := i32(0); i < count; i++ {
   index := [Value{ i: i }]!
   entry := obj(e, list, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', &index[0])
   cutoff := get_int(e, entry, c'android/atl/VinixUidObserver', c'cutpoint')
   if (previous <= cutoff) == (importance <= cutoff) { Drop(slot(e, 23))(e, entry); continue }
   listener := get_object(e, entry, c'android/atl/VinixUidObserver', c'listener', c'Landroid/app/ActivityManager$OnUidImportanceListener;')
   task := new_object(e, c'android/atl/VinixUidUpdate', c'()V', nil)
   put_object(e, task, c'android/atl/VinixUidUpdate', c'listener', c'Landroid/app/ActivityManager$OnUidImportanceListener;', listener)
   put_int(e, task, c'android/atl/VinixUidUpdate', c'uid', i32(C.getuid()))
   put_int(e, task, c'android/atl/VinixUidUpdate', c'importance', importance)
   mut executor := get_object(e, state, c'android/atl/VinixUidImportance', c'executor', c'Ljava/util/concurrent/ExecutorService;')
   if executor == nil {
    executor = static_obj(e, c'java/util/concurrent/Executors', c'newSingleThreadExecutor', c'()Ljava/util/concurrent/ExecutorService;', nil)
    put_object(e, state, c'android/atl/VinixUidImportance', c'executor', c'Ljava/util/concurrent/ExecutorService;', executor)
   }
   args := [Value{ l: task }]!
   call(e, executor, c'java/util/concurrent/Executor', c'execute', c'(Ljava/lang/Runnable;)V', &args[0])
   Drop(slot(e, 23))(e, executor); Drop(slot(e, 23))(e, task)
   Drop(slot(e, 23))(e, listener); Drop(slot(e, 23))(e, entry)
   if pending(e) { return }
  }
 }
}

fn ws_uid_notify(e voidptr, task voidptr) {
 listener := get_object(e, task, c'android/atl/VinixUidUpdate', c'listener', c'Landroid/app/ActivityManager$OnUidImportanceListener;')
 args := [Value{ i: get_int(e, task, c'android/atl/VinixUidUpdate', c'uid') }, Value{ i: get_int(e, task, c'android/atl/VinixUidUpdate', c'importance') }]!
 call(e, listener, c'android/app/ActivityManager$OnUidImportanceListener', c'onUidImportance', c'(II)V', unsafe { &args[0] })
}

fn ws_uid_lifecycle(e voidptr, importance i32) {
 if pending(e) { return }
 args := [Value{ i: importance }]!
 static_void(e, c'android/atl/VinixUidImportance', c'update', c'(I)V', unsafe { &args[0] })
}
