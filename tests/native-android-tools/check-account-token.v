// SPDX-License-Identifier: GPL-2.0-or-later
// Apply the real provider to a retained AccountManager; verify its complete
// method delta and assemble it with the production FutureTask helpers.
module main

import androidtools
import os

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		if name in result || !block.contains('.end method') { return error('duplicate or incomplete method') }
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn main() {
	assert os.args.len == 5, 'ACCOUNT_MANAGER_SMALI TOOLS JAVA OUTPUT'
	source := os.read_file(os.args[1])!
	before := methods(source)!
	assert before.len > 10, 'use an actual AccountManager class'
	patched := androidtools.framework_account_token(source)!
	after := methods(patched)!
	activity := 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	boolean := 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	deprecated := 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	blocking := 'blockingGetAuthToken(Landroid/accounts/Account;Ljava/lang/String;Z)Ljava/lang/String;'
	native := 'vinixStartToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/atl/VinixAccountFuture;)Z'
	targets := [activity, boolean, deprecated, blocking, native]
	assert source.all_before('.method ') == patched.all_before('.method ')
	for name, body in before {
		assert name in after, 'lost method: ' + name
		if name !in targets { assert after[name]! == body, 'changed unrelated method: ' + name }
	}
	for name in after.keys() { assert name in before || name in targets, name }
	for name in targets { assert name in after }
	assert androidtools.framework_account_token(patched)! == patched
	mut rejected := 0
	for bad in [source.replace(' Landroid/accounts/AccountManager;\n', ' LOther;\n'),
		patched + '\n' + after[activity]!, patched.all_before_last('.end method')] {
		androidtools.framework_account_token(bad) or { rejected++; continue }
	}
	assert rejected == 3
	request := after[activity]!
	assert request.contains('new-instance v5, Landroid/atl/VinixAccountFuture;\nconst/4 v6, 0x1')
	for i in 0 .. 5 { assert request.contains('move-object v${i}, p${i}\n') }
	assert request.contains('invoke-direct {v5, p5, p6, v6}')
	assert request.contains('invoke-direct/range {v0 .. v5}, Landroid/accounts/AccountManager;->' + native)
	assert request.contains('if-nez v0, :pending\ngoto :unavailable')
	assert request.contains('FutureTask;->run()V\n:pending\nreturn-object v5')
	assert request.contains('.catch Ljava/lang/UnsatisfiedLinkError;')
	assert after[native]! == '.method private native ' + native + '\n.end method'
	bool_body := after[boolean]!
	assert bool_body.contains('if-eqz p4, :request')
	assert bool_body.contains('const/4 v1, 0x6\nconst-string v2, "Account token notifications are unavailable"')
	assert bool_body.contains('->vinixError(ILjava/lang/String;)V\nreturn-object v0\n:request')
	assert bool_body.contains('move-object v3, p3\nconst/4 v4, 0x0\nmove-object v5, p5\nmove-object v6, p6')
	assert bool_body.contains('invoke-virtual/range {v0 .. v6}, Landroid/accounts/AccountManager;->' + activity)
	assert after[deprecated]!.contains('const/4 v3, 0x0\nmove v4, p3\nmove-object v5, p4\nmove-object v6, p5')
	assert after[deprecated]!.contains('->' + boolean)
	block_body := after[blocking]!
	guard_index := block_body.index('if-ne v0, v1, :worker') or { panic('missing main Looper guard') }
	request_index := block_body.index('->' + boolean) or { panic('missing token request') }
	assert guard_index < request_index
	assert block_body.contains('const/4 v3, 0x0\nmove v4, p3\nconst/4 v5, 0x0\nconst/4 v6, 0x0')
	assert block_body.contains('invoke-interface {v0}, Landroid/accounts/AccountManagerFuture;->getResult()Ljava/lang/Object;')
	assert block_body.contains('const-string v1, "authtoken"')
	assert block_body.contains('Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v0\nreturn-object v0')
	production := os.read_file('tests/native-android-tools/androidtools/framework_accounts.v')!.all_after('fn framework_account_listeners(').all_before('\nfn framework_storage_queries(')
	assert production.count('text = framework_account_token(text)!') == 1
	patch_index := production.index('text = framework_account_token(text)!') or { panic('missing provider call') }
	write_index := production.index('os.write_file(path, text)!') or { panic('missing production write') }
	assert patch_index < write_index
	work := os.abs_path(os.args[4])
	os.mkdir_all(work + '/smali/android/accounts')!
	os.mkdir_all(work + '/smali/android/atl')!
	os.write_file(work + '/smali/android/accounts/AccountManager.smali', patched)!
	for name, text in androidtools.framework_account_client_classes() {
		os.write_file(work + '/smali/' + name + '.smali', text)!
	}
	androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
	assert os.read_bytes(work + '/classes.dex')!.len > 112
	println('ACCOUNT-TOKEN-FRAMEWORK-PASS actual-source exact-method-delta null-options activity-notify-delegation pending-future native-signature main-looper-guard blocking-result idempotence assembly')
}
