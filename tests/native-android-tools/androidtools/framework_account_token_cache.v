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
	return text
}
