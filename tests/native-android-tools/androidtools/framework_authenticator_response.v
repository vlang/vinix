// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Account authenticators return this Binder callback inside their login Intent.
// These are the public response wire contracts only: they neither register an
// authenticator nor persist accounts or tokens. All three callbacks are oneway.
pub fn framework_authenticator_response_classes() map[string]string {
 iface := 'Landroid/accounts/IAccountAuthenticatorResponse;'
 stub := 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub;'
 proxy := 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub\$Proxy;'
 response := 'Landroid/accounts/AccountAuthenticatorResponse;'
 creator := 'Landroid/accounts/AccountAuthenticatorResponse\$Creator;'
 descriptor := 'android.accounts.IAccountAuthenticatorResponse'
 mut classes := map[string]string{}
 classes['android/accounts/IAccountAuthenticatorResponse'] = '.class public interface abstract ${iface}\n.super Ljava/lang/Object;\n.implements Landroid/os/IInterface;\n' +
  '.method public abstract onResult(Landroid/os/Bundle;)V\n.end method\n' +
  '.method public abstract onRequestContinued()V\n.end method\n' +
  '.method public abstract onError(ILjava/lang/String;)V\n.end method\n'
 mut text := '.class public abstract ${stub}\n.super Landroid/os/Binder;\n.implements ${iface}\n' +
  '.field public static final DESCRIPTOR:Ljava/lang/String; = "${descriptor}"\n' +
  '.field public static final TRANSACTION_onResult:I = 0x1\n' +
  '.field public static final TRANSACTION_onRequestContinued:I = 0x2\n' +
  '.field public static final TRANSACTION_onError:I = 0x3\n'
 text += authenticator_response_method('public constructor <init>()V', 1,
  'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\n' +
  'const-string v0, "${descriptor}"\n' +
  'invoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-void')
 text += authenticator_response_method('public static asInterface(Landroid/os/IBinder;)${iface}', 2,
  'if-nez p0, :nonnull\nconst/4 v0, 0x0\nreturn-object v0\n:nonnull\n' +
  'const-string v0, "${descriptor}"\n' +
  'invoke-interface {p0, v0}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;\nmove-result-object v0\n' +
  'instance-of v1, v0, ${iface}\nif-eqz v1, :proxy\ncheck-cast v0, ${iface}\nreturn-object v0\n:proxy\n' +
  'new-instance v0, ${proxy}\ninvoke-direct {v0, p0}, ${proxy}-><init>(Landroid/os/IBinder;)V\nreturn-object v0')
 text += authenticator_response_method('public asBinder()Landroid/os/IBinder;', 0, 'return-object p0')
 text += authenticator_response_method('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 3,
  'const v0, 0x5f4e5446\nif-ne p1, v0, :callbacks\nconst-string v0, "${descriptor}"\n' +
  'invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nconst/4 v0, 0x1\nreturn v0\n:callbacks\n' +
  'const/4 v0, 0x1\nif-eq p1, v0, :result\nconst/4 v0, 0x2\nif-eq p1, v0, :continued\n' +
  'const/4 v0, 0x3\nif-eq p1, v0, :error\n' +
  'invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0\n' +
  ':result\nconst-string v0, "${descriptor}"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\n' +
  'invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :null_result\n' +
  'sget-object v0, Landroid/os/Bundle;->CREATOR:Landroid/os/Parcelable\$Creator;\n' +
  'invoke-interface {v0, p2}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v0\n' +
  'check-cast v0, Landroid/os/Bundle;\ngoto :deliver_result\n:null_result\nconst/4 v0, 0x0\n:deliver_result\n' +
  'invoke-interface {p0, v0}, ${iface}->onResult(Landroid/os/Bundle;)V\ngoto :handled\n' +
  ':continued\nconst-string v0, "${descriptor}"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\n' +
  'invoke-interface {p0}, ${iface}->onRequestContinued()V\ngoto :handled\n' +
  ':error\nconst-string v0, "${descriptor}"\ninvoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\n' +
  'invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v0\n' +
  'invoke-virtual {p2}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v1\n' +
  'invoke-interface {p0, v0, v1}, ${iface}->onError(ILjava/lang/String;)V\n:handled\nconst/4 v0, 0x1\nreturn v0')
 classes['android/accounts/IAccountAuthenticatorResponse\$Stub'] = text
 text = '.class public final ${proxy}\n.super Ljava/lang/Object;\n.implements ${iface}\n.field private remote:Landroid/os/IBinder;\n'
 text += authenticator_response_method('public constructor <init>(Landroid/os/IBinder;)V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${proxy}->remote:Landroid/os/IBinder;\nreturn-void')
 text += authenticator_response_method('public asBinder()Landroid/os/IBinder;', 1,
  'iget-object v0, p0, ${proxy}->remote:Landroid/os/IBinder;\nreturn-object v0')
 text += authenticator_response_method('public getInterfaceDescriptor()Ljava/lang/String;', 1,
  'const-string v0, "${descriptor}"\nreturn-object v0')
 for i, signature in ['onResult(Landroid/os/Bundle;)V', 'onRequestContinued()V', 'onError(ILjava/lang/String;)V'] {
  mut body := 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n:begin\n' +
   'const-string v1, "${descriptor}"\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\n'
  if i == 0 {
   body += 'if-eqz p1, :null_bundle\nconst/4 v1, 0x1\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n' +
    'const/4 v1, 0x0\ninvoke-virtual {p1, v0, v1}, Landroid/os/Bundle;->writeToParcel(Landroid/os/Parcel;I)V\ngoto :dispatch\n' +
    ':null_bundle\nconst/4 v1, 0x0\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n'
  } else if i == 2 {
   body += 'invoke-virtual {v0, p1}, Landroid/os/Parcel;->writeInt(I)V\n' +
    'invoke-virtual {v0, p2}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
  }
  body += ':dispatch\niget-object v1, p0, ${proxy}->remote:Landroid/os/IBinder;\nconst/4 v2, ${i + 1}\nconst/4 v3, 0x0\nconst/4 v4, 0x1\n' +
   'invoke-interface {v1, v2, v0, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n' +
   ':end\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n' +
   '.catchall {:begin .. :end} :failed\n:failed\nmove-exception v1\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nthrow v1'
  text += authenticator_response_method('public ' + signature, 5, body)
 }
 classes['android/accounts/IAccountAuthenticatorResponse\$Stub\$Proxy'] = text
 text = '.class public ${response}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n' +
  '.field private response:${iface}\n.field public static final CREATOR:Landroid/os/Parcelable\$Creator;\n'
 text += authenticator_response_method('static constructor <clinit>()V', 1,
  'new-instance v0, ${creator}\ninvoke-direct {v0}, ${creator}-><init>()V\n' +
  'sput-object v0, ${response}->CREATOR:Landroid/os/Parcelable\$Creator;\nreturn-void')
 text += authenticator_response_method('public constructor <init>(${iface})V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${response}->response:${iface}\nreturn-void')
 text += authenticator_response_method('public constructor <init>(Landroid/os/Parcel;)V', 1,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v0\n' +
  'invoke-static {v0}, ${stub}->asInterface(Landroid/os/IBinder;)${iface}\nmove-result-object v0\niput-object v0, p0, ${response}->response:${iface}\nreturn-void')
 text += authenticator_response_method('public describeContents()I', 1, 'const/4 v0, 0x0\nreturn v0')
 text += authenticator_response_method('public writeToParcel(Landroid/os/Parcel;I)V', 1,
  'iget-object v0, p0, ${response}->response:${iface}\ninvoke-interface {v0}, ${iface}->asBinder()Landroid/os/IBinder;\nmove-result-object v0\n' +
  'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void')
 text += framework_account_interaction_response_accessor()
 for i, signature in ['onResult(Landroid/os/Bundle;)V', 'onRequestContinued()V', 'onError(ILjava/lang/String;)V'] {
  registers := if i == 0 { 'v0, p1' } else if i == 1 { 'v0' } else { 'v0, p1, p2' }
  text += authenticator_response_method('public ' + signature, 1,
   'iget-object v0, p0, ${response}->response:${iface}\n:begin\n' +
   'invoke-interface {${registers}}, ${iface}->${signature}\n:end\nreturn-void\n' +
   '.catch Landroid/os/RemoteException; {:begin .. :end} :remote_failed\n:remote_failed\nmove-exception v0\nreturn-void')
 }
 classes['android/accounts/AccountAuthenticatorResponse'] = text
 text = '.class public final ${creator}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n'
 text += authenticator_response_method('public constructor <init>()V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 text += authenticator_response_method('public createFromParcel(Landroid/os/Parcel;)${response}', 1,
  'new-instance v0, ${response}\ninvoke-direct {v0, p1}, ${response}-><init>(Landroid/os/Parcel;)V\nreturn-object v0')
 text += authenticator_response_method('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 1,
  'invoke-virtual {p0, p1}, ${creator}->createFromParcel(Landroid/os/Parcel;)${response}\nmove-result-object v0\nreturn-object v0')
 text += authenticator_response_method('public newArray(I)[${response}', 1,
  'new-array v0, p1, [${response}\nreturn-object v0')
 text += authenticator_response_method('public bridge synthetic newArray(I)[Ljava/lang/Object;', 1,
  'invoke-virtual {p0, p1}, ${creator}->newArray(I)[${response}\nmove-result-object v0\nreturn-object v0')
 classes['android/accounts/AccountAuthenticatorResponse\$Creator'] = text
 return classes
}

fn authenticator_response_method(signature string, locals int, body string) string {
 return '\n.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn framework_account_authenticator_response(smali string) ! {
 classes := framework_authenticator_response_classes()
 for name, _ in classes {
  if os.exists(smali + '/' + name + '.smali') {
   return error('authenticator response class already exists: ' + name)
  }
 }
 for name, source in classes { os.write_file(smali + '/' + name + '.smali', source)! }
}
