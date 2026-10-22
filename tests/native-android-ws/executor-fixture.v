// SPDX-License-Identifier: GPL-2.0-or-later
// Guest regression for Context executors, queueing and wrapper overrides.
module main

import os

fn checked(args []string) {
 r := os.exec(args)
 if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

fn main() {
 if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
 out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 tools, java, signer := os.args[3], os.args[4], os.args[5]
 root := out + '/smali/org/vinix/bootstrap'
 os.mkdir_all(root)!
 failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "main executor contract failed"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 main_cls := 'Lorg/vinix/bootstrap/Main;'
 task := 'Lorg/vinix/bootstrap/ExecutorTask;'
 choice := 'Lorg/vinix/bootstrap/ExecutorContext;'
 os.write_file(root + '/ExecutorContext.smali', '.class public ${choice}\n.super Landroid/content/ContextWrapper;\n' +
  '.field public answer:Ljava/util/concurrent/Executor;\n.field public calls:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('public getMainExecutor()Ljava/util/concurrent/Executor;', 'iget v0, p0, ${choice}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${choice}->calls:I\niget-object v0, p0, ${choice}->answer:Ljava/util/concurrent/Executor;\nreturn-object v0'))!
 os.write_file(root + '/ExecutorTask.smali', '.class public ${task}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
  '.field private owner:${main_cls}\n.field private expected:I\n' +
  method('public constructor <init>(${main_cls}I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${task}->owner:${main_cls}\niput p2, p0, ${task}->expected:I\nreturn-void') +
  method('public run()V', 'iget-object v0, p0, ${task}->owner:${main_cls}\niget v1, p0, ${task}->expected:I\ninvoke-virtual {v0, v1}, ${main_cls}->step(I)V\nreturn-void'))!
 mut text := '.class public ${main_cls}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' +
  '.field private count:I\n.field private executor:Ljava/util/concurrent/Executor;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
 text += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-virtual {p0}, Landroid/content/Context;->getMainExecutor()Ljava/util/concurrent/Executor;
move-result-object v0
if-eqz v0, :bad
iput-object v0, p0, ${main_cls}->executor:Ljava/util/concurrent/Executor;
# Nested wrappers preserve the base override, including subsequent changes.
new-instance v1, ${choice}
invoke-direct {v1, p0}, ${choice}-><init>(Landroid/content/Context;)V
iput-object v0, v1, ${choice}->answer:Ljava/util/concurrent/Executor;
new-instance v2, Landroid/content/ContextWrapper;
invoke-direct {v2, v1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
new-instance v3, Landroid/content/ContextWrapper;
invoke-direct {v3, v2}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
invoke-virtual {v3}, Landroid/content/Context;->getMainExecutor()Ljava/util/concurrent/Executor;
move-result-object v2
if-ne v2, v0, :bad
const/4 v2, 0
iput-object v2, v1, ${choice}->answer:Ljava/util/concurrent/Executor;
invoke-virtual {v3}, Landroid/content/Context;->getMainExecutor()Ljava/util/concurrent/Executor;
move-result-object v2
if-nez v2, :bad
iget v2, v1, ${choice}->calls:I
const/4 v3, 2
if-ne v2, v3, :bad
# Null commands fail immediately.
:null_start
const/4 v1, 0
invoke-interface {v0, v1}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V
:null_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_ok
:null_ok
move-exception v1
# A closed handler must reject commands rather than silently losing them.
new-instance v1, Landroid/os/HandlerThread;
const-string v2, "executor-rejection"
invoke-direct {v1, v2}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
invoke-virtual {v1}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v2
new-instance v3, Landroid/os/Handler;
invoke-direct {v3, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v2, Landroid/os/HandlerExecutor;
invoke-direct {v2, v3}, Landroid/os/HandlerExecutor;-><init>(Landroid/os/Handler;)V
invoke-virtual {v1}, Landroid/os/HandlerThread;->quit()Z
const-wide/16 v4, 1000
invoke-virtual {v1, v4, v5}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v1}, Ljava/lang/Thread;->isAlive()Z
move-result v1
if-nez v1, :bad
:reject_start
invoke-interface {v2, p0}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V
:reject_end
goto :bad
.catch Ljava/util/concurrent/RejectedExecutionException; {:reject_start .. :reject_end} :reject_ok
:reject_ok
move-exception v1
# A submission from main must be queued, never executed inline.
new-instance v1, ${task}
const/4 v2, 1
invoke-direct {v1, p0, v2}, ${task}-><init>(${main_cls}I)V
invoke-interface {v0, v1}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V
iget v1, p0, ${main_cls}->count:I
if-nez v1, :bad
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, p0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
return-void
' + failure)
 text += method('public run()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eq v0, v1, :bad
iget-object v0, p0, ${main_cls}->executor:Ljava/util/concurrent/Executor;
const/4 v1, 2
:next
new-instance v2, ${task}
invoke-direct {v2, p0, v1}, ${task}-><init>(${main_cls}I)V
invoke-interface {v0, v2}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V
add-int/lit8 v1, v1, 1
const/4 v2, 4
if-lt v1, v2, :next
return-void
' + failure)
 text += method('public step(I)V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
iget v0, p0, ${main_cls}->count:I
add-int/lit8 v0, v0, 1
if-ne v0, p1, :bad
iput v0, p0, ${main_cls}->count:I
const/4 v1, 3
if-ne v0, v1, :done
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "MAIN-EXECUTOR-PASS main-queued worker-to-main fifo nested-wrapper virtual-override mutable-override null-rejected shutdown-rejected"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Main executor dispatch checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
:done
return-void
' + failure)
 os.write_file(root + '/Main.smali', text)!
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
 println('MAIN-EXECUTOR-APK ' + out + '/probe.apk')
}
