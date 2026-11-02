// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const thread_type = 'Lorg/vinix/bootstrap/ReadyHandlerThread;'
const endpoint_type = 'Lorg/vinix/bootstrap/EndpointHandler;'
const reply_type = 'Lorg/vinix/bootstrap/ReplyHandler;'
const forced_type = 'Lorg/vinix/bootstrap/ForcedBinder;'
const thrower_type = 'Lorg/vinix/bootstrap/ThrowingParcelable;'
const msg_type = 'Landroid/os/Message;'
const parcel_type = 'Landroid/os/Parcel;'
const messenger_type = 'Landroid/os/Messenger;'
const binder_type = 'Landroid/os/IBinder;'
const pass_marker = 'MESSENGER-BINDER-PASS endpoint-identity local-proxy queued-reply token-oneway cloned-payload sending-uid parcel-copy-reset null-errors bounded-worker'
const fail_marker = 'MESSENGER-BINDER-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn bad(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn helpers_source() string {
	return method('public static equal(IILjava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static truth(ZLjava/lang/String;)V', 1, '
if-nez p0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static text(Ljava/lang/Object;Ljava/lang/String;)V', 2, '
instance-of v0, p0, Ljava/lang/String;
if-eqz v0, :bad
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
' + bad('exact String value required'))
}

