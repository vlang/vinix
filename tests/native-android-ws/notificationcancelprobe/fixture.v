// SPDX-License-Identifier: GPL-2.0-or-later
module notificationcancelprobe

import os

// The isolated API identity has no notification broker and has never posted a
// notice. Cancellation must be idempotent, with no claim of displaying a notice.
pub fn install(root string) ! {
	os.write_file(root + '/smali/NotificationCancelProbe.smali', r'
.class public final Lorg/vinix/bootstrap/NotificationCancelProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static check()V
.locals 3
new-instance v0, Landroid/app/NotificationManager;
invoke-direct {v0}, Landroid/app/NotificationManager;-><init>()V
const v1, 0x564e49
invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->cancel(I)V
invoke-virtual {v0, v1}, Landroid/app/NotificationManager;->cancel(I)V
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v1, Lorg/vinix/bootstrap/NotificationCancelProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/NotificationCancelProbe;-><init>()V
invoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-nez v0, :posted
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:posted
return-void
.end method
.method public run()V
.locals 2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "NOTIFICATION-CANCEL-PASS absent-broker never-posted idempotent queued-main-handler"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
}
