// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// Reuse VinixAccountFuture's completion, cancellation and Handler dispatch.
// Null options reach the broker, which constructs trusted caller options.
pub fn framework_account_token(source string) !string {
	classes := source.split_into_lines().filter(it.trim_space().starts_with('.class '))
	if classes.len != 1 || !classes[0].trim_space().ends_with(' Landroid/accounts/AccountManager;') {
		return error('expected AccountManager class')
	}
	activity := 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	boolean := 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	deprecated := 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	blocking := 'blockingGetAuthToken(Landroid/accounts/Account;Ljava/lang/String;Z)Ljava/lang/String;'
	native := 'vinixStartToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/atl/VinixAccountFuture;)Z'
	validation := 'if-eqz p1, :invalid\nif-nez p2, :valid\n:invalid\n' +
		'new-instance v0, Ljava/lang/IllegalArgumentException;\n' +
		'const-string v1, "account or authTokenType is null"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n'
	mut method := '.method public ${activity}\n.locals 7\n' + validation +
		'new-instance v5, Landroid/atl/VinixAccountFuture;\nconst/4 v6, 0x1\n' +
		'invoke-direct {v5, p5, p6, v6}, Landroid/atl/VinixAccountFuture;-><init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V\n'
	for i in 0 .. 5 { method += 'move-object v${i}, p${i}\n' }
	method += ':native_start\ninvoke-direct/range {v0 .. v5}, Landroid/accounts/AccountManager;->${native}\n' +
		'move-result v0\n:native_end\nif-nez v0, :pending\ngoto :unavailable\n' +
		'.catch Ljava/lang/UnsatisfiedLinkError; {:native_start .. :native_end} :no_native\n' +
		':no_native\nmove-exception v0\n:unavailable\n' +
		'invoke-virtual {v5}, Ljava/util/concurrent/FutureTask;->run()V\n:pending\nreturn-object v5\n.end method'
	mut text := framework_replace_method(source, activity, method)!
	method = '.method public ${boolean}\n.locals 7\n' + validation +
		'if-eqz p4, :request\nnew-instance v0, Landroid/atl/VinixAccountFuture;\nconst/4 v1, 0x1\n' +
		'invoke-direct {v0, p5, p6, v1}, Landroid/atl/VinixAccountFuture;-><init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V\n' +
		'const/4 v1, 0x6\nconst-string v2, "Account token notifications are unavailable"\n' +
		'invoke-virtual {v0, v1, v2}, Landroid/atl/VinixAccountFuture;->vinixError(ILjava/lang/String;)V\nreturn-object v0\n:request\n'
	for i in 0 .. 4 { method += 'move-object v${i}, p${i}\n' }
	method += 'const/4 v4, 0x0\nmove-object v5, p5\nmove-object v6, p6\n' +
		'invoke-virtual/range {v0 .. v6}, Landroid/accounts/AccountManager;->${activity}\nmove-result-object v0\nreturn-object v0\n.end method'
	text = framework_replace_method(text, boolean, method)!
	method = '.method public ${deprecated}\n.locals 7\n' +
		'move-object v0, p0\nmove-object v1, p1\nmove-object v2, p2\nconst/4 v3, 0x0\n' +
		'move v4, p3\nmove-object v5, p4\nmove-object v6, p5\n' +
		'invoke-virtual/range {v0 .. v6}, Landroid/accounts/AccountManager;->${boolean}\nmove-result-object v0\nreturn-object v0\n.end method'
	text = framework_replace_method(text, deprecated, method)!
	method = '.method public ${blocking}\n.locals 7\n' + validation +
		'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\n' +
		'invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\n' +
		'if-ne v0, v1, :worker\nnew-instance v0, Ljava/lang/IllegalStateException;\n' +
		'const-string v1, "blockingGetAuthToken cannot run on the main Looper"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n:worker\n' +
		'move-object v0, p0\nmove-object v1, p1\nmove-object v2, p2\nconst/4 v3, 0x0\n' +
		'move v4, p3\nconst/4 v5, 0x0\nconst/4 v6, 0x0\n' +
		'invoke-virtual/range {v0 .. v6}, Landroid/accounts/AccountManager;->${boolean}\nmove-result-object v0\n' +
		'invoke-interface {v0}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;\nmove-result-object v0\n' +
		'check-cast v0, Landroid/os/Bundle;\nconst-string v1, "authtoken"\n' +
		'invoke-virtual {v0, v1}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\nreturn-object v0\n.end method'
	text = framework_replace_method(text, blocking, method)!
	return framework_replace_method(text, native, '.method private native ${native}\n.end method')!
}
