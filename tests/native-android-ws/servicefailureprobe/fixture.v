// SPDX-License-Identifier: GPL-2.0-or-later
module servicefailureprobe

import os

pub fn install(root string) ! {
	probe := 'Lorg/vinix/bootstrap/ServiceFailureProbe;'
	mut source := '.class public ${probe}\n.super Ljava/lang/Object;\n.field public static crash:Ljava/lang/IllegalStateException;\n'
	for field in ['secondaryConstructs', 'secondaryCreates', 'badBinds', 'badStarts', 'badDestroys', 'goodCreates', 'goodStarts', 'goodDestroys', 'callbacks'] {
		source += '.field public static ${field}:I\n'
	}
	source += r'
.method public static check(Landroid/content/Context;)V
.locals 6
new-instance v0, Ljava/lang/IllegalStateException;
invoke-direct {v0}, Ljava/lang/IllegalStateException;-><init>()V
sput-object v0, Lorg/vinix/bootstrap/ServiceFailureProbe;->crash:Ljava/lang/IllegalStateException;
invoke-static {}, Landroid/atl/ATLLoadedApp;->getPrimaryApplication()Landroid/atl/ATLLoadedApp;
move-result-object v0
new-instance v1, Lorg/vinix/bootstrap/PrimaryCrash;
invoke-direct {v1}, Lorg/vinix/bootstrap/PrimaryCrash;-><init>()V
const-string v2, "org.vinix.bootstrap.PrimaryCrash"
:primary
invoke-virtual {v0, v1, v2}, Landroid/atl/ATLLoadedApp;->vinixCreateService(Landroid/app/Service;Ljava/lang/String;)Z
:primary_end
goto :bad
:primary_caught
move-exception v3
sget-object v4, Lorg/vinix/bootstrap/ServiceFailureProbe;->crash:Ljava/lang/IllegalStateException;
if-ne v3, v4, :bad
const-string v2, "org.vinix.bootstrap.NotDeclared"
:unknown
invoke-virtual {v0, v1, v2}, Landroid/atl/ATLLoadedApp;->vinixCreateService(Landroid/app/Service;Ljava/lang/String;)Z
:unknown_end
goto :bad
:unknown_caught
move-exception v3
if-ne v3, v4, :bad
const-string v2, "org.vinix.bootstrap.SecondaryCrash"
:forged
invoke-virtual {v0, v1, v2}, Landroid/atl/ATLLoadedApp;->vinixCreateService(Landroid/app/Service;Ljava/lang/String;)Z
:forged_end
goto :bad
:forged_caught
move-exception v3
if-ne v3, v4, :bad
new-instance v1, Lorg/vinix/bootstrap/SecondaryCrash;
invoke-direct {v1}, Lorg/vinix/bootstrap/SecondaryCrash;-><init>()V
invoke-virtual {v0, v1, v2}, Landroid/atl/ATLLoadedApp;->vinixCreateService(Landroid/app/Service;Ljava/lang/String;)Z
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/Intent;
const-class v1, Lorg/vinix/bootstrap/SecondaryCrash;
invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
move-result-object v1
if-eqz v1, :bad
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
move-result-object v1
if-eqz v1, :bad
new-instance v2, Lorg/vinix/bootstrap/FailedServiceConnection;
invoke-direct {v2}, Lorg/vinix/bootstrap/FailedServiceConnection;-><init>()V
const/4 v3, 1
invoke-virtual {p0, v0, v2, v3}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
move-result v0
invoke-static {v0, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/Intent;
const-class v1, Lorg/vinix/bootstrap/HealthyService;
invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
move-result-object v0
if-eqz v0, :bad
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v1, Lorg/vinix/bootstrap/ServiceFailureFence;
invoke-direct {v1, p0, v2}, Lorg/vinix/bootstrap/ServiceFailureFence;-><init>(Landroid/content/Context;Landroid/content/ServiceConnection;)V
invoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.catch Ljava/lang/IllegalStateException; {:primary .. :primary_end} :primary_caught
.catch Ljava/lang/IllegalStateException; {:unknown .. :unknown_end} :unknown_caught
.catch Ljava/lang/IllegalStateException; {:forged .. :forged_end} :forged_caught
.end method
'
	source += '.method public static verify(Landroid/content/Context;Landroid/content/ServiceConnection;)V\n.locals 4\n'
	for field, expected in {'secondaryConstructs': 4, 'secondaryCreates': 4, 'badBinds': 0, 'badStarts': 0, 'badDestroys': 0, 'goodCreates': 1, 'goodStarts': 1, 'callbacks': 0} {
		source += 'sget v0, ${probe}->${field}:I\nconst/4 v1, ${expected}\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
	}
	source += r'
new-instance v0, Landroid/content/Intent;
const-class v1, Lorg/vinix/bootstrap/SecondaryCrash;
invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V
invoke-virtual {p0, v0}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v0, Landroid/content/Intent;
const-class v1, Lorg/vinix/bootstrap/HealthyService;
invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V
invoke-virtual {p0, v0}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget v0, Lorg/vinix/bootstrap/ServiceFailureProbe;->goodDestroys:I
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0, p1}, Landroid/content/Context;->unbindService(Landroid/content/ServiceConnection;)V
:unbind
invoke-virtual {p0, p1}, Landroid/content/Context;->unbindService(Landroid/content/ServiceConnection;)V
:unbind_end
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:abandoned
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SECONDARY-SERVICE-CREATE-PASS failed-not-cached clean-unbind primary-errors-preserved main-loop-live"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.catch Ljava/lang/IllegalArgumentException; {:unbind .. :unbind_end} :abandoned
.end method
'
	os.write_file(root + '/smali/ServiceFailureProbe.smali', source)!
	for name in ['PrimaryCrash', 'SecondaryCrash', 'HealthyService'] {
		kind := 'Lorg/vinix/bootstrap/${name};'
		mut text := '.class public ${kind}\n.super Landroid/app/Service;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\n' + if name == 'SecondaryCrash' { increment('secondaryConstructs') } else { '' } + 'return-void')
		text += method('public onCreate()V', if name == 'HealthyService' { increment('goodCreates') + 'return-void' } else { (if name == 'SecondaryCrash' { increment('secondaryCreates') } else { '' }) + 'sget-object v0, ${probe}->crash:Ljava/lang/IllegalStateException;\nthrow v0' })
		text += method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', (if name == 'SecondaryCrash' { increment('badBinds') } else { '' }) + 'const/4 v0, 0\nreturn-object v0')
		text += method('public onStartCommand(Landroid/content/Intent;II)I', increment(if name == 'HealthyService' { 'goodStarts' } else { 'badStarts' }) + 'const/4 v0, 2\nreturn v0')
		text += method('public onDestroy()V', increment(if name == 'HealthyService' { 'goodDestroys' } else { 'badDestroys' }) + 'return-void')
		os.write_file(root + '/smali/${name}.smali', text)!
	}
	os.write_file(root + '/smali/FailedServiceConnection.smali', '.class public Lorg/vinix/bootstrap/FailedServiceConnection;\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', increment('callbacks') + 'return-void') + method('public onServiceDisconnected(Landroid/content/ComponentName;)V', increment('callbacks') + 'return-void'))!
	os.write_file(root + '/smali/ServiceFailureFence.smali', r'.class public Lorg/vinix/bootstrap/ServiceFailureFence;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private context:Landroid/content/Context;
.field private connection:Landroid/content/ServiceConnection;
.method public constructor <init>(Landroid/content/Context;Landroid/content/ServiceConnection;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/ServiceFailureFence;->context:Landroid/content/Context;
iput-object p2, p0, Lorg/vinix/bootstrap/ServiceFailureFence;->connection:Landroid/content/ServiceConnection;
return-void
.end method
.method public run()V
.locals 2
iget-object v0, p0, Lorg/vinix/bootstrap/ServiceFailureFence;->context:Landroid/content/Context;
iget-object v1, p0, Lorg/vinix/bootstrap/ServiceFailureFence;->connection:Landroid/content/ServiceConnection;
invoke-static {v0, v1}, Lorg/vinix/bootstrap/ServiceFailureProbe;->verify(Landroid/content/Context;Landroid/content/ServiceConnection;)V
return-void
.end method
')!
}

fn increment(field string) string {
	return 'sget v0, Lorg/vinix/bootstrap/ServiceFailureProbe;->${field}:I\nadd-int/lit8 v0, v0, 1\nsput v0, Lorg/vinix/bootstrap/ServiceFailureProbe;->${field}:I\n'
}

fn method(signature string, body string) string {
	return '.method ${signature}\n.locals 1\n${body}\n.end method\n'
}

pub fn manifest() string {
	return '<service android:name="org.vinix.bootstrap.PrimaryCrash" android:exported="false"/><service android:name="org.vinix.bootstrap.SecondaryCrash" android:process=":secondary" android:exported="false"/><service android:name="org.vinix.bootstrap.HealthyService" android:exported="false"/>'
}
