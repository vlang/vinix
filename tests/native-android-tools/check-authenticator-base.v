// SPDX-License-Identifier: GPL-2.0-or-later
// Static/assembly guard. Runtime behavior has a separate ART fixture.
module main

import androidtools
import os

fn main() {
 assert os.args.len in [1, 3, 4], 'usage: check-authenticator-base [TOOLS JAVA [FRESH_OUTPUT]]'
 classes := androidtools.framework_authenticator_base_classes()
 names := ['android/accounts/AbstractAccountAuthenticator',
  'android/accounts/AbstractAccountAuthenticator$Transport',
  'android/accounts/AbstractAccountAuthenticator$DefaultResponse']
 assert androidtools.framework_authenticator_base_class_names() == names
 assert classes.len == 3
 base, transport, worker := classes[names[0]], classes[names[1]], classes[names[2]]
 // The transport's exception mapping must resolve its concrete exception
 // classes on ART, even when the authenticator returns an ordinary result.
 exceptions := androidtools.framework_account_async_classes()
 for name in ['AccountsException', 'AuthenticatorException', 'OperationCanceledException', 'NetworkErrorException'] {
  key := 'android/accounts/' + name
  assert key in exceptions, key
  source := exceptions[key]
  parent := if name == 'AccountsException' { 'Ljava/lang/Exception;' } else { 'Landroid/accounts/AccountsException;' }
  assert source.contains('.super ' + parent), key
  assert source.count('.method public constructor <init>(') == 4, key
  for signature in ['', 'Ljava/lang/String;', 'Ljava/lang/Throwable;', 'Ljava/lang/String;Ljava/lang/Throwable;'] {
   assert source.contains('<init>(' + signature + ')V'), key
  }
 }
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
 // Diagnostics use only stderr, preserve the caught object for the existing
 // mapping, and cannot replace the authenticator response when logging fails.
 handler := base.all_after('.method final vinixHandleException(').all_before('.end method')
 assert handler.count('Ljava/lang/Throwable;->printStackTrace()V') == 1
 assert handler.count('ANDROID-AUTHENTICATOR-EXCEPTION') == 1
 assert handler.contains('.catchall {:trace_start .. :trace_end} :trace_failed\n:trace_failed\nmove-exception v0\n:trace_done\ninstance-of v0, p3,')
 assert handler.contains('sget-object v0, Ljava/lang/System;->err:Ljava/io/PrintStream;')
 assert handler.count('->onError(ILjava/lang/String;)V') == 1
 assert handler.contains('invoke-interface {p1, v0, v1}, Landroid/accounts/IAccountAuthenticatorResponse;->onError(ILjava/lang/String;)V')
 assert !transport.contains('ANDROID-AUTHENTICATOR-EXCEPTION')
 // A canonical-class update must change only this method, including when
 // unrelated content has different formatting. Reapplying it is a no-op.
 signature := 'vinixHandleException(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/Exception;)V'
 declaration := '.method final ' + signature + base.all_after('.method final ' + signature).all_before('.end method') + '.end method'
 historical := '.method final ' + signature + '\n.locals 3\n' + handler.all_after(':trace_done\n') + '.end method'
 old_class := base.replace(declaration, historical).replace('.super Ljava/lang/Object;\n',
  '.super Ljava/lang/Object;\n\n.field private preserveSentinel:I\n')
 patched := androidtools.framework_authenticator_private_exception(old_class)!
 assert patched == old_class.replace(historical, declaration)
 assert androidtools.framework_authenticator_private_exception(patched)! == patched
 for invalid in [old_class.replace(signature, 'missing()V'), old_class + '\n' + historical,
  old_class.replace('.class public abstract Landroid/accounts/AbstractAccountAuthenticator;', '.class public Lother/Class;')] {
  if _ := androidtools.framework_authenticator_private_exception(invalid) {
   panic('unsafe authenticator method update accepted')
  }
 }
 assert transport.count('null bundle returned') == 1
 assert transport.count('authTokenLabelKey') == 1
 assert base.count('Ljava/lang/Thread;->start()V') == 4
 assert worker.contains('"booleanResult"') && worker.contains('"accountSessionBundle"')
 assert worker.contains('android.accounts.AbstractAccountAuthenticato.KEY_AUTH_TOKEN_TYPE')
 assert base.contains('invoke-virtual {v6, v5}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V')
 assert base.contains('invoke-virtual {p1, v0}, Landroid/accounts/AccountAuthenticatorResponse;->onResult(Landroid/os/Bundle;)V\nreturn-object v0')
 if os.args.len >= 3 {
  work := if os.args.len == 4 { os.abs_path(os.args[3]) } else {
   os.join_path(os.temp_dir(), 'vinix-authenticator-base-' + os.getpid().str())
  }
  assert !os.exists(work) && !os.is_link(work), 'assembly output must be fresh'
  os.mkdir_all(work + '/smali/android/accounts')!
  defer { if os.args.len == 3 { os.rmdir_all(work) or {} } }
  for name, source in classes { os.write_file(work + '/smali/' + name + '.smali', source)! }
  for name, source in exceptions {
   if name.starts_with('android/accounts/') { os.write_file(work + '/smali/' + name + '.smali', source)! }
  }
  androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(work + '/classes.dex')!.len > 112
  println('ANDROID-AUTHENTICATOR-BASE-ASSEMBLY-PASS three base classes produce DEX')
 }
 println('ANDROID-AUTHENTICATOR-BASE-SURFACE-PASS permission boundary fourteen dispatch slots exceptions guarded-private-stack-trace asynchronous defaults sessions')
}
