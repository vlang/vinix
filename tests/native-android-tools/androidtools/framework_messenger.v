// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// API28 Messenger uses the existing process-local Binder and Parcel transport.
// This does not add remote Binder credentials or a cross-process transport.
fn messenger_norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn messenger_method(signature string, registers int, body string) string {
	return '.method ${signature}\n.registers ${registers}\n${body}\n.end method'
}

fn messenger_members(source string) !map[string]string {
	mut methods := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in methods || block.count('.end method') != 1 {
			return error('Messenger requires unique complete methods')
		}
		methods[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return methods
}

fn messenger_require(source string, metadata string, expected map[string]string) !map[string]string {
	methods := messenger_members(source)!
	if methods.len != expected.len {
		return error('unexpected Messenger method inventory')
	}
	mut rest := source
	for name, method in expected {
		if name !in methods || messenger_norm(methods[name]) != messenger_norm(method) {
			return error('unexpected Messenger method: ' + name)
		}
		rest = rest.replace(methods[name], '')
	}
	if messenger_norm(rest) != messenger_norm(metadata) {
		return error('unexpected Messenger class metadata or members')
	}
	return methods
}

pub fn framework_imessenger_source(original string) !string {
	expected := '.class interface abstract Landroid/os/IMessenger;\n.super Ljava/lang/Object;\n.method public abstract send(Landroid/os/Message;)V\n.end method'
	if messenger_norm(original) != expected {
		return error('unexpected original IMessenger')
	}
	return original.replace('.class interface abstract ', '.class public interface abstract ')
		.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/IInterface;')
}

pub fn framework_messenger_source(original string) !string {
	metadata := '.class public final Landroid/os/Messenger;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field private final mTarget:Landroid/os/IMessenger;'
	expected := {
		'<init>(Landroid/os/Handler;)V':   messenger_method('public constructor <init>(Landroid/os/Handler;)V', 3,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Handler;->getIMessenger()Landroid/os/IMessenger;\nmove-result-object v0\niput-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\nreturn-void')
		'<init>(Landroid/os/IBinder;)V':   messenger_method('public constructor <init>(Landroid/os/IBinder;)V', 3,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, Landroid/os/Messenger\$1;\ninvoke-direct {v0, p0}, Landroid/os/Messenger\$1;-><init>(Landroid/os/Messenger;)V\niput-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\nreturn-void')
		'describeContents()I':             messenger_method('public describeContents()I', 2, 'const/4 v0, 0x0\nreturn v0')
		'equals(Ljava/lang/Object;)Z':     messenger_method('public equals(Ljava/lang/Object;)Z', 3, 'const/4 v0, 0x0\nreturn v0')
		'getBinder()Landroid/os/IBinder;': messenger_method('public getBinder()Landroid/os/IBinder;', 2, 'const/4 v0, 0x0\nreturn-object v0')
		'hashCode()I':                     messenger_method('public hashCode()I', 2, 'const/4 v0, 0x0\nreturn v0')
		'send(Landroid/os/Message;)V':     '.method public send(Landroid/os/Message;)V\n.registers 3\n.annotation system Ldalvik/annotation/Throws;\nvalue = {\nLandroid/os/RemoteException;\n}\n.end annotation\niget-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\ninvoke-interface {v0, p1}, Landroid/os/IMessenger;->send(Landroid/os/Message;)V\nreturn-void\n.end method'
	}
	methods := messenger_require(original, metadata, expected)!
	mut source := original
	replacements := {
		'<init>(Landroid/os/IBinder;)V':   messenger_method('public constructor <init>(Landroid/os/IBinder;)V', 3,
			'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {p1}, Landroid/os/IMessenger\$Stub;->asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;\nmove-result-object v0\niput-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\nreturn-void')
		'equals(Ljava/lang/Object;)Z':     messenger_method('public equals(Ljava/lang/Object;)Z', 4,
			'instance-of v0, p1, Landroid/os/Messenger;\nif-eqz v0, :different\ncheck-cast p1, Landroid/os/Messenger;\ninvoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {p1}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v1\ninvoke-virtual {v0, v1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n:different\nconst/4 v0, 0x0\nreturn v0')
		'getBinder()Landroid/os/IBinder;': messenger_method('public getBinder()Landroid/os/IBinder;', 2,
			'iget-object v0, p0, Landroid/os/Messenger;->mTarget:Landroid/os/IMessenger;\ninvoke-interface {v0}, Landroid/os/IMessenger;->asBinder()Landroid/os/IBinder;\nmove-result-object v0\nreturn-object v0')
		'hashCode()I':                     messenger_method('public hashCode()I', 2,
			'invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {v0}, Ljava/lang/Object;->hashCode()I\nmove-result v0\nreturn v0')
	}
	for name, replacement in replacements { source = source.replace(methods[name], replacement) }
	source += '\n.field public static final CREATOR:Landroid/os/Parcelable\$Creator;\n'
	source += '\n' + messenger_method('static constructor <clinit>()V', 1,
		'new-instance v0, Landroid/os/Messenger\$1;\ninvoke-direct {v0}, Landroid/os/Messenger\$1;-><init>()V\nsput-object v0, Landroid/os/Messenger;->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void') + '\n'
	source += '\n' + messenger_method('public writeToParcel(Landroid/os/Parcel;I)V', 4,
		'invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void') + '\n'
	source += '\n' + messenger_method('public static writeMessengerOrNullToParcel(Landroid/os/Messenger;Landroid/os/Parcel;)V', 3,
		'const/4 v0, 0x0\nif-eqz p0, :write\ninvoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;\nmove-result-object v0\n:write\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void') + '\n'
	source += '\n' + messenger_method('public static readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;', 3,
		'invoke-virtual {p0}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v0\nif-nez v0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nnew-instance v1, Landroid/os/Messenger;\ninvoke-direct {v1, v0}, Landroid/os/Messenger;-><init>(Landroid/os/IBinder;)V\nreturn-object v1') + '\n'
	return source
}

pub fn framework_messenger_creator_source(original string) !string {
	expected := '.class Landroid/os/Messenger\$1;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingMethod;\nvalue = Landroid/os/Messenger;-><init>(Landroid/os/IBinder;)V\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x0\nname = null\n.end annotation\n.field final synthetic this\$0:Landroid/os/Messenger;\n' +
		messenger_method('constructor <init>(Landroid/os/Messenger;)V', 2, 'iput-object p1, p0, Landroid/os/Messenger\$1;->this\$0:Landroid/os/Messenger;\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + '\n' +
		messenger_method('public send(Landroid/os/Message;)V', 2, 'return-void')
	if messenger_norm(original) != expected {
		return error('unexpected original Messenger anonymous implementation')
	}
	mut source := '.class Landroid/os/Messenger\$1;\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n.annotation system Ldalvik/annotation/EnclosingMethod;\nvalue = Landroid/os/Messenger;-><clinit>()V\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x0\nname = null\n.end annotation\n'
	source += '\n' + messenger_method('constructor <init>()V', 1, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') + '\n'
	source += '\n' + messenger_method('public createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;', 3,
		'invoke-static {p1}, Landroid/os/Messenger;->readMessengerOrNullFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0') + '\n'
	source += '\n' + messenger_method('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 3,
		'invoke-virtual {p0, p1}, Landroid/os/Messenger\$1;->createFromParcel(Landroid/os/Parcel;)Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0') + '\n'
	source += '\n' + messenger_method('public newArray(I)[Landroid/os/Messenger;', 3, 'new-array v0, p1, [Landroid/os/Messenger;\nreturn-object v0') + '\n'
	source += '\n' + messenger_method('public bridge synthetic newArray(I)[Ljava/lang/Object;', 3,
		'invoke-virtual {p0, p1}, Landroid/os/Messenger\$1;->newArray(I)[Landroid/os/Messenger;\nmove-result-object v0\nreturn-object v0') + '\n'
	return source
}

pub fn framework_handler_messenger_source(original string) !string {
	metadata := '.class final Landroid/os/Handler\$MessengerImpl;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/Handler;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x12\nname = "MessengerImpl"\n.end annotation\n.field final synthetic this\$0:Landroid/os/Handler;'
	expected := {
		'<init>(Landroid/os/Handler;)V':                       messenger_method('private constructor <init>(Landroid/os/Handler;)V', 2,
			'iput-object p1, p0, Landroid/os/Handler\$MessengerImpl;->this\$0:Landroid/os/Handler;\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
		'<init>(Landroid/os/Handler;Landroid/os/Handler$1;)V': messenger_method('synthetic constructor <init>(Landroid/os/Handler;Landroid/os/Handler\$1;)V', 3,
			'invoke-direct {p0, p1}, Landroid/os/Handler\$MessengerImpl;-><init>(Landroid/os/Handler;)V\nreturn-void')
		'send(Landroid/os/Message;)V':                         messenger_method('public send(Landroid/os/Message;)V', 3,
			'iget-object v0, p0, Landroid/os/Handler\$MessengerImpl;->this\$0:Landroid/os/Handler;\ninvoke-virtual {v0, p1}, Landroid/os/Handler;->sendMessage(Landroid/os/Message;)Z\nreturn-void')
	}
	methods := messenger_require(original, metadata, expected)!
	mut source := original.replace('.super Ljava/lang/Object;', '.super Landroid/os/IMessenger\$Stub;')
	ctor := methods['<init>(Landroid/os/Handler;)V']
	source = source.replace(ctor, ctor.replace('invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'invoke-direct {p0}, Landroid/os/IMessenger\$Stub;-><init>()V'))
	source = source.replace(methods['send(Landroid/os/Message;)V'], messenger_method('public send(Landroid/os/Message;)V', 3,
		'invoke-static {}, Landroid/os/Binder;->getCallingUid()I\nmove-result v0\niput v0, p1, Landroid/os/Message;->sendingUid:I\niget-object v0, p0, Landroid/os/Handler\$MessengerImpl;->this\$0:Landroid/os/Handler;\ninvoke-virtual {v0, p1}, Landroid/os/Handler;->sendMessage(Landroid/os/Message;)Z\nreturn-void'))
	return source
}

pub fn framework_messenger_classes() map[string]string {
	mut stub := '.class public abstract Landroid/os/IMessenger\$Stub;\n.super Landroid/os/Binder;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/IMessenger;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x409\nname = "Stub"\n.end annotation\n.field private static final DESCRIPTOR:Ljava/lang/String; = "android.os.IMessenger"\n.field static final TRANSACTION_send:I = 0x1\n'
	stub += '\n' + messenger_method('public constructor <init>()V', 2,
		'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-void') + '\n'
	stub += '\n' + messenger_method('public static asInterface(Landroid/os/IBinder;)Landroid/os/IMessenger;', 3,
		'if-nez p0, :present\nconst/4 v0, 0x0\nreturn-object v0\n:present\nconst-string v0, "android.os.IMessenger"\ninvoke-interface {p0, v0}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;\nmove-result-object v0\ninstance-of v1, v0, Landroid/os/IMessenger;\nif-eqz v1, :proxy\ncheck-cast v0, Landroid/os/IMessenger;\nreturn-object v0\n:proxy\nnew-instance v0, Landroid/os/IMessenger\$Stub\$Proxy;\ninvoke-direct {v0, p0}, Landroid/os/IMessenger\$Stub\$Proxy;-><init>(Landroid/os/IBinder;)V\nreturn-object v0') + '\n'
	stub += '\n' + messenger_method('public asBinder()Landroid/os/IBinder;', 1, 'return-object p0') + '\n'
	stub += '\n' + messenger_method('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 7,
		'const v0, 0x5f4e5446\nif-ne p1, v0, :send\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nconst/4 v0, 0x1\nreturn v0\n:send\nconst/4 v0, 0x1\nif-ne p1, v0, :unknown\nconst-string v0, "android.os.IMessenger"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\ninvoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :absent\nsget-object v0, Landroid/os/Message;->CREATOR:Landroid/os/Parcelable\$Creator;\ninvoke-interface {v0, p2}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Landroid/os/Message;\ngoto :deliver\n:absent\nconst/4 v0, 0x0\n:deliver\ninvoke-interface {p0, v0}, Landroid/os/IMessenger;->send(Landroid/os/Message;)V\nconst/4 v0, 0x1\nreturn v0\n:unknown\ninvoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0') + '\n'
	mut proxy := '.class Landroid/os/IMessenger\$Stub\$Proxy;\n.super Ljava/lang/Object;\n.implements Landroid/os/IMessenger;\n.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/os/IMessenger\$Stub;\n.end annotation\n.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0xa\nname = "Proxy"\n.end annotation\n.field private final mRemote:Landroid/os/IBinder;\n'
	proxy += '\n' + messenger_method('constructor <init>(Landroid/os/IBinder;)V', 2,
		'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/os/IMessenger\$Stub\$Proxy;->mRemote:Landroid/os/IBinder;\nreturn-void') + '\n'
	proxy += '\n' + messenger_method('public asBinder()Landroid/os/IBinder;', 2,
		'iget-object v0, p0, Landroid/os/IMessenger\$Stub\$Proxy;->mRemote:Landroid/os/IBinder;\nreturn-object v0') + '\n'
	proxy += '\n' + messenger_method('public getInterfaceDescriptor()Ljava/lang/String;', 2, 'const-string v0, "android.os.IMessenger"\nreturn-object v0') + '\n'
	proxy += '\n' + messenger_method('public send(Landroid/os/Message;)V', 7,
		'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n:begin\nconst-string v1, "android.os.IMessenger"\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\nif-eqz p1, :absent\nconst/4 v1, 0x1\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\nconst/4 v1, 0x0\ninvoke-virtual {p1, v0, v1}, Landroid/os/Message;->writeToParcel(Landroid/os/Parcel;I)V\ngoto :dispatch\n:absent\nconst/4 v1, 0x0\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n:dispatch\niget-object v1, p0, Landroid/os/IMessenger\$Stub\$Proxy;->mRemote:Landroid/os/IBinder;\nconst/4 v2, 0x1\nconst/4 v3, 0x0\nconst/4 v4, 0x1\ninvoke-interface {v1, v2, v0, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n:end\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n.catchall {:begin .. :end} :failed\n:failed\nmove-exception v1\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nthrow v1') + '\n'
	return {
		'android/os/IMessenger\$Stub':        stub
		'android/os/IMessenger\$Stub\$Proxy': proxy
	}
}

pub fn framework_messenger(smali string) ! {
	mut changed := map[string]string{}
	for name in ['Messenger', 'Messenger\$1', 'IMessenger', 'Handler\$MessengerImpl', 'Message'] {
		original := os.read_file(smali + '/android/os/' + name + '.smali')!
		changed['android/os/' + name] = match name {
			'Messenger' { framework_messenger_source(original)! }
			'Messenger\$1' { framework_messenger_creator_source(original)! }
			'IMessenger' { framework_imessenger_source(original)! }
			'Message' { framework_message_parcel_source(original)! }
			else { framework_handler_messenger_source(original)! }
		}
	}
	mut additions := framework_messenger_classes()
	for name, source in framework_message_parcel_classes() { additions[name] = source }
	for name, source in additions {
		if os.exists(smali + '/' + name + '.smali') || os.is_link(smali + '/' + name + '.smali') {
			return error('Messenger class already exists: ' + name)
		}
		changed[name] = source
	}
	for name, source in changed { os.write_file(smali + '/' + name + '.smali', source)! }
}
