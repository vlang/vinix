// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_time_animator_probe(dir string) ! {
 cls := 'Lorg/vinix/bootstrap/TimeAnimatorProbe;'
 animator := 'Landroid/animation/TimeAnimator;'
 os.write_file(dir + '/TimeAnimatorProbe.smali', '.class public ${cls}\n.super Ljava/lang/Object;\n' +
  '.implements Landroid/animation/TimeAnimator$TimeListener;\n.implements Ljava/lang/Runnable;\n' +
  '.field private animator:${animator}\n.field private count:I\n.field private epoch:I\n.field private total:J\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  method('public static check()V', '
new-instance v0, ${cls}
invoke-direct {v0}, ${cls}-><init>()V
new-instance v1, ${animator}
invoke-direct {v1}, ${animator}-><init>()V
iput-object v1, v0, ${cls}->animator:${animator}
invoke-virtual {v1, v0}, ${animator}->setTimeListener(Landroid/animation/TimeAnimator$TimeListener;)V
invoke-virtual {v1}, ${animator}->start()V
return-void') +
  method('public onTimeUpdate(${animator}JJ)V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
iget-object v0, p0, ${cls}->animator:${animator}
if-ne v0, p1, :bad
const-wide/16 v0, 0
cmp-long v2, p2, v0
if-ltz v2, :bad
cmp-long v2, p4, v0
if-ltz v2, :bad
iget v2, p0, ${cls}->count:I
if-nez v2, :later
cmp-long v3, p4, v0
if-nez v3, :bad
cmp-long v3, p2, v0
if-nez v3, :bad
goto :count
:later
iget-wide v0, p0, ${cls}->total:J
sub-long v0, p2, v0
cmp-long v3, v0, p4
if-nez v3, :bad
:count
iput-wide p2, p0, ${cls}->total:J
add-int/lit8 v2, v2, 1
iput v2, p0, ${cls}->count:I
const/4 v3, 3
if-gt v2, v3, :bad
if-ne v2, v3, :done
const-wide/16 v0, 0
cmp-long v2, p2, v0
if-lez v2, :bad
invoke-virtual {p1}, ${animator}->cancel()V
invoke-virtual {p1}, ${animator}->isRunning()Z
move-result v0
if-nez v0, :bad
new-instance v0, Landroid/os/Handler;
invoke-direct {v0}, Landroid/os/Handler;-><init>()V
const-wide/16 v1, 50
invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
:done
return-void
:bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "TIME-ANIMATOR-FAIL count epoch total delta"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
iget v1, p0, ${cls}->count:I
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(I)V
iget v1, p0, ${cls}->epoch:I
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(I)V
invoke-virtual {v0, p2, p3}, Ljava/io/PrintStream;->println(J)V
invoke-virtual {v0, p4, p5}, Ljava/io/PrintStream;->println(J)V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "TimeAnimator timing, cancellation or callback thread"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public run()V', '
iget v0, p0, ${cls}->count:I
const/4 v1, 3
if-ne v0, v1, :bad
iget v0, p0, ${cls}->epoch:I
iget-object v1, p0, ${cls}->animator:${animator}
if-nez v0, :finished
const/4 v0, 1
iput v0, p0, ${cls}->epoch:I
const/4 v0, 0
iput v0, p0, ${cls}->count:I
invoke-virtual {v1}, ${animator}->start()V
return-void
:finished
const/4 v0, 0
invoke-virtual {v1, v0}, ${animator}->setTimeListener(Landroid/animation/TimeAnimator$TimeListener;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TIME-ANIMATOR-PASS frame-times delta first-frame cancel restart main-handler"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "TimeAnimator delivered after cancel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
