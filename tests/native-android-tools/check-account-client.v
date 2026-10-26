// SPDX-License-Identifier: GPL-2.0-or-later
// Surface/assembly checks, not an ART completion or real Google login claim.
module main

import androidtools
import os

fn method(source string, signature string) string {
	for block in source.split('.method ')[1..] {
		if block.all_before('\n').ends_with(' ' + signature) {
			return block.all_after('\n').all_before('.end method')
		}
	}
	panic('missing method ' + signature)
}

fn main() {
	assert os.args.len in [1, 3], 'usage: check-account-client [TOOLS JAVA]'
	prefix := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n'
	manager := androidtools.framework_account_client_addition(prefix)!
	assert androidtools.framework_account_client_addition(manager)! == manager
	mut rejected := false
	androidtools.framework_account_client_addition(manager + manager.all_after(prefix)) or { rejected = true }
	assert rejected
	rejected = false
	androidtools.framework_account_client_addition(manager.all_before('.end method')) or { rejected = true }
	assert rejected
	classes := androidtools.framework_account_client_classes()
	future := classes['android/atl/VinixAccountFuture']
	pending := method(future, '<init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;Z)V')
	assert pending.contains('if-nez p3, :pending\ninvoke-virtual {p0}, Ljava/util/concurrent/FutureTask;->run()V\n:pending')
	assert method(future, '<init>(Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)V').contains('->run()V')
	done := method(future, 'done()V')
	cleanup_at := done.index('->vinixFinished()V') or { panic('missing cleanup') }
	post_at := done.index('->post(Ljava/lang/Runnable;)Z') or { panic('missing callback') }
	assert cleanup_at < post_at
	assert done.contains('.catch Ljava/lang/UnsatisfiedLinkError; {:cleanup_start .. :cleanup_end} :no_native')
	assert future.contains('.method private native vinixFinished()V')
	result := method(future, 'vinixResult(Landroid/os/Bundle;)V')
	assert result.contains('Bundle;-><init>(Landroid/os/Bundle;)V')
	assert result.contains('FutureTask;->set(Ljava/lang/Object;)V')
	assert !result.contains('->run()V')
	error_body := method(future, 'vinixError(ILjava/lang/String;)V')
	assert error_body.contains('const/4 v0, 3\nif-ne p1, v0, :next_3\nnew-instance v1, Ljava/io/IOException;')
	assert error_body.contains('const/4 v0, 4\nif-ne p1, v0, :next_4\nnew-instance v1, Landroid/accounts/OperationCanceledException;')
	assert error_body.contains('FutureTask;->setException(Ljava/lang/Throwable;)V')
	for signature in ['getResult()Ljava/lang/Object;', 'getResult(JLjava/util/concurrent/TimeUnit;)Ljava/lang/Object;'] {
		assert method(future, signature).contains('instance-of v1, v0, Landroid/accounts/OperationCanceledException;\nif-nez v1, :cause')
	}
	for signature in ['cancel(Z)Z', 'isDone()Z', 'isCancelled()Z', 'run()V'] {
		assert !future.contains('.method public ' + signature)
	}
	assert manager.contains('invoke-direct/range {v0 .. v6}')
	assert manager.contains('if-nez v0, :pending\ngoto :unavailable')
	assert manager.contains('FutureTask;->run()V\n:pending\nreturn-object v6')
	assert manager.count('.method private native vinixStartAddition(') == 1
	if os.args.len == 3 {
		work := os.join_path(os.temp_dir(), 'vinix-account-client-' + os.getpid().str())
		os.mkdir_all(work + '/smali/android/accounts')!
		os.mkdir_all(work + '/smali/android/atl')!
		defer { os.rmdir_all(work) or {} }
		os.write_file(work + '/smali/android/accounts/AccountManager.smali', manager)!
		for name, text in classes { os.write_file(work + '/smali/' + name + '.smali', text)! }
		dex := work + '/classes.dex'
		androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
		assert os.read_bytes(dex)!.len > 112
		println('ANDROID-ACCOUNT-CLIENT-ASSEMBLY-PASS pending future terminal methods and native-start range')
	}
	println('ANDROID-ACCOUNT-CLIENT-SOURCE-PASS pending fallback cleanup handler FutureTask completion error mapping')
}
