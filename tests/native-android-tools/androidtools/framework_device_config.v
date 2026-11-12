// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_device_config(smali string) ! {
 path := smali + '/android/provider/DeviceConfig.smali'
 if os.exists(path) { return error('device configuration class already exists') }
 // There is no platform DeviceConfig datastore. Report absent values and
 // failed writes, rather than granting a global configuration authority.
 os.write_file(path, r'.class public final Landroid/provider/DeviceConfig;
.super Ljava/lang/Object;
.method private constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static getProperty(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
.locals 1
invoke-static {p0}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
const/4 v0, 0
return-object v0
.end method
.method public static setProperty(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Z)Z
.locals 1
invoke-static {p0}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
const/4 v0, 0
return v0
.end method
')!
}
