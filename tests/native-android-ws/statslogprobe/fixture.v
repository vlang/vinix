// SPDX-License-Identifier: GPL-2.0-or-later
module statslogprobe

import os

pub fn install(root string) ! {
 os.write_file(root + '/smali/StatsLogProbe.smali', r'.class public Lorg/vinix/bootstrap/StatsLogProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 4
const/4 v0, 4
new-array v0, v0, [B
fill-array-data v0, :bytes
invoke-virtual {v0}, [B->clone()Ljava/lang/Object;
move-result-object v1
check-cast v1, [B
const/4 v2, 3
invoke-static {v0, v2}, Landroid/util/StatsLog;->writeRaw([BI)V
invoke-static {v0, v1}, Ljava/util/Arrays;->equals([B[B)Z
move-result v2
const/4 v3, 1
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v2, 0
invoke-static {v0, v2}, Landroid/util/StatsLog;->writeRaw([BI)V
const/4 v2, 5
invoke-static {v0, v2}, Landroid/util/StatsLog;->writeRaw([BI)V
const/4 v0, 0
invoke-static {v0, v2}, Landroid/util/StatsLog;->writeRaw([BI)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "STATS-LOG-PASS optional-raw-events unchanged-input null oversized zero-length no-delivery-claim"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bytes
.array-data 1
3
0
127
-1
.end array-data
.end method
')!
}
