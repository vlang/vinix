// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The request wire contract only. This does not discover or bind authenticators,
// grant account-manager authority, or create accounts. Transaction order follows
// frameworks/base/core/java/android/accounts/IAccountAuthenticator.aidl.
struct AuthenticatorRequestMethod {
 name string
 arguments []string
}

fn authenticator_request_methods() []AuthenticatorRequestMethod {
 account := 'Landroid/accounts/Account;'
 bundle := 'Landroid/os/Bundle;'
 string_type := 'Ljava/lang/String;'
 features := '[Ljava/lang/String;'
 return [
  AuthenticatorRequestMethod{'addAccount', [string_type, string_type, features, bundle]},
  AuthenticatorRequestMethod{'confirmCredentials', [account, bundle]},
  AuthenticatorRequestMethod{'getAuthToken', [account, string_type, bundle]},
  AuthenticatorRequestMethod{'getAuthTokenLabel', [string_type]},
  AuthenticatorRequestMethod{'updateCredentials', [account, string_type, bundle]},
  AuthenticatorRequestMethod{'editProperties', [string_type]},
  AuthenticatorRequestMethod{'hasFeatures', [account, features]},
  AuthenticatorRequestMethod{'getAccountRemovalAllowed', [account]},
  AuthenticatorRequestMethod{'getAccountCredentialsForCloning', [account]},
  AuthenticatorRequestMethod{'addAccountFromCredentials', [account, bundle]},
  AuthenticatorRequestMethod{'startAddAccountSession', [string_type, string_type, features, bundle]},
  AuthenticatorRequestMethod{'startUpdateCredentialsSession', [account, string_type, bundle]},
  AuthenticatorRequestMethod{'finishSession', [string_type, bundle]},
  AuthenticatorRequestMethod{'isCredentialsUpdateSuggested', [account, string_type]},
 ]
}

pub fn framework_authenticator_request_class_names() []string {
 return ['android/accounts/IAccountAuthenticator',
  'android/accounts/IAccountAuthenticator\$Stub',
  'android/accounts/IAccountAuthenticator\$Stub\$Proxy']
}

fn authenticator_request_signature(method AuthenticatorRequestMethod) string {
 return method.name + '(Landroid/accounts/IAccountAuthenticatorResponse;' + method.arguments.join('') + ')V'
}

fn authenticator_request_method(signature string, locals int, body string) string {
 return '\n.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn authenticator_request_read(argument string, register string, label string) string {
 if argument == 'Ljava/lang/String;' {
  return 'invoke-virtual {p2}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object ${register}\n'
 }
 if argument == '[Ljava/lang/String;' {
  return 'invoke-virtual {p2}, Landroid/os/Parcel;->createStringArray()[Ljava/lang/String;\nmove-result-object ${register}\n'
 }
 return 'invoke-virtual {p2}, Landroid/os/Parcel;->readInt()I\nmove-result v6\nif-eqz v6, :null_${label}\n' +
  'sget-object v6, ${argument}->CREATOR:Landroid/os/Parcelable\$Creator;\n' +
  'invoke-interface {v6, p2}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\n' +
  'move-result-object ${register}\ncheck-cast ${register}, ${argument}\ngoto :read_${label}\n' +
  ':null_${label}\nconst/4 ${register}, 0x0\n:read_${label}\n'
}

fn authenticator_request_write(argument string, register string, label string) string {
 if argument == 'Ljava/lang/String;' {
  return 'invoke-virtual {v0, ${register}}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\n'
 }
 if argument == '[Ljava/lang/String;' {
  return 'invoke-virtual {v0, ${register}}, Landroid/os/Parcel;->writeStringArray([Ljava/lang/String;)V\n'
 }
 return 'if-eqz ${register}, :null_${label}\nconst/4 v1, 0x1\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n' +
  'const/4 v1, 0x0\ninvoke-virtual {${register}, v0, v1}, ${argument}->writeToParcel(Landroid/os/Parcel;I)V\ngoto :written_${label}\n' +
  ':null_${label}\nconst/4 v1, 0x0\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V\n:written_${label}\n'
}

