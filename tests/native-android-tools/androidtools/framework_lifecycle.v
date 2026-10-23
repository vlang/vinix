// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// API 29 callbacks drive AndroidX LifecycleRegistry. Keep pre/post dispatch
// outside the app's override; ordinary callbacks run when it calls super.
// Ordering follows AOSP Activity.java, including reverse activity teardown.
fn framework_activity_lifecycle(smali string) ! {
 callback := 'Landroid/app/Application$ActivityLifecycleCallbacks;'
 helper := 'Landroid/app/VinixLifecycle;'
 events := ['Created', 'Started', 'Resumed', 'Paused', 'Stopped', 'SaveInstanceState', 'Destroyed']
 mut names := []string{}
 for event in events {
  names << 'Pre' + event
  names << event
  names << 'Post' + event
 }
 for owner in ['Activity', 'Application'] {
  path := smali + '/android/app/' + owner + '.smali'
  mut text := os.read_file(path)!
  text += '\n.field private vinixLifecycleCallbacks:Ljava/util/concurrent/CopyOnWriteArrayList;\n'
  for operation in ['register', 'unregister'] {
   body := if operation == 'register' {
    'if-nez v0, :ready\nnew-instance v0, Ljava/util/concurrent/CopyOnWriteArrayList;\ninvoke-direct {v0}, Ljava/util/concurrent/CopyOnWriteArrayList;-><init>()V\niput-object v0, p0, Landroid/app/' + owner + ';->vinixLifecycleCallbacks:Ljava/util/concurrent/CopyOnWriteArrayList;\n:ready\ninvoke-virtual {v0, p1}, Ljava/util/concurrent/CopyOnWriteArrayList;->add(Ljava/lang/Object;)Z\n'
   } else {
    'if-eqz v0, :done\ninvoke-virtual {v0, p1}, Ljava/util/concurrent/CopyOnWriteArrayList;->remove(Ljava/lang/Object;)Z\n:done\n'
   }
   signature := operation + 'ActivityLifecycleCallbacks(' + callback + ')V'
   text = framework_replace_method(text, signature, '.method public synchronized ' + signature + '\n.locals 1\niget-object v0, p0, Landroid/app/' + owner + ';->vinixLifecycleCallbacks:Ljava/util/concurrent/CopyOnWriteArrayList;\n' + body + 'return-void\n.end method')!
  }
  text += '\n.method public vinixLifecycleSnapshot()[Ljava/lang/Object;\n.locals 1\niget-object v0, p0, Landroid/app/' + owner + ';->vinixLifecycleCallbacks:Ljava/util/concurrent/CopyOnWriteArrayList;\nif-eqz v0, :empty\ninvoke-virtual {v0}, Ljava/util/concurrent/CopyOnWriteArrayList;->toArray()[Ljava/lang/Object;\nmove-result-object v0\nreturn-object v0\n:empty\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
  if owner == 'Activity' {
   for index, event in events {
    suffix := if event in ['Created', 'SaveInstanceState'] { '(Landroid/os/Bundle;)V' } else { '()V' }
    method_name := match event { 'Created' { 'Create' } 'Started' { 'Start' } 'Resumed' { 'Resume' } 'Paused' { 'Pause' } 'Stopped' { 'Stop' } 'Destroyed' { 'Destroy' } else { event } }
    original := '.method protected on' + method_name + suffix
    if text.count(original) != 1 { return error('unexpected ATL lifecycle method: ' + original) }
    text = text.replace(original, '.method public vinixLifecycleOn' + method_name + suffix)
    bundle := if event in ['Created', 'SaveInstanceState'] { 'p1' } else { 'v1' }
    args := if bundle == 'p1' { 'p0, p1' } else { 'p0' }
    null_bundle := if bundle == 'v1' { 'const/4 v1, 0x0\n' } else { '' }
    text += '\n.method protected on' + method_name + suffix + '\n.locals 2\n' +
     'invoke-virtual {' + args + '}, Landroid/app/Activity;->vinixLifecycleOn' + method_name + suffix + '\n' + null_bundle +
     'const/16 v0, ' + (index * 3 + 1).str() + '\ninvoke-static {p0, v0, ' + bundle + '}, ' + helper + '->dispatch(Landroid/app/Activity;ILandroid/os/Bundle;)V\nreturn-void\n.end method\n'
    text += '\n.method public vinixPerform' + method_name + suffix + '\n.locals 2\n' + null_bundle +
     'const/16 v0, ' + (index * 3).str() + '\ninvoke-static {p0, v0, ' + bundle + '}, ' + helper + '->dispatch(Landroid/app/Activity;ILandroid/os/Bundle;)V\n' +
     'invoke-virtual {' + args + '}, Landroid/app/Activity;->on' + method_name + suffix + '\n' +
     (if event == 'Resumed' { 'invoke-virtual {p0}, Landroid/app/Activity;->onPostResume()V\n' } else { '' }) +
     'const/16 v0, ' + (index * 3 + 2).str() + '\ninvoke-static {p0, v0, ' + bundle + '}, ' + helper + '->dispatch(Landroid/app/Activity;ILandroid/os/Bundle;)V\nreturn-void\n.end method\n'
   }
  }
  os.write_file(path, text)!
 }
 interface_path := smali + '/android/app/Application$ActivityLifecycleCallbacks.smali'
 mut interface_text := os.read_file(interface_path)!
 mut cases := ''
 mut labels := ''
 for index, name in names {
  suffix := if name.ends_with('Created') || name.ends_with('SaveInstanceState') { '(Landroid/app/Activity;Landroid/os/Bundle;)V' } else { '(Landroid/app/Activity;)V' }
  if index % 3 != 1 {
   interface_text += '\n.method public onActivity' + name + suffix + '\n.locals 0\nreturn-void\n.end method\n'
  }
  labels += '    :event_' + index.str() + '\n'
  args := if suffix.contains('Bundle') { 'v1, p1, p3' } else { 'v1, p1' }
  cases += ':event_' + index.str() + '\ninvoke-interface {' + args + '}, ' + callback + '->onActivity' + name + suffix + '\ngoto :next\n'
 }
 os.write_file(interface_path, interface_text)!
 os.write_file(smali + '/android/app/VinixLifecycle.smali', '.class public final ' + helper + '\n.super Ljava/lang/Object;\n' +
  '.method private static notify([Ljava/lang/Object;Landroid/app/Activity;ILandroid/os/Bundle;Z)V\n.locals 3\nif-eqz p0, :done\nconst/4 v0, 0x0\nif-eqz p4, :loop\narray-length v0, p0\nadd-int/lit8 v0, v0, -1\n:loop\nif-ltz v0, :done\narray-length v2, p0\nif-ge v0, v2, :done\naget-object v1, p0, v0\ncheck-cast v1, ' + callback + '\npacked-switch p2, :events\ngoto :next\n' + cases +
  ':next\nif-eqz p4, :forward\nadd-int/lit8 v0, v0, -1\ngoto :loop\n:forward\nadd-int/lit8 v0, v0, 1\ngoto :loop\n:done\nreturn-void\n:events\n.packed-switch 0x0\n' + labels + '.end packed-switch\n.end method\n' +
  '.method public static dispatch(Landroid/app/Activity;ILandroid/os/Bundle;)V\n.locals 8\n' +
  'move-object v1, p0\nmove v2, p1\nmove-object v3, p2\nconst/4 v4, 0x0\nconst/16 v5, 9\nif-lt p1, v5, :up\nconst/4 v4, 0x1\n:up\n' +
  'invoke-virtual {p0}, Landroid/app/Activity;->getApplication()Landroid/app/Application;\nmove-result-object v6\n' +
  'rem-int/lit8 v5, p1, 3\nconst/4 v7, 2\nif-eqz v5, :application_first\nif-eq v5, v7, :activity_first\nif-nez v4, :activity_first\n:application_first\n' +
  'if-eqz v6, :activity_last\ninvoke-virtual {v6}, Landroid/app/Application;->vinixLifecycleSnapshot()[Ljava/lang/Object;\nmove-result-object v0\nconst/4 v7, 0x0\ninvoke-static {v0, v1, v2, v3, v7}, ' + helper + '->notify([Ljava/lang/Object;Landroid/app/Activity;ILandroid/os/Bundle;Z)V\n' +
  ':activity_last\ninvoke-virtual {p0}, Landroid/app/Activity;->vinixLifecycleSnapshot()[Ljava/lang/Object;\nmove-result-object v0\ninvoke-static {v0, v1, v2, v3, v4}, ' + helper + '->notify([Ljava/lang/Object;Landroid/app/Activity;ILandroid/os/Bundle;Z)V\nreturn-void\n' +
  ':activity_first\ninvoke-virtual {p0}, Landroid/app/Activity;->vinixLifecycleSnapshot()[Ljava/lang/Object;\nmove-result-object v0\ninvoke-static {v0, v1, v2, v3, v4}, ' + helper + '->notify([Ljava/lang/Object;Landroid/app/Activity;ILandroid/os/Bundle;Z)V\nif-eqz v6, :done\n' +
  'invoke-virtual {v6}, Landroid/app/Application;->vinixLifecycleSnapshot()[Ljava/lang/Object;\nmove-result-object v0\nconst/4 v4, 0x0\ninvoke-static {v0, v1, v2, v3, v4}, ' + helper + '->notify([Ljava/lang/Object;Landroid/app/Activity;ILandroid/os/Bundle;Z)V\n:done\nreturn-void\n.end method\n')!
}
