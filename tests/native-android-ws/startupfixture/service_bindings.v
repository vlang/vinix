// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_service_binding_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/ServiceBindingProbe;'
	service := 'Lorg/vinix/bootstrap/BindingService;'
	conn := 'Lorg/vinix/bootstrap/BindingConnection;'
	fail := ':bad\nnew-instance v8, Ljava/lang/AssertionError;\nconst-string v9, "service binding lifecycle or callback state"\ninvoke-direct {v8, v9}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v8'
	mut svc := '.class public ${service}\n.super Landroid/app/Service;\n'
	for field in ['created', 'binds', 'unbinds', 'rebinds', 'destroyed'] {
		svc += '.field public static ${field}:I\n'
	}
	svc += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void')
	for field, signature in {
		'created':   'onCreate()V'
		'destroyed': 'onDestroy()V'
		'rebinds':   'onRebind(Landroid/content/Intent;)V'
	} {
		svc += method('public ' + signature, 'invoke-static {}, ${probe}->mainThread()V\nsget v0, ${service}->${field}:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${service}->${field}:I\nreturn-void')
	}
	svc += method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', '
invoke-static {}, ${probe}->mainThread()V
sget v0, ${service}->binds:I
add-int/lit8 v0, v0, 1
sput v0, ${service}->binds:I
invoke-virtual {p1}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v1
const-string v2, "rebind"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :other
const-string v2, "snapshot"
const/4 v3, 0
invoke-virtual {p1, v2, v3}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v2
const/16 v3, 11
if-ne v2, v3, :bad
:other
# Mutation by the service must not change the binding cache key/unbind intent.
const-string v2, "mutated by service"
invoke-virtual {p1, v2}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
const-string v2, "null"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :binder
const/4 v0, 0
return-object v0
:binder
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
return-object v0
' + fail)
	svc += method('public onUnbind(Landroid/content/Intent;)Z', '
invoke-static {}, ${probe}->mainThread()V
sget v0, ${service}->unbinds:I
add-int/lit8 v0, v0, 1
sput v0, ${service}->unbinds:I
invoke-virtual {p1}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v0
const-string v1, "mutated by service"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-nez v1, :bad
const-string v1, "rebind"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
return v0
' + fail)
	os.write_file(dir + '/BindingService.smali', svc)!
	mut connection := '.class public ${conn}\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n.field public calls:I\n.field public nulls:I\n.field public binder:Landroid/os/IBinder;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	connection += method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', '
invoke-static {}, ${probe}->mainThread()V
if-eqz p1, :bad
if-eqz p2, :bad
iget v0, p0, ${conn}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${conn}->calls:I
iput-object p2, p0, ${conn}->binder:Landroid/os/IBinder;
return-void
' + fail)
	connection += method('public onNullBinding(Landroid/content/ComponentName;)V', 'invoke-static {}, ${probe}->mainThread()V\nif-eqz p1, :bad\niget v0, p0, ${conn}->nulls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${conn}->nulls:I\nreturn-void\n' + fail)
	connection += method('public onServiceDisconnected(Landroid/content/ComponentName;)V', 'goto :bad\n' + fail)
	os.write_file(dir + '/BindingConnection.smali', connection)!
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.implements Ljava/util/concurrent/Executor;\n.field private context:Landroid/content/Context;\n.field private stage:I\n'
	for i in 1 .. 10 { text += '.field private c${i}:${conn}\n' }
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	text += method('public static mainThread()V', 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\ninvoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\nif-ne v0, v1, :bad\nreturn-void\n' + fail)
	text += method('public execute(Ljava/lang/Runnable;)V', 'invoke-static {}, ${probe}->mainThread()V\ninvoke-interface {p1}, Ljava/lang/Runnable;->run()V\nreturn-void')
	text += method('private intent(Ljava/lang/String;)Landroid/content/Intent;', 'new-instance v0, Landroid/content/Intent;\ninvoke-direct {v0, p1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V\niget-object v1, p0, ${probe}->context:Landroid/content/Context;\nconst-class v2, ${service}\ninvoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClass(Landroid/content/Context;Ljava/lang/Class;)Landroid/content/Intent;\nconst-string v1, "snapshot"\nconst/16 v2, 11\ninvoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;\nreturn-object v0')
	text += method('public static check(Landroid/content/Context;)V', 'new-instance v0, ${probe}\ninvoke-direct {v0}, ${probe}-><init>()V\niput-object p0, v0, ${probe}->context:Landroid/content/Context;\ninvoke-virtual {v0}, ${probe}->run()V\nreturn-void')
	// Every stage is queued after the framework's lifecycle runnables, without sleeps.
	mut run := 'invoke-static {}, ${probe}->mainThread()V\niget-object v7, p0, ${probe}->context:Landroid/content/Context;\niget v6, p0, ${probe}->stage:I\n'
	for i in 0 .. 9 { run += 'const/16 v0, ${i}\nif-eq v6, v0, :stage${i}\n' }
	run += 'goto :bad\n:stage0\nconst-string v0, "started"\ninvoke-direct {p0, v0}, ${probe}->intent(Ljava/lang/String;)Landroid/content/Intent;\nmove-result-object v0\ninvoke-virtual {v7, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;\n'
	for i, action in ['rebind', 'rebind', 'other', 'null', 'cancelled'] {
		n := i + 1
		run += binding_probe_bind(probe, conn, n, action, n == 2)
		if n == 1 {
			// Snapshot caller extras at bind time and ignore extras for binder identity.
			run += 'const-string v1, "snapshot"\nconst/16 v2, 22\ninvoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;\n'
		}
	}
	run += binding_probe_unbind(probe, 5) + 'const-string v0, "rebind"\ninvoke-direct {p0, v0}, ${probe}->intent(Ljava/lang/String;)Landroid/content/Intent;\nmove-result-object v0\niget-object v1, p0, ${probe}->c1:${conn}\nconst/4 v2, 1\ninvoke-virtual {v7, v0, v1, v2}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z\ngoto :again\n:stage1\n'
	run += binding_probe_counts(service, [1, 3, 0, 0, 0])
	for i in 1 .. 6 {
		field := if i == 4 { 'nulls' } else { 'calls' }
		expected := if i == 5 { 0 } else { 1 }
		run += 'iget-object v0, p0, ${probe}->c${i}:${conn}\niget v1, v0, ${conn}->${field}:I\nconst/4 v2, ${expected}\nif-ne v1, v2, :bad\n'
	}
	run += binding_probe_binders(probe, conn, 1, 2, true) + binding_probe_binders(probe, conn, 1, 3, false)
	run += binding_probe_unbind(probe, 1) + 'goto :again\n:stage2\n' + binding_probe_counts(service, [
		1,
		3,
		0,
		0,
		0,
	])
	for i in [2, 3, 4] { run += binding_probe_unbind(probe, i) }
	run += 'goto :again\n:stage3\n' + binding_probe_counts(service, [1, 3, 3, 0, 0])
	for i, action in ['rebind', 'other', 'null'] {
		run += binding_probe_bind(probe, conn, i + 6, action, i == 0)
	}
	run += 'goto :again\n:stage4\n' + binding_probe_counts(service, [1, 3, 3, 1, 0])
	run += binding_probe_binders(probe, conn, 1, 6, true) + binding_probe_binders(probe, conn, 3, 7, true)
	run += 'iget-object v0, p0, ${probe}->c8:${conn}\niget v1, v0, ${conn}->nulls:I\nconst/4 v2, 1\nif-ne v1, v2, :bad\n'
	for n in [1, 5] {
		run += ':try${n}\n' + binding_probe_unbind(probe, n) + ':end${n}\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:try${n} .. :end${n}} :caught${n}\n:caught${n}\nmove-exception v0\n'
	}
	run += 'const-string v0, "started"\ninvoke-direct {p0, v0}, ${probe}->intent(Ljava/lang/String;)Landroid/content/Intent;\nmove-result-object v0\ninvoke-virtual {v7, v0}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z\nmove-result v0\nif-eqz v0, :bad\ngoto :again\n:stage5\n' + binding_probe_counts(service, [
		1,
		3,
		3,
		1,
		0,
	])
	for i in [6, 7, 8] { run += binding_probe_unbind(probe, i) }
	run += 'goto :again\n:stage6\n' + binding_probe_counts(service, [1, 3, 6, 1, 1]) + binding_probe_bind(probe, conn, 9, 'rebind', false)
	run += 'goto :again\n:stage7\n' + binding_probe_counts(service, [2, 4, 6, 1, 1]) + binding_probe_binders(probe, conn, 1, 9, false) + binding_probe_unbind(probe, 9)
	run += 'goto :again\n:stage8\n' + binding_probe_counts(service, [2, 4, 7, 1, 2]) + '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-SERVICE-BINDINGS-PASS shared-binder intent-filters snapshots multiple-clients duplicate-client null-binding executor pending-cancel unbind rebind started-lifetime destroy-recreate"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:again
add-int/lit8 v6, v6, 1
iput v6, p0, ${probe}->stage:I
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
' + fail
	// There is no ninth stage; preserve a useful failure if sequencing changes.
	run += '\n:stage9\ngoto :bad\n'
	text += method('public run()V', run)
	os.write_file(dir + '/ServiceBindingProbe.smali', text)!
}

fn binding_probe_bind(probe string, conn string, n int, action string, executor bool) string {
	mut text := 'new-instance v1, ${conn}\ninvoke-direct {v1}, ${conn}-><init>()V\niput-object v1, p0, ${probe}->c${n}:${conn}\nconst-string v0, "${action}"\ninvoke-direct {p0, v0}, ${probe}->intent(Ljava/lang/String;)Landroid/content/Intent;\nmove-result-object v0\nconst/4 v2, 1\n'
	text += if executor {
		'invoke-virtual {v7, v0, v2, p0, v1}, Landroid/content/Context;->bindService(Landroid/content/Intent;ILjava/util/concurrent/Executor;Landroid/content/ServiceConnection;)Z\n'
	} else {
		'invoke-virtual {v7, v0, v1, v2}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z\n'
	}
	return text + 'move-result v2\nif-eqz v2, :bad\n'
}

fn binding_probe_unbind(probe string, n int) string {
	return 'iget-object v0, p0, ${probe}->c${n}:Lorg/vinix/bootstrap/BindingConnection;\ninvoke-virtual {v7, v0}, Landroid/content/Context;->unbindService(Landroid/content/ServiceConnection;)V\n'
}

fn binding_probe_counts(service string, counts []int) string {
	mut text := ''
	for i, name in ['created', 'binds', 'unbinds', 'rebinds', 'destroyed'] {
		text += 'sget v0, ${service}->${name}:I\nconst/16 v1, ${counts[i]}\nif-ne v0, v1, :bad\n'
	}
	return text
}

fn binding_probe_binders(probe string, conn string, a int, b int, equal bool) string {
	return 'iget-object v0, p0, ${probe}->c${a}:${conn}\niget-object v0, v0, ${conn}->binder:Landroid/os/IBinder;\niget-object v1, p0, ${probe}->c${b}:${conn}\niget-object v1, v1, ${conn}->binder:Landroid/os/IBinder;\nif-eqz v0, :bad\nif-eqz v1, :bad\nif-${if equal {
		'ne'
	} else {
		'eq'
	}} v0, v1, :bad\n'
}
