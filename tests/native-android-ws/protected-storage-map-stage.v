// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic-only additive protected-storage delta over the immutable r5 deployment.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const state_root = '/Users/alex/.local/state/vinix/android'
const base_root = state_root + '/maps-account-r5'
const base_seal = '9a8bf61bd526d7ec020d45920367d45e90a2ef4692c6d8fa8b87de801a14c5ca'
const framework_root = state_root + '/combined-account-webview-protected-storage-framework-2026-10-27-r2'
const framework_seal = '67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938'
const native_root = state_root + '/current-native-build-2026-10-27-protected-r1'
const native_seal = '894c9657077cdd913a2c66c1cf78358daaccc4da8b0739ed77bb2a3dbea1b4ee'
const jar_pin = 'a8ba34eb79be2473f89042c8ee940ab1994dbc902c3d45143877f8891d3b428b'
const dex_pin = '2739569a157276b76da82ed51ce41ef805457f95c01fe23ec524b5666bd486c6'
const native_pin = '05ed64c8c0778cc09ea2db7d820c873c7e53c493f99c886c4992f3243f8f913a'
const runtime = 'opt/vinix-android-aarch64'
const jar_path = runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const dex_path = runtime + '/usr/lib/java/dex/android_translation_layer/classes.dex'
const native_path = runtime + '/usr/lib/art/libvinix-android-native.so'
const headless = 'opt/vinix-headless-service'
const deployment = 'opt/vinix-maps-account/build.json'
const overlay = 'protected-storage-diagnostic.tar'
const retained = {
	'tests/native-android-ws/protected-storage-map-stage.v': carry($embed_file(@FILE))
	'tests/native-android-ws/mapsaccountstage/bundle.v': carry($embed_file('mapsaccountstage/bundle.v'))
	'tests/native-android-ws/mapsaccountstage/hostsha.v': carry($embed_file('mapsaccountstage/hostsha.v'))
	'tests/native-android-ws/mapsaccountstage/elf.v': carry($embed_file('mapsaccountstage/elf.v'))
	'tests/native-android-ws/mapsaccountstage/media.v': carry($embed_file('mapsaccountstage/media.v'))
	'tests/native-android-ws/mapsaccountstage/headless.v': carry($embed_file('mapsaccountstage/headless.v'))
	'build-support/android/modulestream/stream.v': carry($embed_file('../../build-support/android/modulestream/stream.v'))
	'build-support/android/modulestream/spawn_abi.h': carry($embed_file('../../build-support/android/modulestream/spawn_abi.h'))
	'build-support/tarcore/writer.v': carry($embed_file('../../build-support/tarcore/writer.v'))
	'build-support/tarcore/gzip.v': carry($embed_file('../../build-support/tarcore/gzip.v'))
	'build-support/tarstream/reader.v': carry($embed_file('../../build-support/tarstream/reader.v'))
	'build-support/tarstream/filter_abi.h': carry($embed_file('../../build-support/tarstream/filter_abi.h'))
	'build-support/tarstream/sparse.v': carry($embed_file('../../build-support/tarstream/sparse.v'))
}

