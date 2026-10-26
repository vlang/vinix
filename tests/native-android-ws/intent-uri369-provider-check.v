// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import x.json2

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn command(root string, name string, argv []string) ! {
	r := os.exec(argv)
	os.write_file(root + '/' + name + '.log', r.output)!
	os.write_file(root + '/' + name + '.json', json2.encode({
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
	}))!
	if r.exit_code != 0 { return error(name + ': ' + r.output) }
}

fn run() ! {
	if os.args.len != 6 {
		return error('usage: provider-check V JAVA SMALI_TOOLS BASELINE_SMALI FRESH_RESULT')
	}
	compiler := os.args[1]
	java := os.args[2]
	tools := os.args[3]
	baseline := os.args[4]
	root := os.abs_path(os.args[5])
	assert !os.exists(root) && !os.is_link(root)
	os.mkdir_all(root + '/driver/androidtools')!
	provider := 'tests/native-android-tools/androidtools/framework_intent_uri.v'
	provider_hash := digest(provider)!
	os.cp(provider, root + '/driver/androidtools/framework_intent_uri.v')!
	marker := 'pub fn framework_replace_method('
	helper := os.read_file('tests/native-android-tools/androidtools/framework.v')!.all_after(marker).all_before('\n// Missing packages')
	os.write_file(root + '/driver/androidtools/framework_method.v', 'module androidtools\n' + marker + helper + '\n')!
	os.write_file(root + '/driver/main.v', 'module main\nimport androidtools\nimport os\nfn main() {\n if os.args.len == 3 {\n  androidtools.framework_intent_uri(os.args[1]) or { println("REJECTION-PASS"); return }\n  panic("accepted invalid input")\n }\n androidtools.framework_intent_uri(os.args[1]) or { panic(err) }\n}\n')!
	command(root, 'compile', [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o', root + '/provider',
		root + '/driver'])!
	files := ['android/content/Intent.smali', 'android/net/Uri.smali',
		'android/content/ComponentName.smali', 'android/graphics/Rect.smali']
	mut before := map[string]string{}
	for file in files {
		path := root + '/smali/' + file
		os.mkdir_all(os.dir(path))!
		os.cp(baseline + '/' + file, path)!
		before[file] = digest(path)!
	}
	intent := root + '/smali/' + files[0]
	original := os.read_file(intent)!
	os.write_file(intent, original.replace('.class public Landroid/content/Intent;', '.class invalid Landroid/content/Intent;'))!
	invalid := digest(intent)!
	command(root, 'malformed', [root + '/provider', root + '/smali', 'reject'])!
	assert digest(intent)! == invalid
	os.write_file(intent, original)!
	command(root, 'apply', [root + '/provider', root + '/smali'])!
	changed := digest(intent)!
	assert changed != before[files[0]]
	command(root, 'duplicate', [root + '/provider', root + '/smali', 'reject'])!
	assert digest(intent)! == changed
	for file in files[1..] {
		assert digest(root + '/smali/' + file)! == before[file]
	}
	dex := root + '/classes.dex'
	assert !os.exists(dex)
	command(root, 'assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs',
		'2', root + '/smali', '-o', dex])!
	assert os.is_file(dex) && os.file_size(dex) > 0, 'smali failed without a nonzero status'
	assert digest(provider)! == provider_hash
	os.write_file(root + '/result.json', json2.encode({
		'provider_sha256':                   json2.Any(provider_hash)
		'input_intent_sha256':               json2.Any(before[files[0]])
		'output_intent_sha256':              json2.Any(changed)
		'dex_sha256':                        json2.Any(digest(dex)!)
		'malformed_and_duplicate_unchanged': json2.Any(true)
		'other_input_classes_unchanged':     json2.Any(true)
	}))!
	println('INTENT369-PROVIDER-HOST-PASS provider=' + provider_hash)
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
