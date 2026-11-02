// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const service_type = 'Lorg/vinix/bootstrap/SinkService;'
const sender_type = 'Lorg/vinix/bootstrap/Sender;'
const receiver_type = 'Lorg/vinix/bootstrap/SinkReceiver;'
const context_type = 'Lorg/vinix/bootstrap/SenderContext;'
const pass_marker = 'PENDING-INTENT-PASS no-create identity send fill-in update cancel one-shot immutable parcel service recovery broadcast cleanup'
const fail_marker = 'PENDING-INTENT-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn checks_source() string {
	return method('public static eq(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
invoke-static {p0, p1}, Ljava/util/Objects;->equals(Ljava/lang/Object;Ljava/lang/Object;)Z
move-result v0
if-nez v0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
invoke-static {p0, p1}, Ljava/util/Objects;->equals(Ljava/lang/Object;Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static mainThread()V', 3, '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
const-string v2, "callback must run on main looper"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void') + method('public static report(Ljava/lang/Throwable;)V', 2, '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw p0') + method('public static canceled(Landroid/app/PendingIntent;)V', 2, '
:try_start
invoke-virtual {p0}, Landroid/app/PendingIntent;->send()V
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "canceled token must reject send"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Landroid/app/PendingIntent$CanceledException; {:try_start .. :try_end} :expected
:expected
move-exception v0
return-void') + method('public static parcel(Landroid/app/PendingIntent;)Landroid/app/PendingIntent;', 3, '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/app/PendingIntent;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v1, Landroid/app/PendingIntent;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v1, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/app/PendingIntent;
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
const-string v2, "parcel must alias live token"
invoke-static {p0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-object v1') + method('public static intent(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;', 2, '
new-instance v0, Landroid/content/Intent;
const-class v1, ${service_type}
invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V
invoke-virtual {v0, p1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "base"
invoke-virtual {v0, v1, p2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "collision"
invoke-virtual {v0, v1, p2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
return-object v0') + method('public static fill(I)Landroid/content/Intent;', 6, '
new-instance v0, Landroid/content/Intent;
const-string v1, "sender-action"
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v1, "collision"
const-string v2, "sender-overwrite"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v1, "unique"
invoke-virtual {v0, v1, p0}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
new-instance v1, Landroid/graphics/Rect;
const/16 v2, 10
const/16 v3, 20
const/16 v4, 30
const/16 v5, 40
invoke-direct {v1, v2, v3, v4, v5}, Landroid/graphics/Rect;-><init>(IIII)V
invoke-virtual {v0, v1}, Landroid/content/Intent;->setSourceBounds(Landroid/graphics/Rect;)V
return-object v0')
}

// v0 = creator, v1 = request, v2 = intent, v3 = flags, v4 = result.
fn factory(name string) string {
	return 'invoke-static {v0, v1, v2, v3}, Landroid/app/PendingIntent;->${name}(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;\nmove-result-object v4\n'
}

fn identity_source() string {
	mut body := '
move-object v0, p0
const-string v1, "identity"
const-string v2, "identity-original"
invoke-static {v0, v1, v2}, ${main_type}->intent(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
move-result-object v2
const-string v3, "${package_name}"
invoke-virtual {v2, v3}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v3, "content://pending-fixture/base"
invoke-static {v3}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v3
const-string v4, "text/plain"
invoke-virtual {v2, v3, v4}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;
const-string v3, "key.id"
invoke-virtual {v2, v3}, Landroid/content/Intent;->setIdentifier(Ljava/lang/String;)Landroid/content/Intent;
const-string v3, "key.category"
invoke-virtual {v2, v3}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;
const/16 v1, 210
const v3, 0x20000000
' + factory('getService') + '
const/4 v5, 0
const-string v6, "NO_CREATE absent must return null"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const v3, 0x28000000
' + factory('getService') + '
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v3, 0
' + factory('getService') + '
move-object v7, v4
const-string v3, "collision"
const-string v4, "different-extras"
invoke-virtual {v2, v3, v4}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const v3, 0x20000000
' + factory('getService') + '
const-string v6, "extras must not change token identity"
invoke-static {v4, v7, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
' + factory('getService') + '
const-string v6, "activity and application share creator"
invoke-static {v4, v7, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v7}, Landroid/app/PendingIntent;->getCreatorPackage()Ljava/lang/String;
move-result-object v4
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v5
const-string v6, "creator package"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v7}, Landroid/app/PendingIntent;->getCreatorUid()I
move-result v4
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v5
const-string v6, "creator uid"
invoke-static {v4, v5, v6}, ${main_type}->eq(IILjava/lang/String;)V
'
	// Clone the filter for each field so each miss has exactly one changed key.
	for index, mutation in [
		'const-string v4, "other-action"\ninvoke-virtual {v2, v4}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;',
		'const-string v4, "content://pending-fixture/other"\ninvoke-static {v4}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;\nmove-result-object v4\nconst-string v5, "text/plain"\ninvoke-virtual {v2, v4, v5}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;',
		'const-string v4, "content://pending-fixture/base"\ninvoke-static {v4}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;\nmove-result-object v4\nconst-string v5, "image/png"\ninvoke-virtual {v2, v4, v5}, Landroid/content/Intent;->setDataAndType(Landroid/net/Uri;Ljava/lang/String;)Landroid/content/Intent;',
		'const-string v4, "other.id"\ninvoke-virtual {v2, v4}, Landroid/content/Intent;->setIdentifier(Ljava/lang/String;)Landroid/content/Intent;',
		'const-string v4, "other.creator.package"\ninvoke-virtual {v2, v4}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;',
		'const-class v4, Lorg/vinix/bootstrap/AliasService;\ninvoke-virtual {v2, v0, v4}, Landroid/content/Intent;->setClass(Landroid/content/Context;Ljava/lang/Class;)Landroid/content/Intent;',
		'const-string v4, "other.category"\ninvoke-virtual {v2, v4}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;',
	] {
		body += 'move-object v8, v2\nnew-instance v2, Landroid/content/Intent;\ninvoke-direct {v2, v8}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V\n' + mutation + '\n' + factory('getService') + 'const/4 v5, 0\nconst-string v6, "filter field ${index} must isolate lookup"\ninvoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\nmove-object v2, v8\n'
	}
	body += 'const/16 v1, 211\n' + factory('getService') + 'const/4 v5, 0\nconst-string v6, "request code must isolate lookup"\ninvoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\nconst/16 v1, 210\n'
	for name in ['getForegroundService', 'getActivity', 'getBroadcast'] {
		body += factory(name) + 'const/4 v5, 0\nconst-string v6, "factory kind must isolate lookup"\ninvoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\nconst/4 v3, 0\n' + factory(name) + 'const-string v6, "factory kind must create distinct token"\ninvoke-static {v4, v7, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\ninvoke-virtual {v4}, Landroid/app/PendingIntent;->cancel()V\nconst v3, 0x20000000\n'
	}
	for flags in ['0x40000000', '0x04000000'] {
		body += 'const v3, ${flags}\n' + factory('getService') + 'const-string v6, "persistent flags must isolate identity"\ninvoke-static {v4, v7, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\nmove-object v8, v4\nconst v5, 0x20000000\nor-int/2addr v3, v5\n' + factory('getService') + 'const-string v6, "matching persistent flags must find token"\ninvoke-static {v4, v8, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\ninvoke-virtual {v8}, Landroid/app/PendingIntent;->cancel()V\n'
	}
	body += '
const/4 v3, 0
' + factory('getActivity') + '
move-object v8, v4
const/4 v4, 2
new-array v4, v4, [Landroid/content/Intent;
const/4 v5, 0
new-instance v6, Landroid/content/Intent;
const-string v9, "first-stack-entry"
invoke-direct {v6, v9}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
aput-object v6, v4, v5
const/4 v5, 1
aput-object v2, v4, v5
const v3, 0x20000000
const/4 v5, 0
invoke-static {v0, v1, v4, v3, v5}, Landroid/app/PendingIntent;->getActivities(Landroid/content/Context;I[Landroid/content/Intent;ILandroid/os/Bundle;)Landroid/app/PendingIntent;
move-result-object v4
const-string v6, "activities identity uses final intent"
invoke-static {v4, v8, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v8}, Landroid/app/PendingIntent;->cancel()V
invoke-static {v7}, ${main_type}->parcel(Landroid/app/PendingIntent;)Landroid/app/PendingIntent;
move-result-object v8
const v3, 0x30000000
' + factory('getService') + '
const/4 v5, 0
const-string v6, "NO_CREATE plus CANCEL_CURRENT returns original canceled token"
invoke-static {v4, v7, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v7}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
invoke-static {v8}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
const v3, 0x20000000
' + factory('getService') + '
const/4 v5, 0
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void'
	return method('private static identity(Landroid/content/Context;)V', 10, body)
}

// Each delivery is inspected only from the real Service/Receiver callback.
fn accept_source() string {
	mut body := '
invoke-static {}, ${main_type}->mainThread()V
sget v0, ${main_type}->callbacks:I
add-int/lit8 v0, v0, 1
sput v0, ${main_type}->callbacks:I
sget v1, ${main_type}->mode:I
const-string v2, "exactly one ordered service callback per send"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
'
	for mode in 1 .. 8 {
		body += 'const/4 v1, ${mode}\nif-eq v0, v1, :mode${mode}\n'
	}
	body += 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "unexpected service mode"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
	for index, base in ['original', 'original', 'updated', 'immutable-original', 'immutable-update', 'replacement', 'one-shot'] {
		mode := index + 1
		action := if mode <= 3 || mode == 6 { 'RECOVERY' } else if mode <= 5 { 'IMMUTABLE' } else { 'ONESHOT' }
		body += ':mode${mode}\nmove-object v0, p0\nconst-string v1, "${action}"\nconst-string v2, "${base}"\n'
		unique := if mode == 1 { 731 } else if mode == 7 { -2 } else { -1 }
		remove := if mode <= 2 { 1 } else { 0 }
		body += 'const/16 v3, ${unique}\nconst/4 v4, ${remove}\ninvoke-static {v0, v1, v2, v3, v4}, ${main_type}->inspect(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;IZ)V\nreturn-void\n'
	}
	return method('public static accept(Landroid/content/Intent;)V', 5, body) + method('public static inspect(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;IZ)V', 3, '
invoke-virtual {p0}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v0
const-string v2, "saved action must survive fill-in"
invoke-static {v0, p1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "base"
invoke-virtual {p0, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v2, "factory extras snapshot or creator update"
invoke-static {v0, p2, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "collision"
invoke-virtual {p0, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v2, "original extras win duplicate fill-in keys"
invoke-static {v0, p2, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "unique"
const/4 v1, -1
invoke-virtual {p0, v0, v1}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v0
const/4 v1, -2
if-ne p3, v1, :normal
const/16 v1, 500
if-eq v0, v1, :unique_done
const/16 v1, 501
const-string v2, "one-shot payload belongs to winning sender"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
goto :unique_done
:normal
const-string v2, "fill-in snapshot, immutability or one-shot payload"
invoke-static {v0, p3, v2}, ${main_type}->eq(IILjava/lang/String;)V
:unique_done
const-string v0, "remove"
invoke-virtual {p0, v0}, Landroid/content/Intent;->hasExtra(Ljava/lang/String;)Z
move-result v0
const-string v2, "UPDATE_CURRENT replaces rather than merges extras"
invoke-static {v0, p4, v2}, ${main_type}->eq(IILjava/lang/String;)V
invoke-virtual {p0}, Landroid/content/Intent;->getSourceBounds()Landroid/graphics/Rect;
move-result-object v0
const/4 v1, -1
if-ne p3, v1, :bounds_present
const/4 v1, 0
const-string v2, "no-fill or immutable send must retain absent bounds"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void
:bounds_present
iget v0, v0, Landroid/graphics/Rect;->left:I
const/16 v1, 10
const-string v2, "source bounds must be copied before sender mutation"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
return-void') + method('public static acceptBroadcast(Landroid/content/Intent;)V', 5, '
invoke-static {}, ${main_type}->mainThread()V
sget v0, ${main_type}->broadcasts:I
add-int/lit8 v0, v0, 1
sput v0, ${main_type}->broadcasts:I
const/4 v1, 1
const-string v2, "exactly one broadcast callback"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
move-object v0, p0
const-string v1, "BROADCAST"
const-string v2, "broadcast"
const/16 v3, 731
const/4 v4, 0
invoke-static {v0, v1, v2, v3, v4}, ${main_type}->inspect(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;IZ)V
return-void')
}

fn queued_send(field string, expected int, fill bool) string {
	mut body := 'const/4 v0, ${expected + 1}\nsput v0, ${main_type}->mode:I\nsget-object v0, ${main_type}->${field}:Landroid/app/PendingIntent;\n'
	if fill {
		body += 'const/16 v1, 731\ninvoke-static {v1}, ${main_type}->fill(I)Landroid/content/Intent;\nmove-result-object v3\nsget-object v1, ${main_type}->senderContext:Landroid/content/Context;\nconst/4 v2, 7\ninvoke-virtual {v0, v1, v2, v3}, Landroid/app/PendingIntent;->send(Landroid/content/Context;ILandroid/content/Intent;)V\nconst-string v1, "unique"\nconst/16 v2, 999\ninvoke-virtual {v3, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;\ninvoke-virtual {v3}, Landroid/content/Intent;->getSourceBounds()Landroid/graphics/Rect;\nmove-result-object v3\nconst/16 v1, 99\niput v1, v3, Landroid/graphics/Rect;->left:I\n'
	} else {
		body += 'invoke-virtual {v0}, Landroid/app/PendingIntent;->send()V\n'
	}
	body += 'sget v0, ${main_type}->callbacks:I\nconst/4 v1, ${expected}\nconst-string v2, "service delivery must be queued, not inline"\ninvoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V\nconst/4 v0, ${expected + 1}\niput v0, p0, ${main_type}->stage:I\nreturn-void\n'
	return body
}

fn token(field string, action string, base string, request int, flags string) string {
	return 'move-object v0, p0\nconst-string v1, "${action}"\nconst-string v2, "${base}"\ninvoke-static {v0, v1, v2}, ${main_type}->intent(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;\nmove-result-object v2\nconst/16 v1, ${request}\nconst v3, ${flags}\n' + factory('getService') + 'sput-object v4, ${main_type}->${field}:Landroid/app/PendingIntent;\n'
}

fn step_source() string {
	mut body := '
iget v0, p0, ${main_type}->stage:I
'
	for stage in 0 .. 10 { body += 'const/16 v1, ${stage}\nif-eq v0, v1, :stage${stage}\n' }
	body += 'return-void\n:stage0\ninvoke-static {p0}, ${main_type}->identity(Landroid/content/Context;)V\n'
	body += token('recovery', 'RECOVERY', 'original', 100, '0x20000000') + '
const/4 v5, 0
const-string v6, "Google recovery query must not invent saved intent"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v5, "remove"
const-string v6, "keep"
invoke-virtual {v2, v5, v6}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const/4 v3, 0
' + factory('getService') + '
sput-object v4, ${main_type}->recovery:Landroid/app/PendingIntent;
invoke-static {v4}, ${main_type}->parcel(Landroid/app/PendingIntent;)Landroid/app/PendingIntent;
move-result-object v5
sput-object v5, ${main_type}->alias:Landroid/app/PendingIntent;
const-string v5, "collision"
const-string v6, "mutated-factory"
invoke-virtual {v2, v5, v6}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
' + queued_send('recovery', 0, true)
	body += ':stage1\n' + wait_count(1) + queued_send('recovery', 1, false)
	body += ':stage2\n' + wait_count(2) + token('updated', 'RECOVERY', 'updated', 100, '0x08000000') + '
sget-object v5, ${main_type}->recovery:Landroid/app/PendingIntent;
const-string v6, "UPDATE_CURRENT preserves existing token"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v0, 3
sput v0, ${main_type}->mode:I
const/4 v0, 0
const/4 v1, 0
invoke-virtual {v4, v0, v1, v0}, Landroid/app/PendingIntent;->send(Landroid/content/Context;ILandroid/content/Intent;)V
sget v0, ${main_type}->callbacks:I
const/4 v1, 2
const-string v2, "null-context send with null fill-in must queue"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
const/4 v0, 3
iput v0, p0, ${main_type}->stage:I
return-void
:stage3
' + wait_count(3) + token('immutable', 'IMMUTABLE', 'immutable-original', 101, '0x04000000') + queued_send('immutable', 3, true)
	body += ':stage4\n' + wait_count(4) + token('updated', 'IMMUTABLE', 'immutable-update', 101, '0x0c000000') + '
sget-object v5, ${main_type}->immutable:Landroid/app/PendingIntent;
const-string v6, "creator update works for immutable token"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
' + queued_send('immutable', 4, true)
	body += ':stage5\n' + wait_count(5) + token('replacement', 'RECOVERY', 'replacement', 100, '0x10000000') + '
sget-object v5, ${main_type}->recovery:Landroid/app/PendingIntent;
const-string v6, "CANCEL_CURRENT replaces token identity"
invoke-static {v4, v5, v6}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v5}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
sget-object v5, ${main_type}->alias:Landroid/app/PendingIntent;
invoke-static {v5}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
invoke-static {v5}, ${main_type}->parcel(Landroid/app/PendingIntent;)Landroid/app/PendingIntent;
move-result-object v5
invoke-static {v5}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
const v3, 0x20000000
' + factory('getService') + '
sget-object v5, ${main_type}->replacement:Landroid/app/PendingIntent;
const-string v6, "NO_CREATE finds replacement token"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
' + queued_send('replacement', 5, false)
	body += ':stage6\n' + wait_count(6) + '
sget-object v0, ${main_type}->replacement:Landroid/app/PendingIntent;
invoke-virtual {v0}, Landroid/app/PendingIntent;->cancel()V
invoke-virtual {v0}, Landroid/app/PendingIntent;->cancel()V
invoke-static {v0}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
' + token('updated', 'RECOVERY', 'replacement', 100, '0x20000000') + '
const/4 v5, 0
const-string v6, "cancel removes token from registry"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
' + token('one', 'ONESHOT', 'one-shot', 102, '0x40000000') + '
const/4 v0, 7
sput v0, ${main_type}->mode:I
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
sput-object v0, ${main_type}->gate:Ljava/util/concurrent/CountDownLatch;
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 2
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
sput-object v0, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 2
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
sput-object v0, ${main_type}->ready:Ljava/util/concurrent/CountDownLatch;
'
	for index, name in ['A', 'B'] {
		body += 'new-instance v0, ${sender_type}\nsget-object v1, ${main_type}->one:Landroid/app/PendingIntent;\nsget-object v2, ${main_type}->senderContext:Landroid/content/Context;\nconst/16 v3, ${500 + index}\ninvoke-direct {v0, v1, v2, v3}, ${sender_type}-><init>(Landroid/app/PendingIntent;Landroid/content/Context;I)V\nsput-object v0, ${main_type}->sender${name}:${sender_type}\nnew-instance v1, Ljava/lang/Thread;\nconst-string v2, "pending-one-shot-${name}"\ninvoke-direct {v1, v0, v2}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;Ljava/lang/String;)V\nsput-object v1, ${main_type}->thread${name}:Ljava/lang/Thread;\ninvoke-virtual {v1}, Ljava/lang/Thread;->start()V\n'
	}
	body += '
const/4 v0, 7
iput v0, p0, ${main_type}->stage:I
return-void
:stage7
sget-object v0, ${main_type}->ready:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->getCount()J
move-result-wide v0
const-wide/16 v2, 0
cmp-long v0, v0, v2
if-nez v0, :waiting
sget-object v0, ${main_type}->gate:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
sget-object v0, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->getCount()J
move-result-wide v0
const-wide/16 v2, 0
cmp-long v0, v0, v2
if-nez v0, :waiting
' + wait_count(7) + '
invoke-static {}, ${main_type}->checkWorkers()V
sget-object v0, ${main_type}->one:Landroid/app/PendingIntent;
invoke-static {v0}, ${main_type}->canceled(Landroid/app/PendingIntent;)V
' + token('updated', 'ONESHOT', 'one-shot', 102, '0x60000000') + '
const/4 v5, 0
const-string v6, "one-shot removed before second sender dispatch"
invoke-static {v4, v5, v6}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
new-instance v2, Landroid/content/Intent;
const-string v0, "BROADCAST"
invoke-direct {v2, v0}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v0, "${package_name}"
invoke-virtual {v2, v0}, Landroid/content/Intent;->setPackage(Ljava/lang/String;)Landroid/content/Intent;
const-string v0, "base"
const-string v1, "broadcast"
invoke-virtual {v2, v0, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v0, "collision"
invoke-virtual {v2, v0, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
move-object v0, p0
const/16 v1, 103
const/4 v3, 0
' + factory('getBroadcast') + '
sput-object v4, ${main_type}->receiverPI:Landroid/app/PendingIntent;
const/16 v0, 731
invoke-static {v0}, ${main_type}->fill(I)Landroid/content/Intent;
move-result-object v3
sget-object v1, ${main_type}->senderContext:Landroid/content/Context;
const/4 v2, 0
invoke-virtual {v4, v1, v2, v3}, Landroid/app/PendingIntent;->send(Landroid/content/Context;ILandroid/content/Intent;)V
const/16 v0, 8
iput v0, p0, ${main_type}->stage:I
return-void
:stage8
sget v0, ${main_type}->broadcasts:I
if-eqz v0, :waiting
const/4 v1, 1
const-string v2, "exact broadcast delivery count"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
invoke-direct {p0}, ${main_type}->cleanup()V
const/16 v0, 9
iput v0, p0, ${main_type}->stage:I
return-void
:stage9
sget v0, ${main_type}->serviceDestroys:I
if-eqz v0, :waiting
const/4 v1, 1
const-string v2, "one service created and destroyed before PASS"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
sget v0, ${main_type}->serviceCreates:I
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
sget v0, ${main_type}->callbacks:I
const/4 v1, 7
const-string v2, "final real service delivery count"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
const/16 v0, 10
iput v0, p0, ${main_type}->stage:I
iget-object v0, p0, ${main_type}->label:Landroid/widget/TextView;
const-string v1, "PendingIntent service recovery contracts passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
return-void
:waiting
return-void'
	return method('private step()V', 8, body)
}

fn wait_count(count int) string {
	return 'sget v0, ${main_type}->callbacks:I\nconst/4 v1, ${count}\nif-lt v0, v1, :waiting\nconst-string v2, "no duplicate or unexpected callback"\ninvoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V\n'
}

fn worker_check_source() string {
	mut body := ''
	for name in ['A', 'B'] {
		body += 'sget-object v0, ${main_type}->sender${name}:${sender_type}\niget-object v1, v0, ${sender_type}->failure:Ljava/lang/Throwable;\nif-eqz v1, :ok${name}\nthrow v1\n:ok${name}\nsget-object v0, ${main_type}->thread${name}:Ljava/lang/Thread;\nconst-wide/16 v1, 1000\ninvoke-virtual {v0, v1, v2}, Ljava/lang/Thread;->join(J)V\ninvoke-virtual {v0}, Ljava/lang/Thread;->isAlive()Z\nmove-result v0\nconst/4 v1, 0\nconst-string v2, "sender must exit before PASS"\ninvoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V\n'
	}
	body += '
sget-object v0, ${main_type}->senderA:${sender_type}
iget v0, v0, ${sender_type}->result:I
sget-object v1, ${main_type}->senderB:${sender_type}
iget v1, v1, ${sender_type}->result:I
add-int v2, v0, v1
const/4 v3, 3
const-string v4, "one sender succeeds and one observes canceled"
invoke-static {v2, v3, v4}, ${main_type}->eq(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v0
invoke-static {v1}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v1
invoke-static {v0, v1, v4}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void'
	return method('private static checkWorkers()V', 5, body)
}

fn lifecycle_source() string {
	mut cleanup := ''
	for name in ['recovery', 'alias', 'immutable', 'replacement', 'one', 'receiverPI', 'updated'] {
		cleanup += 'sget-object v0, ${main_type}->${name}:Landroid/app/PendingIntent;\nif-eqz v0, :skip_${name}\ninvoke-virtual {v0}, Landroid/app/PendingIntent;->cancel()V\n:skip_${name}\n'
	}
	cleanup += '
iget-object v0, p0, ${main_type}->receiver:${receiver_type}
if-eqz v0, :receiver_done
invoke-virtual {p0, v0}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
const/4 v0, 0
iput-object v0, p0, ${main_type}->receiver:${receiver_type}
:receiver_done
move-object v0, p0
const-string v1, "RECOVERY"
const-string v2, "cleanup"
invoke-static {v0, v1, v2}, ${main_type}->intent(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
move-result-object v0
invoke-virtual {p0, v0}, Landroid/content/Context;->stopService(Landroid/content/Intent;)Z
return-void'
	return method('private cleanup()V', 3, cleanup) + method('private again()V', 4, '
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
const-wide/16 v1, 10
invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
move-result v0
const/4 v1, 1
const-string v2, "fixture continuation must enqueue"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
return-void') + method('public onCreate(Landroid/os/Bundle;)V', 4, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
iput-object v0, p0, ${main_type}->label:Landroid/widget/TextView;
const-string v1, "Testing PendingIntent service recovery"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
new-instance v0, ${context_type}
invoke-direct {v0, p0}, ${context_type}-><init>(Landroid/content/Context;)V
sput-object v0, ${main_type}->senderContext:Landroid/content/Context;
new-instance v0, ${receiver_type}
invoke-direct {v0}, ${receiver_type}-><init>()V
iput-object v0, p0, ${main_type}->receiver:${receiver_type}
new-instance v1, Landroid/content/IntentFilter;
const-string v2, "BROADCAST"
invoke-direct {v1, v2}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v0
const-wide/16 v2, 20000
add-long/2addr v0, v2
iput-wide v0, p0, ${main_type}->deadline:J
invoke-direct {p0}, ${main_type}->again()V
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v0
invoke-static {v0}, ${main_type}->report(Ljava/lang/Throwable;)V
return-void') + method('public run()V', 5, '
:try_start
invoke-static {}, ${main_type}->mainThread()V
iget v0, p0, ${main_type}->stage:I
const/16 v1, 10
if-ge v0, v1, :done
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v0
iget-wide v2, p0, ${main_type}->deadline:J
cmp-long v0, v0, v2
if-ltz v0, :before_deadline
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "timed out waiting for real callback or teardown"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:before_deadline
invoke-direct {p0}, ${main_type}->step()V
iget v0, p0, ${main_type}->stage:I
const/16 v1, 10
if-ge v0, v1, :done
invoke-direct {p0}, ${main_type}->again()V
:done
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v0
invoke-static {v0}, ${main_type}->report(Ljava/lang/Throwable;)V
return-void') + method('public onDestroy()V', 0, '
invoke-direct {p0}, ${main_type}->cleanup()V
invoke-super {p0}, Landroid/app/Activity;->onDestroy()V
return-void')
}

fn main_source() string {
	mut source := '.class public final ${main_type}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.field private stage:I\n.field private deadline:J\n.field private label:Landroid/widget/TextView;\n.field private receiver:${receiver_type}\n.field public static senderContext:Landroid/content/Context;\n'
	for name in ['callbacks', 'serviceCreates', 'serviceDestroys', 'broadcasts', 'mode'] { source += '.field public static ${name}:I\n' }
	for name in ['recovery', 'alias', 'immutable', 'replacement', 'one', 'receiverPI', 'updated'] { source += '.field public static ${name}:Landroid/app/PendingIntent;\n' }
	for name in ['gate', 'done', 'ready'] { source += '.field public static ${name}:Ljava/util/concurrent/CountDownLatch;\n' }
	for name in ['A', 'B'] { source += '.field public static sender${name}:${sender_type}\n.field public static thread${name}:Ljava/lang/Thread;\n' }
	return source + method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') + checks_source() + identity_source() + accept_source() + worker_check_source() + step_source() + lifecycle_source()
}

fn service_source() string {
	mut source := '.class public ${service_type}\n.super Landroid/app/Service;\n' + method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void')
	for signature, field in {'onCreate()V': 'serviceCreates', 'onDestroy()V': 'serviceDestroys'} {
		source += method('public ' + signature, 1, 'invoke-static {}, ${main_type}->mainThread()V\nsget v0, ${main_type}->${field}:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${main_type}->${field}:I\ninvoke-super {p0}, Landroid/app/Service;->${signature}\nreturn-void')
	}
	return source + method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 1, 'const/4 v0, 0\nreturn-object v0') + method('public onStartCommand(Landroid/content/Intent;II)I', 1, '
:try_start
invoke-static {p1}, ${main_type}->accept(Landroid/content/Intent;)V
:try_end
const/4 v0, 2
return v0
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v0
invoke-static {v0}, ${main_type}->report(Ljava/lang/Throwable;)V
const/4 v0, 2
return v0')
}

fn sender_source() string {
	return '.class public final ${sender_type}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private token:Landroid/app/PendingIntent;\n.field private context:Landroid/content/Context;\n.field private seed:I\n.field public result:I\n.field public failure:Ljava/lang/Throwable;\n' + method('public constructor <init>(Landroid/app/PendingIntent;Landroid/content/Context;I)V', 0, '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${sender_type}->token:Landroid/app/PendingIntent;
iput-object p2, p0, ${sender_type}->context:Landroid/content/Context;
iput p3, p0, ${sender_type}->seed:I
return-void') + method('public run()V', 5, '
:outer_start
sget-object v0, ${main_type}->ready:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
sget-object v0, ${main_type}->gate:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v1, 2
sget-object v3, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
const/4 v1, 1
const-string v2, "sender gate must release"
invoke-static {v0, v1, v2}, ${main_type}->eq(IILjava/lang/String;)V
iget v0, p0, ${sender_type}->seed:I
invoke-static {v0}, ${main_type}->fill(I)Landroid/content/Intent;
move-result-object v3
iget-object v0, p0, ${sender_type}->token:Landroid/app/PendingIntent;
iget-object v1, p0, ${sender_type}->context:Landroid/content/Context;
const/4 v2, 0
:send_start
invoke-virtual {v0, v1, v2, v3}, Landroid/app/PendingIntent;->send(Landroid/content/Context;ILandroid/content/Intent;)V
:send_end
const/4 v0, 1
iput v0, p0, ${sender_type}->result:I
goto :sent
.catch Landroid/app/PendingIntent$CanceledException; {:send_start .. :send_end} :canceled
:canceled
move-exception v0
const/4 v0, 2
iput v0, p0, ${sender_type}->result:I
:sent
:outer_end
goto :finish
.catchall {:outer_start .. :outer_end} :failed
:failed
move-exception v0
iput-object v0, p0, ${sender_type}->failure:Ljava/lang/Throwable;
:finish
sget-object v0, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void')
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': main_source()
		'org/vinix/bootstrap/SinkService.smali': service_source()
		'org/vinix/bootstrap/AliasService.smali': '.class public final Lorg/vinix/bootstrap/AliasService;\n.super ${service_type}\n' + method('public constructor <init>()V', 0, 'invoke-direct {p0}, ${service_type}-><init>()V\nreturn-void')
		'org/vinix/bootstrap/SinkReceiver.smali': '.class public final ${receiver_type}\n.super Landroid/content/BroadcastReceiver;\n' + method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V\nreturn-void') + method('public onReceive(Landroid/content/Context;Landroid/content/Intent;)V', 1, '\n:try_start\ninvoke-static {p2}, ${main_type}->acceptBroadcast(Landroid/content/Intent;)V\n:try_end\nreturn-void\n.catchall {:try_start .. :try_end} :failed\n:failed\nmove-exception v0\ninvoke-static {v0}, ${main_type}->report(Ljava/lang/Throwable;)V\nreturn-void')
		'org/vinix/bootstrap/Sender.smali': sender_source()
		'org/vinix/bootstrap/SenderContext.smali': '.class public final ${context_type}\n.super Landroid/content/ContextWrapper;\n' + method('public constructor <init>(Landroid/content/Context;)V', 0, 'invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V\nreturn-void') + method('public getApplicationContext()Landroid/content/Context;', 0, 'return-object p0') + method('public startService(Landroid/content/Intent;)Landroid/content/ComponentName;', 2, 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "sender context must not acquire creator authority"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
	}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/AliasService.smali', 'org/vinix/bootstrap/Main.smali',
		'org/vinix/bootstrap/Sender.smali', 'org/vinix/bootstrap/SenderContext.smali',
		'org/vinix/bootstrap/SinkReceiver.smali', 'org/vinix/bootstrap/SinkService.smali']
}
