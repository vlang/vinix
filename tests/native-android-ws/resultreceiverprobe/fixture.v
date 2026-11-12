// SPDX-License-Identifier: GPL-2.0-or-later
module resultreceiverprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/ResultReceiverProbe.smali', r'.class public Lorg/vinix/bootstrap/ResultReceiverProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 7
new-instance v0, Lorg/vinix/bootstrap/TestResultReceiver;
const/4 v1, 0
invoke-direct {v0, v1}, Lorg/vinix/bootstrap/TestResultReceiver;-><init>(Landroid/os/Handler;)V
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1}, Landroid/os/Bundle;-><init>()V
const-string v2, "payload"
const/16 v3, 29
invoke-virtual {v1, v2, v3}, Landroid/os/Bundle;->putInt(Ljava/lang/String;I)V
const/16 v2, 17
invoke-virtual {v0, v2, v1}, Landroid/os/ResultReceiver;->send(ILandroid/os/Bundle;)V
iget v3, v0, Lorg/vinix/bootstrap/TestResultReceiver;->code:I
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-object v3, v0, Lorg/vinix/bootstrap/TestResultReceiver;->data:Landroid/os/Bundle;
if-ne v1, v3, :bad
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v3
iget-object v4, v0, Lorg/vinix/bootstrap/TestResultReceiver;->thread:Ljava/lang/Thread;
if-ne v3, v4, :bad
new-instance v2, Landroid/content/Intent;
invoke-direct {v2}, Landroid/content/Intent;-><init>()V
const-string v3, "callback"
invoke-virtual {v2, v3, v0}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;
invoke-virtual {v2, v3}, Landroid/content/Intent;->getParcelableExtra(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v2
if-ne v2, v0, :bad
invoke-virtual {v0}, Landroid/os/ResultReceiver;->describeContents()I
move-result v2
const/4 v3, 0
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v2, Landroid/os/ResultReceiver;->CREATOR:Landroid/os/Parcelable$Creator;
const/4 v3, 2
invoke-interface {v2, v3}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v2
check-cast v2, [Landroid/os/ResultReceiver;
array-length v2, v2
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v3, 0
invoke-virtual {v0, v2, v3}, Landroid/os/ResultReceiver;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/os/ResultReceiver;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v2}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v3
check-cast v3, Landroid/os/ResultReceiver;
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
const/16 v2, 23
invoke-virtual {v3, v2, v1}, Landroid/os/ResultReceiver;->send(ILandroid/os/Bundle;)V
iget v4, v0, Lorg/vinix/bootstrap/TestResultReceiver;->code:I
invoke-static {v4, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-object v4, v0, Lorg/vinix/bootstrap/TestResultReceiver;->data:Landroid/os/Bundle;
const-string v5, "payload"
invoke-virtual {v4, v5}, Landroid/os/Bundle;->getInt(Ljava/lang/String;)I
move-result v4
const/16 v5, 29
invoke-static {v4, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v2, 24
const/4 v1, 0
invoke-virtual {v3, v2, v1}, Landroid/os/ResultReceiver;->send(ILandroid/os/Bundle;)V
iget-object v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->data:Landroid/os/Bundle;
if-nez v1, :bad
iget v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->calls:I
const/4 v2, 3
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v3, 0
invoke-virtual {v0, v2, v3}, Landroid/os/ResultReceiver;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v1
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
invoke-virtual {v0, v2, v3}, Landroid/os/ResultReceiver;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v4
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
if-ne v1, v4, :bad
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const-string v3, "wrong.receiver.descriptor"
invoke-virtual {v2, v3}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
const/16 v3, 99
invoke-virtual {v2, v3}, Landroid/os/Parcel;->writeInt(I)V
const/4 v3, 0
invoke-virtual {v2, v3}, Landroid/os/Parcel;->writeInt(I)V
const/4 v3, 1
const/4 v4, 0
const/4 v5, 1
:wrong_token
invoke-interface {v1, v3, v2, v4, v5}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:wrong_token_end
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
goto :bad
:token_denied
move-exception v1
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
iget v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->calls:I
const/4 v2, 3
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v1, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v2
invoke-direct {v1, v2}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v0, Lorg/vinix/bootstrap/TestResultReceiver;
invoke-direct {v0, v1}, Lorg/vinix/bootstrap/TestResultReceiver;-><init>(Landroid/os/Handler;)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v2
const/4 v3, 0
invoke-virtual {v0, v2, v3}, Landroid/os/ResultReceiver;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v2, v3}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v3, Landroid/os/ResultReceiver;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v2}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v3
check-cast v3, Landroid/os/ResultReceiver;
invoke-virtual {v2}, Landroid/os/Parcel;->recycle()V
new-instance v2, Lorg/vinix/bootstrap/ResultReceiverWorker;
invoke-direct {v2, v3}, Lorg/vinix/bootstrap/ResultReceiverWorker;-><init>(Landroid/os/ResultReceiver;)V
new-instance v3, Ljava/lang/Thread;
invoke-direct {v3, v2}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v3}, Ljava/lang/Thread;->start()V
invoke-virtual {v3}, Ljava/lang/Thread;->join()V
iget v2, v0, Lorg/vinix/bootstrap/TestResultReceiver;->calls:I
const/4 v3, 0
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
new-instance v2, Lorg/vinix/bootstrap/ResultReceiverFence;
invoke-direct {v2, v0}, Lorg/vinix/bootstrap/ResultReceiverFence;-><init>(Lorg/vinix/bootstrap/TestResultReceiver;)V
invoke-virtual {v1, v2}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.catch Ljava/lang/SecurityException; {:wrong_token .. :wrong_token_end} :token_denied
.end method
')!
	os.write_file(root + '/smali/TestResultReceiver.smali', r'.class public Lorg/vinix/bootstrap/TestResultReceiver;
.super Landroid/os/ResultReceiver;
.field public calls:I
.field public code:I
.field public data:Landroid/os/Bundle;
.field public thread:Ljava/lang/Thread;
.method public constructor <init>(Landroid/os/Handler;)V
.locals 0
invoke-direct {p0, p1}, Landroid/os/ResultReceiver;-><init>(Landroid/os/Handler;)V
return-void
.end method
.method protected onReceiveResult(ILandroid/os/Bundle;)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/TestResultReceiver;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TestResultReceiver;->calls:I
iput p1, p0, Lorg/vinix/bootstrap/TestResultReceiver;->code:I
iput-object p2, p0, Lorg/vinix/bootstrap/TestResultReceiver;->data:Landroid/os/Bundle;
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
iput-object v0, p0, Lorg/vinix/bootstrap/TestResultReceiver;->thread:Ljava/lang/Thread;
return-void
.end method
')!
	os.write_file(root + '/smali/ResultReceiverWorker.smali', r'.class public Lorg/vinix/bootstrap/ResultReceiverWorker;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private receiver:Landroid/os/ResultReceiver;
.method public constructor <init>(Landroid/os/ResultReceiver;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/ResultReceiverWorker;->receiver:Landroid/os/ResultReceiver;
return-void
.end method
.method public run()V
.locals 3
iget-object v0, p0, Lorg/vinix/bootstrap/ResultReceiverWorker;->receiver:Landroid/os/ResultReceiver;
const/16 v1, 31
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/os/ResultReceiver;->send(ILandroid/os/Bundle;)V
return-void
.end method
')!
	os.write_file(root + '/smali/ResultReceiverFence.smali', r'.class public Lorg/vinix/bootstrap/ResultReceiverFence;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private receiver:Lorg/vinix/bootstrap/TestResultReceiver;
.method public constructor <init>(Lorg/vinix/bootstrap/TestResultReceiver;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/ResultReceiverFence;->receiver:Lorg/vinix/bootstrap/TestResultReceiver;
return-void
.end method
.method public run()V
.locals 3
iget-object v0, p0, Lorg/vinix/bootstrap/ResultReceiverFence;->receiver:Lorg/vinix/bootstrap/TestResultReceiver;
iget v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->calls:I
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->code:I
const/16 v2, 31
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
iget-object v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->data:Landroid/os/Bundle;
if-nez v1, :bad
iget-object v1, v0, Lorg/vinix/bootstrap/TestResultReceiver;->thread:Ljava/lang/Thread;
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v2
if-ne v1, v2, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "RESULT-RECEIVER-PASS intent-parcelable local-and-parcel-callback handler-worker descriptor-guard"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
')!
}
