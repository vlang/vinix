// SPDX-License-Identifier: GPL-2.0-or-later
module gnsshardwareprobe
import os
pub fn install(root string) ! {
 os.write_file(root + '/smali/GnssHardwareProbe.smali', r'
.class public final Lorg/vinix/bootstrap/GnssHardwareProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private manager:Landroid/location/LocationManager;
.field private volatile done:Z
.method public constructor <init>(Landroid/location/LocationManager;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/GnssHardwareProbe;->manager:Landroid/location/LocationManager;
return-void
.end method
.method private static metadata(Landroid/location/LocationManager;)V
.locals 3
const/4 v2, 0
invoke-virtual {p0}, Landroid/location/LocationManager;->getGnssHardwareModelName()Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, Landroid/location/LocationManager;->getGnssYearOfHardware()I
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/location/LocationManager;->isLocationEnabled()Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/location/LocationManager;->getAllProviders()Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->size()I
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v1, "gps"
invoke-virtual {p0, v1}, Landroid/location/LocationManager;->isProviderEnabled(Ljava/lang/String;)Z
move-result v0
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0, v1}, Landroid/location/LocationManager;->getLastKnownLocation(Ljava/lang/String;)Landroid/location/Location;
move-result-object v0
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GNSS hardware/location unavailable"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method public run()V
.locals 2
iget-object v0, p0, Lorg/vinix/bootstrap/GnssHardwareProbe;->manager:Landroid/location/LocationManager;
invoke-static {v0}, Lorg/vinix/bootstrap/GnssHardwareProbe;->metadata(Landroid/location/LocationManager;)V
const/4 v1, 1
iput-boolean v1, p0, Lorg/vinix/bootstrap/GnssHardwareProbe;->done:Z
return-void
.end method
.method public static check(Landroid/content/Context;)V
.locals 7
const-string v0, "location"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/location/LocationManager;
invoke-static {v0}, Lorg/vinix/bootstrap/GnssHardwareProbe;->metadata(Landroid/location/LocationManager;)V
invoke-static {v0}, Lorg/vinix/bootstrap/GnssHardwareProbe;->metadata(Landroid/location/LocationManager;)V
new-instance v1, Lorg/vinix/bootstrap/GnssHardwareProbe;
invoke-direct {v1, v0}, Lorg/vinix/bootstrap/GnssHardwareProbe;-><init>(Landroid/location/LocationManager;)V
new-instance v2, Ljava/lang/Thread;
invoke-direct {v2, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
const-wide/16 v3, 3000
invoke-virtual {v2, v3, v4}, Ljava/lang/Thread;->join(J)V
iget-boolean v3, v1, Lorg/vinix/bootstrap/GnssHardwareProbe;->done:Z
const/4 v4, 1
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v3, 0
invoke-virtual {v0, v3}, Landroid/location/LocationManager;->getProviders(Z)Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v1
invoke-static {v1, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0, v4}, Landroid/location/LocationManager;->getProviders(Z)Ljava/util/List;
move-result-object v1
invoke-interface {v1}, Ljava/util/List;->size()I
move-result v1
invoke-static {v1, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {v0}, Lorg/vinix/bootstrap/GnssHardwareProbe;->metadata(Landroid/location/LocationManager;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "GNSS-HARDWARE-PASS absent-model zero-year worker no-provider no-enabled-location no-fix"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
}
