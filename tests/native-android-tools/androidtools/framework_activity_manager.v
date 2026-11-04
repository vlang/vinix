// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_activity_manager(smali string) ! {
 path := smali + '/android/app/ActivityManager.smali'
 mut text := os.read_file(path)!
 // Vinix has no Android Test Harness Mode service or provisioned harness state.
 for signature in ['isRunningInTestHarness()Z', 'isRunningInUserTestHarness()Z'] {
  text = framework_replace_method(text, signature, '.method public static ' + signature + '\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!
 }
 // Android companions share Vinix's single foreground Android user.
 text = framework_replace_method(text, 'getCurrentUser()I',
  '.method public static getCurrentUser()I\n.locals 1\ninvoke-static {}, Landroid/os/UserHandle;->myUserId()I\nmove-result v0\nreturn v0\n.end method')!
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
 os.write_file(info, framework_process_packages_source(info_text)!)!
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

fn process_packages_methods(source string) !map[string]string {
 mut methods := map[string]string{}
 mut body := []string{}
 mut signature := ''
 for line in source.split_into_lines() {
  trimmed := line.trim_space()
  if trimmed.starts_with('.method ') {
   if signature != '' { return error('unterminated process info constructor') }
   signature = trimmed.all_after_last(' ')
   if !signature.contains('(') || signature in methods { return error('unique process info constructor required') }
   body = [line]
  } else if trimmed == '.end method' {
   if signature == '' { return error('unexpected process info constructor end') }
   body << line
   methods[signature] = body.join('\n')
   signature = ''
  } else if signature != '' {
   body << line
  }
 }
 if signature != '' { return error('unterminated process info constructor') }
 return methods
}

fn process_packages_code(source string) string {
 return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

// This is only the public data field. The native process enumeration populates
// fresh package snapshots; constructing an empty info object still leaves null.
// Refuse repeated application and unexpected input before returning any output.
pub fn framework_process_packages_source(original string) !string {
 lines := original.split_into_lines().map(it.all_before('#').trim_space())
 if lines.filter(it.starts_with('.class ')) != ['.class public Landroid/app/ActivityManager$RunningAppProcessInfo;']
  || lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;'] {
  return error('exact process info class and superclass required')
 }
 mut fields := lines.filter(it.starts_with('.field '))
 for index, field in fields {
  for name, values in {'CACHED': '400:0x190', 'FOREGROUND': '100:0x64',
   'FOREGROUND_SERVICE': '125:0x7d', 'GONE': '1000:0x3e8',
   'PERCEPTIBLE': '230:0xe6', 'SERVICE': '300:0x12c', 'VISIBLE': '200:0xc8'} {
   prefix := '.field public static final IMPORTANCE_' + name + ':I = '
   parts := values.split(':')
   if field == prefix + parts[0] { fields[index] = prefix + parts[1] }
  }
 }
 expected_fields := ['.field public static final IMPORTANCE_CACHED:I = 0x190',
  '.field public static final IMPORTANCE_FOREGROUND:I = 0x64',
  '.field public static final IMPORTANCE_FOREGROUND_SERVICE:I = 0x7d',
  '.field public static final IMPORTANCE_GONE:I = 0x3e8',
  '.field public static final IMPORTANCE_PERCEPTIBLE:I = 0xe6',
  '.field public static final IMPORTANCE_SERVICE:I = 0x12c',
  '.field public static final IMPORTANCE_VISIBLE:I = 0xc8',
  '.field public importance:I', '.field public pid:I',
  '.field public processName:Ljava/lang/String;', '.field public uid:I']
 if fields.sorted() != expected_fields.sorted() { return error('exact original eleven process info fields required') }
 methods := process_packages_methods(original)!
 signatures := ['<init>()V', '<init>(ILjava/lang/String;)V', '<init>(ILjava/lang/String;Landroid/app/ActivityManager$1;)V']
 if methods.keys().sorted() != signatures.sorted() { return error('exact original three process info constructors required') }
 for signature in signatures {
  declaration := if signature == '<init>()V' { '.method public constructor ' }
   else if signature == '<init>(ILjava/lang/String;)V' { '.method private constructor ' }
   else { '.method synthetic constructor ' }
  registers := if signature == '<init>()V' { '1' }
   else if signature == '<init>(ILjava/lang/String;)V' { '3' } else { '4' }
  invoke := if signature == signatures[2] {
   'invoke-direct {p0, p1, p2}, Landroid/app/ActivityManager$RunningAppProcessInfo;-><init>(ILjava/lang/String;)V\n'
  } else { 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' }
  assignments := if signature == signatures[1] {
   'iput p1, p0, Landroid/app/ActivityManager$RunningAppProcessInfo;->pid:I\n' +
   'iput-object p2, p0, Landroid/app/ActivityManager$RunningAppProcessInfo;->processName:Ljava/lang/String;\n'
  } else { '' }
  expected := declaration + signature + '\n.registers ' + registers + '\n' + invoke + assignments + 'return-void\n.end method'
  actual := process_packages_code(methods[signature]!)
  if actual != expected && actual != expected.replace('.registers ' + registers, '.locals 0') {
   return error('exact original process info constructor required: ' + signature)
  }
 }
 return original + '\n.field public pkgList:[Ljava/lang/String;\n'
}
