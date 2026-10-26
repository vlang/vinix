// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

pub fn install_service_stop_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/ServiceStopProbe;'
	service := 'Lorg/vinix/bootstrap/ServiceStopService;'
	worker := 'Lorg/vinix/bootstrap/ServiceStopWorker;'
	connection := 'Lorg/vinix/bootstrap/ServiceStopConnection;'
	bad := '\n:bad\nnew-instance v8, Ljava/lang/AssertionError;\nconst-string v9, "service stop result, ordering or destruction count"\ninvoke-direct {v8, v9}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v8'
	mut svc := '.class public ${service}\n.super Landroid/app/Service;\n.field private wasDestroyed:Z\n.field public static failDestroy:Z\n.field public static failure:Ljava/lang/IllegalStateException;\n'
	for name in ['created', 'started', 'binds', 'unbinds', 'destroyed'] {
		svc += '.field public static ${name}:I\n'
	}
	svc += service_stop_method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void')
	for name, signature in {
		'created': 'onCreate()V'
		'started': 'onStartCommand(Landroid/content/Intent;II)I'
		'binds': 'onBind(Landroid/content/Intent;)Landroid/os/IBinder;'
		'unbinds': 'onUnbind(Landroid/content/Intent;)Z'
		'destroyed': 'onDestroy()V'
	} {
		mut body := 'invoke-static {}, ${probe}->mainThread()V\n'
		if name == 'destroyed' {
			body += 'iget-boolean v0, p0, ${service}->wasDestroyed:Z\nif-nez v0, :bad\nconst/4 v0, 1\niput-boolean v0, p0, ${service}->wasDestroyed:Z\n'
		}
		body += 'sget v0, ${service}->${name}:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${service}->${name}:I\n'
		body += match name {
			'started' { 'const/4 v0, 2\nreturn v0' }
			'binds' { 'new-instance v0, Landroid/os/Binder;\ninvoke-direct {v0}, Landroid/os/Binder;-><init>()V\nreturn-object v0' }
			'unbinds' { 'const/4 v0, 0\nreturn v0' }
			'destroyed' { 'sget-boolean v0, ${service}->failDestroy:Z\nif-eqz v0, :done\nsget-object v0, ${service}->failure:Ljava/lang/IllegalStateException;\nthrow v0\n:done\nreturn-void' + bad }
			else { 'return-void' }
		}
		svc += service_stop_method('public ' + signature, body)
	}
	os.write_file(dir + '/ServiceStopService.smali', svc)!
	mut conn := '.class public ${connection}\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n.field public calls:I\n'
	conn += service_stop_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	conn += service_stop_method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', 'invoke-static {}, ${probe}->mainThread()V\nif-eqz p1, :bad\nif-eqz p2, :bad\niget v0, p0, ${connection}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${connection}->calls:I\nreturn-void' + bad)
	conn += service_stop_method('public onServiceDisconnected(Landroid/content/ComponentName;)V', 'goto :bad' + bad)
	os.write_file(dir + '/ServiceStopConnection.smali', conn)!
	mut task := '.class public ${worker}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private owner:${probe}\n.field private mode:I\n.field public failure:Ljava/lang/Throwable;\n'
	task += service_stop_method('public constructor <init>(${probe}I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${worker}->owner:${probe}\niput p2, p0, ${worker}->mode:I\nreturn-void')
	task += service_stop_method('public run()V', '
iget-object v6, p0, ${worker}->owner:${probe}
iget-object v7, v6, ${probe}->context:Landroid/content/Context;
iget v5, p0, ${worker}->mode:I
:try_start
if-nez v5, :intent
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->interrupt()V
:intent
invoke-static {v7}, ${probe}->intent(Landroid/content/Context;)Landroid/content/Intent;
move-result-object v4
const/4 v0, 2
if-eq v5, v0, :exception
invoke-virtual {v7, v4}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v7, v4}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v0
const/4 v1, 1
if-eq v5, v1, :bound
if-nez v0, :bad
goto :interruption
:bound
if-eqz v0, :bad
goto :interruption
:exception
:stop_start
invoke-virtual {v7, v4}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
:stop_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:stop_start .. :stop_end} :expected
:expected
move-exception v0
sget-object v1, ${service}->failure:Ljava/lang/IllegalStateException;
if-ne v0, v1, :bad
invoke-virtual {v7, v4}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v0
if-nez v0, :bad
:interruption
if-nez v5, :done
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->isInterrupted()Z
move-result v0
if-eqz v0, :bad
invoke-static {}, Ljava/lang/Thread;->interrupted()Z
:done
goto :post
' + bad + '
:try_end
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v0
iput-object v0, p0, ${worker}->failure:Ljava/lang/Throwable;
:post
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, v6}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void')
	os.write_file(dir + '/ServiceStopWorker.smali', task)!
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field public context:Landroid/content/Context;\n.field private stage:I\n.field private worker:${worker}\n.field private connection:${connection}\n'
	text += service_stop_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	text += service_stop_method('public static mainThread()V', 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\ninvoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\nif-eq v0, v1, :done\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "service lifecycle must run on main looper"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n:done\nreturn-void')
	text += service_stop_method('public static intent(Landroid/content/Context;)Landroid/content/Intent;', 'new-instance v0, Landroid/content/Intent;\ninvoke-direct {v0}, Landroid/content/Intent;-><init>()V\nconst-class v1, ${service}\ninvoke-virtual {v0, p0, v1}, Landroid/content/Intent;->setClass(Landroid/content/Context;Ljava/lang/Class;)Landroid/content/Intent;\nreturn-object v0')
	text += service_stop_method('public static check(Landroid/content/Context;)V', 'new-instance v0, ${probe}\ninvoke-direct {v0}, ${probe}-><init>()V\niput-object p0, v0, ${probe}->context:Landroid/content/Context;\ninvoke-virtual {v0}, ${probe}->run()V\nreturn-void')
	text += service_stop_method('private advance()V', 'iget v0, p0, ${probe}->stage:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${probe}->stage:I\nreturn-void')
	text += service_stop_method('private launch(I)V', 'invoke-direct {p0}, ${probe}->advance()V\nnew-instance v0, ${worker}\ninvoke-direct {v0, p0, p1}, ${worker}-><init>(${probe}I)V\niput-object v0, p0, ${probe}->worker:${worker}\nnew-instance v1, Ljava/lang/Thread;\ninvoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V\ninvoke-virtual {v1}, Ljava/lang/Thread;->start()V\nreturn-void')
	mut run := 'invoke-static {}, ${probe}->mainThread()V\niget-object v7, p0, ${probe}->context:Landroid/content/Context;\niget-object v0, p0, ${probe}->worker:${worker}\nif-eqz v0, :stage\niget-object v0, v0, ${worker}->failure:Ljava/lang/Throwable;\nif-eqz v0, :stage\nthrow v0\n:stage\niget v6, p0, ${probe}->stage:I\n'
	for n in 0 .. 7 { run += 'const/4 v0, ${n}\nif-eq v6, v0, :stage${n}\n' }
	run += 'goto :bad\n:stage0\n' + service_stop_marker('SERVICE-STOP-BEGIN') + service_stop_counts(service, [0, 0, 0, 0, 0]) + '
invoke-static {v7}, ${probe}->intent(Landroid/content/Context;)Landroid/content/Intent;
move-result-object v0
invoke-virtual {v7, v0}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v0
if-nez v0, :bad
' + service_stop_start(probe) + 'goto :again\n:stage1\n' + service_stop_counts(service, [1, 1, 0, 0, 0]) + '
const/4 v0, 0
invoke-direct {p0, v0}, ${probe}->launch(I)V
return-void
:stage2
' + service_stop_counts(service, [1, 1, 0, 0, 1]) + service_stop_marker('SERVICE-STOP-WORKER-PASS') + service_stop_start(probe) + '
# These main-looper start and bind messages precede the worker stop request.
new-instance v1, ${connection}
invoke-direct {v1}, ${connection}-><init>()V
iput-object v1, p0, ${probe}->connection:${connection}
invoke-static {v7}, ${probe}->intent(Landroid/content/Context;)Landroid/content/Intent;
move-result-object v0
const/4 v2, 1
invoke-virtual {v7, v0, v1, v2}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
move-result v0
if-eqz v0, :bad
const/4 v0, 1
invoke-direct {p0, v0}, ${probe}->launch(I)V
return-void
:stage3
' + service_stop_counts(service, [2, 2, 1, 0, 1]) + '
iget-object v0, p0, ${probe}->connection:${connection}
iget v1, v0, ${connection}->calls:I
const/4 v2, 1
if-ne v1, v2, :bad
invoke-static {v7}, ${probe}->intent(Landroid/content/Context;)Landroid/content/Intent;
move-result-object v1
invoke-virtual {v7, v1}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v7, v0}, Landroid/content/Context;->unbindService(Landroid/content/ServiceConnection;)V
goto :again
:stage4
' + service_stop_counts(service, [2, 2, 1, 1, 2]) + service_stop_marker('SERVICE-STOP-BOUND-PASS') + service_stop_start(probe) + '
const/4 v0, 0
invoke-direct {p0, v0}, ${probe}->launch(I)V
return-void
:stage5
' + service_stop_counts(service, [3, 3, 1, 1, 3]) + service_stop_marker('SERVICE-STOP-RESTART-PASS') + '
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "expected service teardown exception"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
sput-object v0, ${service}->failure:Ljava/lang/IllegalStateException;
const/4 v0, 1
sput-boolean v0, ${service}->failDestroy:Z
' + service_stop_start(probe) + '
const/4 v0, 2
invoke-direct {p0, v0}, ${probe}->launch(I)V
return-void
:stage6
' + service_stop_counts(service, [4, 4, 1, 1, 4]) + service_stop_marker('SERVICE-STOP-EXCEPTION-PASS') + service_stop_marker('SERVICE-STOP-PASS') + '
return-void
:again
invoke-direct {p0}, ${probe}->advance()V
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
' + bad
	text += service_stop_method('public run()V', run)
	os.write_file(dir + '/ServiceStopProbe.smali', text)!
}

fn service_stop_method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

fn service_stop_marker(marker string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${marker}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn service_stop_counts(service string, values []int) string {
	mut body := ''
	for i, name in ['created', 'started', 'binds', 'unbinds', 'destroyed'] {
		body += 'sget v0, ${service}->${name}:I\nconst/4 v1, ${values[i]}\nif-ne v0, v1, :bad\n'
	}
	return body
}

fn service_stop_start(probe string) string {
	return 'invoke-static {v7}, ${probe}->intent(Landroid/content/Context;)Landroid/content/Intent;\nmove-result-object v0\ninvoke-virtual {v7, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;\nmove-result-object v0\nif-eqz v0, :bad\n'
}
