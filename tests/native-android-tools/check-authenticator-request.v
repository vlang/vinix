// SPDX-License-Identifier: GPL-2.0-or-later
// Independently ordered AIDL surface and DEX assembly guard. ART semantics are
// exercised by tests/native-android-ws/authenticator-request-fixture.v.
module main

import androidtools
import os

fn main() {
 assert os.args.len == 1 || os.args.len == 3, 'usage: check-authenticator-request [TOOLS JAVA]'
 classes := androidtools.framework_authenticator_request_classes()
 expected := ['android/accounts/IAccountAuthenticator', 'android/accounts/IAccountAuthenticator\$Stub',
  'android/accounts/IAccountAuthenticator\$Stub\$Proxy']
 // Keep this declaration independent of the provider's method table: both slot
 // order and argument order are part of the platform Binder contract.
 signatures := [
  'addAccount(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)V',
  'confirmCredentials(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Landroid/os/Bundle;)V',
  'getAuthToken(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)V',
  'getAuthTokenLabel(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;)V',
  'updateCredentials(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)V',
  'editProperties(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;)V',
  'hasFeatures(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;[Ljava/lang/String;)V',
  'getAccountRemovalAllowed(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;)V',
  'getAccountCredentialsForCloning(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;)V',
  'addAccountFromCredentials(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Landroid/os/Bundle;)V',
  'startAddAccountSession(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)V',
  'startUpdateCredentialsSession(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)V',
  'finishSession(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Landroid/os/Bundle;)V',
  'isCredentialsUpdateSuggested(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;)V',
 ]
 assert classes.len == expected.len
 assert androidtools.framework_authenticator_request_class_names() == expected
 for name in expected {
  assert name in classes, name
  source := classes[name]
  assert source.starts_with('.class public '), name
  assert source.count('.method ') == source.count('.end method'), name
  assert !source.contains(' native ') && !source.contains('Landroid/util/Log;'), name
 }
 iface, stub, proxy := classes[expected[0]], classes[expected[1]], classes[expected[2]]
 assert iface.count('.method ') == 14
 for i, signature in signatures {
  assert iface.contains('.method public abstract ' + signature + '\n.end method'), signature
  assert stub.contains('TRANSACTION_' + signature.all_before('(') + ':I = ${i + 1}\n'), signature
  assert proxy.contains('.method public ' + signature + '\n.locals 5\n'), signature
  assert stub.contains('const/16 v0, ${i + 1}\nif-eq p1, v0, :request_${i + 1}\n'), signature
  assert proxy.contains('const/16 v2, ${i + 1}\nconst/4 v3, 0x0\nconst/4 v4, 0x1\n'), signature
 }
 assert stub.count('->enforceInterface(Ljava/lang/String;)V') == 14
 assert stub.count('->dataAvail()I') == 14
 assert stub.count('->asInterface(Landroid/os/IBinder;)Landroid/accounts/IAccountAuthenticatorResponse;') == 14
 assert stub.count('invoke-interface/range {v0 .. v5},') == 2
 assert stub.contains('invoke-super {p0, p1, p2, p3, p4}, Landroid/os/Binder;->onTransact')
 assert stub.contains('Landroid/os/BadParcelableException;-><init>(Ljava/lang/String;)V')
 assert proxy.count('->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z') == 14
 assert proxy.count('->writeStrongBinder(Landroid/os/IBinder;)V') == 14
 assert proxy.count('.catchall {:begin .. :end} :failed') == 14
 assert proxy.count('->recycle()V') == 28
 assert proxy.count('->writeStringArray([Ljava/lang/String;)V') == 3
 assert stub.count('->createStringArray()[Ljava/lang/String;') == 3
 assert proxy.count('Landroid/accounts/Account;->writeToParcel') == 9
 assert stub.count('Landroid/accounts/Account;->CREATOR:') == 9
 assert proxy.count('Landroid/os/Bundle;->writeToParcel') == 8
 assert stub.count('Landroid/os/Bundle;->CREATOR:') == 8
 if os.args.len == 3 {
  work := os.join_path(os.temp_dir(), 'vinix-authenticator-request-' + os.getpid().str())
  os.mkdir_all(work + '/smali/android/accounts')!
  defer { os.rmdir_all(work) or {} }
  for name, source in classes { os.write_file(work + '/smali/' + name + '.smali', source)! }
  dex := work + '/classes.dex'
  androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(dex)!.len > 112
  println('ANDROID-AUTHENTICATOR-REQUEST-ASSEMBLY-PASS three request classes produce DEX')
 }
 println('ANDROID-AUTHENTICATOR-REQUEST-SURFACE-PASS fourteen ordered methods typed nullable payloads oneway descriptor trailing-data and cleanup boundaries checked')
}
