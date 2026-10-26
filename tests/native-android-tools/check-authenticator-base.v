// SPDX-License-Identifier: GPL-2.0-or-later
// Static/assembly guard. Runtime behavior has a separate ART fixture.
module main

import androidtools
import os

fn main() {
 assert os.args.len == 1 || os.args.len == 3, 'usage: check-authenticator-base [TOOLS JAVA]'
 classes := androidtools.framework_authenticator_base_classes()
 names := ['android/accounts/AbstractAccountAuthenticator',
  'android/accounts/AbstractAccountAuthenticator$Transport',
  'android/accounts/AbstractAccountAuthenticator$DefaultResponse']
 assert androidtools.framework_authenticator_base_class_names() == names
 assert classes.len == 3
 base, transport, worker := classes[names[0]], classes[names[1]], classes[names[2]]
 for name in names {
  source := classes[name]
  assert source.count('.method ') == source.count('.end method'), name
  assert !source.contains(' native ') && !source.contains('Landroid/util/Log;'), name
  assert !source.contains('clearCallingIdentity') && !source.contains('addAccountExplicitly'), name
 }
 assert base.count('.method public abstract ') == 7
 assert base.contains('public final getIBinder()Landroid/os/IBinder;')
 assert base.contains('->checkCallingOrSelfPermission(Ljava/lang/String;)I')
 assert base.contains('if-eqz v0, :allowed')
 assert base.contains('Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V')
 assert transport.count('->vinixCheckBinderPermission()V\n:begin\n') == 14
 assert transport.count('.catch Ljava/lang/Exception; {:begin .. :end} :failed') == 14
 assert transport.count('->vinixHandleException(') == 14
 assert transport.count('null bundle returned') == 1
 assert transport.count('authTokenLabelKey') == 1
 assert base.count('Ljava/lang/Thread;->start()V') == 4
 assert worker.contains('"booleanResult"') && worker.contains('"accountSessionBundle"')
 assert worker.contains('android.accounts.AbstractAccountAuthenticato.KEY_AUTH_TOKEN_TYPE')
 assert base.contains('invoke-virtual {v6, v5}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V')
 assert base.contains('invoke-virtual {p1, v0}, Landroid/accounts/AccountAuthenticatorResponse;->onResult(Landroid/os/Bundle;)V\nreturn-object v0')
 if os.args.len == 3 {
  work := os.join_path(os.temp_dir(), 'vinix-authenticator-base-' + os.getpid().str())
  os.mkdir_all(work + '/smali/android/accounts')!
  defer { os.rmdir_all(work) or {} }
  for name, source in classes { os.write_file(work + '/smali/' + name + '.smali', source)! }
  androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(work + '/classes.dex')!.len > 112
  println('ANDROID-AUTHENTICATOR-BASE-ASSEMBLY-PASS three base classes produce DEX')
 }
 println('ANDROID-AUTHENTICATOR-BASE-SURFACE-PASS permission boundary fourteen dispatch slots exceptions asynchronous defaults sessions')
}
