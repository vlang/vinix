// SPDX-License-Identifier: GPL-2.0-or-later
// Source and DEX guard; account-interaction-fixture supplies ART behavior tests.
module main

import androidtools
import os

fn validate_interaction(source string, bundle string, pending string, response string) ! {
	if !source.starts_with('.class public final Landroid/atl/VinixAccountInteraction;\n.super Ljava/lang/Object;\n')
		|| source.count('.method ') != 2 || source.contains('.field ')
		|| !source.contains('public static extract(Landroid/os/Bundle;Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;)Landroid/content/Intent;') {
		return error('unexpected interaction helper surface')
	}
	if source.count('->exact(Ljava/lang/Object;Ljava/lang/Class;)Z') != 8
		|| source.count('->vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;') != 3
		|| source.count('->getExtras()Landroid/os/Bundle;') != 2
		|| source.count('->getPackage()Ljava/lang/String;') != 2
		|| !source.contains('"com.google.android.gms.ui.UNPACKING_REDIRECT"')
		|| !source.contains('"am_response"') || !source.contains('"target"')
		|| !source.contains('->vinixMatchesResponse(Landroid/accounts/IAccountAuthenticatorResponse;)Z')
		|| !source.contains('return-object v3') {
		return error('missing exact graph, origin or callback validation')
	}
	for forbidden in ['Ljava/lang/reflect/', '->getParcelable(', '->get(Ljava/lang/String;)',
		'->readFromParcel(', '->onResult(', 'new-instance ', 'iput-', 'invoke-interface '] {
		if source.contains(forbidden) { return error('interaction helper executes or reconstructs application objects') }
	}
	if !bundle.contains('public final declared-synchronized vinixAccountInteractionValue(')
		|| bundle.count('monitor-enter p0') != 1 || bundle.count('monitor-exit p0') != 2
		|| !bundle.contains('const-class v1, Landroid/os/Bundle;\nif-ne v0, v1, :invalid')
		|| !bundle.contains('->vinixIsParcelled()Z\nmove-result v0\nif-nez v0, :invalid')
		|| !bundle.contains('->mMap:Landroid/util/ArrayMap;')
		|| !bundle.contains('->get(Ljava/lang/Object;)Ljava/lang/Object;')
		|| bundle.contains('->vinixGetMap(') {
		return error('Bundle accessor must reject lazy values under its monitor')
	}
	if !pending.contains('public final vinixAccountActivityIntent()')
		|| !pending.contains('const-class v1, Landroid/app/PendingIntent;\nif-ne v0, v1, :invalid')
		|| !pending.contains('->vinixCanceled:Z\nif-nez v0, :invalid')
		|| !pending.contains('->type:I\nif-nez v0, :invalid') {
		return error('PendingIntent accessor must reject subclass, cancellation and non-Activity operations')
	}
	if !response.contains('public final vinixMatchesResponse(')
		|| !response.contains('const-class v1, Landroid/accounts/AccountAuthenticatorResponse;\nif-ne v0, v1, :invalid')
		|| !response.contains('if-eqz p1, :invalid') || !response.contains('if-ne v0, p1, :invalid') {
		return error('callback identity must be exact')
	}
}

fn main() {
	assert os.args.len in [1, 3], 'usage: check-account-interaction [TOOLS JAVA]'
	classes := androidtools.framework_account_interaction_classes()
	assert classes.len == 1
	source := classes['android/atl/VinixAccountInteraction']
	bundle := androidtools.framework_account_interaction_bundle_accessor()
	pending := androidtools.framework_account_interaction_pending_accessor()
	response := androidtools.framework_account_interaction_response_accessor()
	validate_interaction(source, bundle, pending, response)!
	mut rejected := 0
	for index, needle in ['.class public final ', '->exact(', '"am_response"', '->vinixAccountInteractionValue(',
		'->vinixIsParcelled()', 'monitor-enter p0', '->vinixCanceled:Z', '->type:I', 'if-ne v0, p1, :invalid'] {
		mut changed := [source, bundle, pending, response]
		part := if index < 4 { 0 } else if index < 6 { 1 } else if index < 8 { 2 } else { 3 }
		assert changed[part].contains(needle)
		changed[part] = changed[part].replace(needle, 'invalid')
		validate_interaction(changed[0], changed[1], changed[2], changed[3]) or { rejected++; continue }
		panic('interaction guard accepted missing validation')
	}
	if os.args.len == 3 {
		work := os.join_path(os.temp_dir(), 'vinix-account-interaction-' + os.getpid().str())
		defer { os.rmdir_all(work) or {} }
		mut all := classes.clone()
		all['android/os/Bundle'] = '.class public Landroid/os/Bundle;\n.super Landroid/os/BaseBundle;\n' + bundle
		all['android/app/PendingIntent'] = '.class public Landroid/app/PendingIntent;\n.super Ljava/lang/Object;\n' +
			'.field private vinixCanceled:Z\n.field private type:I\n.field private intent:Landroid/content/Intent;\n' + pending
		for name, body in androidtools.framework_authenticator_response_classes() { all[name] = body }
		for name, body in all {
			path := work + '/smali/' + name + '.smali'
			os.mkdir_all(os.dir(path))!
			os.write_file(path, body)!
		}
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[1]), os.args[2])!
		assert os.read_bytes(work + '/classes.dex')!.len > 112
		println('ANDROID-ACCOUNT-INTERACTION-ASSEMBLY-PASS helper Bundle PendingIntent response accessors')
	}
	println('ANDROID-ACCOUNT-INTERACTION-SURFACE-PASS original-intent exact-classes response-identity materialized-bundles negative-mutations=${rejected}')
}
