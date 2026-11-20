// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import os

fn main() {
	if os.args.len != 3 {
		panic('usage: build-signin-platform-framework FRAMEWORK FRESH_EXTERNAL_OUTPUT')
	}
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external output required')
	}
	tools := os.getenv_opt('VINIX_SMALI_TOOLS') or { os.real_path('build/android-framework/tools') }
	mut changed := map[string]string{}
	mut refusals := 0
	for class in androidtools.signin_platform_classes() {
		original := os.read_file(base + '/smali/' + class + '.smali')!
		output := androidtools.framework_signin_platform_source(class, original)!
		for variant in [output, original.replace(' L' + class + ';\n', ' Lother/Class;\n')] {
			mut rejected := false
			androidtools.framework_signin_platform_source(class, variant) or { rejected = true }
			assert rejected, class
			refusals++
		}
		// Every class an added signature names must exist, or ART fails to
		// link app subclasses that override it (see framework_webview_client).
		for line in output[original.len..].split_into_lines() {
			if !line.starts_with('.method ') {
				continue
			}
			for part in line.all_after('(').split(';') {
				type_name := part.all_after('L')
				if part.contains('L') && !type_name.starts_with('java/') {
					assert os.is_file(base + '/smali/' + type_name + '.smali'), line
				}
			}
		}
		changed[class] = output
	}
	os.mkdir_all(root)!
	os.cp_all(base + '/smali', root + '/smali', false)!
	for class, source in changed {
		os.write_file(root + '/smali/' + class + '.smali', source)!
	}
	os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := tools + '/*'
	classes := androidtools.signin_platform_classes().map('L' + it + ';').join(',')
	for args in [
		[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2',
			root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', classes,
			'--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip'],
	] {
		if os.system_args(args) != 0 {
			panic('SDK assembly/readback failed')
		}
	}
	for class in androidtools.signin_platform_classes() {
		readback := os.read_file(root + '/roundtrip/' + class + '.smali')!
		assert readback.len > 0, class
	}
	settings := os.read_file(root + '/roundtrip/android/provider/Settings$System.smali')!
	assert settings.contains('.method public static getConfiguration(Landroid/content/ContentResolver;Landroid/content/res/Configuration;)V')
	println('SIGNIN-PLATFORM-SDK-PASS assembly readback ${refusals}-input-refusals')
}
