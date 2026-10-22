// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_activity_manager(smali string) ! {
 path := smali + '/android/app/ActivityManager.smali'
 mut text := os.read_file(path)!
 for signature in ['getUidImportance(I)I', 'getMyMemoryState(Landroid/app/ActivityManager$RunningAppProcessInfo;)V', 'getRunningAppProcesses()Ljava/util/List;'] {
  text = framework_replace_method(text, signature, '.method public ' + if signature.starts_with('getMy') { 'static ' } else { '' } + 'native ' + signature + '\n.end method')!
 }
 for entry in ['addOnUidImportanceListener:add', 'removeOnUidImportanceListener:remove'] {
  parts := entry.split(':')
  suffix := if parts[1] == 'add' { 'I' } else { '' }
  args := if suffix == '' { 'p0, p1' } else { 'p0, p1, p2' }
  signature := parts[0] + '(Landroid/app/ActivityManager$OnUidImportanceListener;' + suffix + ')V'
  text = framework_replace_method(text, signature, '.method public ' + signature + '\n.locals 0\n' +
   'invoke-static {' + args + '}, Landroid/atl/VinixUidImportance;->' + parts[1] + '(Landroid/app/ActivityManager;Landroid/app/ActivityManager$OnUidImportanceListener;' + suffix + ')V\nreturn-void\n.end method')!
 }
 os.write_file(path, text)!
 os.write_file(smali + '/android/app/ActivityManager$OnUidImportanceListener.smali', interface_class('android/app/ActivityManager$OnUidImportanceListener', ['onUidImportance(II)V']))!
 info := smali + '/android/app/ActivityManager$RunningAppProcessInfo.smali'
 mut info_text := os.read_file(info)!
 info_text += '\n.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n'
 for name, value in {'FOREGROUND': 100, 'FOREGROUND_SERVICE': 125, 'VISIBLE': 200, 'PERCEPTIBLE': 230, 'SERVICE': 300, 'CACHED': 400, 'GONE': 1000} {
  info_text += '.field public static final IMPORTANCE_' + name + ':I = ' + value.str() + '\n'
 }
 os.write_file(info, info_text)!
 // One ART VM hosts the foreground APK and its companions under one Unix UID.
 // Keep a single registry across ActivityManager instances, with owner identity
 // so one manager cannot unregister another manager's listener.
 os.write_file(smali + '/android/atl/VinixUidImportance.smali',
  '.class public final Landroid/atl/VinixUidImportance;\n.super Ljava/lang/Object;\n' +
  '.field private static instance:Landroid/atl/VinixUidImportance;\n' +
  '.field public importance:I\n.field public listeners:Ljava/util/ArrayList;\n.field public executor:Ljava/util/concurrent/ExecutorService;\n' +
  '.method private constructor <init>()V\n.locals 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'const/16 v0, 300\niput v0, p0, Landroid/atl/VinixUidImportance;->importance:I\n' +
  'new-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\n' +
  'iput-object v0, p0, Landroid/atl/VinixUidImportance;->listeners:Ljava/util/ArrayList;\nreturn-void\n.end method\n' +
  '.method public static synchronized state()Landroid/atl/VinixUidImportance;\n.locals 1\n' +
  'sget-object v0, Landroid/atl/VinixUidImportance;->instance:Landroid/atl/VinixUidImportance;\nif-nez v0, :ready\n' +
  'new-instance v0, Landroid/atl/VinixUidImportance;\ninvoke-direct {v0}, Landroid/atl/VinixUidImportance;-><init>()V\n' +
  'sput-object v0, Landroid/atl/VinixUidImportance;->instance:Landroid/atl/VinixUidImportance;\n:ready\nreturn-object v0\n.end method\n' +
  '.method public static synchronized native add(Landroid/app/ActivityManager;Landroid/app/ActivityManager$OnUidImportanceListener;I)V\n.end method\n' +
  '.method public static synchronized native remove(Landroid/app/ActivityManager;Landroid/app/ActivityManager$OnUidImportanceListener;)V\n.end method\n' +
  '.method public static synchronized native update(I)V\n.end method\n' +
  '.method public static synchronized native query(I)I\n.end method\n')!
 os.write_file(smali + '/android/atl/VinixUidObserver.smali',
  '.class public final Landroid/atl/VinixUidObserver;\n.super Ljava/lang/Object;\n' +
  '.field public owner:Landroid/app/ActivityManager;\n.field public listener:Landroid/app/ActivityManager$OnUidImportanceListener;\n.field public cutpoint:I\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n')!
 os.write_file(smali + '/android/atl/VinixUidUpdate.smali',
  '.class public final Landroid/atl/VinixUidUpdate;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field public listener:Landroid/app/ActivityManager$OnUidImportanceListener;\n.field public uid:I\n.field public importance:I\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public native run()V\n.end method\n')!
}
