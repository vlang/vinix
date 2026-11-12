// SPDX-License-Identifier: GPL-2.0-or-later
module updatepolicyprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/UpdatePolicyProbe.smali', r'.class public Lorg/vinix/bootstrap/UpdatePolicyProbe;
.super Ljava/lang/Object;
.method public static check(Landroid/content/Context;)V
.locals 3
const-class v0, Landroid/app/admin/SystemUpdatePolicy;
const-string v0, "device_policy"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/admin/DevicePolicyManager;
invoke-static {v0}, Lorg/vinix/bootstrap/UpdatePolicyProbe;->manager(Landroid/app/admin/DevicePolicyManager;)V
const-class v0, Landroid/app/admin/DevicePolicyManager;
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/admin/DevicePolicyManager;
invoke-static {v0}, Lorg/vinix/bootstrap/UpdatePolicyProbe;->manager(Landroid/app/admin/DevicePolicyManager;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "UPDATE-POLICY-PASS absent-policy unmanaged no-device-owner both-lookups"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
.method private static manager(Landroid/app/admin/DevicePolicyManager;)V
.locals 1
invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->getSystemUpdatePolicy()Landroid/app/admin/SystemUpdatePolicy;
move-result-object v0
check-cast v0, Landroid/app/admin/SystemUpdatePolicy;
if-nez v0, :bad
invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->getSystemUpdatePolicy()Landroid/app/admin/SystemUpdatePolicy;
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->isDeviceManaged()Z
move-result v0
if-nez v0, :bad
invoke-virtual {p0}, Landroid/app/admin/DevicePolicyManager;->getDeviceOwner()Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
')!
}
