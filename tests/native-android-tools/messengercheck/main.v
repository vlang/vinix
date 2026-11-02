// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

const targets = ['android/os/IMessenger.smali', 'android/os/Messenger.smali',
	'android/os/Messenger$1.smali', 'android/os/Handler$MessengerImpl.smali', 'android/os/Message.smali']
const additions = ['android/os/IMessenger$Stub.smali', 'android/os/IMessenger$Stub$Proxy.smali',
	'android/os/VinixMessageCreator.smali']
const sentinels = ['android/os/Handler.smali', 'android/os/Binder.smali', 'android/os/Parcel.smali']

fn norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || block.count('.end method') != 1 {
			return error('unique complete methods required')
		}
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn metadata(source string) !string {
	mut rest := source
	for _, body in methods(source)! { rest = rest.replace(body, '') }
	lines := norm(rest).split_into_lines()
	return lines.filter(!it.starts_with('.field ')).join('\n') + '\n' + lines.filter(it.starts_with('.field ')).sorted().join('\n')
}

// Labels and exception ranges compare by instruction position, including
// adjacent aliases and catches moved beside the end label by baksmali.
fn flow(source string) !string {
	lines := norm(source).split_into_lines()
	mut labels := map[string]string{}
	mut position := 0
	for line in lines {
		if line.starts_with(':') {
			labels[line] = ':i' + position.str()
		} else if !line.starts_with('.catch') {
			position++
		}
	}
	mut result := []string{}
	mut catches := []string{}
	for raw_line in lines {
		line := if raw_line.starts_with('const-string ') {
			raw_line.replace("\\'", "'")
		} else {
			raw_line
		}
		if line in labels { continue }
		if line.starts_with('.catch') {
			parts := line.fields()
			typed := parts[0] == '.catch'
			if parts.len != if typed { 6 } else { 5 } {
				return error('canonical exception handler required')
			}
			offset := if typed { 1 } else { 0 }
			start, end, handler := parts[1 + offset].trim_left('{'), parts[3 + offset].trim_right('}'), parts[4 + offset]
			if start !in labels || end !in labels || handler !in labels {
				return error('missing exception label')
			}
			catches << parts[..1 + offset].join(' ') + ' {' + labels[start] + ' .. ' + labels[end] + '} ' + labels[handler]
			continue
		}
		last := line.fields().last()
		if line.starts_with('if-') || line.starts_with('goto') {
			if last !in labels { return error('missing branch label') }
			result << line[..line.len - last.len] + labels[last]
		} else {
			result << line
		}
	}
	return result.join('\n') + '\n' + catches.sorted().join('\n')
}

fn m(header string, registers int, body string) string {
	return '.method ' + header + '\n.registers ' + registers.str() + '\n' + body + '\n.end method'
}

