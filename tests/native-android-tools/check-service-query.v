// SPDX-License-Identifier: GPL-2.0-or-later
// Host transform checks; service-query-fixture.v supplies the separate ART probe.
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

fn rejected(source string) {
	if _ := androidtools.framework_service_query(source) { panic('accepted malformed service query') }
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'BASE_SMALI [TOOLS JAVA]'
	source := os.read_file(os.args[1] + '/android/content/pm/PackageManager.smali')!
	patched := androidtools.framework_service_query(source)!
	before, after := methods(source), methods(patched)
	signature := 'queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;'
	assert before.len == after.len
	for name, body in before { assert if name == signature { after[name] != body } else { after[name] == body }, name }
	body := after[signature]
	assert body.all_after('    :vinix_service_query_implicit\n') == before[signature].all_after('    .end annotation\n\n')
	guard := body.all_before('    :vinix_service_query_implicit\n')
	assert guard.contains('invoke-virtual {p0, v0, p2}, Landroid/content/pm/PackageManager;->getServiceInfo(')
	assert guard.contains('and-int/lit16 v3, p2, 0x200\n    if-nez v3, :vinix_service_query_found')
	assert guard.contains('Landroid/content/pm/ComponentInfo;->enabled:Z')
	assert guard.contains('Landroid/content/pm/ApplicationInfo;->enabled:Z')
	assert guard.count('Ljava/util/List;->add(') == 1
	assert guard.contains('.catch Landroid/content/pm/PackageManager$NameNotFoundException;')
	for absent in ['->getPrimaryApplication(', '->matchAction(', '->intents:', '->getClassLoader(', '->startOrBindService(', '->exported:', '->permission:', 'com/google'] {
		assert !guard.contains(absent), absent
	}
	for bad in [patched, source.replace('.class public Landroid/content/pm/PackageManager;', '.class public Lwrong/Class;'),
		source.replace('.super Ljava/lang/Object;', '.super Lwrong/Parent;'), source + '\n.class public Lwrong/Extra;\n',
		source + '\n.method public unfinished()V\n', source + '\n' + before[signature],
		source.replace(' ' + signature + '\n', ' missing' + signature + '\n'),
		source.replace('    .registers 10\n', '    .registers 11\n'),
		source.replace('->intents:Ljava/util/ArrayList;', '->missing:Ljava/util/ArrayList;')] { rejected(bad) }
	println('ANDROID-SERVICE-QUERY-TRANSFORM-PASS explicit metadata lookup, disabled flag, single result, preserved implicit path, malformed input rejection')
	if os.args.len == 4 {
		work := os.temp_dir() + '/vinix-service-query-' + os.getpid().str()
		os.mkdir_all(work + '/smali/android/content/pm')!
		defer { os.rmdir_all(work) or {} }
		os.write_file(work + '/smali/android/content/pm/PackageManager.smali', patched)!
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-SERVICE-QUERY-ASSEMBLY-PASS changed PackageManager produces DEX; ART not executed')
	}
}
