// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// These are in-process Binder calls. Remote Binder transport is separate.
fn framework_local_binder(smali string) ! {
	path := smali + '/android/os/Binder.smali'
	mut text := os.read_file(path)!
	text += '\n.field private vinixOwner:Landroid/os/IInterface;\n.field private vinixDescriptor:Ljava/lang/String;\n'
	// Android observes BinderProxy calls only. Local Binder.transact must not
	// notify this listener; this runtime currently has no remote Binder transport.
	text += '\n.field private static volatile vinixProxyTransactListener:Landroid/os/Binder$ProxyTransactListener;\n' +
		'.method public static setProxyTransactListener(Landroid/os/Binder$ProxyTransactListener;)V\n.locals 0\n' +
		'sput-object p0, Landroid/os/Binder;->vinixProxyTransactListener:Landroid/os/Binder$ProxyTransactListener;\nreturn-void\n.end method\n'
	os.write_file(smali + '/android/os/Binder$ProxyTransactListener.smali',
		'.class public interface abstract Landroid/os/Binder$ProxyTransactListener;\n.super Ljava/lang/Object;\n' +
		'.method public abstract onTransactStarted(Landroid/os/IBinder;I)Ljava/lang/Object;\n.end method\n' +
		'.method public abstract onTransactEnded(Ljava/lang/Object;)V\n.end method\n' +
		'.method public onTransactStarted(Landroid/os/IBinder;II)Ljava/lang/Object;\n.locals 1\n' +
		'invoke-interface {p0, p1, p2}, Landroid/os/Binder$ProxyTransactListener;->onTransactStarted(Landroid/os/IBinder;I)Ljava/lang/Object;\n' +
		'move-result-object v0\nreturn-object v0\n.end method\n')!
	methods := {
		'attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V': '.locals 0
iput-object p1, p0, Landroid/os/Binder;->vinixOwner:Landroid/os/IInterface;
iput-object p2, p0, Landroid/os/Binder;->vinixDescriptor:Ljava/lang/String;
return-void'
		'equals(Ljava/lang/Object;)Z': '.locals 1
const/4 v0, 0
if-ne p0, p1, :done
const/4 v0, 1
:done
return v0'
		'queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;': '.locals 1
iget-object v0, p0, Landroid/os/Binder;->vinixDescriptor:Ljava/lang/String;
if-eqz v0, :absent
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :absent
iget-object v0, p0, Landroid/os/Binder;->vinixOwner:Landroid/os/IInterface;
return-object v0
:absent
const/4 v0, 0
return-object v0'
		'transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z': '.locals 2
const/4 v0, 0
if-eqz p2, :dispatch
invoke-virtual {p2, v0}, Landroid/os/Parcel;->setDataPosition(I)V
:dispatch
invoke-virtual {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v1
if-eqz p3, :done
invoke-virtual {p3, v0}, Landroid/os/Parcel;->setDataPosition(I)V
:done
return v1'
	}
	for signature, body in methods {
		text = framework_replace_method(text, signature, '.method public ' + signature + '\n' + body + '\n.end method')!
	}
	text += '
.method protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
.locals 1
const v0, 0x5f4e5446
if-ne p1, v0, :unknown
iget-object v0, p0, Landroid/os/Binder;->vinixDescriptor:Ljava/lang/String;
invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
const/4 v0, 1
return v0
:unknown
const/4 v0, 0
return v0
.end method

.method public getInterfaceDescriptor()Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/os/Binder;->vinixDescriptor:Ljava/lang/String;
return-object v0
.end method

.method public pingBinder()Z
.locals 1
const/4 v0, 1
return v0
.end method

.method public isBinderAlive()Z
.locals 1
const/4 v0, 1
return v0
.end method

.method public linkToDeath(Landroid/os/IBinder$DeathRecipient;I)V
.locals 0
return-void
.end method

.method public unlinkToDeath(Landroid/os/IBinder$DeathRecipient;I)Z
.locals 1
const/4 v0, 1
return v0
.end method
'
	os.write_file(path, text)!
	interface_path := smali + '/android/os/IBinder.smali'
	mut interface_text := os.read_file(interface_path)!
	for signature in ['getInterfaceDescriptor()Ljava/lang/String;', 'pingBinder()Z', 'isBinderAlive()Z',
		'linkToDeath(Landroid/os/IBinder$DeathRecipient;I)V', 'unlinkToDeath(Landroid/os/IBinder$DeathRecipient;I)Z'] {
		if interface_text.contains('.method public abstract ' + signature) { return error('Binder interface already declares ' + signature) }
		interface_text += '\n.method public abstract ' + signature + '\n.end method\n'
	}
	os.write_file(interface_path, interface_text)!
}
