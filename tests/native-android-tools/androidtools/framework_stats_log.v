// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_stats_log(smali string) ! {
 path := smali + '/android/util/StatsLog.smali'
 if os.exists(path) { return error('stats log class already exists') }
 // Legacy raw stats are best effort and have no delivery result. No statsd
 // transport exists here: drop valid events without claiming transmission.
 os.write_file(path, r'.class public final Landroid/util/StatsLog;
.super Ljava/lang/Object;
.method private constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static writeRaw([BI)V
.locals 0
return-void
.end method
')!
}
