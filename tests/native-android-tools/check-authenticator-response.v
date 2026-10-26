// SPDX-License-Identifier: GPL-2.0-or-later
// Response wire surface and DEX build guard. Runtime semantics are exercised by
// tests/native-android-ws/authenticator-response-fixture.v on ART.
module main

import androidtools
import os

fn main() {
 assert os.args.len == 1 || os.args.len == 3, 'usage: check-authenticator-response [TOOLS JAVA]'
 classes := androidtools.framework_authenticator_response_classes()
 expected := ['android/accounts/IAccountAuthenticatorResponse', 'android/accounts/IAccountAuthenticatorResponse\$Stub', 'android/accounts/IAccountAuthenticatorResponse\$Stub\$Proxy', 'android/accounts/AccountAuthenticatorResponse', 'android/accounts/AccountAuthenticatorResponse\$Creator']
 assert classes.len == expected.len
 for name in expected {
  assert name in classes, name
  source := classes[name]
  assert source.starts_with('.class public '), name
  assert source.count('.method ') == source.count('.end method'), name
  assert !source.contains(' native ') && !source.contains('Landroid/util/Log;'), name
 }
 stub := classes[expected[1]]
 assert stub.count('->enforceInterface(Ljava/lang/String;)V') == 3
 assert stub.contains('TRANSACTION_onResult:I = 0x1')
 assert stub.contains('TRANSACTION_onRequestContinued:I = 0x2')
 assert stub.contains('TRANSACTION_onError:I = 0x3')
 proxy := classes[expected[2]]
 assert proxy.count('->transact(ILandroid/os/Parcel;Landroid/os/Parcel;I)Z') == 3
 assert proxy.count('const/4 v3, 0x0\nconst/4 v4, 0x1') == 3
 assert proxy.count('.catchall {:begin .. :end} :failed') == 3
 assert proxy.count('->recycle()V') == 6
 response := classes[expected[3]]
 assert response.count('.catch Landroid/os/RemoteException;') == 3
 assert !response.contains('.catchall') && !response.contains('.catch Ljava/lang/Exception;')
 assert response.contains('->readStrongBinder()Landroid/os/IBinder;')
 assert response.contains('->writeStrongBinder(Landroid/os/IBinder;)V')
 if os.args.len == 3 {
  work := os.join_path(os.temp_dir(), 'vinix-authenticator-response-' + os.getpid().str())
  os.mkdir_all(work + '/smali/android/accounts')!
  defer { os.rmdir_all(work) or {} }
  for name, source in classes { os.write_file(work + '/smali/' + name + '.smali', source)! }
  dex := work + '/classes.dex'
  androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(dex)!.len > 112
  println('ANDROID-AUTHENTICATOR-RESPONSE-ASSEMBLY-PASS five response classes produce DEX')
 }
 println('ANDROID-AUTHENTICATOR-RESPONSE-SURFACE-PASS descriptor transactions oneway parcelable and exception boundaries checked')
}
