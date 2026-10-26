// SPDX-License-Identifier: GPL-2.0-or-later
// Build guard for the no-authenticator asynchronous AccountManager surface.
// Behavioral checks run on ART using account-addition-fixture.v.
module main

import androidtools
import os

fn main() {
 assert os.args.len == 1 || os.args.len == 3, 'usage: check-account-async [TOOLS JAVA]'
 prefix := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n'
 source := androidtools.framework_account_async_addition(prefix)!
 assert source.count('.method public addAccount(') == 1
 assert source.contains('if-nez p1, :valid') && source.contains('Ljava/lang/IllegalArgumentException;')
 assert !source.contains('p2') && !source.contains('p3') && !source.contains('p4') && !source.contains('p5')
 assert androidtools.framework_account_async_addition(source)! == source
 mut rejected := false
 androidtools.framework_account_async_addition(source + source.all_after(prefix)) or { rejected = true }
 assert rejected
 rejected = false
 androidtools.framework_account_async_addition(source.all_before('.end method')) or { rejected = true }
 assert rejected
 classes := androidtools.framework_account_async_classes()
 assert classes.len == 9
 future := classes['android/atl/VinixAccountFuture']
 assert future.contains('.super Ljava/util/concurrent/FutureTask;')
 assert future.contains('->run()V') && future.contains('Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z')
 assert !future.contains('.method public cancel(') && !future.contains('.method public isDone(')
 for name, text in classes {
  assert text.starts_with('.class public '), name
  assert !text.contains(' native ') && !text.contains('println') && !text.contains('authtoken'), name
 }
 if os.args.len == 3 {
  work := os.join_path(os.temp_dir(), 'vinix-account-async-' + os.getpid().str())
  os.mkdir_all(work + '/smali/android/accounts')!
  os.mkdir_all(work + '/smali/android/atl')!
  defer { os.rmdir_all(work) or {} }
  os.write_file(work + '/smali/android/accounts/AccountManager.smali', source)!
  for name, text in classes { os.write_file(work + '/smali/' + name + '.smali', text)! }
  dex := work + '/classes.dex'
  androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(dex)!.len > 112
  println('ANDROID-ACCOUNT-ASYNC-ASSEMBLY-PASS interfaces exceptions future callback and addAccount produce DEX')
 }
 println('ANDROID-ACCOUNT-ASYNC-PASS surface validation idempotence duplicate malformed and credential isolation checked')
}
