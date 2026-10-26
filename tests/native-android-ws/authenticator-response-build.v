// SPDX-License-Identifier: GPL-2.0-or-later
// Append only the authenticator response IPC contract to the verified account API.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const baseline = state + 'account-contract-build-2026-10-26'
const baseline_manifest = '3c54524bff390fca35570edd81961fc9103c85e5fccf9fac8ae6c8056e760b81'
const jar_pin = 'e7ce08fb1ca26e652e0d4c8e66adf31e2ffd4a2abf778eaa603a60ff3e036971'
const compiler = '/Users/alex/code/v/v'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const tools = repo + '/build/android-framework/tools'
const source_file = repo + '/tests/native-android-ws/authenticator-response-build.v'
const provider = repo + '/tests/native-android-tools/androidtools/framework_authenticator_response.v'
const additions = ['android/accounts/IAccountAuthenticatorResponse.smali',
	'android/accounts/IAccountAuthenticatorResponse$Stub.smali',
	'android/accounts/IAccountAuthenticatorResponse$Stub$Proxy.smali',
	'android/accounts/AccountAuthenticatorResponse.smali',
	'android/accounts/AccountAuthenticatorResponse$Creator.smali']

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(root string, label string, argv []string) !string {
	executable := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
	pin := digest(executable)!
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
		'executable': json2.Any(executable), 'executable_sha256': json2.Any(pin)
	})!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
	if digest(executable)! != pin { return error('executable changed during command: ' + executable) }
	return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = digest(root + '/' + key)! }
			else { return error('nonregular framework input: ' + key) }
		}
	}
}

fn class_delta(old map[string]string, new map[string]string) ! {
	if old.len != 2084 || new.len != old.len + additions.len {
		return error('unexpected framework class count')
	}
	for name in additions {
		if name in old || name !in new { return error('unexpected added class: ' + name) }
	}
	for name, pin in old {
		if name !in new || new[name]! != pin { return error('existing class changed: ' + name) }
	}
}

fn jar_delta(old map[string]string, new map[string]string) ! {
	if old.len != 3 || new.len != old.len { return error('unexpected JAR member count') }
	if 'classes.dex' !in old { return error('baseline JAR has no classes.dex') }
	for name, pin in old {
		if name !in new || ((name == 'classes.dex') == (pin == new[name]!)) {
			return error('unexpected JAR member delta: ' + name)
		}
	}
}

fn self_test() ! {
	mut old := map[string]string{}
	for i in 0 .. 2084 { old['other/' + i.str() + '.smali'] = 'old' }
	mut good := old.clone()
	for name in additions { good[name] = 'new' }
	class_delta(old, good)!
	for case in 0 .. 5 {
		mut bad := good.clone()
		match case {
			0 { bad['other/0.smali'] = 'changed' }
			1 { bad.delete('other/0.smali') }
			2 { bad['surprise.smali'] = 'new' }
			3 { bad.delete(additions[0]) }
			else { bad.delete(additions[0]); bad['surprise.smali'] = 'new' }
		}
		class_delta(old, bad) or { continue }
		return error('invalid class delta accepted: ' + case.str())
	}
	mut wrong_base := old.clone()
	wrong_base.delete('other/0.smali')
	wrong_base[additions[0]] = 'old'
	class_delta(wrong_base, good) or {
		jar_old := {'classes.dex': 'old', 'manifest': 'same', 'resources': 'same'}
		jar_good := {'classes.dex': 'new', 'manifest': 'same', 'resources': 'same'}
		jar_delta(jar_old, jar_good)!
		for case in 0 .. 4 {
			mut bad := jar_good.clone()
			match case {
				0 { bad['classes.dex'] = 'old' }
				1 { bad['manifest'] = 'changed' }
				2 { bad.delete('manifest') }
				else { bad['extra'] = 'new' }
			}
			jar_delta(jar_old, bad) or { continue }
			return error('invalid JAR delta accepted: ' + case.str())
		}
		println('AUTHENTICATOR-RESPONSE-BUILD-SELF-TEST-PASS six invalid class deltas and four invalid JAR deltas rejected')
		return
	}
	return error('preexisting response class accepted')
}

fn build(root string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh external directory required') }
	if !root.starts_with(state + 'account-contract-') || os.real_path(os.dir(root)) != os.dir(root)
		|| root.contains_any(' \n\t') { return error('canonical external account-contract directory required') }
	os.mkdir_all(root + '/commands')!
	os.mkdir_all(root + '/source/androidtools')!
	mut inputs := map[string]string{}
	for path in [provider, source_file, compiler, os.real_path(java), os.executable(),
		baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json'] {
		inputs[path] = digest(path)!
	}
	for name in os.ls(tools)!.filter(it.ends_with('.jar')) { inputs[tools + '/' + name] = digest(tools + '/' + name)! }
	if inputs[baseline + '/api-impl.jar']! != jar_pin || inputs[baseline + '/sha256.json']! != baseline_manifest {
		return error('sealed account-contract baseline differs')
	}
	command(root, 'check-baseline', [repo + '/build/android-maps/account-contract-retain', 'check', baseline, baseline_manifest])!
	os.cp(source_file, root + '/builder-source.v')!
	os.cp(os.executable(), root + '/builder')!
	os.cp(provider, root + '/source/androidtools/framework_authenticator_response.v')!
	os.write_file(root + '/source/main.v', 'module main\nimport androidtools\nimport os\nfn main() {\n' +
		'root := os.args[1]\nfor name, source in androidtools.framework_authenticator_response_classes() {\n' +
		'path := root + "/" + name + ".smali"\nif os.exists(path) { panic("response class already exists: " + name) }\n' +
		'os.mkdir_all(os.dir(path))!\nos.write_file(path, source)!\n}\n}\n')!
	command(root, 'java-version', [java, '--version'])!
	command(root, 'v-version', [compiler, 'version'])!
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
	jar_delta(old_jar, new_jar)!
	for path, pin in inputs { if digest(path)! != pin { return error('input changed during build: ' + path) } }
	write_json(root + '/build.json', {
		'scope': json2.Any('Verified failed-account framework plus authenticator response IPC only; Google authentication remains unavailable'),
		'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
		'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'baseline_manifest_sha256': json2.Any(baseline_manifest),
		'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
		'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
		'changed_classes': json2.Any([]string{}),
		'added_classes': json2.Any(additions), 'class_count': json2.Any(new.len)
	})!
	println('AUTHENTICATOR-RESPONSE-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 2 { eprintln('usage: authenticator-response-build FRESH_EXTERNAL_ROOT | --self-test'); exit(2) }
	build(os.abs_path(os.args[1])) or { eprintln(err); exit(1) }
}
