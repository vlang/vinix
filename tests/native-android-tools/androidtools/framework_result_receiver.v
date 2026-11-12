// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_result_receiver(smali string) ! {
	os.write_file(smali + '/android/os/ResultReceiver.smali', r'.class public Landroid/os/ResultReceiver;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable;
.field public static final CREATOR:Landroid/os/Parcelable$Creator;
.field private local:Z
.field private handler:Landroid/os/Handler;
.field private receiver:Landroid/os/IBinder;
.method static constructor <clinit>()V
.locals 1
new-instance v0, Landroid/os/VinixResultReceiverCreator;
invoke-direct {v0}, Landroid/os/VinixResultReceiverCreator;-><init>()V
sput-object v0, Landroid/os/ResultReceiver;->CREATOR:Landroid/os/Parcelable$Creator;
return-void
.end method
.method public constructor <init>(Landroid/os/Handler;)V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
const/4 v0, 1
iput-boolean v0, p0, Landroid/os/ResultReceiver;->local:Z
iput-object p1, p0, Landroid/os/ResultReceiver;->handler:Landroid/os/Handler;
return-void
.end method
.method constructor <init>(Landroid/os/Parcel;)V
.locals 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-virtual {p1}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;
move-result-object v0
iput-object v0, p0, Landroid/os/ResultReceiver;->receiver:Landroid/os/IBinder;
return-void
.end method
.method public describeContents()I
.locals 1
const/4 v0, 0
return v0
.end method
.method public synchronized writeToParcel(Landroid/os/Parcel;I)V
.locals 1
iget-object v0, p0, Landroid/os/ResultReceiver;->receiver:Landroid/os/IBinder;
if-nez v0, :write
new-instance v0, Landroid/os/VinixResultReceiverBinder;
invoke-direct {v0, p0}, Landroid/os/VinixResultReceiverBinder;-><init>(Landroid/os/ResultReceiver;)V
iput-object v0, p0, Landroid/os/ResultReceiver;->receiver:Landroid/os/IBinder;
:write
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V
return-void
.end method
.method protected onReceiveResult(ILandroid/os/Bundle;)V
.locals 0
return-void
.end method
.method public final vinixDeliver(ILandroid/os/Bundle;)V
.locals 2
iget-object v0, p0, Landroid/os/ResultReceiver;->handler:Landroid/os/Handler;
if-eqz v0, :direct
new-instance v1, Landroid/os/VinixResultReceiverDelivery;
invoke-direct {v1, p0, p1, p2}, Landroid/os/VinixResultReceiverDelivery;-><init>(Landroid/os/ResultReceiver;ILandroid/os/Bundle;)V
invoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
:direct
invoke-virtual {p0, p1, p2}, Landroid/os/ResultReceiver;->onReceiveResult(ILandroid/os/Bundle;)V
return-void
.end method
.method public send(ILandroid/os/Bundle;)V
.locals 5
iget-boolean v0, p0, Landroid/os/ResultReceiver;->local:Z
if-eqz v0, :remote
invoke-virtual {p0, p1, p2}, Landroid/os/ResultReceiver;->vinixDeliver(ILandroid/os/Bundle;)V
return-void
:remote
iget-object v1, p0, Landroid/os/ResultReceiver;->receiver:Landroid/os/IBinder;
if-eqz v1, :done
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
:parcel
const-string v2, "com.android.internal.os.IResultReceiver"
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V
invoke-virtual {v0, p1}, Landroid/os/Parcel;->writeInt(I)V
if-eqz p2, :null_data
const/4 v2, 1
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
const/4 v2, 0
invoke-virtual {p2, v0, v2}, Landroid/os/Bundle;->writeToParcel(Landroid/os/Parcel;I)V
goto :send
:null_data
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
:send
const/4 v2, 1
const/4 v3, 0
const/4 v4, 1
invoke-interface {v1, v2, v0, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
:parcel_end
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
:done
return-void
:remote_failure
move-exception v1
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-void
:failed
move-exception v1
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
throw v1
.catch Landroid/os/RemoteException; {:parcel .. :parcel_end} :remote_failure
.catchall {:parcel .. :parcel_end} :failed
.end method
')!
	os.write_file(smali + '/android/os/VinixResultReceiverBinder.smali', r'.class public final Landroid/os/VinixResultReceiverBinder;
.super Landroid/os/Binder;
.field private receiver:Landroid/os/ResultReceiver;
.method public constructor <init>(Landroid/os/ResultReceiver;)V
.locals 2
invoke-direct {p0}, Landroid/os/Binder;-><init>()V
iput-object p1, p0, Landroid/os/VinixResultReceiverBinder;->receiver:Landroid/os/ResultReceiver;
const/4 v0, 0
const-string v1, "com.android.internal.os.IResultReceiver"
invoke-virtual {p0, v0, v1}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
return-void
.end method
.method protected onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
.locals 3
const v0, 0x5f4e5446
if-ne p1, v0, :result
const-string v0, "com.android.internal.os.IResultReceiver"
invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
const/4 v0, 1
return v0
:result
const/4 v0, 1
if-ne p1, v0, :other
const-string v0, "com.android.internal.os.IResultReceiver"
invoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V
invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I
move-result v0
invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I
move-result v1
if-eqz v1, :null_data
sget-object v1, Landroid/os/Bundle;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v1, p2}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/os/Bundle;
goto :deliver
:null_data
const/4 v1, 0
:deliver
iget-object v2, p0, Landroid/os/VinixResultReceiverBinder;->receiver:Landroid/os/ResultReceiver;
invoke-virtual {v2, v0, v1}, Landroid/os/ResultReceiver;->vinixDeliver(ILandroid/os/Bundle;)V
const/4 v0, 1
return v0
:other
invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z
move-result v0
return v0
.end method
')!
	os.write_file(smali + '/android/os/VinixResultReceiverDelivery.smali', r'.class public final Landroid/os/VinixResultReceiverDelivery;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private receiver:Landroid/os/ResultReceiver;
.field private code:I
.field private data:Landroid/os/Bundle;
.method public constructor <init>(Landroid/os/ResultReceiver;ILandroid/os/Bundle;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/os/VinixResultReceiverDelivery;->receiver:Landroid/os/ResultReceiver;
iput p2, p0, Landroid/os/VinixResultReceiverDelivery;->code:I
iput-object p3, p0, Landroid/os/VinixResultReceiverDelivery;->data:Landroid/os/Bundle;
return-void
.end method
.method public run()V
.locals 3
iget-object v0, p0, Landroid/os/VinixResultReceiverDelivery;->receiver:Landroid/os/ResultReceiver;
iget v1, p0, Landroid/os/VinixResultReceiverDelivery;->code:I
iget-object v2, p0, Landroid/os/VinixResultReceiverDelivery;->data:Landroid/os/Bundle;
invoke-virtual {v0, v1, v2}, Landroid/os/ResultReceiver;->onReceiveResult(ILandroid/os/Bundle;)V
return-void
.end method
')!
	os.write_file(smali + '/android/os/VinixResultReceiverCreator.smali', r'.class public final Landroid/os/VinixResultReceiverCreator;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable$Creator;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
.locals 1
new-instance v0, Landroid/os/ResultReceiver;
invoke-direct {v0, p1}, Landroid/os/ResultReceiver;-><init>(Landroid/os/Parcel;)V
return-object v0
.end method
.method public newArray(I)[Ljava/lang/Object;
.locals 1
new-array v0, p1, [Landroid/os/ResultReceiver;
return-object v0
.end method
')!
}
