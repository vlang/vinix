// SPDX-License-Identifier: GPL-2.0-or-later
// ART regression for unavailable authenticators and asynchronous account callbacks.
module main

import os

fn checked(args []string) {
 r := os.exec(args)
 if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string, locals int) string {
 return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn main() {
 if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
 out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
 tools, java, signer := os.args[3], os.args[4], os.args[5]
 root := out + '/smali/org/vinix/bootstrap'
 os.mkdir_all(root)!
 main_cls := 'Lorg/vinix/bootstrap/Main;'
 probe := 'Lorg/vinix/bootstrap/AccountAdditionProbe;'
 failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "account addition contract failed"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut text := '.class public ' + main_cls + '\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' +
  '.field public handler:Landroid/os/Handler;\n.field private worker:Landroid/os/HandlerThread;\n.field private completed:I\n'
 text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
 text += method('public static checkFuture(Landroid/accounts/AccountManagerFuture;)V', '
invoke-interface {p0}, Landroid/accounts/AccountManagerFuture;->isDone()Z
move-result v0
if-eqz v0, :bad
invoke-interface {p0}, Landroid/accounts/AccountManagerFuture;->isCancelled()Z
move-result v0
if-nez v0, :bad
const/4 v0, 0
invoke-interface {p0, v0}, Landroid/accounts/AccountManagerFuture;->cancel(Z)Z
move-result v0
if-nez v0, :bad
const/4 v0, 1
invoke-interface {p0, v0}, Landroid/accounts/AccountManagerFuture;->cancel(Z)Z
move-result v0
if-nez v0, :bad
:result_start
invoke-interface {p0}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
:result_end
goto :bad
.catch Landroid/accounts/AuthenticatorException; {:result_start .. :result_end} :result_failed
:result_failed
move-exception v4
instance-of v0, v4, Landroid/accounts/AccountsException;
if-eqz v0, :bad
:repeat_start
invoke-interface {p0}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;
:repeat_end
goto :bad
.catch Landroid/accounts/AuthenticatorException; {:repeat_start .. :repeat_end} :repeat_failed
:repeat_failed
move-exception v0
if-ne v0, v4, :bad
:timed_start
const-wide/16 v0, 0
sget-object v2, Ljava/util/concurrent/TimeUnit;->NANOSECONDS:Ljava/util/concurrent/TimeUnit;
invoke-interface {p0, v0, v1, v2}, Landroid/accounts/AccountManagerFuture;->getResult(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;
:timed_end
goto :bad
.catch Landroid/accounts/AuthenticatorException; {:timed_start .. :timed_end} :timed_failed
:timed_failed
move-exception v0
if-ne v0, v4, :bad
:unit_start
const-wide/16 v0, 0
const/4 v2, 0
invoke-interface {p0, v0, v1, v2}, Landroid/accounts/AccountManagerFuture;->getResult(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;
:unit_end
goto :bad
.catch Ljava/lang/NullPointerException; {:unit_start .. :unit_end} :unit_failed
:unit_failed
move-exception v0
invoke-interface {p0}, Landroid/accounts/AccountManagerFuture;->isDone()Z
move-result v0
if-eqz v0, :bad
invoke-interface {p0}, Landroid/accounts/AccountManagerFuture;->isCancelled()Z
move-result v0
if-nez v0, :bad
return-void
' + failure, 5)
 text += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, Landroid/accounts/AccountManager;->get(Landroid/content/Context;)Landroid/accounts/AccountManager;
move-result-object v0
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
move-object v5, p0
const/4 v6, 0
const/4 v7, 0
:null_start
invoke-virtual/range {v0 .. v7}, Landroid/accounts/AccountManager;->addAccount(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
:null_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:null_start .. :null_end} :null_failed
:null_failed
move-exception v1
const-string v1, "com.google"
invoke-virtual/range {v0 .. v7}, Landroid/accounts/AccountManager;->addAccount(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v1
invoke-static {v1}, ${main_cls}->checkFuture(Landroid/accounts/AccountManagerFuture;)V
invoke-virtual {v0}, Landroid/accounts/AccountManager;->getAccounts()[Landroid/accounts/Account;
move-result-object v0
array-length v0, v0
if-nez v0, :bad
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
new-instance v2, Landroid/os/Handler;
invoke-direct {v2, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v2, p0, ${main_cls}->handler:Landroid/os/Handler;
# Main caller, no handler: callback must queue on main rather than run inline.
const/4 v3, 0
new-instance v0, ${probe}
invoke-direct {v0, p0, v3, v1}, ${probe}-><init>(${main_cls}Landroid/os/Handler;Landroid/os/Looper;)V
invoke-virtual {v0}, ${probe}->run()V
iget v2, v0, ${probe}->calls:I
if-nez v2, :bad
# A caller without a Looper must still default its callback to main.
new-instance v0, ${probe}
invoke-direct {v0, p0, v3, v1}, ${probe}-><init>(${main_cls}Landroid/os/Handler;Landroid/os/Looper;)V
new-instance v2, Ljava/lang/Thread;
invoke-direct {v2, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
# A supplied Handler moves the callback onto its own thread.
new-instance v0, Landroid/os/HandlerThread;
const-string v1, "account-callback"
invoke-direct {v0, v1}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
iput-object v0, p0, ${main_cls}->worker:Landroid/os/HandlerThread;
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v1
new-instance v2, Landroid/os/Handler;
invoke-direct {v2, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v0, ${probe}
invoke-direct {v0, p0, v2, v1}, ${probe}-><init>(${main_cls}Landroid/os/Handler;Landroid/os/Looper;)V
invoke-virtual {v0}, ${probe}->run()V
return-void
' + failure, 8)
 text += method('public run()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
iget v0, p0, ${main_cls}->completed:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_cls}->completed:I
const/4 v1, 3
if-gt v0, v1, :bad
if-ne v0, v1, :done
iget-object v0, p0, ${main_cls}->worker:Landroid/os/HandlerThread;
invoke-virtual {v0}, Landroid/os/HandlerThread;->quit()Z
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "ACCOUNT-ASYNC-PASS null-type no-callback no-accounts main-queued worker-to-main explicit-handler callback-once same-future done cancel-false result-authenticator-exception repeat timed null-unit"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Unavailable authenticator callback checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
:done
return-void
' + failure, 2)
 os.write_file(root + '/Main.smali', text)!
 mut callback := '.class public final ' + probe + '\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.implements Landroid/accounts/AccountManagerCallback;\n' +
  '.field private owner:' + main_cls + '\n.field private handler:Landroid/os/Handler;\n.field private expected:Landroid/os/Looper;\n' +
  '.field private returned:Ljava/util/concurrent/CountDownLatch;\n.field private future:Landroid/accounts/AccountManagerFuture;\n.field public calls:I\n'
 callback += method('public constructor <init>(' + main_cls + 'Landroid/os/Handler;Landroid/os/Looper;)V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${probe}->owner:${main_cls}
iput-object p2, p0, ${probe}->handler:Landroid/os/Handler;
iput-object p3, p0, ${probe}->expected:Landroid/os/Looper;
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, ${probe}->returned:Ljava/util/concurrent/CountDownLatch;
return-void', 2)
 callback += method('public run()V', '
iget-object v5, p0, ${probe}->owner:${main_cls}
invoke-static {v5}, Landroid/accounts/AccountManager;->get(Landroid/content/Context;)Landroid/accounts/AccountManager;
move-result-object v0
const-string v1, "com.google"
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
move-object v6, p0
iget-object v7, p0, ${probe}->handler:Landroid/os/Handler;
invoke-virtual/range {v0 .. v7}, Landroid/accounts/AccountManager;->addAccount(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;
move-result-object v0
iput-object v0, p0, ${probe}->future:Landroid/accounts/AccountManagerFuture;
invoke-static {v0}, ${main_cls}->checkFuture(Landroid/accounts/AccountManagerFuture;)V
iget-object v0, p0, ${probe}->returned:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void', 8)
 callback += method('public run(Landroid/accounts/AccountManagerFuture;)V', '
# Inline execution cannot pass: the submission releases this gate after return.
iget-object v0, p0, ${probe}->returned:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v1, 2
sget-object v3, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, ${probe}->future:Landroid/accounts/AccountManagerFuture;
if-ne v0, p1, :bad
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
iget-object v1, p0, ${probe}->expected:Landroid/os/Looper;
if-ne v0, v1, :bad
iget v0, p0, ${probe}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${probe}->calls:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-static {p1}, ${main_cls}->checkFuture(Landroid/accounts/AccountManagerFuture;)V
iget-object v0, p0, ${probe}->owner:${main_cls}
iget-object v1, v0, ${main_cls}->handler:Landroid/os/Handler;
invoke-virtual {v1, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-eqz v0, :bad
return-void
' + failure, 4)
 os.write_file(root + '/AccountAdditionProbe.smali', callback)!
 for name in ['App', 'High', 'Low'] {
  os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
 }
 dex := out + '/classes.dex'
 if os.exists(dex) { os.rm(dex)! }
 checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])
 assert os.is_file(dex)
 os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
 checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
 checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
 println('ACCOUNT-ASYNC-APK ' + out + '/probe.apk')
}
