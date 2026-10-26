// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// Storage is authenticator-owned; the broker routes requests. These methods
// pass the complete request to native code, which authenticates the caller and
// applies account/package visibility.
// A missing backend must throw; Java must not invent an account or a snapshot.
pub fn framework_account_store(source string) !string {
	if !source.contains(' Landroid/accounts/AccountManager;\n') {
		return error('AccountManager class required')
	}
	account := 'Landroid/accounts/Account;'
	string_type := 'Ljava/lang/String;'
	add_args := account + string_type + 'Landroid/os/Bundle;'
	add_native := 'vinixAddExplicitly(' + add_args + 'Ljava/util/Map;)Z'
	accounts_native := 'vinixAccounts(' + string_type + string_type + ')[Landroid/accounts/Account;'
	mut text := source
	for with_visibility in [false, true] {
		args := add_args + if with_visibility { 'Ljava/util/Map;' } else { '' }
		signature := 'addAccountExplicitly(' + args + ')Z'
		registers := if with_visibility { 'p0, p1, p2, p3, p4' } else { 'p0, p1, p2, p3, v0' }
		body := if with_visibility { '' } else { 'const/4 v0, 0x0\n' }
		text = framework_replace_method(text, signature,
			'.method public ' + signature + '\n.locals 1\n' + body +
				'invoke-direct {' + registers + '}, Landroid/accounts/AccountManager;->' + add_native + '\n' +
				'move-result v0\nreturn v0\n.end method')!
	}
	for signature, registers in {
		'getAccounts()[Landroid/accounts/Account;':                                                     'p0, v0, v0'
		'getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;':                             'p0, p1, v0'
		'getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;': 'p0, p1, p2'
	} {
		text = framework_replace_method(text, signature,
			'.method public ' + signature + '\n.locals 1\nconst/4 v0, 0x0\n' +
				'invoke-direct {' + registers + '}, Landroid/accounts/AccountManager;->' + accounts_native + '\n' +
				'move-result-object v0\nreturn-object v0\n.end method')!
	}
	for signature in [add_native, accounts_native] {
		text = framework_replace_method(text, signature, '.method private native ' + signature + '\n.end method')!
	}
	for signature in ['getUserData(' + account + string_type + ')' + string_type,
		'setUserData(' + account + string_type + string_type + ')V',
		'setAccountVisibility(' + account + string_type + 'I)Z',
		'getPassword(' + account + ')' + string_type, 'setPassword(' + account + string_type + ')V'] {
		text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
	}
	return text
}
