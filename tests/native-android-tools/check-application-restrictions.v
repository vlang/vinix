// SPDX-License-Identifier: GPL-2.0-or-later
// Host transformation and DEX checks. Runtime Bundle isolation needs ART.
module main

import androidtools
import os

fn methods(source string) map[string]string {
	mut result := map[string]string{}
	for block in source.split('.method ')[1..] {
		name := block.all_before('\n').all_after_last(' ')
		assert name !in result, name
		assert block.contains('.end method'), name
		result[name] = '.method ' + block.all_before('.end method') + '.end method'
	}
	return result
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'BASE_SMALI [TOOLS JAVA]'
	name := 'android/os/UserManager.smali'
	old := os.read_file(os.args[1] + '/' + name)!
	new := androidtools.framework_application_restrictions_user_manager(old)!
	method := androidtools.framework_application_restrictions_method()
	signature := 'getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;'
	before, after := methods(old), methods(new)
	assert new == old + '\n' + method + '\n'
	assert before.len == 6 && after.len == 7
	for declaration, body in before { assert after[declaration] == body, declaration }
	assert signature !in before && after[signature] == method
	assert method == '.method public ' + signature + '\n' +
		'    .locals 1\n' +
		'    new-instance v0, Landroid/os/Bundle;\n' +
		'    invoke-direct {v0}, Landroid/os/Bundle;-><init>()V\n' +
		'    return-object v0\n.end method'
	// Verify the real retained framework provides the constructor and inherited
	// queries used by both this API and the generic runtime regression.
	bundle := os.read_file(os.args[1] + '/android/os/Bundle.smali')!
	assert bundle.split_into_lines().filter(it.starts_with('.super ')) == ['.super Landroid/os/BaseBundle;']
	assert '<init>()V' in methods(bundle)
	base := methods(os.read_file(os.args[1] + '/android/os/BaseBundle.smali')!)
	for available in ['<init>()V', 'size()I', 'isEmpty()Z',
		'getStringArray(Ljava/lang/String;)[Ljava/lang/String;',
		'putStringArray(Ljava/lang/String;[Ljava/lang/String;)V'] {
		assert available in base, available
	}
	assert base['<init>()V'].contains('new-instance v0, Landroid/util/ArrayMap;')
	for rejected in [
		new,
		old.replace('.class public Landroid/os/UserManager;', '.class public Lwrong/Class;'),
		old.replace('.super Ljava/lang/Object;', '.super Lwrong/Parent;'),
		old + '\n.class public Lwrong/Extra;\n',
		old + '\n.method public unfinished()V\n',
		old + '\n' + before['isUserUnlocked()Z'] + '\n',
		old.replace('.method public isUserUnlocked()Z', '.method private isUserUnlocked()Z'),
		old + '\n.field private unexpected:I\n',
		old.replace('supportsMultipleUsers()Z', 'missingSupportsMultipleUsers()Z'),
	] {
		if _ := androidtools.framework_application_restrictions_user_manager(rejected) {
			panic('accepted unexpected or already transformed UserManager')
		}
	}
	println('ANDROID-APPLICATION-RESTRICTIONS-TRANSFORM-PASS one added API, six original methods preserved, fresh Bundle, real Bundle APIs, nine invalid inputs rejected')
	if os.args.len == 4 {
		work := os.temp_dir() + '/vinix-application-restrictions-' + os.getpid().str()
		defer { os.rmdir_all(work) or {} }
		path := work + '/smali/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, new)!
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-APPLICATION-RESTRICTIONS-ASSEMBLY-PASS changed UserManager produces DEX; ART not executed')
	}
}
