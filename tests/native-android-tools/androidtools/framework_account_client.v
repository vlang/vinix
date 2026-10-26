// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

// Keep the unavailable-only generator stable for historical fixtures. The
// production provider adds a pending future whose state remains FutureTask's.
pub fn framework_account_client_classes() map[string]string {
	mut classes := framework_account_async_classes()
	name := 'android/atl/VinixAccountFuture'
	mut future := classes[name]
	old_ctor := future.all_after('.method public constructor <init>(').all_before('.end method')
	pending_ctor := ('.method public constructor <init>(' + old_ctor + '.end method\n')
		.replace('Landroid/os/Handler;)V', 'Landroid/os/Handler;Z)V')
		.replace('invoke-virtual {p0}, Ljava/util/concurrent/FutureTask;->run()V\nreturn-void',
			'if-nez p3, :pending\ninvoke-virtual {p0}, Ljava/util/concurrent/FutureTask;->run()V\n:pending\nreturn-void')
	future += pending_ctor
	future = future.replace('.method protected done()V\n.locals 3\n',
		'.method protected done()V\n.locals 3\n:cleanup_start\n' +
		'invoke-direct {p0}, Landroid/atl/VinixAccountFuture;->vinixFinished()V\n:cleanup_end\n' +
		'goto :dispatch\n.catch Ljava/lang/UnsatisfiedLinkError; {:cleanup_start .. :cleanup_end} :no_native\n' +
		':no_native\nmove-exception v0\n:dispatch\n')
	future = future.replace('instance-of v1, v0, Landroid/accounts/AuthenticatorException;',
		'instance-of v1, v0, Landroid/accounts/OperationCanceledException;\nif-nez v1, :cause\n' +
		'instance-of v1, v0, Landroid/accounts/AuthenticatorException;')
	future += '.method private native vinixFinished()V\n.end method\n'
	future += '.method public vinixResult(Landroid/os/Bundle;)V\n.locals 2\n' +
		'if-nez p1, :valid\nconst/4 v0, 0x5\nconst-string v1, "Null authenticator result"\n' +
		'invoke-virtual {p0, v0, v1}, Landroid/atl/VinixAccountFuture;->vinixError(ILjava/lang/String;)V\nreturn-void\n' +
		':valid\nnew-instance v0, Landroid/os/Bundle;\n' +
		'invoke-direct {v0, p1}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V\n' +
		'invoke-super {p0, v0}, Ljava/util/concurrent/FutureTask;->set(Ljava/lang/Object;)V\nreturn-void\n.end method\n'
	future += '.method public vinixError(ILjava/lang/String;)V\n.locals 2\n'
	for code, exception in {3: 'java/io/IOException', 4: 'android/accounts/OperationCanceledException',
		6: 'java/lang/UnsupportedOperationException', 7: 'java/lang/IllegalArgumentException'} {
		future += 'const/4 v0, ${code}\nif-ne p1, v0, :next_${code}\n' +
			'new-instance v1, L${exception};\n' +
			'invoke-direct {v1, p2}, L${exception};-><init>(Ljava/lang/String;)V\ngoto :failed\n:next_${code}\n'
	}
	future += 'new-instance v1, Landroid/accounts/AuthenticatorException;\n' +
		'invoke-direct {v1, p2}, Landroid/accounts/AuthenticatorException;-><init>(Ljava/lang/String;)V\n:failed\n' +
		'invoke-super {p0, v1}, Ljava/util/concurrent/FutureTask;->setException(Ljava/lang/Throwable;)V\nreturn-void\n.end method\n'
	classes[name] = future
	return classes
}

pub fn framework_account_client_addition(source string) !string {
	signature := 'addAccount(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;'
	native := 'vinixStartAddition(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/atl/VinixAccountFuture;)Z'
	mut method := '.method public ${signature}\n.locals 8\n' +
		'if-nez p1, :valid\nnew-instance v0, Ljava/lang/IllegalArgumentException;\n' +
		'const-string v1, "accountType is null"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n' +
		'new-instance v6, Landroid/atl/VinixAccountFuture;\nconst/4 v7, 0x1\n' +
		'invoke-direct {v6, p6, p7, v7}, Landroid/atl/VinixAccountFuture;-><init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V\n'
	for i in 0 .. 6 { method += 'move-object v${i}, p${i}\n' }
	method += ':native_start\ninvoke-direct/range {v0 .. v6}, Landroid/accounts/AccountManager;->${native}\n' +
		'move-result v0\n:native_end\nif-nez v0, :pending\ngoto :unavailable\n' +
		'.catch Ljava/lang/UnsatisfiedLinkError; {:native_start .. :native_end} :no_native\n' +
		':no_native\nmove-exception v0\n:unavailable\n' +
		'invoke-virtual {v6}, Ljava/util/concurrent/FutureTask;->run()V\n:pending\nreturn-object v6\n.end method'
	text := framework_replace_method(source, signature, method)!
	return framework_replace_method(text, native, '.method private native ${native}\n.end method')!
}
