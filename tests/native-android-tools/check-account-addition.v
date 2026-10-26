// SPDX-License-Identifier: GPL-2.0-or-later
// Account insertion must never retain inherited credential logging.
module main

import androidtools
import os

const signature = 'addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z'

fn check_rejection(source string) !string {
 patched := androidtools.framework_account_addition(source)!
 assert patched.count('.method public ' + signature + '\n') == 1
 body := patched.all_after('.method public ' + signature + '\n').all_before('.end method')
 // Only construction of a fixed exception is permitted. In particular, no
 // supplied account, password or Bundle can be read, formatted or persisted.
 for line in body.split_into_lines().map(it.trim_space()).filter(it.len > 0) {
  assert line.starts_with('.locals ') || line == 'new-instance v0, Ljava/lang/UnsupportedOperationException;' ||
   line.starts_with('const-string v1, "') ||
   line == 'invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V' || line == 'throw v0'
 }
 assert body.contains('throw v0\n')
 assert !body.contains('return') && !body.contains('p1') && !body.contains('p2') && !body.contains('p3')
 assert !patched.contains('->println(') && !patched.contains('->append(') && !patched.contains('INHERITED-ACCOUNT-LOG')
 assert patched.contains('.method public getAccounts()[Landroid/accounts/Account;\n.locals 1\n# unchanged empty snapshot\nconst/4 v0, 0\nreturn-object v0\n.end method')
 return patched
}

fn check_assembly(sources []string) ! {
 if os.args.len == 1 { return }
 work := os.join_path(os.temp_dir(), 'vinix-account-addition-' + os.getpid().str())
 os.mkdir_all(work + '/smali')!
 defer { os.rmdir_all(work) or {} }
 for source in sources {
  os.write_file(work + '/smali/AccountManager.smali', source)!
  dex := work + '/classes.dex'
  androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(dex)!.len > 112
 }
 println('ANDROID-ACCOUNT-ADDITION-ASSEMBLY-PASS replacement and inserted methods produce DEX')
}

fn main() {
 assert os.args.len == 1 || os.args.len == 3, 'usage: check-account-addition [TOOLS JAVA]'
 prefix := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n'
 unrelated := '.method public getAccounts()[Landroid/accounts/Account;\n.locals 1\n# unchanged empty snapshot\nconst/4 v0, 0\nreturn-object v0\n.end method\n'
 inherited := '.method public ' + signature + '\n.locals 3\n' +
  'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
  'new-instance v1, Ljava/lang/StringBuilder;\ninvoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V\n' +
  'const-string v2, "INHERITED-ACCOUNT-LOG"\n' +
  'invoke-virtual {v1, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;\n' +
  'invoke-virtual {v1, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
  'invoke-virtual {v1, p3}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;\n' +
  'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/Object;)V\nconst/4 v0, 0\nreturn v0\n.end method\n'
 replaced := check_rejection(prefix + inherited + unrelated)!
 inserted := check_rejection(prefix + unrelated)!
 mut rejected := false
 androidtools.framework_account_addition(prefix + inherited + inherited + unrelated) or { rejected = true }
 assert rejected
 rejected = false
 androidtools.framework_account_addition(prefix + inherited.all_before('.end method')) or { rejected = true }
 assert rejected
 check_assembly([replaced, inserted])!
 println('ANDROID-ACCOUNT-ADDITION-PASS unsupported insertion removes credential logging; missing, duplicate and malformed declarations checked')
}