fn carry(data embed_file.EmbedFileData) string {
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' { panic('requires -prod embedded source closure') }
	return data.to_string()
}
fn as_json[T](value T) !json2.Any { return json2.decode[json2.Any](json2.encode(value)) }
fn write_json(path string, value json2.Any) ! {
	os.mkdir_all(os.dir(path), mode: 0o755)!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn read_json(path string) !map[string]json2.Any {
	if os.lstat(path)!.size > 8 * 1024 * 1024 { return error('receipt exceeds bound') }
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}
fn copy_file(source string, destination string, mode u32) ! {
	if os.real_path(source) != source || os.lstat(source)!.get_filetype() != .regular
		|| os.exists(destination) || os.is_link(destination) { return error('canonical regular source and fresh destination required') }
	os.mkdir_all(os.dir(destination), mode: 0o755)!
	os.cp(source, destination)!
	os.chmod(destination, int(mode))!
}
fn changed_paths() []string {
	return [jar_path, dex_path, native_path, headless + '/guest-inputs.json',
		headless + '/framework-build.json', headless + '/framework-sha256.json',
		headless + '/native-build.json', headless + '/native-sha256.json']
}
fn exact_regular_names(names []string) ! {
	mut actual := names.clone()
	mut expected := changed_paths()
	expected << deployment
	actual.sort()
	expected.sort()
	if actual != expected { return error('nine-file payload allowlist differs') }
}
fn exact_service_abi(launch string, native string) ! {
	if !stage.valid_pin(launch) || launch != native { return error('retained launcher service ABI differs') }
}
fn pins(value map[string]json2.Any) !map[string]string {
	return json2.decode[map[string]string](json2.encode(value['inputs_sha256']!))!
}
fn class_count_2104(value json2.Any) bool {
	return match value {
		int { value == 2104 }
		i64 { value == 2104 }
		u64 { value == 2104 }
		f64 { value == 2104 }
		else { false }
	}
}
// Require exact decoded key sets and values outside the deliberately changed keys.
fn exact_delta(before map[string]json2.Any, after map[string]json2.Any, replacements map[string]json2.Any) ! {
	if before.len != after.len { return error('receipt key set changed') }
	for name, old in before {
		actual := after[name] or { return error('receipt key removed: ' + name) }
		if replacement := replacements[name] {
			if actual != replacement || old == replacement { return error('expected receipt change differs: ' + name) }
		} else if actual != old { return error('unrelated receipt change: ' + name) }
	}
	for name in replacements.keys() { if name !in before { return error('replacement key absent') } }
}
fn repin_headless(original map[string]json2.Any, replacements map[string]string) !map[string]json2.Any {
	if original.len != 1 || replacements.len != 2 || '/' + jar_path !in replacements
		|| '/' + native_path !in replacements { return error('headless replacement set differs') }
	old := pins(original)!
	expected := {
		'/' + runtime + '/usr/bin/run-android': '1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112'
		'/' + runtime + '/usr/bin/vinix-android-native': 'b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d'
		'/' + native_path: '70b8db58c59d769f4f4ae4e6775fb7c3a2c4c9af42cfd3f14076092ec14818c0'
		'/' + jar_path: '71d05c6e6288978de66a5c71279e8cb27d92c9166950813ddbf0c33ff86e1d0d'
		'/' + headless + '/bin/headless-service-controller': '70f23b12fb5a770587bfcebcf33ed1320fe050399f08bd256362a037f24eb0b6'
		'/' + headless + '/bin/headless-service-guest': 'd518cfc5145924479b5ad630aac2a3d3ef7dcea66f53515c03df03735e88ce05'
		'/' + headless + '/fixture.apk': '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
	}
	if old != expected { return error('headless r5 seven-path contract differs') }
	mut updated := old.clone()
	mut changes := map[string]json2.Any{}
	for name, pin in replacements {
		if !stage.valid_pin(pin) { return error('invalid replacement pin') }
		updated[name] = pin
		changes[name] = json2.Any(pin)
	}
	exact_delta(as_json(old)!.as_map(), as_json(updated)!.as_map(), changes)!
	return {'inputs_sha256': as_json(updated)!}
}
fn repin_deployment(original map[string]json2.Any, replacements map[string]string) !map[string]json2.Any {
	mut expected := changed_paths().map('/' + it)
	mut actual := replacements.keys()
	expected.sort()
	actual.sort()
	if actual != expected { return error('deployment replacement allowlist differs') }
	old := pins(original)!
	mut updated := old.clone()
	mut changes := map[string]json2.Any{}
	for name, pin in replacements {
		if !stage.valid_pin(pin) { return error('invalid deployment pin') }
		updated[name] = pin
		changes[name] = json2.Any(pin)
	}
	exact_delta(as_json(old)!.as_map(), as_json(updated)!.as_map(), changes)!
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	result['framework_manifest_sha256'] = json2.Any(framework_seal)
	result['native_manifest_sha256'] = json2.Any(native_seal)
	exact_delta(original, result, {
		'inputs_sha256': as_json(updated)!
		'framework_manifest_sha256': json2.Any(framework_seal)
		'native_manifest_sha256': json2.Any(native_seal)
	})!
	return result
}
fn payload_inventory(root string) ![]stage.Entry {
	mut entries := []stage.Entry{}
	stage.inventory(root + '/opt', '', 'opt', mut entries)!
	names := entries.filter(it.kind == 'regular').map(it.name)
	mut expected := changed_paths()
	expected << deployment
	exact_regular_names(names)!
	if entries.any(it.kind !in ['regular', 'directory']) { return error('unsafe payload inode') }
	for entry in entries.filter(it.kind == 'directory') {
		if !expected.any(it.starts_with(entry.name + '/')) { return error('unexpected overlay directory') }
	}
	return entries
}
// Audit every occurrence: first inode mode persists when later TARs overwrite contents.
fn inherited_modes(original []stage.Entry, planned []stage.Entry) !map[string]u32 {
	mut modes := map[string]u32{}
	for target in planned {
		if !stage.relative(target.name) || target.kind !in ['regular', 'directory'] || target.mode & 0o7022 != 0 {
			return error('unsafe diagnostic destination')
		}
		for old in original {
			if old.name == target.name {
				if old.kind != target.kind || old.mode & 0o7022 != 0 { return error('unsafe existing destination: ' + old.name) }
				if target.name !in modes {
					if old.mode & (target.mode & ~u32(0o222)) != target.mode & ~u32(0o222) { return error('insufficient original mode') }
					modes[target.name] = old.mode
				}
			} else if target.name.starts_with(old.name + '/') && (old.kind != 'directory' || old.mode & 0o7022 != 0) {
				return error('unsafe existing ancestor: ' + old.name)
			}
		}
		if target.name !in modes { return error('diagnostic destination absent from original media: ' + target.name) }
	}
	return modes
}
fn collect(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		path := if relative == '' { name } else { relative + '/' + name }
		match os.lstat(root + '/' + path)!.get_filetype() {
			.directory { collect(root, path, mut files)! }
			.regular { if path != 'sha256.json' { files[path] = stage.hash(root + '/' + path)! } }
			else { return error('unexpected sealed output inode') }
		}
	}
}
fn original_bundle(request map[string]json2.Any, name string) !stage.Bundle {
	ref := request[name]!.as_map()
	return stage.load_bundle(stage.text_field(ref, 'root')!, stage.text_field(ref, 'seal')!)!
}
fn run(destination string) ! {
	root := stage.external(destination)!
	stage.disjoint(root, [base_root, framework_root, native_root, os.getwd()])!
	println('PROTECTED-STORAGE-MAPS auditing immutable inputs')
	base_files := stage.load_inventory(base_root, base_seal)!
	request := read_json(base_root + '/request.json')!
	old_framework := original_bundle(request, 'framework')!
	old_native := original_bundle(request, 'native')!
	launch := original_bundle(request, 'launch')!
	framework := stage.load_bundle(framework_root, framework_seal)!
	native := stage.load_bundle(native_root, native_seal)!
	stage.verify_framework(old_framework, old_framework.seal, stage.text_field(request, 'framework_jar')!, stage.text_field(request, 'framework_dex')!)!
	stage.verify_native(old_native, old_framework)!
	stage.verify_launch(launch, old_framework, old_native)!
	// New framework is a separate exact diagnostic profile; the full stager stays strict.
	if framework.files['api-impl.jar']! != jar_pin || framework.files['classes.dex']! != dex_pin
		|| stage.text_field(framework.receipt, 'profile')! != 'protected-storage-2104'
		|| !class_count_2104(framework.receipt['class_count']!)
		|| stage.text_field(framework.receipt, 'baseline_manifest_sha256')! != old_framework.seal
		|| stage.text_field(framework.receipt, 'api_impl_sha256')! != jar_pin
		|| stage.text_field(framework.receipt, 'classes_dex_sha256')! != dex_pin { return error('exact protected framework profile differs') }
	stage.verify_native(native, framework)!
	if native.files['native/libvinix-android-native.so']! != native_pin { return error('protected native pin differs') }
	exact_service_abi(launch.files['abi/headless.v']!, native.files['native/atlframework/headless.v']!)!
	mut bundles := [old_framework, old_native, launch, framework, native]
	account := original_bundle(request, 'account')!
	dependencies := stage.verify_account(account)!
	browser_client := original_bundle(request, 'browser_client')!
	stage.verify_browser_client(browser_client, dependencies)!
	guest := original_bundle(request, 'guest')!
	stage.verify_static_controller(guest, 'vinix-maps-account-guest-build-v1', 'maps-account-guest')!
	token_controller := original_bundle(request, 'token_controller')!
	stage.verify_static_controller(token_controller, 'vinix-account-token-cache-controller-v1', 'account-token-cache-controller')!
	browser := original_bundle(request, 'browser')!
	token := original_bundle(request, 'token')!
	ui_root := stage.text_field(request, 'ui')!
	ui_seal := 'bcb7656ee29c66d2d54fad120aff2d09f078e3a7684ce59c3ac1dd88aa16d394'
	ui_files := stage.load_inventory(ui_root, ui_seal)!
	ui := read_json(ui_root + '/stage.json')!
	ui_controller := stage.load_bundle(stage.text_field(ui, 'controller_build')!,
		'503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a')!
	stage.verify_ui_controller(ui_controller, old_framework, old_native)!
	bundles << [account, browser_client, guest, token_controller, browser, token, ui_controller]
	os.mkdir(root, mode: 0o755)!
	os.mkdir(root + '/commands', mode: 0o755)!
	mut inputs := map[string]string{}
	inputs[base_root + '/sha256.json'] = base_seal
	inputs[ui_root + '/sha256.json'] = ui_seal
	for bundle in bundles { inputs[bundle.root + '/sha256.json'] = bundle.seal }
	for path, source in retained {
		copy_path := root + '/source/' + path
		os.mkdir_all(os.dir(copy_path), mode: 0o755)!
		os.write_file(copy_path, source)!
		if os.read_file(os.getwd() + '/' + path)! != source { return error('compiled source differs from checkout: ' + path) }
		inputs[os.getwd() + '/' + path] = sha256.sum(source.bytes()).hex()
	}
	inputs[os.real_path(os.executable())] = stage.hash(os.real_path(os.executable()))!
	inputs['/usr/bin/git'] = stage.hash('/usr/bin/git')!
	revision := stage.command(root, 'source-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!.trim_space()
	if revision.len != 40 { return error('full source revision required') }
	os.mkdir(root + '/tools', mode: 0o755)!
	for name in ['mcopy', 'mtype', 'mdir', 'shasum'] {
		source := os.real_path(os.find_abs_path_of_executable(name)!)
		inputs[source] = stage.hash(source)!
		copy_file(source, root + '/tools/' + name, 0o755)!
		inputs[root + '/tools/' + name] = inputs[source]!
	}
	os.setenv('PATH', root + '/tools:' + os.getenv('PATH'), true)
	base := read_json(base_root + '/stage.json')!
	original := os.read_file(base_root + '/limine-after.conf')!
	config := stage.configure(original, overlay)!
	mut before := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	before['maps-account.tar'] = stage.text_field(base, 'overlay_sha256')!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar',
		'maps372-diagnostics.tar', 'headless-service.tar', 'maps-account.tar'] || before.len != config.modules.len {
		return error('exact original seven-module set differs')
	}
	if stage.command(root, 'original-limine', [root + '/tools/mtype', '-i', base_root + '/boot.img', '::/boot/limine.conf'])! != original {
		return error('source media configuration differs')
	}
	for name in config.modules {
		if stage.module_hash(root, 'original-' + name, base_root + '/boot.img', name)! != before[name]! { return error('original module differs: ' + name) }
	}
	mut original_entries := json2.decode[[]stage.Entry](os.read_file(base_root + '/original-module-inventory.json')!)!
	original_entries << json2.decode[[]stage.Entry](json2.encode(base['overlay_inventory']!))!
	for pair in [[framework_root + '/api-impl.jar', jar_path], [framework_root + '/classes.dex', dex_path],
		[native_root + '/native/libvinix-android-native.so', native_path],
		[framework_root + '/build.json', headless + '/framework-build.json'],
		[framework_root + '/sha256.json', headless + '/framework-sha256.json'],
		[native_root + '/build.json', headless + '/native-build.json'],
		[native_root + '/sha256.json', headless + '/native-sha256.json']] {
		copy_file(pair[0], root + '/payload/' + pair[1], 0o644)!
	}
	old_headless := read_json(base_root + '/payload/' + headless + '/guest-inputs.json')!
	write_json(root + '/payload/' + headless + '/guest-inputs.json', as_json(repin_headless(old_headless, {
		'/' + jar_path: jar_pin, '/' + native_path: native_pin
	})!)!)!
	mut replacements := map[string]string{}
	for path in changed_paths() { replacements['/' + path] = stage.hash(root + '/payload/' + path)! }
	old_deployment := read_json(base_root + '/payload/' + deployment)!
	write_json(root + '/payload/' + deployment, as_json(repin_deployment(old_deployment, replacements)!)!)!
	entries_before := payload_inventory(root + '/payload')!
	modes := inherited_modes(original_entries, entries_before)!
	for entry in entries_before { os.chmod(root + '/payload/' + entry.name, int(modes[entry.name]!))! }
	entries := payload_inventory(root + '/payload')!
	write_json(root + '/overlay-plan.json', as_json(entries)!)!
	write_json(root + '/original-inode-modes.json', as_json(modes)!)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	println('PROTECTED-STORAGE-MAPS cloning media and appending nine files')
	for name in ['boot.img', 'efivars.fd'] {
		if C.clonefile((base_root + '/' + name).str, (root + '/' + name).str, 0) != 0
			|| stage.hash(root + '/' + name)! != base_files[name]! { return error('fresh APFS media clone differs') }
	}
	stage.command_expected(root, 'overlay-absent', [root + '/tools/mdir', '-i', root + '/boot.img', '::/boot/' + overlay], 1)!
	mut sources := map[string]string{}
	for entry in entries.filter(it.kind == 'regular') { sources[entry.name] = root + '/payload/' + entry.name }
	stage.write_overlay(root + '/' + overlay, sources, entries)!
	stage.verify_overlay(root + '/' + overlay, entries)!
	stage.command(root, 'install-overlay', [root + '/tools/mcopy', '-i', root + '/boot.img', root + '/' + overlay, '::/boot/' + overlay])!
	stage.command(root, 'install-limine', [root + '/tools/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	if stage.command(root, 'readback-limine', [root + '/tools/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated
		|| stage.module_hash(root, 'readback-overlay', root + '/boot.img', overlay)! != stage.hash(root + '/' + overlay)! {
		return error('diagnostic media readback differs')
	}
	mut after := map[string]string{}
	for name in config.modules {
		after[name] = stage.module_hash(root, 'preserved-' + name, root + '/boot.img', name)!
		if after[name] != before[name] { return error('existing module changed') }
	}
	println('PROTECTED-STORAGE-MAPS rechecking complete input bundles')
	for bundle in bundles { stage.recheck(bundle)! }
	if stage.load_inventory(ui_root, ui_seal)! != ui_files { return error('original UI bundle changed') }
	if stage.load_inventory(base_root, base_seal)! != base_files { return error('immutable r5 changed') }
	for path, pin in inputs { if stage.hash(path)! != pin { return error('source/tool changed: ' + path) } }
	if payload_inventory(root + '/payload')! != entries { return error('payload changed') }
	write_json(root + '/stage.json', {
		'kind': json2.Any('vinix-protected-storage-maps-diagnostic-v1'), 'format': json2.Any(1),
		'scope': json2.Any('Credential-free startup diagnostic only; unchanged roles retain original receipts and launcher seven-argument ABI. No Google login proof.'),
		'source_revision': json2.Any(revision),
		'base_root': json2.Any(base_root), 'base_manifest_sha256': json2.Any(base_seal),
		'framework_manifest_sha256': json2.Any(framework_seal), 'native_manifest_sha256': json2.Any(native_seal),
		'retained_launch_manifest_sha256': json2.Any(launch.seal),
		'deployment_input_delta': as_json(replacements)!,
		'deployment_top_level_delta': as_json(['inputs_sha256', 'framework_manifest_sha256', 'native_manifest_sha256'])!,
		'inputs_sha256': as_json(inputs)!, 'original_modules_sha256': as_json(before)!, 'preserved_modules_sha256': as_json(after)!,
		'overlay_inventory': as_json(entries)!, 'overlay_sha256': json2.Any(stage.hash(root + '/' + overlay)!),
		'limine_before_sha256': json2.Any(stage.hash(root + '/limine-before.conf')!), 'limine_after_sha256': json2.Any(stage.hash(root + '/limine-after.conf')!),
		'staged_boot_sha256': json2.Any(stage.hash(root + '/boot.img')!), 'staged_efivars_sha256': json2.Any(stage.hash(root + '/efivars.fd')!),
		'guest_terminal_command': json2.Any('/opt/vinix-maps-account/bin/maps-account-guest --broker'),
	})!
	mut files := map[string]string{}
	collect(root, '', mut files)!
	write_json(root + '/sha256.json', as_json(files)!)!
	println('PROTECTED-STORAGE-MAPS-STAGE PASS ' + root + ' seal=' + stage.hash(root + '/sha256.json')!)
}

fn self_test() ! {
	old := {'a': json2.Any('old'), 'b': json2.Any('same')}
	exact_delta(old, {'a': json2.Any('new'), 'b': json2.Any('same')}, {'a': json2.Any('new')})!
	for bad in [{'a': json2.Any('new')}, {'a': json2.Any('new'), 'b': json2.Any('bad')},
		{'a': json2.Any('new'), 'b': json2.Any('same'), 'c': json2.Any('extra')}] {
		if _ := exact_delta(old, bad, {'a': json2.Any('new')}) { return error('unsafe receipt delta accepted') }
	}
	mut allowed := changed_paths()
	allowed << deployment
	exact_regular_names(allowed)!
	for bad in [allowed[..allowed.len - 1], [deployment], []string{}] {
		if _ := exact_regular_names(bad) { return error('missing payload accepted') }
	}
	allowed << 'opt/escape'
	if _ := exact_regular_names(allowed) { return error('additional payload accepted') }
	exact_service_abi(jar_pin, jar_pin)!
	if _ := exact_service_abi(jar_pin, dex_pin) { return error('ABI mismatch accepted') }
	if _ := exact_service_abi('', '') { return error('empty ABI accepted') }
	plan := [stage.Entry{name: 'opt/a', kind: 'regular', mode: 0o644}]
	good := [stage.Entry{name: 'opt', kind: 'directory', mode: 0o755}, stage.Entry{name: 'opt/a', kind: 'regular', mode: 0o755}]
	if inherited_modes(good, plan)!['opt/a']! != 0o755 { return error('first mode not retained') }
	for bad in [stage.Entry{name: 'opt', kind: 'symlink', mode: 0o755}, stage.Entry{name: 'opt/a', kind: 'regular', mode: 0o777},
		stage.Entry{name: 'opt/a', kind: 'regular', mode: 0o4755}] {
		mut entries := good.clone()
		entries << bad
		if _ := inherited_modes(entries, plan) { return error('unsafe existing header accepted') }
	}
	println('PROTECTED-STORAGE-MAPS-STAGE SELFTEST PASS exact receipt deltas nine-file payload service ABI inherited modes protected ancestors')
}
fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != '--prepare' { eprintln('usage: protected-storage-map-stage --prepare FRESH_EXTERNAL_OUTPUT | --self-test'); exit(2) }
	run(os.args[2]) or { eprintln(err); exit(1) }
}
