// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Use the boot runtime's BlockGuard hooks: policies belong to the calling
// thread, and actual libcore I/O (not just noteSlowCall) reaches the listener.
fn framework_strict_mode(smali string) ! {
 strict := 'Landroid/os/StrictMode;'
 policy := 'Landroid/os/StrictMode$ThreadPolicy;'
 builder := 'Landroid/os/StrictMode$ThreadPolicy$Builder;'
 listener := 'Landroid/os/StrictMode$OnThreadViolationListener;'
 executor := 'Ljava/util/concurrent/Executor;'
 violation := 'Landroid/os/strictmode/Violation;'
 guard := 'Landroid/os/StrictMode$VinixGuard;'
 callback := 'Landroid/os/StrictMode$VinixCallback;'
 ctor := '(I' + listener + executor + ')V'
 mut text := '.class public final ' + policy + '\n.super Ljava/lang/Object;\n' +
  '.field public static final LAX:' + policy + '\n.field final mask:I\n' +
  '.field final listener:' + listener + '\n.field final callbackExecutor:' + executor + '\n'
 text += signature_method('constructor <init>' + ctor,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ' + policy + '->mask:I\n' +
  'iput-object p2, p0, ' + policy + '->listener:' + listener + '\niput-object p3, p0, ' + policy + '->callbackExecutor:' + executor + '\nreturn-void')
 text += signature_method('static constructor <clinit>()V',
  'new-instance v0, ' + policy + '\nconst/4 v1, 0\ninvoke-direct {v0, v1, v1, v1}, ' + policy + '-><init>' + ctor + '\nsput-object v0, ' + policy + '->LAX:' + policy + '\nreturn-void')
 os.write_file(smali + '/android/os/StrictMode$ThreadPolicy.smali', text)!
 text = '.class public final ' + builder + '\n.super Ljava/lang/Object;\n.field private mask:I\n' +
  '.field private listener:' + listener + '\n.field private executor:' + executor + '\n'
 text += signature_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 text += signature_method('public constructor <init>(' + policy + ')V',
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niget v0, p1, ' + policy + '->mask:I\niput v0, p0, ' + builder + '->mask:I\n' +
  'iget-object v0, p1, ' + policy + '->listener:' + listener + '\niput-object v0, p0, ' + builder + '->listener:' + listener + '\n' +
  'iget-object v0, p1, ' + policy + '->callbackExecutor:' + executor + '\niput-object v0, p0, ' + builder + '->executor:' + executor + '\nreturn-void')
 // Bits match the SDK's thread mask. Resource mismatches need framework
 // resource instrumentation; this generator does not claim that coverage.
 for name, bit in {'DiskWrites': 1, 'DiskReads': 2, 'Network': 4, 'CustomSlowCalls': 8, 'ResourceMismatches': 16, 'UnbufferedIo': 32} {
  for prefix in ['detect', 'permit'] {
   text += signature_method('public ' + prefix + name + '()' + builder,
    'iget v0, p0, ' + builder + '->mask:I\nconst v1, ' + (if prefix == 'detect' { bit } else { ~bit }).str() + '\n' +
    (if prefix == 'detect' { 'or-int' } else { 'and-int' }) + ' v0, v0, v1\niput v0, p0, ' + builder + '->mask:I\nreturn-object p0')
  }
 }
 for name, mask in {'detectAll': 63, 'penaltyLog': 0x40000000, 'penaltyDeath': 0x10000000, 'penaltyDeathOnNetwork': 0x02000000} {
  text += signature_method('public ' + name + '()' + builder,
   'iget v0, p0, ' + builder + '->mask:I\nconst v1, ' + mask.str() + '\nor-int v0, v0, v1\niput v0, p0, ' + builder + '->mask:I\nreturn-object p0')
 }
 text += signature_method('public permitAll()' + builder,
  'iget v0, p0, ' + builder + '->mask:I\nconst v1, -65536\nand-int v0, v0, v1\niput v0, p0, ' + builder + '->mask:I\nreturn-object p0')
 text += signature_method('public penaltyListener(' + executor + listener + ')' + builder,
  'if-nez p1, :valid\nnew-instance v0, Ljava/lang/NullPointerException;\nconst-string v1, "executor must not be null"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n' +
  'iput-object p1, p0, ' + builder + '->executor:' + executor + '\niput-object p2, p0, ' + builder + '->listener:' + listener + '\nreturn-object p0')
 text += signature_method('public penaltyListener(' + listener + executor + ')' + builder,
  'invoke-virtual {p0, p2, p1}, ' + builder + '->penaltyListener(' + executor + listener + ')' + builder + '\nmove-result-object v0\nreturn-object v0')
 text += signature_method('public build()' + policy,
  'iget v1, p0, ' + builder + '->mask:I\niget-object v2, p0, ' + builder + '->listener:' + listener + '\n' +
  'iget-object v3, p0, ' + builder + '->executor:' + executor + '\nif-nez v2, :build\nif-eqz v1, :build\n' +
  'const v4, 0x50000000\nand-int v4, v1, v4\nif-nez v4, :build\nconst v4, 0x40000000\nor-int v1, v1, v4\n' +
  'iput v1, p0, ' + builder + '->mask:I\n:build\nnew-instance v0, ' + policy + '\ninvoke-direct {v0, v1, v2, v3}, ' + policy + '-><init>' + ctor + '\nreturn-object v0')
 os.write_file(smali + '/android/os/StrictMode$ThreadPolicy$Builder.smali', text)!
 os.write_file(smali + '/android/os/StrictMode$OnThreadViolationListener.smali',
  interface_class('android/os/StrictMode$OnThreadViolationListener', ['onThreadViolation(' + violation + ')V']))!
 path := smali + '/android/os/StrictMode.smali'
 text = os.read_file(path)!
 text = framework_replace_method(text, 'getThreadPolicy()' + policy, signature_method('public static getThreadPolicy()' + policy,
  'invoke-static {}, Ldalvik/system/BlockGuard;->getThreadPolicy()Ldalvik/system/BlockGuard$Policy;\nmove-result-object v0\n' +
  'instance-of v1, v0, ' + guard + '\nif-eqz v1, :lax\ncheck-cast v0, ' + guard + '\niget-object v0, v0, ' + guard + '->policy:' + policy + '\nreturn-object v0\n:lax\nsget-object v0, ' + policy + '->LAX:' + policy + '\nreturn-object v0'))!
 text = framework_replace_method(text, 'setThreadPolicy(' + policy + ')V', signature_method('public static setThreadPolicy(' + policy + ')V',
  'iget v0, p0, ' + policy + '->mask:I\nif-eqz v0, :lax\nnew-instance v0, ' + guard + '\ninvoke-direct {v0, p0}, ' + guard + '-><init>(' + policy + ')V\ngoto :set\n' +
  ':lax\nsget-object v0, Ldalvik/system/BlockGuard;->LAX_POLICY:Ldalvik/system/BlockGuard$Policy;\n:set\ninvoke-static {v0}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\nreturn-void'))!
 for name, permit in {'allowThreadDiskReads': 'permitDiskReads', 'allowThreadDiskWrites': 'permitDiskWrites'} {
  text = framework_replace_method(text, name + '()' + policy, signature_method('public static ' + name + '()' + policy,
   'invoke-static {}, ' + strict + '->getThreadPolicy()' + policy + '\nmove-result-object v0\nnew-instance v1, ' + builder + '\n' +
   'invoke-direct {v1, v0}, ' + builder + '-><init>(' + policy + ')V\n' +
   (if name == 'allowThreadDiskWrites' { 'invoke-virtual {v1}, ' + builder + '->permitDiskReads()' + builder + '\n' } else { '' }) +
   'invoke-virtual {v1}, ' + builder + '->' + permit + '()' + builder + '\ninvoke-virtual {v1}, ' + builder + '->build()' + policy + '\nmove-result-object v1\n' +
   'invoke-static {v1}, ' + strict + '->setThreadPolicy(' + policy + ')V\nreturn-object v0'))!
 }
 text = framework_replace_method(text, 'noteSlowCall(Ljava/lang/String;)V', signature_method('public static noteSlowCall(Ljava/lang/String;)V',
  'invoke-static {}, ' + strict + '->getThreadPolicy()' + policy + '\nmove-result-object v0\niget v1, v0, ' + policy + '->mask:I\n' +
  'and-int/lit8 v1, v1, 8\nif-eqz v1, :done\nnew-instance v1, Landroid/os/strictmode/CustomViolation;\n' +
  'invoke-direct {v1, p0}, Landroid/os/strictmode/CustomViolation;-><init>(Ljava/lang/String;)V\n' +
  'invoke-static {v0, v1}, ' + strict + '->vinixViolation(' + policy + violation + ')V\n:done\nreturn-void'))!
 // Suppress recursive reports from logging, scheduling and listener code.
 // Always restore the caller's exact BlockGuard policy, including on throws.
 text += signature_method('static vinixViolation(' + policy + violation + ')V',
  'invoke-static {}, Ldalvik/system/BlockGuard;->getThreadPolicy()Ldalvik/system/BlockGuard$Policy;\nmove-result-object v0\n' +
  'sget-object v1, Ldalvik/system/BlockGuard;->LAX_POLICY:Ldalvik/system/BlockGuard$Policy;\ninvoke-static {v1}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\n' +
  ':start\niget v1, p0, ' + policy + '->mask:I\nconst v2, 0x40000000\nand-int v2, v1, v2\nif-eqz v2, :death\n' +
  'invoke-virtual {p1}, Ljava/lang/Throwable;->printStackTrace()V\n:death\nconst v2, 0x10000000\nand-int v2, v1, v2\nif-eqz v2, :callback\n' +
  'new-instance v1, Ljava/lang/RuntimeException;\nconst-string v2, "StrictMode ThreadPolicy violation"\ninvoke-direct {v1, v2, p1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;Ljava/lang/Throwable;)V\nthrow v1\n' +
  ':callback\niget-object v1, p0, ' + policy + '->listener:' + listener + '\nif-eqz v1, :end\niget-object v2, p0, ' + policy + '->callbackExecutor:' + executor + '\nif-eqz v2, :end\n' +
  'new-instance v3, ' + callback + '\ninvoke-direct {v3, v1, p1}, ' + callback + '-><init>(' + listener + violation + ')V\n' +
  'invoke-interface {v2, v3}, ' + executor + '->execute(Ljava/lang/Runnable;)V\n:end\ngoto :restore\n' +
  '.catch Ljava/util/concurrent/RejectedExecutionException; {:start .. :end} :rejected\n.catchall {:start .. :end} :failed\n' +
  ':rejected\nmove-exception v1\n:reject_start\ninvoke-virtual {v1}, Ljava/lang/Throwable;->printStackTrace()V\n:reject_end\ngoto :restore\n.catchall {:reject_start .. :reject_end} :failed\n' +
  ':restore\ninvoke-static {v0}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\nreturn-void\n' +
  ':failed\nmove-exception v1\ninvoke-static {v0}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\nthrow v1')
 os.write_file(path, text)!
 text = '.class final ' + guard + '\n.super Ljava/lang/Object;\n.implements Ldalvik/system/BlockGuard$Policy;\n.field final policy:' + policy + '\n' +
  signature_method('constructor <init>(' + policy + ')V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + guard + '->policy:' + policy + '\nreturn-void') +
  signature_method('public getPolicyMask()I', 'iget-object v0, p0, ' + guard + '->policy:' + policy + '\niget v0, v0, ' + policy + '->mask:I\nreturn v0')
 for method, name in {'onWriteToDisk': 'DiskWrite', 'onReadFromDisk': 'DiskRead', 'onNetwork': 'Network', 'onUnbufferedIO': 'UnbufferedIo'} {
  bit := {'DiskWrite': 1, 'DiskRead': 2, 'Network': 4, 'UnbufferedIo': 32}[name]
  klass := 'Landroid/os/strictmode/' + name + 'Violation;'
  text += signature_method('public ' + method + '()V',
   'iget-object v0, p0, ' + guard + '->policy:' + policy + '\niget v1, v0, ' + policy + '->mask:I\nand-int/lit8 v2, v1, ' + bit.str() + '\nif-eqz v2, :done\n' +
   (if name == 'Network' { 'const v2, 0x02000000\nand-int v2, v1, v2\nif-eqz v2, :report\nnew-instance v1, Landroid/os/NetworkOnMainThreadException;\ninvoke-direct {v1}, Landroid/os/NetworkOnMainThreadException;-><init>()V\nthrow v1\n:report\n' } else { '' }) +
   'new-instance v1, ' + klass + '\ninvoke-direct {v1}, ' + klass + '-><init>()V\ninvoke-static {v0, v1}, ' + strict + '->vinixViolation(' + policy + violation + ')V\n:done\nreturn-void')
 }
 os.write_file(smali + '/android/os/StrictMode$VinixGuard.smali', text)!
 text = '.class final ' + callback + '\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field final listener:' + listener + '\n.field final violation:' + violation + '\n' +
  signature_method('constructor <init>(' + listener + violation + ')V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + callback + '->listener:' + listener + '\niput-object p2, p0, ' + callback + '->violation:' + violation + '\nreturn-void') +
  signature_method('public run()V',
  'invoke-static {}, Ldalvik/system/BlockGuard;->getThreadPolicy()Ldalvik/system/BlockGuard$Policy;\nmove-result-object v0\nsget-object v1, Ldalvik/system/BlockGuard;->LAX_POLICY:Ldalvik/system/BlockGuard$Policy;\n' +
  'invoke-static {v1}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\n:start\n' +
  'iget-object v1, p0, ' + callback + '->listener:' + listener + '\niget-object v2, p0, ' + callback + '->violation:' + violation + '\ninvoke-interface {v1, v2}, ' + listener + '->onThreadViolation(' + violation + ')V\n:end\n' +
  'invoke-static {v0}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\nreturn-void\n.catchall {:start .. :end} :failed\n' +
  ':failed\nmove-exception v1\ninvoke-static {v0}, Ldalvik/system/BlockGuard;->setThreadPolicy(Ldalvik/system/BlockGuard$Policy;)V\nthrow v1')
 os.write_file(smali + '/android/os/StrictMode$VinixCallback.smali', text)!
 if !os.is_file(smali + '/android/os/NetworkOnMainThreadException.smali') {
  os.write_file(smali + '/android/os/NetworkOnMainThreadException.smali',
   '.class public Landroid/os/NetworkOnMainThreadException;\n.super Ljava/lang/RuntimeException;\n' +
   signature_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/RuntimeException;-><init>()V\nreturn-void'))!
 }
 os.mkdir_all(smali + '/android/os/strictmode')!
 os.write_file(smali + '/android/os/strictmode/Violation.smali', '.class public abstract ' + violation + '\n.super Ljava/lang/Throwable;\n' +
  signature_method('public constructor <init>(Ljava/lang/String;)V', 'invoke-direct {p0, p1}, Ljava/lang/Throwable;-><init>(Ljava/lang/String;)V\nreturn-void'))!
 for name in ['DiskRead', 'DiskWrite', 'Network', 'UnbufferedIo', 'Custom'] {
  klass := 'Landroid/os/strictmode/' + name + 'Violation;'
  os.write_file(smali + '/android/os/strictmode/' + name + 'Violation.smali', '.class public final ' + klass + '\n.super ' + violation + '\n' +
   signature_method('public constructor <init>(' + (if name == 'Custom' { 'Ljava/lang/String;' } else { '' }) + ')V',
   (if name == 'Custom' { 'move-object v0, p1\n' } else { 'const/4 v0, 0\n' }) + 'invoke-direct {p0, v0}, ' + violation + '-><init>(Ljava/lang/String;)V\nreturn-void'))!
 }
}
