// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_power(smali string) ! {
 path := smali + '/android/os/PowerManager.smali'
 mut text := os.read_file(path)! + '\n.field private vinixThermalListeners:Ljava/util/HashMap;\n'
 for index, name in ['NONE', 'LIGHT', 'MODERATE', 'SEVERE', 'CRITICAL', 'EMERGENCY', 'SHUTDOWN'] {
  text += '.field public static final THERMAL_STATUS_' + name + ':I = ' + index.str() + '\n'
 }
 text = framework_replace_method(text, '<init>()V',
  '.method public constructor <init>()V\n.locals 1\n' +
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, Ljava/util/HashMap;\n' +
  'invoke-direct {v0}, Ljava/util/HashMap;-><init>()V\n' +
  'iput-object v0, p0, Landroid/os/PowerManager;->vinixThermalListeners:Ljava/util/HashMap;\nreturn-void\n.end method')!
 // The guest has no thermal driver, throttling policy or device idle service.
 // NONE describes the current policy; it is not a temperature measurement.
 for signature in ['getCurrentThermalStatus()I', 'getLocationPowerSaveMode()I', 'isDeviceIdleMode()Z', 'isDeviceLightIdleMode()Z'] {
  text = framework_replace_method(text, signature, '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!
 }
 text = framework_replace_method(text, 'isInteractive()Z', '.method public isInteractive()Z\n.locals 1\n' +
  'invoke-virtual {p0}, Landroid/os/PowerManager;->isScreenOn()Z\nmove-result v0\nreturn v0\n.end method')!
 text += '.method private vinixThermalTask(Landroid/os/PowerManager$OnThermalStatusChangedListener;)Ljava/lang/Runnable;\n.locals 2\n' +
  'if-eqz p1, :null\niget-object v0, p0, Landroid/os/PowerManager;->vinixThermalListeners:Ljava/util/HashMap;\n' +
  'invoke-virtual {v0, p1}, Ljava/util/HashMap;->containsKey(Ljava/lang/Object;)Z\nmove-result v1\nif-nez v1, :duplicate\n' +
  'new-instance v1, Landroid/atl/VinixThermalUpdate;\ninvoke-direct {v1, p1}, Landroid/atl/VinixThermalUpdate;-><init>(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V\n' +
  'invoke-virtual {v0, p1, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\nreturn-object v1\n' +
  ':null\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n' +
  ':duplicate\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "thermal listener already registered"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n.end method\n'
 for executor in [false, true] {
  signature := if executor { 'Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;' } else { 'Landroid/os/PowerManager$OnThermalStatusChangedListener;' }
  listener := if executor { 'p2' } else { 'p1' }
  mut body := '.method public synchronized addThermalStatusListener(' + signature + ')V\n.locals 3\n'
  if executor {
   body += 'if-nez p1, :valid\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n:valid\n'
  }
  body += 'invoke-direct {p0, ' + listener + '}, Landroid/os/PowerManager;->vinixThermalTask(Landroid/os/PowerManager$OnThermalStatusChangedListener;)Ljava/lang/Runnable;\nmove-result-object v0\n:submit\n'
  if executor {
   body += 'invoke-interface {p1, v0}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V\n'
  } else {
   body += 'invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\n' +
    'new-instance v2, Landroid/os/Handler;\ninvoke-direct {v2, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V\n' +
    'invoke-virtual {v2, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\nmove-result v1\nif-nez v1, :submitted\n' +
    'new-instance v0, Ljava/util/concurrent/RejectedExecutionException;\ninvoke-direct {v0}, Ljava/util/concurrent/RejectedExecutionException;-><init>()V\nthrow v0\n'
  }
  // Explicit executors can reject work. Remove the registration so retry works.
  body += ':submitted\nreturn-void\n.catchall {:submit .. :submitted} :rejected\n:rejected\nmove-exception v0\n' +
   'iget-object v1, p0, Landroid/os/PowerManager;->vinixThermalListeners:Ljava/util/HashMap;\n' +
   'invoke-virtual {v1, ' + listener + '}, Ljava/util/HashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;\nthrow v0\n.end method'
  text = framework_replace_method(text, 'addThermalStatusListener(' + signature + ')V', body)!
 }
 text = framework_replace_method(text, 'removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V',
  '.method public synchronized removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V\n.locals 2\n' +
  'if-eqz p1, :null\niget-object v0, p0, Landroid/os/PowerManager;->vinixThermalListeners:Ljava/util/HashMap;\n' +
  'invoke-virtual {v0, p1}, Ljava/util/HashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;\nmove-result-object v1\nif-eqz v1, :absent\nreturn-void\n' +
  ':null\nnew-instance v0, Ljava/lang/NullPointerException;\ninvoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n' +
  ':absent\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "thermal listener not registered"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n.end method')!
 os.write_file(path, text)!
 os.write_file(smali + '/android/os/PowerManager$OnThermalStatusChangedListener.smali',
  interface_class('android/os/PowerManager$OnThermalStatusChangedListener', ['onThermalStatusChanged(I)V']))!
 os.write_file(smali + '/android/atl/VinixThermalUpdate.smali',
  '.class public final Landroid/atl/VinixThermalUpdate;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field private listener:Landroid/os/PowerManager$OnThermalStatusChangedListener;\n' +
  '.method public constructor <init>(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'iput-object p1, p0, Landroid/atl/VinixThermalUpdate;->listener:Landroid/os/PowerManager$OnThermalStatusChangedListener;\nreturn-void\n.end method\n' +
  '.method public run()V\n.locals 2\niget-object v0, p0, Landroid/atl/VinixThermalUpdate;->listener:Landroid/os/PowerManager$OnThermalStatusChangedListener;\n' +
  'const/4 v1, 0\ninvoke-interface {v0, v1}, Landroid/os/PowerManager$OnThermalStatusChangedListener;->onThermalStatusChanged(I)V\nreturn-void\n.end method\n')!
}
