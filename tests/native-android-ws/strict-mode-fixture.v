// SPDX-License-Identifier: GPL-2.0-or-later
// Signed guest regression: real libcore disk I/O, executor delivery and restore.
module main

import os

fn checked(args []string) {
 r := os.exec(args)
 if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

fn main() {
 if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
 out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 tools, java, signer := os.args[3], os.args[4], os.args[5]
 root := out + '/smali/org/vinix/bootstrap'
 os.mkdir_all(root)!
 strict := 'Landroid/os/StrictMode;'
 policy := 'Landroid/os/StrictMode\$ThreadPolicy;'
 builder := 'Landroid/os/StrictMode\$ThreadPolicy\$Builder;'
 listener := 'Landroid/os/StrictMode\$OnThreadViolationListener;'
 violation := 'Landroid/os/strictmode/Violation;'
 probe := 'Lorg/vinix/bootstrap/Probe;'
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n.implements Ljava/util/concurrent/Executor;\n.implements ${listener}\n.implements Ljava/lang/Runnable;\n'
 text += '.field public static custom:I\n.field public static reads:I\n.field public static writes:I\n.field public static networks:I\n.field public static mode:I\n.field public static queued:Ljava/lang/Runnable;\n.field public static worker:Z\n.field public static callbackThread:Ljava/lang/Thread;\n'
 text += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 text += method('public execute(Ljava/lang/Runnable;)V', '
sget v0, ${probe}->mode:I
const/4 v1, 1
if-ne v0, v1, :queue
new-instance v0, Ljava/util/concurrent/RejectedExecutionException;
invoke-direct {v0}, Ljava/util/concurrent/RejectedExecutionException;-><init>()V
throw v0
:queue
const/4 v1, 2
if-ne v0, v1, :inline
sput-object p1, ${probe}->queued:Ljava/lang/Runnable;
return-void
:inline
invoke-interface {p1}, Ljava/lang/Runnable;->run()V
return-void')
 text += method('public onThreadViolation(${violation})V', '
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v0
sget-object v1, ${policy}->LAX:${policy}
if-ne v0, v1, :bad
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
sput-object v0, ${probe}->callbackThread:Ljava/lang/Thread;
# A listener reporting another slow call must not recurse.
const-string v0, "recursive"
invoke-static {v0}, ${strict}->noteSlowCall(Ljava/lang/String;)V
sget v0, ${probe}->mode:I
const/4 v1, 3
if-ne v0, v1, :classify
new-instance v0, Ljava/lang/IllegalStateException;
invoke-direct {v0}, Ljava/lang/IllegalStateException;-><init>()V
throw v0
:classify
instance-of v0, p1, Landroid/os/strictmode/CustomViolation;
if-eqz v0, :read
invoke-virtual {p1}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v0
const-string v1, "fixture"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
sget v0, ${probe}->custom:I
add-int/lit8 v0, v0, 1
sput v0, ${probe}->custom:I
return-void
:read
instance-of v0, p1, Landroid/os/strictmode/DiskReadViolation;
if-eqz v0, :write
sget v0, ${probe}->reads:I
add-int/lit8 v0, v0, 1
sput v0, ${probe}->reads:I
return-void
:write
instance-of v0, p1, Landroid/os/strictmode/DiskWriteViolation;
if-eqz v0, :network
sget v0, ${probe}->writes:I
add-int/lit8 v0, v0, 1
sput v0, ${probe}->writes:I
return-void
:network
instance-of v0, p1, Landroid/os/strictmode/NetworkViolation;
if-eqz v0, :bad
sget v0, ${probe}->networks:I
add-int/lit8 v0, v0, 1
sput v0, ${probe}->networks:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "StrictMode callback type, message or recursion guard"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('public run()V', '
# A newly created Java thread must start LAX, independent of its parent.
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v0
sget-object v1, ${policy}->LAX:${policy}
if-ne v0, v1, :bad
new-instance v1, ${builder}
invoke-direct {v1}, ${builder}-><init>()V
invoke-virtual {v1}, ${builder}->detectCustomSlowCalls()${builder}
invoke-virtual {v1, p0, p0}, ${builder}->penaltyListener(Ljava/util/concurrent/Executor;${listener})${builder}
invoke-virtual {v1}, ${builder}->build()${policy}
move-result-object v1
invoke-static {v1}, ${strict}->setThreadPolicy(${policy})V
sget-object v2, ${probe}->queued:Ljava/lang/Runnable;
invoke-interface {v2}, Ljava/lang/Runnable;->run()V
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v2
if-ne v1, v2, :bad
const/4 v1, 1
sput-boolean v1, ${probe}->worker:Z
invoke-static {v0}, ${strict}->setThreadPolicy(${policy})V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "StrictMode worker isolation/restoration"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('public static test(Landroid/content/Context;)V', '
const/4 v8, 0
const/4 v9, 1
new-instance v0, ${probe}
invoke-direct {v0}, ${probe}-><init>()V
new-instance v1, ${builder}
invoke-direct {v1}, ${builder}-><init>()V
invoke-virtual {v1}, ${builder}->detectCustomSlowCalls()${builder}
invoke-virtual {v1}, ${builder}->detectDiskReads()${builder}
invoke-virtual {v1}, ${builder}->detectDiskWrites()${builder}
invoke-virtual {v1}, ${builder}->detectNetwork()${builder}
invoke-virtual {v1, v0, v0}, ${builder}->penaltyListener(Ljava/util/concurrent/Executor;${listener})${builder}
invoke-virtual {v1}, ${builder}->build()${policy}
move-result-object v2
invoke-static {v2}, ${strict}->setThreadPolicy(${policy})V
const-string v3, "fixture"
invoke-static {v3}, ${strict}->noteSlowCall(Ljava/lang/String;)V
sget v4, ${probe}->custom:I
if-ne v4, v9, :bad
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v4
if-ne v4, v2, :bad
# Real FileOutputStream/FileInputStream must exercise libcore BlockGuardOs.
invoke-virtual {p0}, Landroid/content/Context;->getCacheDir()Ljava/io/File;
move-result-object v4
new-instance v5, Ljava/io/File;
const-string v6, "strict-mode-test"
invoke-direct {v5, v4, v6}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v4, Ljava/io/FileOutputStream;
invoke-direct {v4, v5}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v6, 42
invoke-virtual {v4, v6}, Ljava/io/FileOutputStream;->write(I)V
invoke-virtual {v4}, Ljava/io/FileOutputStream;->close()V
sget v4, ${probe}->writes:I
if-lez v4, :bad
new-instance v4, Ljava/io/FileInputStream;
invoke-direct {v4, v5}, Ljava/io/FileInputStream;-><init>(Ljava/io/File;)V
invoke-virtual {v4}, Ljava/io/FileInputStream;->read()I
move-result v7
if-ne v6, v7, :bad
invoke-virtual {v4}, Ljava/io/FileInputStream;->close()V
sget v4, ${probe}->reads:I
if-lez v4, :bad
invoke-virtual {v5}, Ljava/io/File;->delete()Z
# Network hook has the right typed callback (real network I/O tested by Maps).
invoke-static {}, Ldalvik/system/BlockGuard;->getThreadPolicy()Ldalvik/system/BlockGuard\$Policy;
move-result-object v4
invoke-interface {v4}, Ldalvik/system/BlockGuard\$Policy;->onNetwork()V
sget v4, ${probe}->networks:I
if-ne v4, v9, :bad
# Temporary write permission removes both disk flags, retaining custom checks.
invoke-static {}, ${strict}->allowThreadDiskWrites()${policy}
move-result-object v4
if-ne v4, v2, :bad
invoke-static {}, Ldalvik/system/BlockGuard;->getThreadPolicy()Ldalvik/system/BlockGuard\$Policy;
move-result-object v4
invoke-interface {v4}, Ldalvik/system/BlockGuard\$Policy;->getPolicyMask()I
move-result v4
and-int/lit8 v4, v4, 15
const/16 v5, 12
if-ne v4, v5, :bad
invoke-static {v2}, ${strict}->setThreadPolicy(${policy})V
# Rejected scheduling and throwing listeners must restore the original policy.
sput v9, ${probe}->mode:I
invoke-static {v3}, ${strict}->noteSlowCall(Ljava/lang/String;)V
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v4
if-ne v4, v2, :bad
const/4 v4, 3
sput v4, ${probe}->mode:I
:throw_start
invoke-static {v3}, ${strict}->noteSlowCall(Ljava/lang/String;)V
:throw_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:throw_start .. :throw_end} :thrown
:thrown
move-exception v4
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v4
if-ne v4, v2, :bad
const/4 v4, 2
sput v4, ${probe}->mode:I
invoke-static {v3}, ${strict}->noteSlowCall(Ljava/lang/String;)V
new-instance v4, Ljava/lang/Thread;
invoke-direct {v4, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v4}, Ljava/lang/Thread;->start()V
const-wide/16 v5, 5000
invoke-virtual {v4, v5, v6}, Ljava/lang/Thread;->join(J)V
sget-boolean v5, ${probe}->worker:Z
if-eqz v5, :bad
sget-object v5, ${probe}->callbackThread:Ljava/lang/Thread;
if-ne v5, v4, :bad
sget v4, ${probe}->custom:I
const/4 v5, 2
if-ne v4, v5, :bad
sput v8, ${probe}->mode:I
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v4
if-ne v4, v2, :bad
# Copy/permitAll leaves no detections and never mutates the original policy.
new-instance v4, ${builder}
invoke-direct {v4, v2}, ${builder}-><init>(${policy})V
invoke-virtual {v4}, ${builder}->permitAll()${builder}
invoke-virtual {v4}, ${builder}->build()${policy}
move-result-object v4
invoke-static {v4}, ${strict}->setThreadPolicy(${policy})V
invoke-static {v3}, ${strict}->noteSlowCall(Ljava/lang/String;)V
sget v4, ${probe}->custom:I
if-ne v4, v5, :bad
invoke-static {v2}, ${strict}->setThreadPolicy(${policy})V
# penaltyDeath throws with a real violation cause and restores the policy.
new-instance v4, ${builder}
invoke-direct {v4, v2}, ${builder}-><init>(${policy})V
invoke-virtual {v4}, ${builder}->penaltyDeath()${builder}
invoke-virtual {v4}, ${builder}->build()${policy}
move-result-object v4
invoke-static {v4}, ${strict}->setThreadPolicy(${policy})V
:death_start
invoke-static {v3}, ${strict}->noteSlowCall(Ljava/lang/String;)V
:death_end
goto :bad
.catch Ljava/lang/RuntimeException; {:death_start .. :death_end} :death
:death
move-exception v5
invoke-virtual {v5}, Ljava/lang/Throwable;->getCause()Ljava/lang/Throwable;
move-result-object v5
instance-of v5, v5, Landroid/os/strictmode/CustomViolation;
if-eqz v5, :bad
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v5
if-ne v5, v4, :bad
# Network death takes precedence over ordinary logging/listener delivery.
new-instance v4, ${builder}
invoke-direct {v4, v2}, ${builder}-><init>(${policy})V
invoke-virtual {v4}, ${builder}->penaltyDeathOnNetwork()${builder}
invoke-virtual {v4}, ${builder}->build()${policy}
move-result-object v4
invoke-static {v4}, ${strict}->setThreadPolicy(${policy})V
invoke-static {}, Ldalvik/system/BlockGuard;->getThreadPolicy()Ldalvik/system/BlockGuard\$Policy;
move-result-object v5
:network_death_start
invoke-interface {v5}, Ldalvik/system/BlockGuard\$Policy;->onNetwork()V
:network_death_end
goto :bad
.catch Landroid/os/NetworkOnMainThreadException; {:network_death_start .. :network_death_end} :network_death
:network_death
move-exception v5
invoke-static {}, ${strict}->getThreadPolicy()${policy}
move-result-object v5
if-ne v5, v4, :bad
:null_start
invoke-virtual {v1, v8, v0}, ${builder}->penaltyListener(Ljava/util/concurrent/Executor;${listener})${builder}
:null_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_ok
:null_ok
move-exception v4
sget-object v4, ${policy}->LAX:${policy}
invoke-static {v4}, ${strict}->setThreadPolicy(${policy})V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "STRICT-MODE-PASS real-disk-read-write typed-network custom-message executor worker-isolation recursion-guard copy-permit restoration rejection throwing-listener death network-death null-executor"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "StrictMode policy contract failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 os.write_file(root + '/Probe.smali', text)!
 os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
  method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, ${probe}->test(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "StrictMode real I/O, listeners and restoration checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void'))!
 for name in ['App', 'High', 'Low'] {
  os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
 }
 dex := out + '/classes.dex'
 if os.exists(dex) { os.rm(dex)! }
 checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
 assert os.is_file(dex)
 os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
 checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
 checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
 println('STRICT-MODE-APK ' + out + '/probe.apk')
}
