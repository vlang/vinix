// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_clock_probe(dir string) ! {
	os.write_file(dir + '/ClockProbe.smali', '.class public Lorg/vinix/bootstrap/ClockProbe;\n.super Ljava/lang/Object;\n' +
		method('public static check()V', '
invoke-static {}, Landroid/os/SystemClock;->currentThreadTimeMicro()J
move-result-wide v0
invoke-static {}, Landroid/os/SystemClock;->currentThreadTimeMillis()J
move-result-wide v2
const-wide/16 v4, 1000
mul-long/2addr v2, v4
invoke-static {}, Landroid/os/SystemClock;->currentThreadTimeMicro()J
move-result-wide v4
cmp-long v6, v2, v4
if-gtz v6, :bad
const-wide/16 v4, 999
add-long/2addr v2, v4
cmp-long v6, v2, v0
if-ltz v6, :bad
const-wide/16 v2, 0
cmp-long v6, v0, v2
if-ltz v6, :bad
const v6, 1000000
:work
add-int/lit8 v6, v6, -1
if-nez v6, :work
invoke-static {}, Landroid/os/SystemClock;->currentThreadTimeMicro()J
move-result-wide v2
cmp-long v6, v2, v0
if-lez v6, :bad
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtimeNanos()J
move-result-wide v0
invoke-static {}, Landroid/os/SystemClock;->currentThreadTimeMicro()J
move-result-wide v2
const-wide/16 v4, 100
invoke-static {v4, v5}, Ljava/lang/Thread;->sleep(J)V
invoke-static {}, Landroid/os/SystemClock;->currentThreadTimeMicro()J
move-result-wide v4
sub-long/2addr v4, v2
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtimeNanos()J
move-result-wide v2
sub-long/2addr v2, v0
const-wide/16 v0, 2000
div-long/2addr v2, v0
cmp-long v6, v4, v2
if-gez v6, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-THREAD-CLOCK-PASS millis micro rounding CPU-work excludes-sleep"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "current thread CPU clock"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
