// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(root string, name string, argv []string, expected string) ! {
	r := os.exec(argv)
	os.write_file(root + '/' + name + '.log', r.output)!
	os.write_file(root + '/' + name + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code)
	}))!
	if r.exit_code != 0 { return error(name + ': ' + r.output) }
	if expected != '' && !r.output.contains(expected) { return error(name + ': wrong outcome') }
}

fn run() ! {
	if os.args.len != 6 { return error('usage: intent-parcel-provider-check V JAVA SMALI_TOOLS BASELINE_SMALI FRESH_RESULT') }
	root := os.abs_path(os.args[5])
	if os.exists(root) || os.is_link(root) { return error('fresh results directory required') }
	os.mkdir_all(root + '/source/androidtools')!
	provider := 'tests/native-android-tools/androidtools/framework_intent_parcel.v'
	provider_pin := digest(provider)!
	os.cp(provider, root + '/source/androidtools/framework_intent_parcel.v')!
	os.write_file(root + '/source/main.v', 'module main\nimport os\nimport androidtools\nfn main() {\n' +
		'path := os.args[1]\nsource := os.read_file(path)!\n' +
		'output := androidtools.framework_intent_parcel_source(source) or {\n' +
		'if os.args.len == 3 { println("REJECTION-PASS " + err.msg()); return }; panic(err)\n}\n' +
		'if os.args.len == 3 { panic("invalid input accepted") }\n' +
		'os.write_file(path, output)!\nos.write_file(os.dir(path) + "/VinixIntentCreator.smali", androidtools.framework_intent_parcel_creator_source())!\n}\n')!
	command(root, 'compile', [os.args[1], '-cc', '/usr/bin/cc', '-o', root + '/provider', root + '/source'], '')!
	path := root + '/smali/android/content/Intent.smali'
	os.mkdir_all(os.dir(path))!
	original := os.read_file(os.args[4] + '/android/content/Intent.smali')!
	mut mutations := {
		'wrong-class': original.replace('.class public Landroid/content/Intent;', '.class public Lother/Intent;')
		'not-parcelable': original.replace('.implements Landroid/os/Parcelable;\n', '')
		'inherited-state': original.replace('.super Ljava/lang/Object;', '.super Lother/State;')
		'unknown-field': original + '\n.field private unmodeled:I\n'
		'indented-unknown-field': original + '\n\t.field private unmodeled:I\n'
		'duplicate-field': original + '\n.field private flags:I\n'
		'missing-field': original.replace('.field private flags:I\n', '')
		'existing-creator': original + '\n.field public static CREATOR:Landroid/os/Parcelable\$Creator;\n'
		'existing-initializer': original + '\n.method static constructor <clinit>()V\n.locals 0\nreturn-void\n.end method\n'
	}
	for signature in ['<init>(Landroid/os/Parcel;)V', 'describeContents()I',
		'writeToParcel(Landroid/os/Parcel;I)V', 'readFromParcel(Landroid/os/Parcel;)V',
		'vinixReadFromParcel(Landroid/os/Parcel;)V'] {
		mutations[signature] = original + '\n.method public ' + signature + '\n.locals 0\n.end method\n'
	}
	mut index := 0
	for _, invalid in mutations {
		os.write_file(path, invalid)!
		pin := digest(path)!
		command(root, 'rejection-' + index.str(), [root + '/provider', path, 'reject'], 'REJECTION-PASS')!
		if digest(path)! != pin || os.exists(os.dir(path) + '/VinixIntentCreator.smali') {
			return error('rejected transformation mutated input')
		}
		index++
	}
	os.write_file(path, original)!
	command(root, 'apply', [root + '/provider', path], '')!
	output := os.read_file(path)!
	append := output[original.len..]
	if output.count(' CREATOR:') != 1 || !append.contains('Unsupported Intent parcel state')
		|| append.contains('Ljava/io/PrintStream;') || append.contains('Ljava/lang/System;')
		|| append.contains('Ljava/lang/StringBuilder;') { return error('unexpected codec or logging') }
	changed := digest(path)!
	creator := digest(os.dir(path) + '/VinixIntentCreator.smali')!
	command(root, 'duplicate-application', [root + '/provider', path, 'reject'], 'REJECTION-PASS')!
	if digest(path)! != changed || digest(os.dir(path) + '/VinixIntentCreator.smali')! != creator {
		return error('duplicate application changed output')
	}
	command(root, 'assemble', [os.args[2], '-cp', os.args[3] + '/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'], '')!
	if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 {
		return error('assembly produced no DEX')
	}
	if digest(provider)! != provider_pin { return error('provider changed during check') }
	os.write_file(root + '/result.json', json2.encode({
		'provider_sha256': json2.Any(provider_pin), 'input_sha256': json2.Any(sha256.sum(original.bytes()).hex()),
		'output_sha256': json2.Any(changed), 'creator_sha256': json2.Any(creator),
		'dex_sha256': json2.Any(digest(root + '/classes.dex')!), 'rejections': json2.Any(index + 1)
	}))!
	println('INTENT-PARCEL-PROVIDER-PASS rejections=' + (index + 1).str() + ' assembly no-argument-logging')
}

fn main() { run() or { eprintln(err); exit(1) } }
