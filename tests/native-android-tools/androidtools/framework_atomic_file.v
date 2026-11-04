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
 os.write_file(path, framework_traffic_stats_uid_source(text)!)!
}

fn traffic_stats_uid_methods(source string) !map[string]string {
 mut result := map[string]string{}
 mut current := []string{}
 mut signature := ''
 for line in source.split_into_lines() {
  trimmed := line.trim_space()
  if trimmed.starts_with('.method ') {
   if signature != '' { return error('unterminated TrafficStats method') }
   signature = trimmed.all_after_last(' ')
   if signature == '' || signature in result { return error('duplicate TrafficStats method') }
   current = [line]
  } else if trimmed == '.end method' {
   if signature == '' { return error('unexpected TrafficStats method end') }
   current << line
   result[signature] = current.join('\n')
   current = []string{}
   signature = ''
  } else if signature != '' {
   current << line
  }
 }
 if signature != '' { return error('unterminated TrafficStats method') }
 return result
}

fn traffic_stats_uid_code(source string) string {
 return source.split_into_lines().map(it.trim_space()).filter(it != '' && !it.starts_with('#')).join('\n')
}

fn traffic_stats_uid_replace(source string, before string, after string) !string {
 if source.count(before) != 1 { return error('one complete TrafficStats method block required') }
 return source.replace(before, after)
}

// Store only the caller thread's requested UID. Socket attribution and per-UID
// kernel counters remain unavailable; no process UID or permission is changed.
// Validate both source and assembled forms before returning any replacement.
pub fn framework_traffic_stats_uid_source(original string) !string {
 lines := original.split_into_lines().map(it.trim_space())
 if lines.filter(it.starts_with('.class ')) != ['.class public Landroid/net/TrafficStats;']
  || lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;'] {
  return error('exact TrafficStats class and superclass required')
 }
 fields := lines.filter(it.starts_with('.field ')).sorted()
 if fields != ['.field private static tags:Ljava/lang/ThreadLocal;',
  '.field public static final UNSUPPORTED:I = -1'].sorted()
  && fields != ['.field private static tags:Ljava/lang/ThreadLocal;',
  '.field public static final UNSUPPORTED:I = -0x1'].sorted() {
  return error('exact original TrafficStats fields required')
 }
 methods := traffic_stats_uid_methods(original)!
 expected := ['<clinit>()V', '<init>()V', 'setThreadStatsTag(I)V', 'clearThreadStatsTag()V',
  'getThreadStatsTag()I', 'clearThreadStatsUid()V', 'getUidRxBytes(I)J', 'getUidTxBytes(I)J']
 if methods.keys().sorted() != expected.sorted() { return error('exact original TrafficStats methods required') }
 for signature in expected {
  declaration := if signature == '<clinit>()V' { '.method static constructor ' + signature }
   else if signature == '<init>()V' { '.method public constructor ' + signature }
   else { '.method public static ' + signature }
  if methods[signature]!.all_before('\n').trim_space() != declaration {
   return error('original TrafficStats method declaration differs: ' + signature)
  }
 }
 old_init := '.method static constructor <clinit>()V\n.locals 1\n' +
  'new-instance v0, Ljava/lang/ThreadLocal;\ninvoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V\n' +
  'sput-object v0, Landroid/net/TrafficStats;->tags:Ljava/lang/ThreadLocal;\nreturn-void\n.end method'
 init := traffic_stats_uid_code(methods['<clinit>()V']!)
 if init != old_init && init != old_init.replace('.locals 1', '.registers 1') {
  return error('exact original TrafficStats thread-local initializer required')
 }
 old_clear := '.method public static clearThreadStatsUid()V\n.locals 0\nreturn-void\n.end method'
 clear := traffic_stats_uid_code(methods['clearThreadStatsUid()V']!)
 if clear != old_clear && clear != old_clear.replace('.locals 0', '.registers 0') {
  return error('exact original TrafficStats UID clear method required')
 }
 uid_init := 'new-instance v0, Ljava/lang/ThreadLocal;\ninvoke-direct {v0}, Ljava/lang/ThreadLocal;-><init>()V\n' +
  'sput-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;\n'
 mut text := traffic_stats_uid_replace(original, methods['<clinit>()V']!,
  old_init.replace('return-void\n.end method', uid_init + 'return-void\n.end method'))!
 text = traffic_stats_uid_replace(text, methods['clearThreadStatsUid()V']!,
  '.method public static clearThreadStatsUid()V\n.locals 1\n' +
  'sget-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;\n' +
  'invoke-virtual {v0}, Ljava/lang/ThreadLocal;->remove()V\nreturn-void\n.end method')!
 text += '\n.field private static uids:Ljava/lang/ThreadLocal;\n' +
  '.method public static setThreadStatsUid(I)V\n.locals 2\n' +
  'sget-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;\n' +
  'invoke-static {p0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;\nmove-result-object v1\n' +
  'invoke-virtual {v0, v1}, Ljava/lang/ThreadLocal;->set(Ljava/lang/Object;)V\nreturn-void\n.end method\n' +
  '.method public static getThreadStatsUid()I\n.locals 1\n' +
  'sget-object v0, Landroid/net/TrafficStats;->uids:Ljava/lang/ThreadLocal;\n' +
  'invoke-virtual {v0}, Ljava/lang/ThreadLocal;->get()Ljava/lang/Object;\nmove-result-object v0\n' +
  'if-nez v0, :uid\nconst/4 v0, -1\nreturn v0\n:uid\ncheck-cast v0, Ljava/lang/Integer;\n' +
  'invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I\nmove-result v0\nreturn v0\n.end method\n'
 return text
}
