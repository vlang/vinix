// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools

fn main() {
	source := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n' +
		'.method public getAccounts()[Landroid/accounts/Account;\n.locals 1\nconst/4 v0, 0x0\nreturn-object v0\n.end method\n'
	patched := androidtools.framework_account_token_cache(source)!
	for signature in [
		'peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
		'setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
		'invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V',
	] {
		assert patched.count('.method public native ' + signature + '\n.end method') == 1
	}
	assert patched.contains('.method public clearPassword(Landroid/accounts/Account;)V\n.locals 1\nconst/4 v0, 0x0\ninvoke-virtual {p0, p1, v0}, Landroid/accounts/AccountManager;->setPassword(Landroid/accounts/Account;Ljava/lang/String;)V\nreturn-void\n.end method')
	assert patched.count('.method ') == source.count('.method ') + 4
	assert patched.contains(source.all_after('.super Ljava/lang/Object;\n'))
	assert androidtools.framework_account_token_cache(patched)! == patched
	mut rejected := false
	androidtools.framework_account_token_cache('.class public Lwrong/Class;\n') or { rejected = true }
	assert rejected
	println('ACCOUNT-TOKEN-CACHE-PROVIDER-PASS native signatures idempotence unrelated-method')
}