fn messenger_expected() map[string]string {
	return {
		'<init>(Landroid/os/IBinder;)V':                                            m('public constructor <init>(Landroid/os/IBinder;)V', 3,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {p1}, Landroid/os/IMessenger$Stub;->asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;\nmove-result-object v0\niput-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\nreturn-void')
		'equals(Ljava/lang/Object;)Z':                                              m('public equals(Ljava/lang/Object;)Z', 4,
			'instance-of v0, p1, Landroid/os/Messenger;\nif-eqz v0, :false\ncheck-cast p1, Landroid/os/Messenger;\ninvoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {p1}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v1\ninvoke-virtual {v0, v1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n:false\nconst/4 v0, 0x0\nreturn v0')
		'getBinder()Landroid/os/IBinder;':                                          m('public getBinder()Landroid/os/IBinder;', 2,
			'iget-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\ninvoke-interface {v0}, Landroid/os/IMessenger;->asBinder()Landroid/os/IBinder;\nmove-result-object v0\nreturn-object v0')
		'hashCode()I':                                                              m('public hashCode()I', 2,
			'invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {v0}, Ljava/lang/Object;->hashCode()I\nmove-result v0\nreturn v0')
		'<clinit>()V':                                                              m('static constructor <clinit>()V', 1,
			'new-instance v0, Landroid/os/Messenger$1;\ninvoke-direct {v0}, Landroid/os/Messenger$1;-><init>()V\nsput-object v0, Landroid/os/Messenger;->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
		'writeToParcel(Landroid/os/Parcel;I)V':                                     m('public writeToParcel(Landroid/os/Parcel;I)V', 4,
			'invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void')
		'writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V': m('public static writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V', 3,
			'const/4 v0, 0x0\nif-eqz p0, :write\ninvoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\n:write\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void')
		'readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;': m('public static readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;', 3,
			'invoke-virtual {p0}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v0\nif-nez v0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nnew-instance v1, Landroid/os/Messenger;\ninvoke-direct {v1, v0}, Landroid/os/Messenger;-><init>(Landroid/os/IBinder;)V\nreturn-object v1')
	}
}

fn fixed_classes() map[string]string {
	mut creator := '.class Landroid/os/Messenger$1;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n.annotation system Ldalvik/annotation/EnclosingMethod;\nvalue = Landroid/os/Messenger;-><clinit>()V\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x0\nname = null\n.end annotation\n'
	creator += m('constructor <init>()V', 1, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + '\n'
	creator += m('public createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;', 3,
		'invoke-static {p1}, Landroid/os/Messenger;->readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0') + '\n'
	creator += m('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 3,
		'invoke-virtual {p0, p1}, Landroid/os/Messenger$1;->createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0') + '\n'
	creator += m('public newArray(I)[Landroid/os/Messenger;', 3, 'new-array v0, p1, [Landroid/os/Messenger;\nreturn-object v0') + '\n'
	creator += m('public bridge synthetic newArray(I)[Ljava/lang/Object;', 3,
		'invoke-virtual {p0, p1}, Landroid/os/Messenger$1;->newArray(I)[Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0') + '\n'
	mut stub := '.class public abstract Landroid/os/IMessenger$Stub;\n.super Landroid/os/Binder;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/IMessenger;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x409\nname = "Stub"\n.end annotation\n.field private static final DESCRIPTOR:Ljava/lang/String; = "android.os.IMessenger"\n.field static final TRANSACTION_send:I = 0x1\n'
	stub += m('public constructor <init>()V', 2,
		'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-void') + '\n'
	stub += m('public static asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;', 3,
		'if-nez p0, :nonnull\nconst/4 v0, 0x0\nreturn-object v0\n:nonnull\nconst-string v0, "android.os.IMessenger"\ninvoke-interface {p0, v0}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;\nmove-result-object v0\ninstance-of v1, v0, Landroid/os/IMessenger;\nif-eqz v1, :proxy\ncheck-cast v0, Landroid/os/IMessenger;\nreturn-object v0\n:proxy\nnew-instance v0, Landroid/os/IMessenger$Stub$Proxy;\ninvoke-direct {v0, p0}, Landroid/os/IMessenger$Stub$Proxy;-><init>(Landroid/os/IBinder;)V\nreturn-object v0') + '\n'
	stub += m('public asBinder()Landroid/os/IBinder;', 1, 'return-object p0') + '\n'
	stub += m('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 7,
		'const v0, 0x5f4e5446\nif-ne p1, v0, :send\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nconst/4 v0, 0x1\nreturn v0\n:send\nconst/4 v0, 0x1\nif-ne p1, v0, :unknown\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\ninvoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :null\nsget-object v0, Landroid/os/Message;->CREATOR:Landroid/os/Parcelable$Creator;\ninvoke-interface {v0, p2}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Landroid/os/Message;\ngoto :deliver\n:null\nconst/4 v0, 0x0\n:deliver\ninvoke-interface {p0, v0}, Landroid/os/IMessenger;->send(Landroid/os/Message;)V\nconst/4 v0, 0x1\nreturn v0\n:unknown\ninvoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0') + '\n'
	mut proxy := '.class Landroid/os/IMessenger$Stub$Proxy;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/IMessenger$Stub;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0xa\nname = "Proxy"\n.end annotation\n.field private final mRemote:Landroid/os/IBinder;\n'
	proxy += m('constructor <init>(Landroid/os/IBinder;)V', 2, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/os/IMessenger$Stub$Proxy;->mRemote:Landroid/os/IBinder;\nreturn-void') + '\n'
	proxy += m('public asBinder()Landroid/os/IBinder;', 2, 'iget-object v0, p0, Landroid/os/IMessenger$Stub$Proxy;->mRemote:Landroid/os/IBinder;\nreturn-object v0') + '\n'
	proxy += m('public getInterfaceDescriptor()Ljava/lang/String;', 2, 'const-string v0, "android.os.IMessenger"\nreturn-object v0') + '\n'
	proxy += m('public send(Landroid/os/Message;)V', 7,
		'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n:start\nconst-string v1, "android.os.IMessenger"\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\nif-eqz p1, :null\nconst/4 v1, 0x1\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\nconst/4 v1, 0x0\ninvoke-virtual {p1, v0, v1}, Landroid/os/Message;->writeToParcel(Landroid/os/Parcel;I)V\ngoto :dispatch\n:null\nconst/4 v1, 0x0\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n:dispatch\niget-object v1, p0, Landroid/os/IMessenger$Stub$Proxy;->mRemote:Landroid/os/IBinder;\nconst/4 v2, 0x1\nconst/4 v3, 0x0\nconst/4 v4, 0x1\ninvoke-interface {v1, v2, v0, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n:end\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n.catchall {:start .. :end} :failure\n:failure\nmove-exception v1\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nthrow v1') + '\n'
	return {
		'android/os/Messenger$1.smali':           creator
		'android/os/IMessenger$Stub.smali':       stub
		'android/os/IMessenger$Stub$Proxy.smali': proxy
		'android/os/VinixMessageCreator.smali':   message_creator
	}
}

const message_creator = '.class final Landroid/os/VinixMessageCreator;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable$Creator;
.method public constructor <init>()V
.registers 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
.registers 5
invoke-static {}, Landroid/os/Message;->obtain()Landroid/os/Message;
move-result-object v0
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->what:I
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->arg1:I
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->arg2:I
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
if-eqz v1, :object_done
const-class v1, Landroid/os/Message;
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
invoke-virtual {p1, v1}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;
move-result-object v1
iput-object v1, v0, Landroid/os/Message;->obj:Ljava/lang/Object;
:object_done
invoke-virtual {p1}, Landroid/os/Parcel;->readLong()J
move-result-wide v1
iput-wide v1, v0, Landroid/os/Message;->when:J
invoke-virtual {p1}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;
move-result-object v1
iput-object v1, v0, Landroid/os/Message;->data:Landroid/os/Bundle;
invoke-static {p1}, Landroid/os/Messenger;->readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;
move-result-object v1
iput-object v1, v0, Landroid/os/Message;->replyTo:Landroid/os/Messenger;
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v1
iput v1, v0, Landroid/os/Message;->sendingUid:I
return-object v0
.end method
.method public newArray(I)[Ljava/lang/Object;
.registers 3
new-array v0, p1, [Landroid/os/Message;
return-object v0
.end method'

const message_write = '.method public writeToParcel(Landroid/os/Parcel;I)V
.registers 5
iget-object v0, p0, Landroid/os/Message;->callback:Ljava/lang/Runnable;
if-eqz v0, :no_callback
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Can\'t marshal callbacks across processes."
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
:no_callback
iget v0, p0, Landroid/os/Message;->what:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
iget v0, p0, Landroid/os/Message;->arg1:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
iget v0, p0, Landroid/os/Message;->arg2:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
iget-object v0, p0, Landroid/os/Message;->obj:Ljava/lang/Object;
if-eqz v0, :null_object
:object_start
check-cast v0, Landroid/os/Parcelable;
const/4 v1, 0x1
invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {p1, v0, p2}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V
:object_end
goto :object_done
:object_error
move-exception v0
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Can\'t marshal non-Parcelable objects across processes."
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
:null_object
const/4 v0, 0x0
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
:object_done
iget-wide v0, p0, Landroid/os/Message;->when:J
invoke-virtual {p1, v0, v1}, Landroid/os/Parcel;->writeLong(J)V
iget-object v0, p0, Landroid/os/Message;->data:Landroid/os/Bundle;
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
iget-object v0, p0, Landroid/os/Message;->replyTo:Landroid/os/Messenger;
invoke-static {v0, p1}, Landroid/os/Messenger;->writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V
iget v0, p0, Landroid/os/Message;->sendingUid:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
return-void
.catch Ljava/lang/ClassCastException; {:object_start .. :object_end} :object_error
.end method'

fn require_methods(before string, after string, replaced map[string]string, count int, raw bool) ! {
	old, changed := methods(before)!, methods(after)!
	if old.len != count { return error('baseline method count') }
	mut names := old.keys()
	for name, expected in replaced {
		if name !in changed || flow(changed[name])! != flow(expected)! {
			return error('changed method contract: ' + name)
		}
		if name !in names { names << name }
	}
	if changed.keys().sorted() != names.sorted() { return error('method surface changed') }
	for name, body in old {
		if name !in replaced && (if raw {
			changed[name] != body
		} else {
			flow(changed[name])! != flow(body)!
		}) {
			return error('unrelated method changed: ' + name)
		}
	}
}

fn verify(before map[string]string, after map[string]string, raw bool) ! {
	mut inventory := targets.clone()
	inventory << additions
	inventory << sentinels
	if after.keys().sorted() != inventory.sorted() { return error('batch class inventory') }
	for path in sentinels {
		if after[path] != before[path] { return error('Handler/Binder/Parcel changed') }
	}
	iface := targets[0]
	if norm(after[iface]) != '.class public interface abstract Landroid/os/IMessenger;\n.super Ljava/lang/Object;\n.implements Landroid/os/IInterface;\n.method public abstract send(Landroid/os/Message;)V\n.end method' {
		return error('IMessenger IInterface shape')
	}
	messenger := targets[1]
	require_methods(before[messenger], after[messenger], messenger_expected(), 7, raw)!
	if metadata(after[messenger])! != metadata(before[messenger] + '\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;')! {
		return error('Messenger field metadata')
	}
	handler := targets[3]
	old_handler := methods(before[handler])!
	changed_handler := {
		'<init>(Landroid/os/Handler;)V': old_handler['<init>(Landroid/os/Handler;)V'].replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'invoke-direct {p0}, Landroid/os/IMessenger$Stub;-><init>()V')
		'send(Landroid/os/Message;)V':   m('public send(Landroid/os/Message;)V', 3,
			'invoke-static {}, Landroid/os/Binder;->getCallingUid()I\nmove-result v0\niput v0, p1, Landroid/os/Message;->sendingUid:I\niget-object v0, p0, Landroid/os/Handler$MessengerImpl;->this$0:Landroid/os/Handler;\ninvoke-virtual {v0, p1}, Landroid/os/Handler;->sendMessage(Landroid/os/Message;)Z\nreturn-void')
	}
	require_methods(before[handler], after[handler], changed_handler, 3, raw)!
	if metadata(after[handler])! != metadata(before[handler].replace('.super Ljava/lang/Object;', '.super Landroid/os/IMessenger$Stub;'))! {
		return error('handler endpoint metadata')
	}
	message := targets[4]
	old_message := methods(before[message])!
	changed_message := {
		'<clinit>()V':                                      old_message['<clinit>()V'].replace('return-void', 'new-instance v0, Landroid/os/VinixMessageCreator;\ninvoke-direct {v0}, Landroid/os/VinixMessageCreator;-><init>()V\nsput-object v0, Landroid/os/Message;->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
		'<init>()V':                                        old_message['<init>()V'].replace('.registers 1', '.registers 2').replace('return-void', 'const/4 v0, -0x1\niput v0, p0, Landroid/os/Message;->sendingUid:I\nreturn-void')
		'clearForRecycle()V':                               old_message['clearForRecycle()V'].replace('return-void', 'const/4 v0, -0x1\niput v0, p0, Landroid/os/Message;->sendingUid:I\nreturn-void')
		'copyFrom(Landroid/os/Message;)V':                  old_message['copyFrom(Landroid/os/Message;)V'].replace('.registers 3', '.registers 3\niget v0, p1, Landroid/os/Message;->sendingUid:I\niput v0, p0, Landroid/os/Message;->sendingUid:I')
		'obtain(Landroid/os/Message;)Landroid/os/Message;': old_message['obtain(Landroid/os/Message;)Landroid/os/Message;'].replace('return-object v0', 'iget v1, p0, Landroid/os/Message;->sendingUid:I\niput v1, v0, Landroid/os/Message;->sendingUid:I\nreturn-object v0')
		'writeToParcel(Landroid/os/Parcel;I)V':             message_write
	}
	require_methods(before[message], after[message], changed_message, 28, raw)!
	if metadata(after[message])! != metadata(before[message].replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n.field public sendingUid:I'))! {
		return error('Message exact Parcelable members')
	}
	for path, expected in fixed_classes() {
		actual := after[path]
		a, e := methods(actual)!, methods(expected)!
		if a.keys().sorted() != e.keys().sorted() || metadata(actual)! != metadata(expected)! {
			return error('fixed class schema: ' + path)
		}
		for name, body in e {
			if flow(a[name])! != flow(body)! {
				return error('fixed class protocol: ' + path + ' ' + name)
			}
		}
	}
}

fn read(directory string) !map[string]string {
	mut result := map[string]string{}
	for path in os.walk_ext(directory, '.smali') {
		result[path[directory.len + 1..]] = os.read_file(path)!
	}
	return result
}

fn main() {
	$if prod {
		panic('live assertions required')
	}
	assert os.args.len in [2, 3], 'WORK [--roundtrip]'
	work := os.args[1]
	assert flow('const-string v0, "Can\'t"')! == flow('const-string v0, "Can\\\'t"')!
	if os.args.len == 3 {
		assert os.args[2] == '--roundtrip'
		before := read(work + '/baseline-roundtrip')!
		for directory in ['patched-roundtrip', 'second-roundtrip'] {
			verify(before, read(work + '/' + directory)!, false)!
		}
		assert read(work + '/patched-roundtrip')! == read(work + '/second-roundtrip')!
		println('MESSENGER-ROUNDTRIP-PASS five-changed three-added three-retained API28-wire stable-second-DEX')
		return
	}
	before := read(work + '/proof')!
	assert before.len == 8
	androidtools.framework_messenger(work + '/proof')!
	after := read(work + '/proof')!
	verify(before, after, true)!
	mut refusals := 0
	for path in targets {
		for invalid in [after[path], before[path] + '\n.field private unexpected:I\n',
			before[path].replace('.end method', '')] {
			for name, source in before { os.write_file(work + '/proof/' + name, source)! }
			for name in additions { os.rm(work + '/proof/' + name) or {} }
			os.write_file(work + '/proof/' + path, invalid)!
			expected := read(work + '/proof')!
			mut refused := false
			androidtools.framework_messenger(work + '/proof') or { refused = true }
			assert refused && read(work + '/proof')! == expected, 'refusal before writes'
			refusals++
		}
	}
	for name in additions {
		for kind in ['file', 'directory', 'symlink'] {
			for path, source in before { os.write_file(work + '/proof/' + path, source)! }
			for path in additions { os.rm(work + '/proof/' + path) or {} }
			path := work + '/proof/' + name
			if kind == 'file' {
				os.write_file(path, 'collision')!
			} else if kind == 'directory' {
				os.mkdir(path)!
			} else {
				os.symlink('absent-messenger-helper', path)!
			}
			mut refused := false
			androidtools.framework_messenger(work + '/proof') or { refused = true }
			assert refused
			for original, source in before {
				assert os.read_file(work + '/proof/' + original)! == source
			}
			for other in additions {
				if other != name {
					assert !os.exists(work + '/proof/' + other) && !os.is_link(work + '/proof/' + other)
				}
			}
			if kind == 'directory' {
				assert os.is_dir(path)
				os.rmdir(path)!
			} else if kind == 'symlink' {
				assert os.readlink(path)! == 'absent-messenger-helper'
				os.rm(path)!
			} else {
				assert os.read_file(path)! == 'collision'
				os.rm(path)!
			}
			refusals++
		}
	}
	mut controls := 0
	mutations := {
		'android/os/IMessenger.smali':            [
			'.implements Landroid/os/IInterface;',
			'.implements Ljava/lang/Runnable;',
		]
		'android/os/Messenger.smali':             [
			'->asInterface(Landroid/os/IBinder;)',
			'->wrongInterface(Landroid/os/IBinder;)',
		]
		'android/os/Messenger$1.smali':           ['[Landroid/os/Messenger;', '[Landroid/os/Message;']
		'android/os/Handler$MessengerImpl.smali': [
			'Landroid/os/Binder;->getCallingUid()',
			'Landroid/os/Process;->myUid()',
		]
		'android/os/IMessenger$Stub.smali':       ['->enforceInterface(', '->writeInterfaceToken(']
		'android/os/IMessenger$Stub$Proxy.smali': ['const/4 v4, 0x1', 'const/4 v4, 0x0']
		'android/os/VinixMessageCreator.smali':   ['->arg1:I', '->arg2:I']
		'android/os/Message.smali':               [
			'.catch Ljava/lang/ClassCastException;',
			'.catch Ljava/lang/RuntimeException;',
		]
	}
	for path, change in mutations {
		mut broken := after.clone()
		broken[path] = broken[path].replace(change[0], change[1])
		assert broken[path] != after[path]
		mut refused := false
		verify(before, broken, true) or { refused = true }
		assert refused, 'semantic control escaped oracle'
		controls++
	}
	for change in [
		['android/os/IMessenger$Stub.smali', '"android.os.IMessenger"', '"wrong.IMessenger"'],
		['android/os/IMessenger$Stub.smali', 'const/4 v0, 0x1', 'const/4 v0, 0x2'],
		['android/os/IMessenger$Stub$Proxy.smali', '->recycle()V', '->dataSize()I'],
		['android/os/IMessenger$Stub$Proxy.smali', '{:begin .. :end}', '{:dispatch .. :end}'],
		['android/os/IMessenger$Stub$Proxy.smali', 'throw v1', 'return-void'],
		['android/os/Messenger.smali', '->hashCode()I', '->describeContents()I'],
		['android/os/Messenger.smali', '->equals(Ljava/lang/Object;)Z',
			'->wrongEquals(Ljava/lang/Object;)Z'],
		['android/os/Message.smali', 'const/4 v0, -0x1', 'const/4 v0, 0x0'],
		['android/os/Message.smali', 'iget v1, p0, Landroid/os/Message;->sendingUid:I',
			'const/4 v1, 0x0'],
		['android/os/Message.smali', 'iget v0, p1, Landroid/os/Message;->sendingUid:I',
			'const/4 v0, 0x0'],
		['android/os/Message.smali', '{:object_try_start .. :object_try_end}',
			'{:object_try_start .. :object_done}'],
		['android/os/Message.smali', '} :object_error', '} :null_object'],
		['android/os/VinixMessageCreator.smali', '->readMessengerOrNullFromParcel(', '->getBinder('],
		['android/os/Handler.smali', 'getIMessenger()', 'wrongMessenger()'],
		['android/os/Binder.smali', 'getCallingUid()', 'wrongCallingUid()'],
		['android/os/Parcel.smali', 'readStrongBinder()', 'wrongStrongBinder()'],
	] {
		mut broken := after.clone()
		broken[change[0]] = broken[change[0]].replace(change[1], change[2])
		assert broken[change[0]] != after[change[0]], 'control did not mutate source'
		mut refused := false
		verify(before, broken, true) or { refused = true }
		assert refused, 'wire, UID, pooling, catch, identity or retained sentinel control escaped oracle'
		controls++
	}
	for path, source in after { os.write_file(work + '/proof/' + path, source)! }
	println('MESSENGER-SOURCE-PASS refusals=' + refusals.str() + ' semantic-controls=' + controls.str() + ' five-changed three-added three-retained API28-wire')
}
