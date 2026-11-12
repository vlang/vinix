// SPDX-License-Identifier: GPL-2.0-or-later
module vmpolicyprobe

import os

pub fn install(root string) ! {
	mut source := r'.class public Lorg/vinix/bootstrap/VmPolicyProbe;
.super Ljava/lang/Object;
.implements Landroid/os/StrictMode$OnVmViolationListener;
.implements Ljava/util/concurrent/Executor;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public onVmViolation(Landroid/os/strictmode/Violation;)V
.locals 0
return-void
.end method
.method public execute(Ljava/lang/Runnable;)V
.locals 0
invoke-interface {p1}, Ljava/lang/Runnable;->run()V
return-void
.end method
.method public static field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
.locals 2
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0, p1}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
return-object v0
.end method
.method public static check()V
.locals 10
invoke-static {}, Landroid/os/StrictMode;->getVmPolicy()Landroid/os/StrictMode$VmPolicy;
move-result-object v9
new-instance v0, Landroid/os/StrictMode$VmPolicy$Builder;
invoke-direct {v0}, Landroid/os/StrictMode$VmPolicy$Builder;-><init>()V
new-instance v7, Lorg/vinix/bootstrap/VmPolicyProbe;
invoke-direct {v7}, Lorg/vinix/bootstrap/VmPolicyProbe;-><init>()V
invoke-virtual {v0, v7, v7}, Landroid/os/StrictMode$VmPolicy$Builder;->penaltyListener(Ljava/util/concurrent/Executor;Landroid/os/StrictMode$OnVmViolationListener;)Landroid/os/StrictMode$VmPolicy$Builder;
const-class v1, Ljava/lang/String;
const/4 v2, 7
invoke-virtual {v0, v1, v2}, Landroid/os/StrictMode$VmPolicy$Builder;->setClassInstanceLimit(Ljava/lang/Class;I)Landroid/os/StrictMode$VmPolicy$Builder;
'
	for name in ['LeakedClosableObjects', 'LeakedSqlLiteObjects', 'FileUriExposure', 'LeakedRegistrationObjects', 'ActivityLeaks', 'ContentUriWithoutPermission', 'CredentialProtectedWhileLocked', 'ImplicitDirectBoot', 'UnsafeIntentLaunch', 'IncorrectContextUse', 'NonSdkApiUsage', 'UntaggedSockets'] {
		source += 'invoke-virtual {v0}, Landroid/os/StrictMode$VmPolicy$Builder;->detect${name}()Landroid/os/StrictMode$VmPolicy$Builder;\nmove-result-object v2\nif-ne v0, v2, :bad\n'
	}
	source += r'invoke-virtual {v0}, Landroid/os/StrictMode$VmPolicy$Builder;->build()Landroid/os/StrictMode$VmPolicy;
move-result-object v3
new-instance v4, Landroid/os/StrictMode$VmPolicy$Builder;
invoke-direct {v4, v3}, Landroid/os/StrictMode$VmPolicy$Builder;-><init>(Landroid/os/StrictMode$VmPolicy;)V
const/16 v2, 9
invoke-virtual {v0, v1, v2}, Landroid/os/StrictMode$VmPolicy$Builder;->setClassInstanceLimit(Ljava/lang/Class;I)Landroid/os/StrictMode$VmPolicy$Builder;
const/16 v2, 11
invoke-virtual {v4, v1, v2}, Landroid/os/StrictMode$VmPolicy$Builder;->setClassInstanceLimit(Ljava/lang/Class;I)Landroid/os/StrictMode$VmPolicy$Builder;
invoke-virtual {v4}, Landroid/os/StrictMode$VmPolicy$Builder;->build()Landroid/os/StrictMode$VmPolicy;
move-result-object v5
const/16 v2, 12
invoke-virtual {v4, v1, v2}, Landroid/os/StrictMode$VmPolicy$Builder;->setClassInstanceLimit(Ljava/lang/Class;I)Landroid/os/StrictMode$VmPolicy$Builder;
const-string v2, "limits"
invoke-static {v3, v2}, Lorg/vinix/bootstrap/VmPolicyProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v6
check-cast v6, Ljava/util/Map;
invoke-interface {v6, v1}, Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v6
check-cast v6, Ljava/lang/Integer;
invoke-virtual {v6}, Ljava/lang/Integer;->intValue()I
move-result v6
const/4 v8, 7
invoke-static {v6, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {v5, v2}, Lorg/vinix/bootstrap/VmPolicyProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v6
check-cast v6, Ljava/util/Map;
invoke-interface {v6, v1}, Ljava/util/Map;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v6
check-cast v6, Ljava/lang/Integer;
invoke-virtual {v6}, Ljava/lang/Integer;->intValue()I
move-result v6
const/16 v8, 11
invoke-static {v6, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
'
	for name in ['listener', 'executor'] {
		source += 'const-string v2, "${name}"\ninvoke-static {v5, v2}, Lorg/vinix/bootstrap/VmPolicyProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;\nmove-result-object v6\nif-ne v6, v7, :bad\n'
	}
	source += r'const-string v2, "mask"
invoke-static {v5, v2}, Lorg/vinix/bootstrap/VmPolicyProbe;->field(Ljava/lang/Object;Ljava/lang/String;)Ljava/lang/Object;
move-result-object v6
check-cast v6, Ljava/lang/Integer;
invoke-virtual {v6}, Ljava/lang/Integer;->intValue()I
move-result v6
const v8, 0x3fbf
invoke-static {v6, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {v5}, Landroid/os/StrictMode;->setVmPolicy(Landroid/os/StrictMode$VmPolicy;)V
invoke-static {}, Landroid/os/StrictMode;->getVmPolicy()Landroid/os/StrictMode$VmPolicy;
move-result-object v6
if-ne v5, v6, :bad
const/4 v2, 0
:copy_start
new-instance v0, Landroid/os/StrictMode$VmPolicy$Builder;
invoke-direct {v0, v2}, Landroid/os/StrictMode$VmPolicy$Builder;-><init>(Landroid/os/StrictMode$VmPolicy;)V
:copy_end
goto :bad
.catch Ljava/lang/NullPointerException; {:copy_start .. :copy_end} :copy_null
:copy_null
move-exception v0
:set_start
invoke-static {v2}, Landroid/os/StrictMode;->setVmPolicy(Landroid/os/StrictMode$VmPolicy;)V
:set_end
goto :bad
.catch Ljava/lang/NullPointerException; {:set_start .. :set_end} :set_null
:set_null
move-exception v0
invoke-static {}, Landroid/os/StrictMode;->getVmPolicy()Landroid/os/StrictMode$VmPolicy;
move-result-object v0
if-ne v0, v5, :bad
invoke-static {v9}, Landroid/os/StrictMode;->setVmPolicy(Landroid/os/StrictMode$VmPolicy;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "VM-POLICY-PASS copy immutable-limits listener executor masks get-set null-rejection"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
invoke-static {v9}, Landroid/os/StrictMode;->setVmPolicy(Landroid/os/StrictMode$VmPolicy;)V
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
'
	os.write_file(root + '/smali/VmPolicyProbe.smali', source)!
}
