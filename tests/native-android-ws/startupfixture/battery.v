// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_battery_probe(dir string) ! {
 os.write_file(dir + '/BatteryProbe.smali', '.class public Lorg/vinix/bootstrap/BatteryProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', '
const-string v0, "batterymanager"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/BatteryManager;
if-eqz v0, :bad
const-class v1, Landroid/os/BatteryManager;
invoke-virtual {p0, v1}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v1
instance-of v1, v1, Landroid/os/BatteryManager;
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/os/BatteryManager;->isCharging()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/BatteryManager;->computeChargeTimeRemaining()J
move-result-wide v1
const-wide/16 v3, -1
cmp-long v1, v1, v3
if-nez v1, :bad
invoke-virtual {p0}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v5
iget v6, v5, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
const/16 v1, 28
iput v1, v5, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
const/4 v7, 1
:next
invoke-virtual {v0, v7}, Landroid/os/BatteryManager;->getIntProperty(I)I
move-result v1
const v2, -0x80000000
if-ne v1, v2, :restore_bad
invoke-virtual {v0, v7}, Landroid/os/BatteryManager;->getLongProperty(I)J
move-result-wide v1
const-wide v3, -0x8000000000000000L
cmp-long v1, v1, v3
if-nez v1, :restore_bad
add-int/lit8 v7, v7, 1
const/4 v1, 6
if-le v7, v1, :next
const/16 v1, 27
iput v1, v5, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
const/4 v1, 4
invoke-virtual {v0, v1}, Landroid/os/BatteryManager;->getIntProperty(I)I
move-result v1
if-nez v1, :restore_bad
iput v6, v5, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-BATTERY-PASS string-and-class-service unknown-properties legacy-target no-estimate"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:restore_bad
iput v6, v5, Landroid/content/pm/ApplicationInfo;->targetSdkVersion:I
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "battery service unsupported data"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
