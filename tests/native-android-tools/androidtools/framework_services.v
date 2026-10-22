// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_companion_contexts(smali string) ! {
	provider := smali + '/android/content/ContentProvider.smali'
	mut text := os.read_file(provider)! + '\n.field private vinixContext:Landroid/content/Context;\n'
	text = framework_replace_method(text, 'getContext()Landroid/content/Context;', '.method public getContext()Landroid/content/Context;
.locals 1
iget-object v0, p0, Landroid/content/ContentProvider;->vinixContext:Landroid/content/Context;
return-object v0
.end method')!
	// Android attaches the owning package context before calling onCreate, once.
	text = framework_replace_method(text, 'attachInfo(Landroid/content/Context;Landroid/content/pm/ProviderInfo;)V', '.method public attachInfo(Landroid/content/Context;Landroid/content/pm/ProviderInfo;)V
.locals 1
iget-object v0, p0, Landroid/content/ContentProvider;->vinixContext:Landroid/content/Context;
if-nez v0, :done
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iput-object p1, p0, Landroid/content/ContentProvider;->vinixContext:Landroid/content/Context;
invoke-virtual {p0}, Landroid/content/ContentProvider;->onCreate()Z
:done
return-void
.end method')!
	os.write_file(provider, text)!
	context := smali + '/android/content/Context.smali'
	os.write_file(context, os.read_file(context)! + '
.method public bindService(Landroid/content/Intent;ILjava/util/concurrent/Executor;Landroid/content/ServiceConnection;)Z
.locals 1
invoke-static {p3}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
if-nez p4, :connection
new-instance v0, Ljava/lang/IllegalArgumentException;
invoke-direct {v0}, Ljava/lang/IllegalArgumentException;-><init>()V
throw v0
:connection
new-instance v0, Landroid/content/VinixServiceConnection;
invoke-direct {v0, p3, p4}, Landroid/content/VinixServiceConnection;-><init>(Ljava/util/concurrent/Executor;Landroid/content/ServiceConnection;)V
invoke-virtual {p0, p1, v0, p2}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
move-result v0
return v0
.end method
')!
	connection := smali + '/android/content/ServiceConnection.smali'
	mut iface := os.read_file(connection)!
	if !iface.contains('onServiceDisconnected(') {
		iface += '\n.method public abstract onServiceDisconnected(Landroid/content/ComponentName;)V\n.end method\n'
	}
	for name in ['onBindingDied', 'onNullBinding'] {
		if !iface.contains(name + '(') {
			iface += '\n.method public ' + name + '(Landroid/content/ComponentName;)V\n.locals 0\nreturn-void\n.end method\n'
		}
	}
	os.write_file(connection, iface)!
	mut wrapper := '.class public final Landroid/content/VinixServiceConnection;\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n' +
		'.field private final executor:Ljava/util/concurrent/Executor;\n.field private final connection:Landroid/content/ServiceConnection;\n' +
		'.method public constructor <init>(Ljava/util/concurrent/Executor;Landroid/content/ServiceConnection;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/content/VinixServiceConnection;->executor:Ljava/util/concurrent/Executor;
iput-object p2, p0, Landroid/content/VinixServiceConnection;->connection:Landroid/content/ServiceConnection;
return-void
.end method
'
	mut event := '.class public final Landroid/content/VinixServiceEvent;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
		'.field public connection:Landroid/content/ServiceConnection;\n.field public component:Landroid/content/ComponentName;\n.field public binder:Landroid/os/IBinder;\n.field public event:I\n' +
		'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
		'.method public run()V\n.locals 4\niget-object v0, p0, Landroid/content/VinixServiceEvent;->connection:Landroid/content/ServiceConnection;\n' +
		'iget-object v1, p0, Landroid/content/VinixServiceEvent;->component:Landroid/content/ComponentName;\niget v2, p0, Landroid/content/VinixServiceEvent;->event:I\n'
	for index, name in ['onServiceConnected', 'onServiceDisconnected', 'onBindingDied', 'onNullBinding'] {
		signature := name + '(Landroid/content/ComponentName;' + if index == 0 { 'Landroid/os/IBinder;)V' } else { ')V' }
		wrapper += '.method public ' + signature + '\n.locals 3\nnew-instance v0, Landroid/content/VinixServiceEvent;\n' +
			'invoke-direct {v0}, Landroid/content/VinixServiceEvent;-><init>()V\n' +
			'iget-object v1, p0, Landroid/content/VinixServiceConnection;->connection:Landroid/content/ServiceConnection;\n' +
			'iput-object v1, v0, Landroid/content/VinixServiceEvent;->connection:Landroid/content/ServiceConnection;\n' +
			'iput-object p1, v0, Landroid/content/VinixServiceEvent;->component:Landroid/content/ComponentName;\n' +
			'const/4 v2, ' + index.str() + '\niput v2, v0, Landroid/content/VinixServiceEvent;->event:I\n'
		if index == 0 { wrapper += 'iput-object p2, v0, Landroid/content/VinixServiceEvent;->binder:Landroid/os/IBinder;\n' }
		wrapper += 'iget-object v1, p0, Landroid/content/VinixServiceConnection;->executor:Ljava/util/concurrent/Executor;\n' +
			'invoke-interface {v1, v0}, Ljava/util/concurrent/Executor;->execute(Ljava/lang/Runnable;)V\nreturn-void\n.end method\n'
		event += 'const/4 v3, ' + index.str() + '\nif-ne v2, v3, :next' + index.str() + '\n'
		if index == 0 {
			event += 'iget-object v2, p0, Landroid/content/VinixServiceEvent;->binder:Landroid/os/IBinder;\n' +
				'invoke-interface {v0, v1, v2}, Landroid/content/ServiceConnection;->' + signature + '\n'
		} else { event += 'invoke-interface {v0, v1}, Landroid/content/ServiceConnection;->' + signature + '\n' }
		event += 'return-void\n:next' + index.str() + '\n'
	}
	event += 'return-void\n.end method\n'
	os.write_file(smali + '/android/content/VinixServiceConnection.smali', wrapper)!
	os.write_file(smali + '/android/content/VinixServiceEvent.smali', event)!
}
