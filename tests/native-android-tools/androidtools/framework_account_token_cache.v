// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// These are the authenticator's explicit token storage APIs. getAuthToken
// still reaches the authenticator: custom-token results are never cached here.
pub fn framework_account_token_cache(source string) !string {
	if !source.contains(' Landroid/accounts/AccountManager;\n') {
		return error('AccountManager class required')
	}
	mut text := source
	for signature in [
		'peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
		'setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
		'invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V',
	] {
		text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
	}
	text = framework_replace_method(text, 'clearPassword(Landroid/accounts/Account;)V',
		'.method public clearPassword(Landroid/accounts/Account;)V\n.locals 1\nconst/4 v0, 0x0\ninvoke-virtual {p0, p1, v0}, Landroid/accounts/AccountManager;->setPassword(Landroid/accounts/Account;Ljava/lang/String;)V\nreturn-void\n.end method')!
	return text
}