fn await_source() string {
	return method('private static await(Ljava/util/concurrent/CountDownLatch;)V', 6, '
sget-wide v0, ${main_type}->deadline:J
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v2
sub-long/2addr v0, v2
const-wide/16 v2, 0
cmp-long v4, v0, v2
if-lez v4, :bad
sget-object v2, Ljava/util/concurrent/TimeUnit;->NANOSECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {p0, v0, v1, v2}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
if-eqz v0, :bad
sget-object v0, ${main_type}->failure:Ljava/lang/Throwable;
if-eqz v0, :done
throw v0
:done
return-void
' + bad('Messenger worker callback or barrier exceeded the shared deadline')) +
		method('private static barrier(Landroid/os/Handler;${main_type})V', 3, '
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
sput-object v0, ${main_type}->barrierLatch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {p0, p1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v1
const-string v2, "worker barrier must be accepted"
invoke-static {v1, v2}, ${main_type}->truth(ZLjava/lang/String;)V
invoke-static {v0}, ${main_type}->await(Ljava/util/concurrent/CountDownLatch;)V
return-void') + method('public run()V', 1, '
sget-object v0, ${main_type}->barrierLatch:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void')
}

fn ready_thread_source() string {
	return '.class public final ${thread_type}\n.super Landroid/os/HandlerThread;\n' +
		'.field public volatile preparedLooper:Landroid/os/Looper;\n.field private final ready:Ljava/util/concurrent/CountDownLatch;\n' +
		method('public constructor <init>()V', 2, '
const-string v0, "messenger-binder-fixture"
invoke-direct {p0, v0}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, ${thread_type}->ready:Ljava/util/concurrent/CountDownLatch;
return-void') + method('protected onLooperPrepared()V', 1, '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
iput-object v0, p0, ${thread_type}->preparedLooper:Landroid/os/Looper;
iget-object v0, p0, ${thread_type}->ready:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void') + method('public awaitLooper(J)Landroid/os/Looper;', 6, '
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v0
sub-long v0, p1, v0
const-wide/16 v2, 0
cmp-long v4, v0, v2
if-lez v4, :bad
iget-object v2, p0, ${thread_type}->ready:Ljava/util/concurrent/CountDownLatch;
sget-object v3, Ljava/util/concurrent/TimeUnit;->NANOSECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v2, v0, v1, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v2
if-eqz v2, :bad
iget-object v0, p0, ${thread_type}->preparedLooper:Landroid/os/Looper;
if-eqz v0, :bad
return-object v0
' + bad('worker startup must publish its Looper before the shared deadline'))
}

fn handler_source(name string, entry string, reply bool) string {
	owner := 'Lorg/vinix/bootstrap/${name};'
	finish := if reply { 'goto :complete\n' } else { 'return-void\n' }
	return '.class public final ${owner}\n.super Landroid/os/Handler;\n' +
		method('public constructor <init>(Landroid/os/Looper;)V', 0, 'invoke-direct {p0, p1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V\nreturn-void') +
		method('public handleMessage(${msg_type})V', 2, '
:try_start
invoke-static {p1}, ${main_type}->${entry}(${msg_type})V
:try_end
' + finish + '
:failed
move-exception v0
sput-object v0, ${main_type}->failure:Ljava/lang/Throwable;
:complete
sget-object v1, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v1}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void
.catchall {:try_start .. :try_end} :failed')
}

fn forced_binder_source() string {
	return '.class public final ${forced_type}\n.super Landroid/os/Binder;\n' +
		'.field public final delegate:${binder_type}\n.field public calls:I\n.field public presence:I\n' +
		'.field public failure:Landroid/os/RemoteException;\n.field public drop:Z\n' +
		method('public constructor <init>(${binder_type})V', 0, '
invoke-direct {p0}, Landroid/os/Binder;-><init>()V
iput-object p1, p0, ${forced_type}->delegate:${binder_type}
return-void') + method('public queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;', 1, 'const/4 v0, 0\nreturn-object v0') +
		method('public getInterfaceDescriptor()Ljava/lang/String;', 1, 'const-string v0, "android.os.IMessenger"\nreturn-object v0') +
		method('protected onTransact(I${parcel_type}${parcel_type}I)Z', 4, '
iget v0, p0, ${forced_type}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${forced_type}->calls:I
const/4 v0, 1
const-string v1, "forced proxy must use transaction code one"
invoke-static {p1, v0, v1}, ${main_type}->equal(IILjava/lang/String;)V
const-string v1, "forced proxy must use FLAG_ONEWAY"
invoke-static {p4, v0, v1}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v0, 0
const-string v1, "oneway proxy must pass a null reply Parcel"
invoke-static {p3, v0, v1}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p2}, ${parcel_type}->readString()Ljava/lang/String;
move-result-object v0
const-string v1, "android.os.IMessenger"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p2}, ${parcel_type}->readInt()I
move-result v0
iput v0, p0, ${forced_type}->presence:I
const/4 v1, 1
const-string v2, "forced proxy must write the Message presence marker"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v0, 0
invoke-virtual {p2, v0}, ${parcel_type}->setDataPosition(I)V
iget-object v0, p0, ${forced_type}->failure:Landroid/os/RemoteException;
if-eqz v0, :not_throwing
throw v0
:not_throwing
iget-boolean v0, p0, ${forced_type}->drop:Z
if-eqz v0, :forward
const/4 v0, 0
return v0
:forward
iget-object v0, p0, ${forced_type}->delegate:${binder_type}
invoke-interface {v0, p1, p2, p3, p4}, ${binder_type}->transact(I${parcel_type}${parcel_type}I)Z
move-result v0
return v0')
}

fn protocol_source() string {
	return method('private static assertWorker()V', 3, '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
sget-object v1, ${main_type}->workerLooper:Landroid/os/Looper;
const-string v2, "request and reply must run on the dedicated worker Looper"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
sget-object v1, ${main_type}->launchThread:Ljava/lang/Thread;
const-string v2, "Messenger delivery must not execute inline on the sender thread"
invoke-static {v0, v1, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void') + method('public static receive(${msg_type})V', 8, '
invoke-static {}, ${main_type}->assertWorker()V
sget v0, ${main_type}->requestCount:I
add-int/lit8 v0, v0, 1
sput v0, ${main_type}->requestCount:I
iget v0, p0, ${msg_type}->what:I
const/4 v1, 1
const-string v2, "request what must be one"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${msg_type}->arg1:I
sget v1, ${main_type}->expectedStage:I
const-string v2, "request arg1 must preserve the current sequence"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${msg_type}->arg2:I
const/16 v1, 0x77
const-string v2, "request arg2 must survive transport"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${msg_type}->sendingUid:I
sget v1, ${main_type}->expectedUid:I
const-string v2, "Handler endpoint must overwrite the claimed Message UID before enqueue"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
sget-object v0, ${main_type}->original:${msg_type}
sget-boolean v1, ${main_type}->expectedClone:Z
const-string v2, "local identity and proxy Message cloning must be distinct"
if-eqz v1, :local_message
invoke-static {p0, v0, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
goto :payload
:local_message
invoke-static {p0, v0, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
:payload
invoke-virtual {p0}, ${msg_type}->getData()Landroid/os/Bundle;
move-result-object v3
sget-object v4, ${main_type}->originalData:Landroid/os/Bundle;
iget-object v5, p0, ${msg_type}->obj:Ljava/lang/Object;
sget-object v6, ${main_type}->originalObj:Landroid/content/ComponentName;
const-string v2, "proxy payload must clone Parcelable object and Bundle"
if-eqz v1, :local_payload
invoke-static {v3, v4, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v5, v6, v2}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
goto :payload_values
:local_payload
invoke-static {v3, v4, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v5, v6, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
:payload_values
check-cast v5, Landroid/content/ComponentName;
invoke-virtual {v5}, Landroid/content/ComponentName;->flattenToString()Ljava/lang/String;
move-result-object v0
invoke-virtual {v6}, Landroid/content/ComponentName;->flattenToString()Ljava/lang/String;
move-result-object v1
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "component"
invoke-virtual {v3, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "component-value"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "tag"
invoke-virtual {v3, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "messenger-tag"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
iget-object v4, p0, ${msg_type}->replyTo:${messenger_type}
invoke-virtual {v4}, ${messenger_type}->getBinder()${binder_type}
move-result-object v0
sget-object v1, ${main_type}->expectedReplyBinder:${binder_type}
const-string v2, "request replyTo must preserve the real reply endpoint Binder"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, ${msg_type}->obtain()${msg_type}
move-result-object v0
const/4 v1, 3
iput v1, v0, ${msg_type}->what:I
const/16 v1, 17
iput v1, v0, ${msg_type}->arg1:I
sget v1, ${main_type}->expectedStage:I
iput v1, v0, ${msg_type}->arg2:I
const v1, -22222
iput v1, v0, ${msg_type}->sendingUid:I
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1, v3}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V
invoke-virtual {v0, v1}, ${msg_type}->setData(Landroid/os/Bundle;)V
invoke-virtual {v4, v0}, ${messenger_type}->send(${msg_type})V
return-void') + method('public static reply(${msg_type})V', 4, '
invoke-static {}, ${main_type}->assertWorker()V
sget v0, ${main_type}->replyCount:I
add-int/lit8 v0, v0, 1
sput v0, ${main_type}->replyCount:I
iget v0, p0, ${msg_type}->what:I
const/4 v1, 3
const-string v2, "reply what must be three"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${msg_type}->arg1:I
const/16 v1, 17
const-string v2, "reply result arg1 must be preserved"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${msg_type}->arg2:I
sget v1, ${main_type}->expectedStage:I
const-string v2, "reply arg2 must identify the current request"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
iget v0, p0, ${msg_type}->sendingUid:I
sget v1, ${main_type}->expectedUid:I
const-string v2, "reply UID gate must observe the actual local Binder caller"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0}, ${msg_type}->getData()Landroid/os/Bundle;
move-result-object v3
const-string v0, "component"
invoke-virtual {v3, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "component-value"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
const-string v0, "tag"
invoke-virtual {v3, v0}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "messenger-tag"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
return-void')
}

fn request_source() string {
	return method('private static request(${messenger_type}I)${msg_type}', 5, '
invoke-static {}, ${msg_type}->obtain()${msg_type}
move-result-object v0
const/4 v1, 1
iput v1, v0, ${msg_type}->what:I
iput p1, v0, ${msg_type}->arg1:I
const/16 v1, 0x77
iput v1, v0, ${msg_type}->arg2:I
const v1, -31337
iput v1, v0, ${msg_type}->sendingUid:I
iput-object p0, v0, ${msg_type}->replyTo:${messenger_type}
new-instance v1, Landroid/content/ComponentName;
const-string v2, "org.vinix.bootstrap"
const-string v3, "org.vinix.bootstrap.EndpointHandler"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
iput-object v1, v0, ${msg_type}->obj:Ljava/lang/Object;
sput-object v1, ${main_type}->originalObj:Landroid/content/ComponentName;
new-instance v4, Landroid/os/Bundle;
invoke-direct {v4}, Landroid/os/Bundle;-><init>()V
const-string v1, "component"
const-string v2, "component-value"
invoke-virtual {v4, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "tag"
const-string v2, "messenger-tag"
invoke-virtual {v4, v1, v2}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v4}, ${msg_type}->setData(Landroid/os/Bundle;)V
sput-object v4, ${main_type}->originalData:Landroid/os/Bundle;
return-object v0') + method('private static deliver(${messenger_type}${messenger_type}ZI)V', 4, '
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
sput-object v0, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
sput-boolean p2, ${main_type}->expectedClone:Z
sput p3, ${main_type}->expectedStage:I
invoke-static {p1, p3}, ${main_type}->request(${messenger_type}I)${msg_type}
move-result-object v1
sput-object v1, ${main_type}->original:${msg_type}
invoke-virtual {p0, v1}, ${messenger_type}->send(${msg_type})V
invoke-static {v0}, ${main_type}->await(Ljava/util/concurrent/CountDownLatch;)V
sget v2, ${main_type}->requestCount:I
const-string v3, "exact request callback count after completed reply"
invoke-static {v2, p3, v3}, ${main_type}->equal(IILjava/lang/String;)V
sget v2, ${main_type}->replyCount:I
const-string v3, "exact reply callback count after completed reply"
invoke-static {v2, p3, v3}, ${main_type}->equal(IILjava/lang/String;)V
# Local messages belong to the queue; their recycled fields are never read here.
if-eqz p2, :done
invoke-virtual {v1}, ${msg_type}->recycle()V
:done
return-void')
}

fn identity_source() string {
	return method('private static identity(${messenger_type}${messenger_type}${messenger_type})V', 5, '
invoke-virtual {p0}, ${messenger_type}->getBinder()${binder_type}
move-result-object v0
invoke-virtual {p1}, ${messenger_type}->getBinder()${binder_type}
move-result-object v1
const-string v2, "two Messengers for one Handler must retain its cached Binder"
invoke-static {v0, v1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-interface {v0}, ${binder_type}->getInterfaceDescriptor()Ljava/lang/String;
move-result-object v1
const-string v2, "android.os.IMessenger"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p0, p1}, ${messenger_type}->equals(Ljava/lang/Object;)Z
move-result v1
const-string v2, "same Handler Messengers must compare equal"
invoke-static {v1, v2}, ${main_type}->truth(ZLjava/lang/String;)V
invoke-virtual {p1, p0}, ${messenger_type}->equals(Ljava/lang/Object;)Z
move-result v1
invoke-static {v1, v2}, ${main_type}->truth(ZLjava/lang/String;)V
invoke-virtual {p0}, ${messenger_type}->hashCode()I
move-result v1
invoke-virtual {p1}, ${messenger_type}->hashCode()I
move-result v2
const-string v3, "same Binder Messenger hashes must agree"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Object;->hashCode()I
move-result v2
const-string v3, "Messenger hash must use its Binder identity"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {p0, p2}, ${messenger_type}->equals(Ljava/lang/Object;)Z
move-result v1
const/4 v2, 0
const-string v3, "different Binder identities must compare unequal"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v4, 0
invoke-virtual {p0, v4}, ${messenger_type}->equals(Ljava/lang/Object;)Z
move-result v1
const-string v3, "Messenger equals null must be false"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const-string v4, "not a Messenger"
invoke-virtual {p0, v4}, ${messenger_type}->equals(Ljava/lang/Object;)Z
move-result v1
const-string v3, "Messenger equals non-Messenger must be false"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
return-void') + method('private static messengerParcel(${messenger_type})V', 6, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:try_start
const/4 v1, 0
invoke-virtual {p0, v0, v1}, ${messenger_type}->writeToParcel(${parcel_type}I)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
sget-object v2, ${messenger_type}->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v2, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel_type})Ljava/lang/Object;
move-result-object v3
check-cast v3, ${messenger_type}
invoke-virtual {v3}, ${messenger_type}->getBinder()${binder_type}
move-result-object v3
invoke-virtual {p0}, ${messenger_type}->getBinder()${binder_type}
move-result-object v4
const-string v5, "same-Parcel Messenger CREATOR must preserve strong Binder identity"
invoke-static {v3, v4, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataSize(I)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
invoke-static {p0, v0}, ${messenger_type}->writeMessengerOrNullToParcel(${messenger_type}${parcel_type})V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
invoke-static {v0}, ${messenger_type}->readMessengerOrNullFromParcel(${parcel_type})${messenger_type}
move-result-object v3
invoke-virtual {v3}, ${messenger_type}->getBinder()${binder_type}
move-result-object v3
invoke-static {v3, v4, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataSize(I)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
const/4 v3, 0
invoke-static {v3, v0}, ${messenger_type}->writeMessengerOrNullToParcel(${messenger_type}${parcel_type})V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
invoke-static {v0}, ${messenger_type}->readMessengerOrNullFromParcel(${parcel_type})${messenger_type}
move-result-object v4
const-string v5, "null Messenger helpers must roundtrip null"
invoke-static {v4, v3, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
invoke-interface {v2, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel_type})Ljava/lang/Object;
move-result-object v4
invoke-static {v4, v3, v5}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v3, 2
invoke-interface {v2, v3}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v4
instance-of v1, v4, [Landroid/os/Messenger;
const-string v5, "Messenger CREATOR must construct Messenger arrays"
invoke-static {v1, v5}, ${main_type}->truth(ZLjava/lang/String;)V
array-length v1, v4
invoke-static {v1, v3, v5}, ${main_type}->equal(IILjava/lang/String;)V
:try_end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
:failed
move-exception v5
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v5
.catchall {:try_start .. :try_end} :failed')
}

fn transaction_source() string {
	return method('private static badToken(${binder_type})V', 5, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:outer_start
const-string v1, "fixture.wrong.IMessenger"
invoke-virtual {v0, v1}, ${parcel_type}->writeInterfaceToken(Ljava/lang/String;)V
const/4 v1, 0
invoke-virtual {v0, v1}, ${parcel_type}->writeInt(I)V
const/4 v1, 1
const/4 v2, 0
:send_start
invoke-interface {p0, v1, v0, v2, v1}, ${binder_type}->transact(I${parcel_type}${parcel_type}I)Z
:send_end
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "wrong Messenger token must be rejected"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:denied
move-exception v3
:outer_end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
:failed
move-exception v4
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v4
.catch Ljava/lang/SecurityException; {:send_start .. :send_end} :denied
.catchall {:outer_start .. :send_start} :failed
.catchall {:send_start .. :send_end} :failed
.catchall {:send_end .. :outer_end} :failed') +
		method('private static nullSend(${messenger_type})V', 3, '
const/4 v0, 0
:try_start
invoke-virtual {p0, v0}, ${messenger_type}->send(${msg_type})V
:try_end
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "local Messenger null send must throw NPE"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:caught
move-exception v2
return-void
.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :caught') +
		method('private static unknownTransaction(${binder_type})V', 5, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:try_start
const/16 v1, 0x46
const/4 v2, 0
const/4 v3, 1
invoke-interface {p0, v1, v0, v2, v3}, ${binder_type}->transact(I${parcel_type}${parcel_type}I)Z
move-result v1
const-string v3, "unknown Binder transaction must remain unhandled"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
:try_end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
:failed
move-exception v4
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v4
.catchall {:try_start .. :try_end} :failed')
}

fn transport_errors_source() string {
	return method('private static transportErrors(${messenger_type}${forced_type}${messenger_type}Landroid/os/Handler;${main_type})V', 6, '
const/16 v0, 7
invoke-static {p2, v0}, ${main_type}->request(${messenger_type}I)${msg_type}
move-result-object v0
new-instance v1, Landroid/os/RemoteException;
invoke-direct {v1}, Landroid/os/RemoteException;-><init>()V
iput-object v1, p1, ${forced_type}->failure:Landroid/os/RemoteException;
:try_start
invoke-virtual {p0, v0}, ${messenger_type}->send(${msg_type})V
:try_end
new-instance v2, Ljava/lang/AssertionError;
const-string v3, "throwing transport must preserve RemoteException"
invoke-direct {v2, v3}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v2
:caught
move-exception v2
const-string v3, "proxy must preserve the exact transport exception"
invoke-static {v2, v1, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const/4 v2, 0
iput-object v2, p1, ${forced_type}->failure:Landroid/os/RemoteException;
iget v3, p1, ${forced_type}->calls:I
const/4 v4, 2
const-string v5, "throwing proxy must make exactly one transport call"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v3, 1
iput-boolean v3, p1, ${forced_type}->drop:Z
# API-28 AIDL ignores transact=false. This controlled wrapper does not forward.
invoke-virtual {p0, v0}, ${messenger_type}->send(${msg_type})V
iget v3, p1, ${forced_type}->calls:I
const/4 v4, 3
const-string v5, "false transport result must be ignored without retry or delivery claim"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
iput-boolean v2, p1, ${forced_type}->drop:Z
invoke-static {p3, p4}, ${main_type}->barrier(Landroid/os/Handler;${main_type})V
sget v3, ${main_type}->requestCount:I
const-string v5, "nonforwarding error controls must not reach the endpoint after a queue barrier"
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
sget v3, ${main_type}->replyCount:I
invoke-static {v3, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, ${msg_type}->recycle()V
return-void
.catch Landroid/os/RemoteException; {:try_start .. :try_end} :caught')
}

fn tests_source() string {
	return method('private static tests(${main_type})V', 10, '
invoke-static {}, Landroid/os/Binder;->getCallingUid()I
move-result v0
sput v0, ${main_type}->expectedUid:I
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v1
const-string v2, "in-process endpoint UID must match the real isolated fixture UID"
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
const/16 v1, 10150
invoke-static {v0, v1, v2}, ${main_type}->equal(IILjava/lang/String;)V
sget-object v0, ${main_type}->workerLooper:Landroid/os/Looper;
new-instance v1, ${endpoint_type}
invoke-direct {v1, v0}, ${endpoint_type}-><init>(Landroid/os/Looper;)V
new-instance v2, ${reply_type}
invoke-direct {v2, v0}, ${reply_type}-><init>(Landroid/os/Looper;)V
new-instance v3, ${messenger_type}
invoke-direct {v3, v1}, ${messenger_type}-><init>(Landroid/os/Handler;)V
new-instance v4, ${messenger_type}
invoke-direct {v4, v1}, ${messenger_type}-><init>(Landroid/os/Handler;)V
new-instance v5, ${messenger_type}
invoke-direct {v5, v2}, ${messenger_type}-><init>(Landroid/os/Handler;)V
invoke-virtual {v5}, ${messenger_type}->getBinder()${binder_type}
move-result-object v6
sput-object v6, ${main_type}->expectedReplyBinder:${binder_type}
invoke-static {v3, v4, v5}, ${main_type}->identity(${messenger_type}${messenger_type}${messenger_type})V
invoke-static {v3}, ${main_type}->messengerParcel(${messenger_type})V
invoke-static {v5, p0}, ${main_type}->messageControls(${messenger_type}${main_type})V
invoke-virtual {v3}, ${messenger_type}->getBinder()${binder_type}
move-result-object v6
new-instance v4, ${messenger_type}
invoke-direct {v4, v6}, ${messenger_type}-><init>(${binder_type})V
invoke-static {v3, v4, v5}, ${main_type}->identity(${messenger_type}${messenger_type}${messenger_type})V
const/4 v7, 0
const/4 v8, 1
invoke-static {v3, v5, v7, v8}, ${main_type}->deliver(${messenger_type}${messenger_type}ZI)V
const/4 v8, 2
invoke-static {v4, v5, v7, v8}, ${main_type}->deliver(${messenger_type}${messenger_type}ZI)V
new-instance v7, ${forced_type}
invoke-direct {v7, v6}, ${forced_type}-><init>(${binder_type})V
new-instance v8, ${messenger_type}
invoke-direct {v8, v7}, ${messenger_type}-><init>(${binder_type})V
new-instance v9, ${messenger_type}
invoke-direct {v9, v7}, ${messenger_type}-><init>(${binder_type})V
invoke-static {v8, v9, v3}, ${main_type}->identity(${messenger_type}${messenger_type}${messenger_type})V
const/4 v0, 1
const/4 v2, 3
invoke-static {v8, v5, v0, v2}, ${main_type}->deliver(${messenger_type}${messenger_type}ZI)V
iget v0, v7, ${forced_type}->calls:I
const/4 v2, 1
const-string v4, "forced proxy must forward exactly one valid request"
invoke-static {v0, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v6}, ${main_type}->badToken(${binder_type})V
invoke-static {v6}, ${main_type}->unknownTransaction(${binder_type})V
invoke-static {v3}, ${main_type}->nullSend(${messenger_type})V
invoke-static {v1, p0}, ${main_type}->barrier(Landroid/os/Handler;${main_type})V
sget v0, ${main_type}->requestCount:I
const/4 v2, 3
const-string v4, "rejected token, unknown transaction and null send must not enqueue after barrier"
invoke-static {v0, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
sget v0, ${main_type}->replyCount:I
invoke-static {v0, v2, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-static {v8, v7, v5, v1, p0}, ${main_type}->transportErrors(${messenger_type}${forced_type}${messenger_type}Landroid/os/Handler;${main_type})V
return-void')
}

fn message_fixture_method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn message_controls_source() string {
	return message_fixture_method('private static messageLong(JJLjava/lang/String;)V', 1, '
cmp-long v0, p0, p2
if-eqz v0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p4}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + message_fixture_method('private static messageReject(${msg_type}Ljava/lang/RuntimeException;ZLjava/lang/String;)V', 4, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:outer_start
const/4 v1, 0
:attempt_start
invoke-virtual {p0, v0, v1}, ${msg_type}->writeToParcel(${parcel_type}I)V
:attempt_end
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "unsupported Message payload must throw"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:caught
move-exception v1
if-eqz p2, :identity
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v2
const-class v3, Ljava/lang/RuntimeException;
invoke-static {v2, v3, p3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v2
invoke-static {v2, p3}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
if-eqz p1, :checked
invoke-static {v1, p1, p3}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
goto :checked
:identity
const-string v2, "ordinary Parcelable failure identity must propagate"
invoke-static {v1, p1, v2}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
goto :checked
:checked
:outer_end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
.catch Ljava/lang/RuntimeException; {:attempt_start .. :attempt_end} :caught
.catchall {:outer_start .. :attempt_start} :failed
.catchall {:attempt_start .. :attempt_end} :failed
.catchall {:attempt_end .. :outer_end} :failed
:failed
move-exception v1
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v1') + message_fixture_method('private static messageWrite(${msg_type}Landroid/os/Messenger;)V', 9, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:begin
const/4 v1, 0
invoke-virtual {p0, v0, v1}, ${msg_type}->writeToParcel(${parcel_type}I)V
invoke-virtual {v0, v1}, ${parcel_type}->setDataPosition(I)V
invoke-virtual {v0}, ${parcel_type}->readInt()I
move-result v1
const/16 v2, 0x123
const-string v3, "Message wire what must be first"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readInt()I
move-result v1
const/16 v2, 0x44
const-string v3, "Message wire arg1 must be second"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readInt()I
move-result v1
const/4 v2, -7
const-string v3, "Message wire arg2 must be third"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readInt()I
move-result v1
const/4 v2, 1
const-string v3, "nonnull Message obj must have presence word one"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const/4 v1, 0
invoke-virtual {v0, v1}, ${parcel_type}->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;
move-result-object v1
iget-object v2, p0, ${msg_type}->obj:Ljava/lang/Object;
const-string v3, "Parcelable object must cross the Parcel as a copy"
invoke-static {v1, v2, v3}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v2, v1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v1
const-string v3, "Parcelable component value must survive Message writing"
invoke-static {v1, v3}, ${main_type}->truth(ZLjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readLong()J
move-result-wide v1
const-wide v3, 0x100000001L
const-string v5, "Message when must follow obj"
invoke-static {v1, v2, v3, v4, v5}, ${main_type}->messageLong(JJLjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readBundle()Landroid/os/Bundle;
move-result-object v1
invoke-virtual {p0}, ${msg_type}->getData()Landroid/os/Bundle;
move-result-object v2
const-string v3, "Message Bundle must be read as a copy"
invoke-static {v1, v2, v3}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v2, "payload"
invoke-virtual {v1, v2}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "message-wire"
invoke-static {v1, v2}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readStrongBinder()Landroid/os/IBinder;
move-result-object v1
invoke-virtual {p1}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;
move-result-object v2
const-string v3, "Message replyTo must preserve same-Parcel strong Binder identity"
invoke-static {v1, v2, v3}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->readInt()I
move-result v1
const v2, 0x123456
const-string v3, "Message sendingUid is the final wire field"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->dataAvail()I
move-result v1
const/4 v2, 0
const-string v3, "exact API28 Message payload must consume the Parcel"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v0, v2}, ${parcel_type}->setDataPosition(I)V
sget-object v1, ${msg_type}->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v1, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel_type})Ljava/lang/Object;
move-result-object v1
const-string v3, "Message Creator must allocate a different Message"
invoke-static {v1, p0, v3}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
check-cast v1, ${msg_type}
iget v2, v1, ${msg_type}->sendingUid:I
const v3, 0x123456
const-string v4, "Creator wire UID is payload before Handler overwrites it"
invoke-static {v2, v3, v4}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v1}, ${msg_type}->recycle()V
:end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
.catchall {:begin .. :end} :failed
:failed
move-exception v8
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v8') + message_fixture_method('private static messagePayload(Landroid/os/Messenger;)V', 9, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:begin
const/16 v2, 0x123
invoke-virtual {v0, v2}, ${parcel_type}->writeInt(I)V
const/16 v2, 0x44
invoke-virtual {v0, v2}, ${parcel_type}->writeInt(I)V
const/4 v2, -7
invoke-virtual {v0, v2}, ${parcel_type}->writeInt(I)V
const/4 v2, 1
invoke-virtual {v0, v2}, ${parcel_type}->writeInt(I)V
new-instance v1, Landroid/content/ComponentName;
const-string v2, "org.vinix.bootstrap"
const-string v3, "org.vinix.bootstrap.Main"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v2, 0
invoke-virtual {v0, v1, v2}, ${parcel_type}->writeParcelable(Landroid/os/Parcelable;I)V
const-wide v2, 0x100000001L
invoke-virtual {v0, v2, v3}, ${parcel_type}->writeLong(J)V
new-instance v4, Landroid/os/Bundle;
invoke-direct {v4}, Landroid/os/Bundle;-><init>()V
const-string v2, "payload"
const-string v3, "message-wire"
invoke-virtual {v4, v2, v3}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0, v4}, ${parcel_type}->writeBundle(Landroid/os/Bundle;)V
invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;
move-result-object v2
invoke-virtual {v0, v2}, ${parcel_type}->writeStrongBinder(Landroid/os/IBinder;)V
const v2, 0x123456
invoke-virtual {v0, v2}, ${parcel_type}->writeInt(I)V
const/4 v2, 0
invoke-virtual {v0, v2}, ${parcel_type}->setDataPosition(I)V
sget-object v2, ${msg_type}->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v2, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel_type})Ljava/lang/Object;
move-result-object v5
check-cast v5, ${msg_type}
iget v2, v5, ${msg_type}->what:I
const/16 v3, 0x123
const-string v8, "Message Creator must read manual what"
invoke-static {v2, v3, v8}, ${main_type}->equal(IILjava/lang/String;)V
iget v2, v5, ${msg_type}->arg1:I
const/16 v3, 0x44
const-string v8, "Message Creator must read manual arg1"
invoke-static {v2, v3, v8}, ${main_type}->equal(IILjava/lang/String;)V
iget v2, v5, ${msg_type}->arg2:I
const/4 v3, -7
const-string v8, "Message Creator must read manual arg2"
invoke-static {v2, v3, v8}, ${main_type}->equal(IILjava/lang/String;)V
iget-object v2, v5, ${msg_type}->obj:Ljava/lang/Object;
const-string v8, "Creator object must be a Parcelable value copy"
invoke-static {v2, v1, v8}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v1, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v2
const-string v8, "Creator must read the manual Parcelable component"
invoke-static {v2, v8}, ${main_type}->truth(ZLjava/lang/String;)V
invoke-virtual {v5}, ${msg_type}->getData()Landroid/os/Bundle;
move-result-object v2
const-string v8, "Creator Bundle must be independent of manual source"
invoke-static {v2, v4, v8}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v3, "payload"
invoke-virtual {v2, v3}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v2
const-string v3, "message-wire"
invoke-static {v2, v3}, ${main_type}->text(Ljava/lang/Object;Ljava/lang/String;)V
iget-object v2, v5, ${msg_type}->replyTo:Landroid/os/Messenger;
invoke-virtual {v2}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;
move-result-object v2
invoke-virtual {p0}, Landroid/os/Messenger;->getBinder()Landroid/os/IBinder;
move-result-object v3
const-string v8, "Creator reply Binder must survive on this same Parcel"
invoke-static {v2, v3, v8}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v5}, ${msg_type}->getWhen()J
move-result-wide v6
const-wide v2, 0x100000001L
const-string v8, "Creator must read manual 64-bit when"
invoke-static {v6, v7, v2, v3, v8}, ${main_type}->messageLong(JJLjava/lang/String;)V
invoke-static {v5, p0}, ${main_type}->messageWrite(${msg_type}Landroid/os/Messenger;)V
invoke-virtual {v5}, ${msg_type}->recycle()V
:end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
.catchall {:begin .. :end} :failed
:failed
move-exception v8
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v8') + message_fixture_method('private static messageControls(Landroid/os/Messenger;Lorg/vinix/bootstrap/Main;)V', 7, '
new-instance v0, ${msg_type}
invoke-direct {v0}, ${msg_type}-><init>()V
iget v1, v0, ${msg_type}->sendingUid:I
const/4 v2, -1
const-string v3, "new Message sender UID must be unknown"
invoke-static {v1, v2, v3}, ${main_type}->equal(IILjava/lang/String;)V
const v1, 0x12345
iput v1, v0, ${msg_type}->sendingUid:I
invoke-static {v0}, ${msg_type}->obtain(${msg_type})${msg_type}
move-result-object v2
iget v3, v2, ${msg_type}->sendingUid:I
const-string v4, "Message.obtain copy must preserve sender UID"
invoke-static {v3, v1, v4}, ${main_type}->equal(IILjava/lang/String;)V
new-instance v3, ${msg_type}
invoke-direct {v3}, ${msg_type}-><init>()V
invoke-virtual {v3, v0}, ${msg_type}->copyFrom(${msg_type})V
iget v4, v3, ${msg_type}->sendingUid:I
const-string v5, "Message.copyFrom must preserve sender UID"
invoke-static {v4, v1, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v2}, ${msg_type}->recycle()V
const/4 v4, -1
invoke-static {}, ${msg_type}->obtain()${msg_type}
move-result-object v1
iget v2, v1, ${msg_type}->sendingUid:I
const-string v5, "pooled Message sender UID must remain unknown"
invoke-static {v2, v4, v5}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v1}, ${msg_type}->recycle()V
invoke-virtual {v3}, ${msg_type}->recycle()V
invoke-virtual {v0}, ${msg_type}->recycle()V
invoke-static {p0}, ${main_type}->messagePayload(Landroid/os/Messenger;)V
invoke-static {}, ${main_type}->messageNullPayload()V
sget-object v0, ${msg_type}->CREATOR:Landroid/os/Parcelable$Creator;
const/4 v1, 3
invoke-interface {v0, v1}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v0
instance-of v2, v0, [Landroid/os/Message;
const-string v3, "Message Creator must allocate Message arrays"
invoke-static {v2, v3}, ${main_type}->truth(ZLjava/lang/String;)V
array-length v2, v0
const-string v3, "Message Creator array length must match"
invoke-static {v2, v1, v3}, ${main_type}->equal(IILjava/lang/String;)V
new-instance v0, ${msg_type}
invoke-direct {v0}, ${msg_type}-><init>()V
new-instance v1, Ljava/lang/Object;
invoke-direct {v1}, Ljava/lang/Object;-><init>()V
iput-object v1, v0, ${msg_type}->obj:Ljava/lang/Object;
const/4 v1, 0
const/4 v2, 1
const-string v3, "Can\'t marshal non-Parcelable objects across processes."
invoke-static {v0, v1, v2, v3}, ${main_type}->messageReject(${msg_type}Ljava/lang/RuntimeException;ZLjava/lang/String;)V
const/4 v4, 0
invoke-static {v4, p1}, ${msg_type}->obtain(Landroid/os/Handler;Ljava/lang/Runnable;)${msg_type}
move-result-object v4
const-string v3, "Can\'t marshal callbacks across processes."
invoke-static {v4, v1, v2, v3}, ${main_type}->messageReject(${msg_type}Ljava/lang/RuntimeException;ZLjava/lang/String;)V
invoke-virtual {v4}, ${msg_type}->recycle()V
new-instance v1, Ljava/lang/ClassCastException;
invoke-direct {v1}, Ljava/lang/ClassCastException;-><init>()V
new-instance v4, ${thrower_type}
invoke-direct {v4, v1}, ${thrower_type}-><init>(Ljava/lang/RuntimeException;)V
iput-object v4, v0, ${msg_type}->obj:Ljava/lang/Object;
const-string v3, "Can\'t marshal non-Parcelable objects across processes."
invoke-static {v0, v1, v2, v3}, ${main_type}->messageReject(${msg_type}Ljava/lang/RuntimeException;ZLjava/lang/String;)V
new-instance v1, Ljava/lang/SecurityException;
invoke-direct {v1}, Ljava/lang/SecurityException;-><init>()V
new-instance v4, ${thrower_type}
invoke-direct {v4, v1}, ${thrower_type}-><init>(Ljava/lang/RuntimeException;)V
iput-object v4, v0, ${msg_type}->obj:Ljava/lang/Object;
const/4 v2, 0
const/4 v3, 0
invoke-static {v0, v1, v2, v3}, ${main_type}->messageReject(${msg_type}Ljava/lang/RuntimeException;ZLjava/lang/String;)V
invoke-virtual {v0}, ${msg_type}->recycle()V
return-void') + message_null_payload_source()
}

fn message_null_payload_source() string {
	return message_fixture_method('private static messageNullPayload()V', 8, '
invoke-static {}, ${parcel_type}->obtain()${parcel_type}
move-result-object v0
:begin
new-instance v1, ${msg_type}
invoke-direct {v1}, ${msg_type}-><init>()V
const/4 v3, 0
invoke-virtual {v1, v0, v3}, ${msg_type}->writeToParcel(${parcel_type}I)V
invoke-virtual {v0, v3}, ${parcel_type}->setDataPosition(I)V
sget-object v2, ${msg_type}->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v2, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel_type})Ljava/lang/Object;
move-result-object v2
check-cast v2, ${msg_type}
const-string v7, "null-payload Creator result must be a separate Message"
invoke-static {v1, v2, v7}, ${main_type}->different(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget-object v3, v2, ${msg_type}->obj:Ljava/lang/Object;
const/4 v4, 0
const-string v7, "null Message object must survive zero presence word"
invoke-static {v3, v4, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget-object v3, v2, ${msg_type}->replyTo:Landroid/os/Messenger;
const-string v7, "null Message reply messenger must remain null"
invoke-static {v3, v4, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {v2}, ${msg_type}->peekData()Landroid/os/Bundle;
move-result-object v3
const-string v7, "null Message Bundle must remain absent"
invoke-static {v3, v4, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
iget v3, v2, ${msg_type}->sendingUid:I
const/4 v4, -1
const-string v7, "null payload must retain unknown sender UID"
invoke-static {v3, v4, v7}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v2}, ${msg_type}->getWhen()J
move-result-wide v3
const-wide/16 v5, 0
const-string v7, "null payload must retain zero when"
invoke-static {v3, v4, v5, v6, v7}, ${main_type}->messageLong(JJLjava/lang/String;)V
invoke-virtual {v0}, ${parcel_type}->dataAvail()I
move-result v3
const/4 v4, 0
const-string v7, "null payload must consume the exact Parcel"
invoke-static {v3, v4, v7}, ${main_type}->equal(IILjava/lang/String;)V
invoke-virtual {v1}, ${msg_type}->recycle()V
invoke-virtual {v2}, ${msg_type}->recycle()V
:end
invoke-virtual {v0}, ${parcel_type}->recycle()V
return-void
.catchall {:begin .. :end} :failed
:failed
move-exception v7
invoke-virtual {v0}, ${parcel_type}->recycle()V
throw v7')
}

fn message_thrower_source() string {
	return '.class public final ${thrower_type}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public failure:Ljava/lang/RuntimeException;\n' +
		message_fixture_method('public constructor <init>(Ljava/lang/RuntimeException;)V', 0, 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${thrower_type}->failure:Ljava/lang/RuntimeException;\nreturn-void') +
		message_fixture_method('public describeContents()I', 1, 'const/4 v0, 0\nreturn v0') +
		message_fixture_method('public writeToParcel(${parcel_type}I)V', 1, 'iget-object v0, p0, ${thrower_type}->failure:Ljava/lang/RuntimeException;\nthrow v0')
}

fn main_class() string {
	return '.class public final ${main_type}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' +
		'.field private static deadline:J\n.field public static workerLooper:Landroid/os/Looper;\n' +
		'.field public static launchThread:Ljava/lang/Thread;\n.field public static done:Ljava/util/concurrent/CountDownLatch;\n' +
		'.field public static barrierLatch:Ljava/util/concurrent/CountDownLatch;\n.field public static volatile failure:Ljava/lang/Throwable;\n' +
		'.field public static volatile requestCount:I\n.field public static volatile replyCount:I\n' +
		'.field public static original:${msg_type}\n.field public static originalData:Landroid/os/Bundle;\n' +
		'.field public static originalObj:Landroid/content/ComponentName;\n.field public static expectedClone:Z\n' +
		'.field public static expectedStage:I\n.field public static expectedUid:I\n.field public static expectedReplyBinder:${binder_type}\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		helpers_source() + await_source() + protocol_source() + request_source() + identity_source() +
		transaction_source() + transport_errors_source() + message_controls_source() + tests_source() + lifecycle_source() +
		method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->run(${main_type})V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Messenger Binder request and reply passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2
.catchall {:try_start .. :try_end} :failed')
}

fn fixture_sources() map[string]string {
	return {
		'org/vinix/bootstrap/Main.smali': main_class()
		'org/vinix/bootstrap/ReadyHandlerThread.smali': ready_thread_source()
		'org/vinix/bootstrap/EndpointHandler.smali': handler_source('EndpointHandler', 'receive', false)
		'org/vinix/bootstrap/ReplyHandler.smali': handler_source('ReplyHandler', 'reply', true)
		'org/vinix/bootstrap/ForcedBinder.smali': forced_binder_source()
		'org/vinix/bootstrap/ThrowingParcelable.smali': message_thrower_source()
	}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/EndpointHandler.smali', 'org/vinix/bootstrap/ForcedBinder.smali',
		'org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/ReadyHandlerThread.smali',
		'org/vinix/bootstrap/ReplyHandler.smali', 'org/vinix/bootstrap/ThrowingParcelable.smali']
}

fn verify_source_references(source string) {
	assert source.starts_with('.class public final Lorg/vinix/bootstrap/'), 'fixture application classes only'
	assert !source.contains('Landroid/os/HandlerThread;->getLooper(')
		&& !source.contains('Landroid/os/HandlerThread;->quit('), 'no unbounded HandlerThread getter or quit path'
	if source.starts_with('.class public final ${main_type}') {
		for reference in ['${messenger_type}->getBinder()', '${messenger_type}-><init>(Landroid/os/Handler;)V',
			'${messenger_type}-><init>(${binder_type})V', '${messenger_type}->CREATOR:',
			'${messenger_type}->writeToParcel(', '${messenger_type}->writeMessengerOrNullToParcel(',
			'${messenger_type}->readMessengerOrNullFromParcel(', '${messenger_type}->send(${msg_type})V',
			'${msg_type}->sendingUid:I', '${msg_type}->writeToParcel(', '${msg_type}->CREATOR:',
			'${msg_type}->copyFrom(', '${msg_type}->obtain(${msg_type})${msg_type}',
			'${msg_type}->recycle()V', 'Landroid/os/Binder;->getCallingUid()I', 'Landroid/os/Process;->myUid()I',
			'->await(JLjava/util/concurrent/TimeUnit;)Z', 'Ljava/lang/Thread;->join(J)V',
			'${main_type}->barrier(', '${main_type}->messageControls(', 'fixture.wrong.IMessenger',
			'Landroid/os/RemoteException;', 'Ljava/lang/ClassCastException;', 'Ljava/lang/SecurityException;'] {
			assert source.contains(reference), 'missing Messenger runtime control: ' + reference
		}
		run := source.all_after('.method private static run(').all_before('.end method')
		deadline_at := run.index('->deadline:J') or { panic('missing deadline publication') }
		start_at := run.index('Ljava/lang/Thread;->start()V') or { panic('missing worker start') }
		assert deadline_at < start_at, 'deadline must precede worker start'
	} else if source.starts_with('.class public final ${thread_type}') {
		assert source.contains('.field public volatile preparedLooper:Landroid/os/Looper;')
		assert source.contains('->await(JLjava/util/concurrent/TimeUnit;)Z') && source.contains('->myLooper()Landroid/os/Looper;')
	} else if source.starts_with('.class public final ${forced_type}') {
		assert source.contains('.super Landroid/os/Binder;') && source.contains('${binder_type}->transact(')
		assert source.contains('android.os.IMessenger') && source.contains('->readInt()I')
		assert !source.contains('.method public transact('), 'forced wrapper must retain the framework Binder.transact implementation'
	} else if source.starts_with('.class public final ${thrower_type}') {
		assert source.contains('.implements Landroid/os/Parcelable;') && source.contains('writeToParcel(')
	} else {
		assert source.contains('.super Landroid/os/Handler;') && source.contains('.method public handleMessage(')
		assert source.contains('->countDown()V') && source.contains('->failure:Ljava/lang/Throwable;')
	}
}

fn lifecycle_source() string {
	return method('private static merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;', 0, '
if-eqz p0, :new_failure
if-eq p0, p1, :done
invoke-virtual {p0, p1}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:done
return-object p0
:new_failure
return-object p1') + method('private static cleanup(${thread_type}Ljava/lang/Throwable;)V', 4, '
move-object v0, p1
:try_start
iget-object v1, p0, ${thread_type}->preparedLooper:Landroid/os/Looper;
if-eqz v1, :join
invoke-virtual {v1}, Landroid/os/Looper;->quit()V
:join
const-wide/16 v1, 1000
invoke-virtual {p0, v1, v2}, Ljava/lang/Thread;->join(J)V
invoke-virtual {p0}, Ljava/lang/Thread;->isAlive()Z
move-result v1
if-eqz v1, :try_end
new-instance v1, Ljava/lang/AssertionError;
const-string v3, "Messenger worker must terminate within one second"
invoke-direct {v1, v3}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:try_end
goto :check
:failed
move-exception v1
invoke-static {v0, v1}, ${main_type}->merge(Ljava/lang/Throwable;Ljava/lang/Throwable;)Ljava/lang/Throwable;
move-result-object v0
:check
if-eqz v0, :done
throw v0
:done
return-void
.catchall {:try_start .. :try_end} :failed') + method('private static run(${main_type})V', 5, '
new-instance v0, ${thread_type}
invoke-direct {v0}, ${thread_type}-><init>()V
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v1
sput-object v1, ${main_type}->launchThread:Ljava/lang/Thread;
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v1
const-wide v3, 0x1dcd65000L
add-long/2addr v1, v3
sput-wide v1, ${main_type}->deadline:J
:try_start
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
sget-wide v1, ${main_type}->deadline:J
invoke-virtual {v0, v1, v2}, ${thread_type}->awaitLooper(J)Landroid/os/Looper;
move-result-object v1
sput-object v1, ${main_type}->workerLooper:Landroid/os/Looper;
invoke-static {p0}, ${main_type}->tests(${main_type})V
:try_end
const/4 v1, 0
invoke-static {v0, v1}, ${main_type}->cleanup(${thread_type}Ljava/lang/Throwable;)V
return-void
:failed
move-exception v1
invoke-static {v0, v1}, ${main_type}->cleanup(${thread_type}Ljava/lang/Throwable;)V
return-void
.catchall {:try_start .. :try_end} :failed')
}
