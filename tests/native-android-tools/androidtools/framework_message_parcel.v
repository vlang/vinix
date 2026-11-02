// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn message_parcel_norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

fn message_parcel_methods(source string) !map[string]string {
	lines := source.split_into_lines().map(it.trim_space())
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := source.split('.method ')[1..]
	if headers.len != blocks.len || ends.len != blocks.len || ends.any(it != '.end method') {
		return error('balanced canonical Message methods required')
	}
	mut methods := map[string]string{}
	for block in blocks {
		header := block.all_before('\n')
		name := header.all_after_last(' ')
		if header.trim_space() != header || !name.contains('(') || name in methods
			|| block.count('.end method') != 1 {
			return error('unique complete Message methods required')
		}
		methods[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return methods
}

// Keep the preexisting message queue, pooling and copy behavior. Only the
// sender field and the Android-28 Parcelable representation are introduced.
pub fn framework_message_parcel_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [
		'.class public final Landroid/os/Message;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != [
		'.super Ljava/lang/Object;',
	] || lines.any(it.fields().len > 0 && it.fields()[0] == '.implements') {
		return error('canonical non-Parcelable Message required')
	}
	fields := ['.field static final FLAGS_TO_CLEAR_ON_COPY_FROM:I = 0x1',
		'.field static final FLAG_ASYNCHRONOUS:I = 0x2', '.field static final FLAG_IN_USE:I = 0x1',
		'.field private static final MAX_POOL_SIZE:I = 0x32',
		'.field private static sPool:Landroid/os/Message;', '.field private static sPoolSize:I',
		'.field private static final sPoolSync:Ljava/lang/Object;', '.field public arg1:I',
		'.field public arg2:I', '.field callback:Ljava/lang/Runnable;',
		'.field data:Landroid/os/Bundle;', '.field flags:I', '.field next:Landroid/os/Message;',
		'.field public obj:Ljava/lang/Object;', '.field public replyTo:Landroid/os/Messenger;',
		'.field target:Landroid/os/Handler;', '.field public what:I', '.field when:J']
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.field') != fields {
		return error('exact original Message fields required')
	}
	methods := message_parcel_methods(original)!
	expected_names := ['<clinit>()V', '<init>()V', 'obtain()Landroid/os/Message;',
		'obtain(Landroid/os/Handler;)Landroid/os/Message;',
		'obtain(Landroid/os/Handler;I)Landroid/os/Message;',
		'obtain(Landroid/os/Handler;III)Landroid/os/Message;',
		'obtain(Landroid/os/Handler;IIILjava/lang/Object;)Landroid/os/Message;',
		'obtain(Landroid/os/Handler;ILjava/lang/Object;)Landroid/os/Message;',
		'obtain(Landroid/os/Handler;Ljava/lang/Runnable;)Landroid/os/Message;',
		'obtain(Landroid/os/Message;)Landroid/os/Message;', 'clearForRecycle()V',
		'copyFrom(Landroid/os/Message;)V', 'describeContents()I', 'getCallback()Ljava/lang/Runnable;',
		'getData()Landroid/os/Bundle;', 'getTarget()Landroid/os/Handler;', 'getWhen()J',
		'isAsynchronous()Z', 'isInUse()Z', 'markInUse()V', 'peekData()Landroid/os/Bundle;', 'recycle()V',
		'sendToTarget()V', 'setAsynchronous(Z)V', 'setData(Landroid/os/Bundle;)V',
		'setTarget(Landroid/os/Handler;)V', 'toString()Ljava/lang/String;',
		'toString(J)Ljava/lang/String;']
	if methods.keys().sorted() != expected_names.sorted() {
		return error('exact original Message method surface required')
	}
	expected_targets := {
		'<clinit>()V':        '.method static constructor <clinit>()V
.registers 1
new-instance v0, Ljava/lang/Object;
invoke-direct {v0}, Ljava/lang/Object;-><init>()V
sput-object v0, Landroid/os/Message;->sPoolSync:Ljava/lang/Object;
const/4 v0, 0x0
sput v0, Landroid/os/Message;->sPoolSize:I
return-void
.end method'
		'<init>()V':          '.method public constructor <init>()V
.registers 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method'
		'clearForRecycle()V': '.method clearForRecycle()V
.registers 4
const/4 v0, 0x0
const/4 v2, 0x0
iput v0, p0, Landroid/os/Message;->flags:I
iput v0, p0, Landroid/os/Message;->what:I
iput v0, p0, Landroid/os/Message;->arg1:I
iput v0, p0, Landroid/os/Message;->arg2:I
iput-object v2, p0, Landroid/os/Message;->obj:Ljava/lang/Object;
iput-object v2, p0, Landroid/os/Message;->replyTo:Landroid/os/Messenger;
const-wide/16 v0, 0x0
iput-wide v0, p0, Landroid/os/Message;->when:J
iput-object v2, p0, Landroid/os/Message;->target:Landroid/os/Handler;
iput-object v2, p0, Landroid/os/Message;->callback:Ljava/lang/Runnable;
iput-object v2, p0, Landroid/os/Message;->data:Landroid/os/Bundle;
return-void
.end method'
	}
	for name, expected in expected_targets {
		if message_parcel_norm(methods[name]) != expected {
			return error('retained Message initialization and pooling required: ' + name)
		}
	}
	copy_method := methods['copyFrom(Landroid/os/Message;)V']
	obtain := methods['obtain(Landroid/os/Message;)Landroid/os/Message;']
	if !message_parcel_norm(copy_method).starts_with('.method public copyFrom(Landroid/os/Message;)V\n.registers 3\n')
		|| copy_method.count('.registers 3') != 1 || copy_method.count('return-void') != 1
		|| !message_parcel_norm(obtain).starts_with('.method public static obtain(Landroid/os/Message;)Landroid/os/Message;\n.registers 4\n')
		|| obtain.count('return-object v0') != 1 {
		return error('retained Message copy register and return shapes required')
	}
	mut patched := original.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n.field public sendingUid:I')
	clinit := methods['<clinit>()V']
	patched = patched.replace(clinit, clinit.replace('return-void', 'new-instance v0, Landroid/os/VinixMessageCreator;\ninvoke-direct {v0}, Landroid/os/VinixMessageCreator;-><init>()V\nsput-object v0, Landroid/os/Message;->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void'))
	constructor := methods['<init>()V']
	patched = patched.replace(constructor, constructor.replace('.registers 1', '.registers 2').replace('return-void', 'const/4 v0, -0x1\niput v0, p0, Landroid/os/Message;->sendingUid:I\nreturn-void'))
	clear := methods['clearForRecycle()V']
	patched = patched.replace(clear, clear.replace('return-void', 'const/4 v0, -0x1\niput v0, p0, Landroid/os/Message;->sendingUid:I\nreturn-void'))
	patched = patched.replace(copy_method, copy_method.replace('.registers 3', '.registers 3\niget v0, p1, Landroid/os/Message;->sendingUid:I\niput v0, p0, Landroid/os/Message;->sendingUid:I'))
	patched = patched.replace(obtain, obtain.replace('return-object v0', 'iget v1, p0, Landroid/os/Message;->sendingUid:I\niput v1, v0, Landroid/os/Message;->sendingUid:I\nreturn-object v0'))
	return patched + '\n' + framework_message_parcel_write_method() + '\n'
}

pub fn framework_message_parcel_write_method() string {
	return '.method public writeToParcel(Landroid/os/Parcel;I)V
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
:object_try_start
check-cast v0, Landroid/os/Parcelable;
const/4 v1, 0x1
invoke-virtual {p1, v1}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {p1, v0, p2}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V
:object_try_end
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
.catch Ljava/lang/ClassCastException; {:object_try_start .. :object_try_end} :object_error
.end method'
}

pub fn framework_message_parcel_classes() map[string]string {
	return {
		'android/os/VinixMessageCreator': '.class final Landroid/os/VinixMessageCreator;
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
.end method
'
	}
}

pub fn framework_message_parcel(smali string) ! {
	path := smali + '/android/os/Message.smali'
	patched := framework_message_parcel_source(os.read_file(path)!)!
	classes := framework_message_parcel_classes()
	for name, _ in classes {
		creator_path := smali + '/' + name + '.smali'
		if os.exists(creator_path) || os.is_link(creator_path) {
			return error('Message Parcelable creator collision')
		}
	}
	os.write_file(path, patched)!
	for name, source in classes {
		creator_path := smali + '/' + name + '.smali'
		os.mkdir_all(os.dir(creator_path))!
		os.write_file(creator_path, source)!
	}
}
