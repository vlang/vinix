// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_atomic_file(smali string) ! {
 mut text := '.class public Landroid/util/AtomicFile;\n.super Ljava/lang/Object;\n'
 for field in ['base', 'temp', 'backup'] {
  text += '.field private ' + field + ':Ljava/io/File;\n'
 }
 text += '.method public constructor <init>(Ljava/io/File;)V\n.locals 0\n' +
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'invoke-direct {p0, p1}, Landroid/util/AtomicFile;->vinixInit(Ljava/io/File;)V\nreturn-void\n.end method\n' +
  '.method private native vinixInit(Ljava/io/File;)V\n.end method\n'
 for signature in ['getBaseFile()Ljava/io/File;', 'startWrite()Ljava/io/FileOutputStream;',
  'finishWrite(Ljava/io/FileOutputStream;)V', 'failWrite(Ljava/io/FileOutputStream;)V',
  'openRead()Ljava/io/FileInputStream;', 'readFully()[B', 'delete()V'] {
  text += '.method public native ' + signature + '\n.end method\n'
 }
 os.write_file(smali + '/android/util/AtomicFile.smali', text)!
}

fn framework_traffic_stats(smali string) ! {
 path := smali + '/android/net/TrafficStats.smali'
 mut text := os.read_file(path)! + '\n.field public static final UNSUPPORTED:I = -1\n' +
  '.field private static tags:Ljava/lang/ThreadLocal;\n' +
  '.method static constructor <clinit>()V\n.locals 1\n' +
  'new-instance v0, Ljava/lang/ThreadLocal;\ninvoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V\n' +
  'sput-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\nreturn-void\n.end method\n'
 text = framework_replace_method(text, 'setThreadStatsTag(I)V',
  '.method public static setThreadStatsTag(I)V\n.locals 2\n' +
  'sget-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\n' +
  'invoke-static {p0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;\nmove-result-object v1\n' +
  'invoke-virtual {v0, v1}, Ljava/lang/ThreadLocal;->set(Ljava/lang/Object;)V\nreturn-void\n.end method')!
 text = framework_replace_method(text, 'clearThreadStatsTag()V',
  '.method public static clearThreadStatsTag()V\n.locals 1\n' +
  'sget-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\n' +
  'invoke-virtual {v0}, Ljava/lang/ThreadLocal;->remove()V\nreturn-void\n.end method')!
 text += '.method public static getThreadStatsTag()I\n.locals 1\n' +
  'sget-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\n' +
  'invoke-virtual {v0}, Ljava/lang/ThreadLocal;->get()Ljava/lang/Object;\nmove-result-object v0\n' +
  'if-nez v0, :tag\nconst/4 v0, -1\nreturn v0\n:tag\ncheck-cast v0, Ljava/lang/Integer;\n' +
  'invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I\nmove-result v0\nreturn v0\n.end method\n'
 // Vinix has no per-UID kernel traffic accounting or privileged UID tagging.
 text += '.method public static clearThreadStatsUid()V\n.locals 0\nreturn-void\n.end method\n'
 for name in ['getUidRxBytes', 'getUidTxBytes'] {
  text += '.method public static ' + name + '(I)J\n.locals 2\nconst-wide/16 v0, -1\nreturn-wide v0\n.end method\n'
 }
 os.write_file(path, text)!
}