pub fn framework_authenticator_request_classes() map[string]string {
 names := framework_authenticator_request_class_names()
 iface := 'L' + names[0] + ';'
 stub := 'L' + names[1] + ';'
 proxy := 'L' + names[2] + ';'
 response := 'Landroid/accounts/IAccountAuthenticatorResponse;'
 response_stub := 'Landroid/accounts/IAccountAuthenticatorResponse\$Stub;'
 descriptor := 'android.accounts.IAccountAuthenticator'
 methods := authenticator_request_methods()
 mut classes := map[string]string{}
 mut text := '.class public interface abstract ${iface}\n.super Ljava/lang/Object;\n.implements Landroid/os/IInterface;\n'
 for method in methods {
  text += '.method public abstract ' + authenticator_request_signature(method) + '\n.end method\n'
 }
 classes[names[0]] = text
 text = '.class public abstract ${stub}\n.super Landroid/os/Binder;\n.implements ${iface}\n' +
  '.field public static final DESCRIPTOR:Ljava/lang/String; = "${descriptor}"\n'
 for i, method in methods {
  text += '.field public static final TRANSACTION_${method.name}:I = ${i + 1}\n'
 }
 text += authenticator_request_method('public constructor <init>()V', 1,
  'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\nconst-string v0, "${descriptor}"\n' +
  'invoke-virtual {p0, p0, v0}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V\nreturn-void')
 text += authenticator_request_method('public static asInterface(Landroid/os/IBinder;)${iface}', 2,
  'if-nez p0, :nonnull\nconst/4 v0, 0x0\nreturn-object v0\n:nonnull\nconst-string v0, "${descriptor}"\n' +
  'invoke-interface {p0, v0}, Landroid/os/IBinder;->queryLocalInterface(Ljava/lang/String;)Landroid/os/IInterface;\nmove-result-object v0\n' +
  'instance-of v1, v0, ${iface}\nif-eqz v1, :proxy\ncheck-cast v0, ${iface}\nreturn-object v0\n:proxy\n' +
  'new-instance v0, ${proxy}\ninvoke-direct {v0, p0}, ${proxy}-><init>(Landroid/os/IBinder;)V\nreturn-object v0')
 text += authenticator_request_method('public asBinder()Landroid/os/IBinder;', 0, 'return-object p0')
 mut body := 'const v0, 0x5f4e5446\nif-ne p1, v0, :requests\nconst-string v0, "${descriptor}"\n' +
  'invoke-virtual {p3, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nconst/4 v0, 0x1\nreturn v0\n:requests\n'
 for i, _ in methods {
  body += 'const/16 v0, ${i + 1}\nif-eq p1, v0, :request_${i + 1}\n'
 }
 body += 'invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\nmove-result v0\nreturn v0\n'
 for i, method in methods {
  body += ':request_${i + 1}\nconst-string v0, "${descriptor}"\n' +
   'invoke-virtual {p2, v0}, Landroid/os/Parcel;->enforceInterface(Ljava/lang/String;)V\n' +
   'invoke-virtual {p2}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v6\n' +
   'invoke-static {v6}, ${response_stub}->asInterface(Landroid/os/IBinder;)${response}\nmove-result-object v1\n'
  for j, argument in method.arguments {
   body += authenticator_request_read(argument, 'v${j + 2}', '${i + 1}_${j}')
  }
  body += 'invoke-virtual {p2}, Landroid/os/Parcel;->dataAvail()I\nmove-result v6\nif-nez v6, :trailing_data\n' +
   'move-object v0, p0\ninvoke-interface/range {v0 .. v${method.arguments.len + 1}}, ${iface}->' +
   authenticator_request_signature(method) + '\ngoto :handled\n'
 }
 body += ':trailing_data\nnew-instance v0, Landroid/os/BadParcelableException;\n' +
  'const-string v1, "Unexpected authenticator request data"\n' +
  'invoke-direct {v0, v1}, Landroid/os/BadParcelableException;-><init>(Ljava/lang/String;)V\nthrow v0\n' +
  ':handled\nconst/4 v0, 0x1\nreturn v0'
 text += authenticator_request_method('public onTransact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z', 7, body)
 classes[names[1]] = text
 text = '.class public final ${proxy}\n.super Ljava/lang/Object;\n.implements ${iface}\n.field private remote:Landroid/os/IBinder;\n'
 text += authenticator_request_method('public constructor <init>(Landroid/os/IBinder;)V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${proxy}->remote:Landroid/os/IBinder;\nreturn-void')
 text += authenticator_request_method('public asBinder()Landroid/os/IBinder;', 1,
  'iget-object v0, p0, ${proxy}->remote:Landroid/os/IBinder;\nreturn-object v0')
 text += authenticator_request_method('public getInterfaceDescriptor()Ljava/lang/String;', 1,
  'const-string v0, "${descriptor}"\nreturn-object v0')
 for i, method in methods {
  body = 'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v0\n:begin\n' +
   'const-string v1, "${descriptor}"\ninvoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInterfaceToken(Ljava/lang/String;)V\n' +
   'const/4 v1, 0x0\nif-eqz p1, :response_ready\n' +
   'invoke-interface {p1}, ${response}->asBinder()Landroid/os/IBinder;\nmove-result-object v1\n:response_ready\n' +
   'invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\n'
  for j, argument in method.arguments {
   body += authenticator_request_write(argument, 'p${j + 2}', '${j}')
  }
  body += 'iget-object v1, p0, ${proxy}->remote:Landroid/os/IBinder;\nconst/16 v2, ${i + 1}\nconst/4 v3, 0x0\nconst/4 v4, 0x1\n' +
   'invoke-interface {v1, v2, v0, v3, v4}, Landroid/os/IBinder;->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z\n' +
   ':end\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nreturn-void\n' +
   '.catchall {:begin .. :end} :failed\n:failed\nmove-exception v1\ninvoke-virtual {v0}, Landroid/os/Parcel;->recycle()V\nthrow v1'
  text += authenticator_request_method('public ' + authenticator_request_signature(method), 5, body)
 }
 classes[names[2]] = text
 return classes
}

fn framework_account_authenticator_request(smali string) ! {
 classes := framework_authenticator_request_classes()
 for name, _ in classes {
  if os.exists(smali + '/' + name + '.smali') {
   return error('authenticator request class already exists: ' + name)
  }
 }
 for name, source in classes { os.write_file(smali + '/' + name + '.smali', source)! }
}
