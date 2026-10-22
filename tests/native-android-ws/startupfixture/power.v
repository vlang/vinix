// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_power_probe(dir string) ! {
 os.write_file(dir + '/PowerProbe.smali', '.class public Lorg/vinix/bootstrap/PowerProbe;\n.super Ljava/lang/Object;\n' +
  '.implements Ljava/util/concurrent/Executor;\n.implements Landroid/os/PowerManager$OnThermalStatusChangedListener;\n' +
  '.field private count:I\n.field private submitted:I\n.field private main:Z\n.field private reject:Z\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  method('public execute(Ljava/lang/Runnable;)V', '
iget-boolean v0, p0, Lorg/vinix/bootstrap/PowerProbe;->reject:Z
if-eqz v0, :accept
new-instance v0, Ljava/util/concurrent/RejectedExecutionException;
invoke-direct {v0}, Ljava/util/concurrent/RejectedExecutionException;-><init>()V
throw v0
:accept
iget v0, p0, Lorg/vinix/bootstrap/PowerProbe;->submitted:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/PowerProbe;->submitted:I
invoke-interface {p1}, Ljava/lang/Runnable;->run()V
return-void') +
  method('public onThermalStatusChanged(I)V', '
if-nez p1, :bad
iget v0, p0, Lorg/vinix/bootstrap/PowerProbe;->count:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/PowerProbe;->count:I
iget-boolean v1, p0, Lorg/vinix/bootstrap/PowerProbe;->main:Z
if-eqz v1, :done
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v1
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v2
if-ne v1, v2, :bad
const/4 v1, 2
if-ne v0, v1, :done
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-POWER-PASS no-throttling-policy executor main-handler duplicate remove readd rejection null"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "thermal status or main callback"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public static check(Landroid/content/Context;)V', '
const-string v0, "power"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/PowerManager;
invoke-virtual {v0}, Landroid/os/PowerManager;->getCurrentThermalStatus()I
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/PowerManager;->getLocationPowerSaveMode()I
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/PowerManager;->isDeviceIdleMode()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/PowerManager;->isDeviceLightIdleMode()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/os/PowerManager;->isInteractive()Z
move-result v1
if-eqz v1, :bad
new-instance v1, Lorg/vinix/bootstrap/PowerProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/PowerProbe;-><init>()V
invoke-virtual {v0, v1, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
iget v2, v1, Lorg/vinix/bootstrap/PowerProbe;->count:I
const/4 v3, 1
if-ne v2, v3, :bad
iget v2, v1, Lorg/vinix/bootstrap/PowerProbe;->submitted:I
if-ne v2, v3, :bad
:duplicate_start
invoke-virtual {v0, v1, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
:duplicate_end
.catch Ljava/lang/IllegalArgumentException; {:duplicate_start .. :duplicate_end} :duplicate_ok
goto :bad
:duplicate_ok
move-exception v2
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
:absent_start
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
:absent_end
.catch Ljava/lang/IllegalArgumentException; {:absent_start .. :absent_end} :absent_ok
goto :bad
:absent_ok
move-exception v2
iput-boolean v3, v1, Lorg/vinix/bootstrap/PowerProbe;->reject:Z
:reject_start
invoke-virtual {v0, v1, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
:reject_end
.catch Ljava/util/concurrent/RejectedExecutionException; {:reject_start .. :reject_end} :reject_ok
goto :bad
:reject_ok
move-exception v2
const/4 v2, 0
iput-boolean v2, v1, Lorg/vinix/bootstrap/PowerProbe;->reject:Z
invoke-virtual {v0, v1, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
iget v4, v1, Lorg/vinix/bootstrap/PowerProbe;->count:I
const/4 v5, 2
if-ne v4, v5, :bad
:null_executor_start
invoke-virtual {v0, v2, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
:null_executor_end
.catch Ljava/lang/NullPointerException; {:null_executor_start .. :null_executor_end} :null_executor_ok
goto :bad
:null_executor_ok
move-exception v4
:null_listener_start
invoke-virtual {v0, v1, v2}, Landroid/os/PowerManager;->addThermalStatusListener(Ljava/util/concurrent/Executor;Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
:null_listener_end
.catch Ljava/lang/NullPointerException; {:null_listener_start .. :null_listener_end} :null_listener_ok
goto :bad
:null_listener_ok
move-exception v4
new-instance v1, Lorg/vinix/bootstrap/PowerProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/PowerProbe;-><init>()V
iput-boolean v3, v1, Lorg/vinix/bootstrap/PowerProbe;->main:Z
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
iget v2, v1, Lorg/vinix/bootstrap/PowerProbe;->count:I
if-nez v2, :bad
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->addThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
invoke-virtual {v0, v1}, Landroid/os/PowerManager;->removeThermalStatusListener(Landroid/os/PowerManager$OnThermalStatusChangedListener;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "power policy or thermal registration lifecycle"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
