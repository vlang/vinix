// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Binding callbacks run on the main looper. Registration/cancellation can come
// from other threads; cancel pending requests before their runnable executes.
fn framework_service_bindings(smali string) ! {
	service := 'Landroid/app/Service;'
	binding := 'Landroid/atl/VinixServiceBinding;'
	record := 'Landroid/atl/VinixServiceBindingRecord;'
	list := 'Ljava/util/ArrayList;'
	path := smali + '/android/app/Service.smali'
	mut text := os.read_file(path)! + '\n.field public vinixBindings:Ljava/util/HashMap;\n.field public vinixStarted:Z\n'
	text += service_binding_method('public onUnbind(Landroid/content/Intent;)Z', 'const/4 v0, 0\nreturn v0')
	text += service_binding_method('public onRebind(Landroid/content/Intent;)V', 'return-void')
	os.write_file(path, text)!
	os.write_file(smali + '/android/atl/VinixServiceBindingRecord.smali', '.class public final ${record}\n.super Ljava/lang/Object;\n' +
		'.field public intent:Landroid/content/Intent;\n.field public binder:Landroid/os/IBinder;\n.field public clients:${list}\n.field public rebind:Z\n' +
		service_binding_method('public constructor <init>(Landroid/content/Intent;)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
			'invoke-virtual {p1}, Landroid/content/Intent;->cloneFilter()Landroid/content/Intent;\nmove-result-object v0\niput-object v0, p0, ${record}->intent:Landroid/content/Intent;\n' +
			'new-instance v0, ${list}\ninvoke-direct {v0}, ${list}-><init>()V\niput-object v0, p0, ${record}->clients:${list}\nreturn-void'))!
	mut body := '.class public final ${binding}\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n.implements Ljava/lang/Runnable;\n' +
		'.field private static final requests:${list}\n.field public volatile active:Z\n.field private context:Landroid/content/Context;\n' +
		'.field private key:Landroid/content/ServiceConnection;\n.field private callback:Landroid/content/ServiceConnection;\n' +
		'.field private service:${service}\n.field private record:${record}\n' +
		service_binding_method('static constructor <clinit>()V', 'new-instance v0, ${list}\ninvoke-direct {v0}, ${list}-><init>()V\nsput-object v0, ${binding}->requests:${list}\nreturn-void') +
		service_binding_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/4 v0, 1\niput-boolean v0, p0, ${binding}->active:Z\nreturn-void') +
		service_binding_method('private static key(Landroid/content/ServiceConnection;)Landroid/content/ServiceConnection;', '
instance-of v0, p0, Landroid/content/VinixServiceConnection;
if-eqz v0, :done
check-cast p0, Landroid/content/VinixServiceConnection;
invoke-virtual {p0}, Landroid/content/VinixServiceConnection;->vinixConnection()Landroid/content/ServiceConnection;
move-result-object p0
:done
return-object p0') +
		service_binding_method('public static synchronized register(Landroid/content/Context;Landroid/content/ServiceConnection;)${binding}', '
new-instance v0, ${binding}
invoke-direct {v0}, ${binding}-><init>()V
iput-object p0, v0, ${binding}->context:Landroid/content/Context;
iput-object p1, v0, ${binding}->callback:Landroid/content/ServiceConnection;
invoke-static {p1}, ${binding}->key(Landroid/content/ServiceConnection;)Landroid/content/ServiceConnection;
move-result-object v1
iput-object v1, v0, ${binding}->key:Landroid/content/ServiceConnection;
sget-object v1, ${binding}->requests:${list}
invoke-virtual {v1, v0}, ${list}->add(Ljava/lang/Object;)Z
return-object v0') +
		service_binding_method('public static synchronized abandon(${binding})V', 'const/4 v0, 0\niput-boolean v0, p0, ${binding}->active:Z\nsget-object v0, ${binding}->requests:${list}\ninvoke-virtual {v0, p0}, ${list}->remove(Ljava/lang/Object;)Z\nreturn-void') +
		service_binding_method('public static synchronized unbind(Landroid/content/Context;Landroid/content/ServiceConnection;)V', '
if-eqz p1, :bad
invoke-static {p1}, ${binding}->key(Landroid/content/ServiceConnection;)Landroid/content/ServiceConnection;
move-result-object p1
sget-object v0, ${binding}->requests:${list}
invoke-virtual {v0}, ${list}->size()I
move-result v1
const/4 v2, 0
new-instance v3, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v4
invoke-direct {v3, v4}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
:next
add-int/lit8 v1, v1, -1
if-ltz v1, :done
invoke-virtual {v0, v1}, ${list}->get(I)Ljava/lang/Object;
move-result-object v4
check-cast v4, ${binding}
iget-object v5, v4, ${binding}->context:Landroid/content/Context;
if-ne p0, v5, :next
iget-object v5, v4, ${binding}->key:Landroid/content/ServiceConnection;
if-ne p1, v5, :next
invoke-virtual {v0, v1}, ${list}->remove(I)Ljava/lang/Object;
const/4 v5, 0
iput-boolean v5, v4, ${binding}->active:Z
invoke-virtual {v3, v4}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
const/4 v2, 1
goto :next
:done
if-nez v2, :return
:bad
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Service not registered"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:return
return-void') +
		service_binding_method('public static connect(${service}Landroid/content/Intent;Landroid/content/ServiceConnection;)V', '
check-cast p2, ${binding}
iget-boolean v0, p2, ${binding}->active:Z
if-eqz v0, :done
iget-object v0, p0, ${service}->vinixBindings:Ljava/util/HashMap;
if-nez v0, :map
new-instance v0, Ljava/util/HashMap;
invoke-direct {v0}, Ljava/util/HashMap;-><init>()V
iput-object v0, p0, ${service}->vinixBindings:Ljava/util/HashMap;
:map
invoke-virtual {p1}, Landroid/content/Intent;->cloneFilter()Landroid/content/Intent;
move-result-object v1
new-instance v2, Landroid/content/Intent$FilterComparison;
invoke-direct {v2, v1}, Landroid/content/Intent$FilterComparison;-><init>(Landroid/content/Intent;)V
invoke-virtual {v0, v2}, Ljava/util/HashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v1
check-cast v1, ${record}
if-nez v1, :existing
new-instance v1, ${record}
invoke-direct {v1, p1}, ${record}-><init>(Landroid/content/Intent;)V
invoke-virtual {v0, v2, v1}, Ljava/util/HashMap;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p0, p1}, ${service}->onBind(Landroid/content/Intent;)Landroid/os/IBinder;
move-result-object v0
iput-object v0, v1, ${record}->binder:Landroid/os/IBinder;
goto :attach
:existing
iget-object v0, v1, ${record}->clients:${list}
invoke-virtual {v0}, ${list}->size()I
move-result v2
if-nez v2, :attach
iget-boolean v2, v1, ${record}->rebind:Z
if-eqz v2, :attach
const/4 v2, 0
iput-boolean v2, v1, ${record}->rebind:Z
invoke-virtual {p0, p1}, ${service}->onRebind(Landroid/content/Intent;)V
:attach
iput-object p0, p2, ${binding}->service:${service}
iput-object v1, p2, ${binding}->record:${record}
iget-object v0, v1, ${record}->clients:${list}
invoke-virtual {v0}, ${list}->iterator()Ljava/util/Iterator;
move-result-object v2
:duplicates
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v3
if-eqz v3, :add
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v3
check-cast v3, ${binding}
iget-boolean v4, v3, ${binding}->active:Z
if-eqz v4, :duplicates
iget-object v4, v3, ${binding}->context:Landroid/content/Context;
iget-object v5, p2, ${binding}->context:Landroid/content/Context;
if-ne v4, v5, :duplicates
iget-object v4, v3, ${binding}->key:Landroid/content/ServiceConnection;
iget-object v5, p2, ${binding}->key:Landroid/content/ServiceConnection;
if-eq v4, v5, :done
goto :duplicates
:add
invoke-virtual {v0, p2}, ${list}->add(Ljava/lang/Object;)Z
iget-boolean v0, p2, ${binding}->active:Z
if-eqz v0, :done
invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
iget-object v2, v1, ${record}->binder:Landroid/os/IBinder;
iget-object v3, p2, ${binding}->callback:Landroid/content/ServiceConnection;
if-eqz v2, :null
invoke-interface {v3, v0, v2}, Landroid/content/ServiceConnection;->onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V
goto :done
:null
invoke-interface {v3, v0}, Landroid/content/ServiceConnection;->onNullBinding(Landroid/content/ComponentName;)V
:done
return-void') +
		service_binding_method('public run()V', '
iget-object v0, p0, ${binding}->record:${record}
if-eqz v0, :done
iget-object v1, v0, ${record}->clients:${list}
invoke-virtual {v1, p0}, ${list}->remove(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :clear
invoke-virtual {v1}, ${list}->isEmpty()Z
move-result v1
if-eqz v1, :clear
iget-object v1, p0, ${binding}->service:${service}
iget-object v2, v0, ${record}->intent:Landroid/content/Intent;
invoke-virtual {v1, v2}, ${service}->onUnbind(Landroid/content/Intent;)Z
move-result v2
iput-boolean v2, v0, ${record}->rebind:Z
invoke-static {v1}, ${binding}->maybeDestroy(${service})V
:clear
const/4 v0, 0
iput-object v0, p0, ${binding}->record:${record}
iput-object v0, p0, ${binding}->service:${service}
:done
return-void') +
		service_binding_method('public static maybeDestroy(${service})V', '
iget-boolean v0, p0, ${service}->vinixStarted:Z
if-nez v0, :done
iget-object v0, p0, ${service}->vinixBindings:Ljava/util/HashMap;
if-eqz v0, :destroy
invoke-virtual {v0}, Ljava/util/HashMap;->values()Ljava/util/Collection;
move-result-object v0
invoke-interface {v0}, Ljava/util/Collection;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :destroy
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, ${record}
iget-object v1, v1, ${record}->clients:${list}
invoke-virtual {v1}, ${list}->isEmpty()Z
move-result v1
if-eqz v1, :done
goto :next
:destroy
invoke-virtual {p0}, ${service}->get_atl_loaded_app()Landroid/atl/ATLLoadedApp;
move-result-object v0
invoke-static {v0}, Landroid/atl/ATLLoadedApp;->access$000(Landroid/atl/ATLLoadedApp;)Ljava/util/HashMap;
move-result-object v0
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/util/HashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v2
if-ne v2, p0, :done
invoke-virtual {v0, v1}, Ljava/util/HashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p0}, ${service}->onDestroy()V
:done
return-void')
	for signature in [
		'onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V',
		'onServiceDisconnected(Landroid/content/ComponentName;)V',
	] {
		body += service_binding_method('public ' + signature, 'return-void')
	}
	os.write_file(smali + '/android/atl/VinixServiceBinding.smali', body)!
	// Keep resolution and service construction in ATL; replace only dispatch.
	runnable := smali + '/android/atl/ATLLoadedApp$1.smali'
	mut run := os.read_file(runnable)!
	begin := run.index('    iget-object v1, p0, Landroid/atl/ATLLoadedApp$1;->val$serviceConnection:Landroid/content/ServiceConnection;\n\n    if-eqz v1, :cond_6a') or { return error('service dispatch anchor') }
	end := run.index('    :goto_69') or { return error('service return anchor') }
	run = run[..begin] + '    iget-object v1, p0, Landroid/atl/ATLLoadedApp$1;->val$serviceConnection:Landroid/content/ServiceConnection;\n    if-eqz v1, :cond_6a\n' +
		'    iget-object v2, p0, Landroid/atl/ATLLoadedApp$1;->val$intent:Landroid/content/Intent;\n    invoke-static {v0, v2, v1}, ${binding}->connect(${service}Landroid/content/Intent;Landroid/content/ServiceConnection;)V\n' + run[end..]
	run = run.replace('    :try_start_0\n', '    :try_start_0\n    iget-object v0, p0, Landroid/atl/ATLLoadedApp$1;->val$serviceConnection:Landroid/content/ServiceConnection;\n    if-eqz v0, :active\n    check-cast v0, ${binding}\n    iget-boolean v0, v0, ${binding}->active:Z\n    if-nez v0, :active\n    return-void\n    :active\n')
	run = run.replace('    :cond_6a\n', '    :cond_6a\n    const/4 v1, 1\n    iput-boolean v1, v0, ${service}->vinixStarted:Z\n')
	os.write_file(runnable, run)!
	// Snapshot the resolved intent before it is queued or exposed to a service.
	app := smali + '/android/atl/ATLLoadedApp.smali'
	mut app_text := os.read_file(app)!
	anchor := '    :cond_70\n    invoke-virtual {v0}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;'
	if app_text.count(anchor) != 1 { return error('service resolution anchor') }
	app_text = app_text.replace(anchor, '    :cond_70\n    new-instance v4, Landroid/content/Intent;\n    invoke-direct {v4, p1}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V\n    invoke-virtual {v4, v0}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;\n    move-object p1, v4\n    invoke-virtual {v0}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;')
	app_text = app_text.replace('    invoke-virtual {v0}, Landroid/app/Service;->onDestroy()V\n\n    iget-object v0, p0, Landroid/atl/ATLLoadedApp;->running_services:Ljava/util/HashMap;\n\n    invoke-virtual {v0, v1}, Ljava/util/HashMap;->remove(Ljava/lang/Object;)Ljava/lang/Object;', '    const/4 v1, 0\n    iput-boolean v1, v0, ${service}->vinixStarted:Z\n    invoke-static {v0}, ${binding}->maybeDestroy(${service})V')
	os.write_file(app, app_text)!
	context := smali + '/android/app/ContextImpl.smali'
	mut ctx := os.read_file(context)!
	ctx = framework_replace_method(ctx, 'bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z', '.method public bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
.locals 3
if-nez p2, :lookup
new-instance v0, Ljava/lang/IllegalArgumentException;
invoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V
throw v0
:lookup
invoke-direct {p0, p1}, Landroid/app/ContextImpl;->atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;
move-result-object v0
if-eqz v0, :missing
invoke-static {p0, p2}, ${binding}->register(Landroid/content/Context;Landroid/content/ServiceConnection;)${binding}
move-result-object v1
invoke-virtual {v0, p1, v1}, Landroid/atl/ATLLoadedApp;->startOrBindService(Landroid/content/Intent;Landroid/content/ServiceConnection;)Landroid/content/ComponentName;
move-result-object v0
if-eqz v0, :abandon
const/4 v0, 1
return v0
:abandon
invoke-static {v1}, ${binding}->abandon(${binding})V
:missing
const/4 v0, 0
return v0
.end method')!
	ctx += service_binding_method('public unbindService(Landroid/content/ServiceConnection;)V', 'invoke-static {p0, p1}, ${binding}->unbind(Landroid/content/Context;Landroid/content/ServiceConnection;)V\nreturn-void')
	os.write_file(context, ctx)!
	wrapper := smali + '/android/content/ContextWrapper.smali'
	os.write_file(wrapper, os.read_file(wrapper)! + service_binding_method('public unbindService(Landroid/content/ServiceConnection;)V', 'iget-object v0, p0, Landroid/content/ContextWrapper;->baseContext:Landroid/content/Context;\ninvoke-virtual {v0, p1}, Landroid/content/Context;->unbindService(Landroid/content/ServiceConnection;)V\nreturn-void'))!
	executor := smali + '/android/content/VinixServiceConnection.smali'
	os.write_file(executor, os.read_file(executor)! + service_binding_method('public vinixConnection()Landroid/content/ServiceConnection;', 'iget-object v0, p0, Landroid/content/VinixServiceConnection;->connection:Landroid/content/ServiceConnection;\nreturn-object v0'))!
}

fn service_binding_method(signature string, body string) string {
	return '\n.method ${signature}\n.locals 6\n${body}\n.end method\n'
}
