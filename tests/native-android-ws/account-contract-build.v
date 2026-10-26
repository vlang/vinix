// SPDX-License-Identifier: GPL-2.0-or-later
// Small framework-only build; retains direct inputs, without historical audits.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const baseline = '/Users/alex/.local/state/vinix/android/intent-uri371-framework-build-2026-10-26/framework'
const jar_pin = '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
const compiler = '/Users/alex/code/v/v'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const tools = repo + '/build/android-framework/tools'
const additions = ['android/accounts/AccountManagerCallback.smali',
	'android/accounts/AccountManagerFuture.smali', 'android/accounts/AccountsException.smali',
	'android/accounts/AuthenticatorException.smali', 'android/accounts/OperationCanceledException.smali',
	'android/atl/VinixAccountFailure.smali', 'android/atl/VinixAccountFuture.smali',
	'android/atl/VinixAccountCallback.smali']

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err.code() == 0 { break }; return err }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(root string, label string, argv []string) !string {
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code)
	})!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
	return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = digest(root + '/' + key)! }
			else { return error('nonregular framework input: ' + key) }
		}
	}
}

fn class_delta(old map[string]string, new map[string]string) ! {
	changed := 'android/accounts/AccountManager.smali'
	if old.len != 2076 || new.len != old.len + additions.len {
		return error('unexpected framework class count')
	}
	for name in additions {
		if name in old || name !in new { return error('unexpected added class: ' + name) }
	}
	for name, pin in old {
		if name !in new { return error('missing existing class: ' + name) }
		if (name == changed) == (pin == new[name]!) {
			return error('unexpected framework class delta: ' + name)
		}
	}
}

fn self_test() ! {
	mut old := map[string]string{}
	for i in 0 .. 2075 { old['other/' + i.str() + '.smali'] = 'old' }
	old['android/accounts/AccountManager.smali'] = 'old'
	mut good := old.clone()
	good['android/accounts/AccountManager.smali'] = 'new'
	for name in additions { good[name] = 'new' }
	class_delta(old, good)!
	for case in 0 .. 5 {
		mut bad := good.clone()
		match case {
			0 { bad['other/0.smali'] = 'changed' }
			1 { bad.delete('other/0.smali') }
			2 { bad['surprise.smali'] = 'new' }
			3 { bad['android/accounts/AccountManager.smali'] = 'old' }
			else { bad.delete(additions[0]) }
		}
		class_delta(old, bad) or { continue }
		return error('invalid class delta accepted: ' + case.str())
	}
	println('ACCOUNT-CONTRACT-BUILD-SELF-TEST-PASS five invalid class deltas rejected')
}

fn build(root string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh external directory required') }
	if !root.starts_with('/Users/alex/.local/state/vinix/android/') {
		return error('external Android state directory required')
	}
	os.mkdir_all(root + '/commands')!
	os.mkdir_all(root + '/source/androidtools')!
	mut inputs := map[string]string{}
	provider := repo + '/tests/native-android-tools/androidtools/framework_accounts.v'
	method_file := repo + '/tests/native-android-tools/androidtools/framework.v'
	classes_file := repo + '/tests/native-android-tools/androidtools/framework_classes.v'
	for path in [provider, method_file, classes_file, compiler, os.real_path(java),
		repo + '/tests/native-android-ws/account-contract-build.v', baseline + '/api-impl.jar'] {
		inputs[path] = digest(path)!
	}
	for name in os.ls(tools)!.filter(it.ends_with('.jar')) { inputs[tools + '/' + name] = digest(tools + '/' + name)! }
	if inputs[baseline + '/api-impl.jar']! != jar_pin { return error('Framework371 JAR differs') }
	os.cp(repo + '/tests/native-android-ws/account-contract-build.v', root + '/builder-source.v')!
	os.cp(provider, root + '/source/androidtools/framework_accounts.v')!
	method_marker := 'pub fn framework_replace_method('
	method_text := os.read_file(method_file)!.all_after(method_marker).all_before('\n// Missing packages')
	interface_marker := 'fn interface_class('
	interface_text := os.read_file(classes_file)!.all_after(interface_marker).all_before('\npub fn framework_extra_classes')
	if !method_text.starts_with('source string,') || !interface_text.starts_with('name string,') {
		return error('framework helper boundaries changed')
	}
	os.write_file(root + '/source/androidtools/helpers.v', 'module androidtools\n\n' + method_marker + method_text + '\n' + interface_marker + interface_text + '\n')!
	os.write_file(root + '/source/main.v', 'module main\nimport androidtools\nimport os\nfn main() {\n' +
		'root := os.args[1]\npath := root + "/android/accounts/AccountManager.smali"\n' +
		'text := androidtools.framework_account_addition(os.read_file(path)!)!\n' +
		'os.write_file(path, androidtools.framework_account_async_addition(text)!)!\n' +
		'for name, source in androidtools.framework_account_async_classes() { os.mkdir_all(os.dir(root + "/" + name))!; os.write_file(root + "/" + name + ".smali", source)! }\n}\n')!
	command(root, 'clone-smali', ['/bin/cp', '-c', '-R', baseline + '/smali', root + '/smali'])!
	os.cp(baseline + '/api-impl.jar', root + '/api-impl.jar')!
	mut old := map[string]string{}
	inventory(root + '/smali', '', mut old)!
	command(root, 'compile-provider', [compiler, '-cc', 'cc', '-path', root + '/source|@vlib', '-o', root + '/provider', root + '/source'])!
	command(root, 'apply-provider', [root + '/provider', root + '/smali'])!
	mut new := map[string]string{}
	inventory(root + '/smali', '', mut new)!
	class_delta(old, new)!
	command(root, 'assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
	if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('assembly produced no fresh DEX') }
	command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
	for pair in [[baseline + '/api-impl.jar', 'old'], [root + '/api-impl.jar', 'new']] {
		command(root, pair[1] + '-disassemble', [java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', pair[0], '-o', root + '/' + pair[1] + '-dex'])!
		command(root, pair[1] + '-unzip', ['/usr/bin/unzip', '-q', pair[0], '-d', root + '/' + pair[1] + '-jar'])!
	}
	mut old_dex := map[string]string{}
	mut new_dex := map[string]string{}
	inventory(root + '/old-dex', '', mut old_dex)!
	inventory(root + '/new-dex', '', mut new_dex)!
	class_delta(old_dex, new_dex)!
	mut old_jar := map[string]string{}
	mut new_jar := map[string]string{}
	inventory(root + '/old-jar', '', mut old_jar)!
	inventory(root + '/new-jar', '', mut new_jar)!
	if old_jar.len != new_jar.len || old_jar.len != 3 { return error('JAR member count differs') }
	for name, pin in old_jar {
		if name !in new_jar || ((name == 'classes.dex') == (pin == new_jar[name]!)) { return error('unexpected JAR member delta: ' + name) }
	}
	for path, pin in inputs { if digest(path)! != pin { return error('input changed during build: ' + path) } }
	write_json(root + '/build.json', {
		'scope': json2.Any('Framework371 plus unsupported-account asynchronous contract; authentication remains unavailable'),
		'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
		'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
		'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
		'changed_classes': json2.Any(['android/accounts/AccountManager.smali']),
		'added_classes': json2.Any(additions), 'class_count': json2.Any(new.len)
	})!
	println('ACCOUNT-CONTRACT-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 2 { eprintln('usage: account-contract-build FRESH_EXTERNAL_ROOT | --self-test'); exit(2) }
	build(os.abs_path(os.args[1])) or { eprintln(err); exit(1) }
}
