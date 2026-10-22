// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_message_queue_probe(dir string) ! {
 os.write_file(dir + '/MessageQueueProbe.smali', '.class public Lorg/vinix/bootstrap/MessageQueueProbe;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private passed:Z\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  method('public static check()V', '
new-instance v0, Lorg/vinix/bootstrap/MessageQueueProbe;
invoke-direct {v0}, Lorg/vinix/bootstrap/MessageQueueProbe;-><init>()V
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
const-wide/16 v2, 5000
invoke-virtual {v1, v2, v3}, Ljava/lang/Thread;->join(J)V
iget-boolean v0, v0, Lorg/vinix/bootstrap/MessageQueueProbe;->passed:Z
if-eqz v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-MESSAGE-QUEUE-PASS empty ready delayed front removal quit isolated-looper"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "MessageQueue idle state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public run()V', '
invoke-static {}, Landroid/os/Looper;->prepare()V
invoke-static {}, Landroid/os/Looper;->myQueue()Landroid/os/MessageQueue;
move-result-object v0
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v1
if-eqz v1, :done
new-instance v1, Landroid/os/Handler;
invoke-direct {v1}, Landroid/os/Handler;-><init>()V
const/4 v2, 1
invoke-virtual {v1, v2}, Landroid/os/Handler;->sendEmptyMessage(I)Z
move-result v3
if-eqz v3, :done
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v3
if-nez v3, :done
invoke-virtual {v1, v2}, Landroid/os/Handler;->removeMessages(I)V
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v3
if-eqz v3, :done
const-wide/32 v3, 100000
invoke-virtual {v1, v2, v3, v4}, Landroid/os/Handler;->sendEmptyMessageDelayed(IJ)Z
move-result v3
if-eqz v3, :done
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v3
if-eqz v3, :done
const/4 v2, 2
invoke-virtual {v1, v2}, Landroid/os/Handler;->obtainMessage(I)Landroid/os/Message;
move-result-object v2
invoke-virtual {v1, v2}, Landroid/os/Handler;->sendMessageAtFrontOfQueue(Landroid/os/Message;)Z
move-result v3
if-eqz v3, :done
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v3
if-nez v3, :done
const/4 v2, 2
invoke-virtual {v1, v2}, Landroid/os/Handler;->removeMessages(I)V
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v3
if-eqz v3, :done
const/4 v2, 0
invoke-virtual {v1, v2}, Landroid/os/Handler;->removeCallbacksAndMessages(Ljava/lang/Object;)V
invoke-virtual {v0}, Landroid/os/MessageQueue;->isIdle()Z
move-result v3
if-eqz v3, :done
const/4 v2, 1
iput-boolean v2, p0, Lorg/vinix/bootstrap/MessageQueueProbe;->passed:Z
:done
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-virtual {v0}, Landroid/os/Looper;->quit()V
return-void'))!
}
