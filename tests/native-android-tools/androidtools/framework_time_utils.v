// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Report the version of the rules libcore actually loaded, including its
// fallback if the installed database is unavailable. Never guess a version
// from the host or ICU: their databases may differ from java.util.TimeZone.
fn framework_time_utils(smali string) ! {
 os.write_file(smali + '/android/util/TimeUtils.smali', '.class public Landroid/util/TimeUtils;
.super Ljava/lang/Object;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static getTimeZoneDatabaseVersion()Ljava/lang/String;
.locals 1
invoke-static {}, Llibcore/util/ZoneInfoDB;->getInstance()Llibcore/util/ZoneInfoDB\$TzData;
move-result-object v0
invoke-virtual {v0}, Llibcore/util/ZoneInfoDB\$TzData;->getVersion()Ljava/lang/String;
move-result-object v0
return-object v0
.end method
')!
}
