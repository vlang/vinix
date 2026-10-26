// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import x.json2

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn command(root string, name string, argv []string, expected string) ! {
	r := os.exec(argv)
	os.write_file(root + '/' + name + '.log', r.output)!
	os.write_file(root + '/' + name + '.json', json2.encode({
		'argv':      json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
	}))!
	if r.exit_code != 0 { return error(name + ': ' + r.output) }
	assert expected == '' || r.output.contains(expected), name + ': wrong outcome'
}

fn inventory(root string, files []string) !map[string]string {
	mut hashes := map[string]string{}
	for file in files {
		hashes[file] = digest(root + '/smali/' + file)!
	}
	return hashes
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
	os.write_file(root + '/driver/main.v', 'module main\nimport androidtools\nimport os\nfn main() {\n if os.args.len == 3 {\n  androidtools.framework_intent_uri(os.args[1]) or { println("REJECTION-PASS " + err.msg()); return }\n  panic("accepted invalid input")\n }\n androidtools.framework_intent_uri(os.args[1]) or { panic(err) }\n}\n')!
	command(root, 'compile', [compiler, '-nocache', '-cc', '/usr/bin/cc', '-o', root + '/provider',
		root + '/driver'], '')!
	files := ['android/content/Intent.smali', 'android/net/Uri.smali',
		'android/content/ComponentName.smali', 'android/graphics/Rect.smali']
	for file in files {
		path := root + '/smali/' + file
		os.mkdir_all(os.dir(path))!
		os.cp(baseline + '/' + file, path)!
	}
	before := inventory(root, files)!
	intent := root + '/smali/' + files[0]
	original := os.read_file(intent)!
	getter_start := '.method public getDataString()Ljava/lang/String;'
	assert original.count(getter_start) == 1
	getter := getter_start + original.all_after(getter_start).all_before('.end method') + '.end method'
	mutations := {
		'malformed':        original.replace('.class public Landroid/content/Intent;', '.class invalid Landroid/content/Intent;')
		'missing-getter':   original.replace(getter, '')
		'duplicate-getter': original + '\n' + getter + '\n'
	}
	for name, source in mutations {
		os.write_file(intent, source)!
		invalid := inventory(root, files)!
		expected := if name == 'malformed' {
			'requires the canonical Intent class'
		} else {
			'missing or duplicate method getDataString()Ljava/lang/String;'
		}
		command(root, name, [root + '/provider', root + '/smali', 'reject'], 'REJECTION-PASS Intent URI parser ' + expected)!
		assert inventory(root, files)! == invalid, name + ': rejection mutated input'
	}
	os.write_file(intent, original)!
	command(root, 'apply', [root + '/provider', root + '/smali'], '')!
	changed := digest(intent)!
	assert changed != before[files[0]]
	output := os.read_file(intent)!
	expected_getter := r'.method public getDataString()Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/content/Intent;->data:Landroid/net/Uri;
if-nez v0, :has_data
const/4 v0, 0
return-object v0
:has_data
invoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;
move-result-object v0
return-object v0
.end method'
	assert output.count(getter_start) == 1 && output.contains(expected_getter)
	applied := inventory(root, files)!
	command(root, 'duplicate-application', [root + '/provider', root + '/smali', 'reject'], 'REJECTION-PASS Intent URI parser input already defines ')!
	assert inventory(root, files)! == applied
	for file in files[1..] {
		assert applied[file] == before[file]
	}
	dex := root + '/classes.dex'
	assert !os.exists(dex)
	command(root, 'assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs',
		'2', root + '/smali', '-o', dex], '')!
	assert os.is_file(dex) && os.file_size(dex) > 0, 'smali failed without a nonzero status'
	assert digest(provider)! == provider_hash
	os.write_file(root + '/result.json', json2.encode({
		'provider_sha256':               json2.Any(provider_hash)
		'input_intent_sha256':           json2.Any(before[files[0]])
		'output_intent_sha256':          json2.Any(changed)
		'dex_sha256':                    json2.Any(digest(dex)!)
		'four_rejections_unchanged':     json2.Any(true)
		'getter_null_branch_explicit':   json2.Any(true)
		'other_input_classes_unchanged': json2.Any(true)
	}))!
	println('INTENT371-PROVIDER-HOST-PASS provider=' + provider_hash)
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
