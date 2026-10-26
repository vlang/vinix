// SPDX-License-Identifier: GPL-2.0-or-later
// Apply the production provider to an actual retained AccountManager class,
// check the complete method delta, and assemble that real transformed class.
module main

import androidtools
import os

struct ClassParts {
	methods  map[string]string
	metadata string
}

fn parts(source string) !ClassParts {
	mut methods := map[string]string{}
	mut metadata := []string{}
	mut current := []string{}
	mut signature := ''
	for line in source.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('.method ') {
			if signature != '' { return error('nested method') }
			signature = trimmed.all_after_last(' ')
			if signature in methods { return error('duplicate method: ' + signature) }
		}
		if signature != '' {
			current << line
			if trimmed == '.end method' {
				methods[signature] = current.join('\n')
				current = []string{}
				signature = ''
			}
		} else if trimmed != '' {
			metadata << line
		}
	}
	if signature != '' { return error('unterminated method') }
	return ClassParts{methods, metadata.join('\n')}
}

fn main() {
	assert os.args.len == 4, 'usage: check-account-store-framework ACCOUNT_MANAGER_SMALI SMALI_TOOLS JAVA'
	source := os.read_file(os.args[1])!
	before := parts(source)!
	assert before.methods.len > 5, 'use an actual AccountManager class, not a minimal fixture'
	patched := androidtools.framework_account_store(source)!
	after := parts(patched)!
	add3 := 'addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z'
	add4 := 'addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Ljava/util/Map;)Z'
	add_native := 'vinixAddExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Ljava/util/Map;)Z'
	query_native := 'vinixAccounts(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;'
	public_natives := [
		'getUserData(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
		'setUserData(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
		'setAccountVisibility(Landroid/accounts/Account;Ljava/lang/String;I)Z',
		'getPassword(Landroid/accounts/Account;)Ljava/lang/String;',
		'setPassword(Landroid/accounts/Account;Ljava/lang/String;)V',
	]
	queries := {
		'getAccounts()[Landroid/accounts/Account;':                                                     'p0, v0, v0'
		'getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;':                             'p0, p1, v0'
		'getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;': 'p0, p1, p2'
	}
	mut targets := [add3, add4, add_native, query_native]
	targets << public_natives
	targets << queries.keys()
	assert before.metadata == after.metadata, 'provider changed class/field metadata'
	for name, method in before.methods {
		assert name in after.methods, 'lost method: ' + name
		if name !in targets {
			assert after.methods[name]! == method, 'changed unrelated method: ' + name
		}
	}
	for name in after.methods.keys() {
		assert name in before.methods || name in targets, 'unexpected added method: ' + name
	}
	for name in targets {
		assert name in after.methods, 'missing store API: ' + name
	}
	for name, registers in {
		add3: 'p0, p1, p2, p3, v0'
		add4: 'p0, p1, p2, p3, p4'
	} {
		method := after.methods[name]!
		assert method.contains('invoke-direct {' + registers + '}, Landroid/accounts/AccountManager;->' + add_native)
		assert method.contains('move-result v0\nreturn v0'), 'must return backend insertion result'
		assert !method.contains('System;->out') && !method.contains('throw ')
	}
	assert after.methods[add3]!.contains('const/4 v0, 0x0\ninvoke-direct'), 'three-argument add requires null visibility map'
	for name, registers in queries {
		method := after.methods[name]!
		assert method.contains('invoke-direct {' + registers + '}, Landroid/accounts/AccountManager;->' + query_native)
		assert method.contains('move-result-object v0\nreturn-object v0')
		assert !method.contains('new-array'), 'query cannot fabricate an empty result'
	}
	for name in public_natives {
		assert after.methods[name]! == '.method public native ' + name + '\n.end method'
	}
	for name in [add_native, query_native] {
		assert after.methods[name]! == '.method private native ' + name + '\n.end method'
	}
	assert androidtools.framework_account_store(patched)! == patched, 'provider must replace existing hooks without duplicating them'
	mut rejected := 0
	for bad in [source.replace(' Landroid/accounts/AccountManager;\n', ' LOther;\n'),
		source + '\n' + before.methods[add3]!] {
		androidtools.framework_account_store(bad) or {
			rejected++
			continue
		}
	}
	assert rejected == 2, 'wrong class and duplicate existing method must be rejected'
	production := os.read_file('tests/native-android-tools/androidtools/framework_accounts.v')!.all_after('fn framework_account_listeners(').all_before('\nfn framework_storage_queries(')
	assert production.count('text = framework_account_store(text)!') == 1
	assert production.index('text = framework_account_store(text)!') or { panic('missing store provider') } < production.index('os.write_file(path, text)!') or { panic('missing AccountManager write') }
	work := os.join_path(os.temp_dir(), 'vinix-account-store-framework-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work + '/smali/android/accounts')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/smali/android/accounts/AccountManager.smali', patched)!
	androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
	assert os.read_bytes(work + '/classes.dex')!.len > 112
	println('ACCOUNT-STORE-FRAMEWORK-PASS actual-source exact-method-delta both-add-overloads native-store-queries package-target password-userdata visibility idempotence assembly')
}
