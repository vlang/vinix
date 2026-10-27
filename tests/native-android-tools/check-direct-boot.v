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

fn component_rejected(source string) {
	if _ := androidtools.framework_component_direct_boot(source) { panic('accepted malformed ComponentInfo') }
}

fn parser_rejected(source string) {
	if _ := androidtools.framework_parser_direct_boot(source) { panic('accepted malformed direct boot parser') }
}

fn main() {
	assert os.args.len == 2 || os.args.len == 4, 'BASE_SMALI [TOOLS JAVA]'
	component := os.read_file(os.args[1] + '/android/content/pm/ComponentInfo.smali')!
	parser := os.read_file(os.args[1] + '/android/content/pm/PackageParser.smali')!
	new_component := androidtools.framework_component_direct_boot(component)!
	new_parser := androidtools.framework_parser_direct_boot(parser)!
	before, after := methods(component), methods(new_component)
	assert new_component.count('.field public directBootAware:Z') == 1
	assert before.len == after.len
	for name, body in before {
		if name == '<init>(Landroid/content/pm/ComponentInfo;)V' {
			assert after[name].count('->directBootAware:Z') == 2
			assert after[name].contains('iget-boolean v0, p1, Landroid/content/pm/ComponentInfo;->directBootAware:Z')
		} else { assert after[name] == body, name }
	}
	old_methods, new_methods := methods(parser), methods(new_parser)
	assert new_methods.len == old_methods.len + 1
	mut changed := 0
	for name, body in old_methods {
		if name.starts_with('parseActivity(') || name.starts_with('parseService(') || name.starts_with('parseProvider(') {
			assert new_methods[name].count('->vinixParseDirectBoot(') == 1
			assert new_methods[name].contains('move-object/from16 v0, p2\n    move-object/from16 v1, p4')
			changed++
		} else if name.starts_with('parseActivityAlias(') {
			assert new_methods[name].count('->directBootAware:Z') == 2
			changed++
		} else { assert new_methods[name] == body, name }
	}
	assert changed == 4
	helper := new_methods['vinixParseDirectBoot(Landroid/content/res/Resources;Landroid/util/AttributeSet;Landroid/content/pm/ComponentInfo;)V']
	assert helper.contains('const v1, 0x01010505')
	assert helper.contains('const/4 v2, 0x0') && helper.contains('getBoolean(IZ)Z') && helper.contains('recycle()V')
	for bad in [new_component, component.replace('.class public ', '.class private '),
		component.replace('    .registers 3\n', '    .registers 4\n'),
		component + '\n.class public LExtra;\n', component + '\n.method public unfinished()V\n'] { component_rejected(bad) }
	for bad in [new_parser, parser.replace('.super Ljava/lang/Object;', '.super LWrong;'),
		parser.replace('    .registers 20\n', '    .registers 21\n'),
		parser.replace('targetActivity:Ljava/lang/String;', 'missingTarget:Ljava/lang/String;'),
		parser + '\n.class public LExtra;\n', parser + '\n.method public unfinished()V\n'] { parser_rejected(bad) }
	println('ANDROID-DIRECT-BOOT-TRANSFORM-PASS inherited field, false default, copy, component parsers, alias, TypedArray resources, malformed input rejection')
	if os.args.len == 4 {
		work := os.temp_dir() + '/vinix-direct-boot-' + os.getpid().str()
		os.mkdir_all(work + '/smali/android/content/pm')!
		defer { os.rmdir_all(work) or {} }
		os.write_file(work + '/smali/android/content/pm/ComponentInfo.smali', new_component)!
		os.write_file(work + '/smali/android/content/pm/PackageParser.smali', new_parser)!
		androidtools.framework_assemble(work + '/smali', work + '/classes.dex', os.real_path(os.args[2]), os.args[3])!
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-DIRECT-BOOT-ASSEMBLY-PASS ComponentInfo and PackageParser produce DEX; ART not executed')
	}
}
