// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		assert name !in result, name
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn transform(name string, source string) !string {
	return match name {
		'android/content/Context' { androidtools.framework_credential_storage_context(source)! }
		'android/content/ContextWrapper' { androidtools.framework_credential_storage_wrapper(source)! }
		else { androidtools.framework_credential_storage_impl(source)! }
	}
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'BASE_SMALI [TOOLS JAVA]'
	work := os.temp_dir() + '/vinix-credential-storage-' + os.getpid().str()
	defer { os.rmdir_all(work) or {} }
	for name in ['android/content/Context', 'android/content/ContextWrapper', 'android/app/ContextImpl'] {
		old := os.read_file(os.args[1] + '/' + name + '.smali')!
		new := transform(name, old)!
		assert new.starts_with(old), name
		before, after := methods(old), methods(new)
		assert after.len == before.len + 2
		for signature, body in before { assert after[signature] == body, name + signature }
		for signature in ['createCredentialProtectedStorageContext()Landroid/content/Context;', 'isCredentialProtectedStorage()Z'] {
			assert signature in after && signature !in before
		}
		if name.ends_with('ContextImpl') {
			assert new.contains('and-int/lit8 v4, v4, -0x5')
			assert new.contains('xor-int/lit8 v0, v0, 0x1')
			assert after['createCredentialProtectedStorageContext()Landroid/content/Context;'].contains('new-instance v0, Landroid/app/ContextImpl;')
			// Configuration mode preservation is an inherited baseline requirement.
			assert before['createConfigurationContext(Landroid/content/res/Configuration;)Landroid/content/Context;'].contains('->atl_flags:I')
		}
		for bad in [new, old.replace('.super ', '.super LWrong; #'), old + '\n.class public LExtra;\n',
			old + '\n.method public unfinished()V\n'] {
			if _ := transform(name, bad) { panic('accepted malformed credential storage source: ' + name) }
		}
		if os.args.len == 4 {
			path := work + '/smali/' + name + '.smali'
			os.mkdir_all(os.dir(path))!
			os.write_file(path, new)!
		}
	}
	println('ANDROID-CREDENTIAL-STORAGE-TRANSFORM-PASS six additions, original methods preserved, fresh contexts, DE-bit clearing, wrapper delegation, malformed input rejection')
	if os.args.len == 4 {
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-CREDENTIAL-STORAGE-ASSEMBLY-PASS three classes produce DEX; ART not executed')
	}
}
