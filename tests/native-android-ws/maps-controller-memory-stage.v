// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic-only bounded-memory controller replacement over the service-query image.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const state_root = '/Users/alex/.local/state/vinix/android'
const base_root = state_root + '/maps-service-query-r1'
const base_seal = '4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b'
const startup_root = state_root + '/maps-startup-r1'
const startup_seal = 'f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332'
const controller_stage_root = state_root + '/maps-controller-r1'
const controller_stage_seal = '3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a'
// Exact complete ARM producer sealed after the polling lifetime correction.
const controller_root = state_root + '/maps-account-guest-build-2026-10-27-r7'
const controller_seal = '680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890'
const controller_pin = '9c213a85235b802fc3b068ff2d195ea207ba82ded7fe6cdee408e0bd55921c0c'
const old_controller_root = state_root + '/maps-account-guest-build-2026-10-27-r6'
const old_controller_seal = '1b8e4555a67eae4c3b1c109f3d94064c96eba65dd3fd3c88d72649b5fdbc9106'
const old_controller_pin = '894e57f0eaf773777b3107100068edf1f9b57b427b565756767c576a0de8c6b6'
const framework_root = state_root + '/combined-account-webview-service-query-framework-2026-10-27-r1'
const framework_seal = '12f21e139e2602fa9517c6df7d2fda866d366d4d5f0cce6d7e07d62bbd044559'
const native_seal = 'a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20'
const launch_seal = '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
const controller_path = 'opt/vinix-maps-account/bin/maps-account-guest'
const alias_path = 'usr/bin/run-android-calculator'
const deployment_path = 'opt/vinix-maps-account/build.json'
const overlay = 'maps-controller-memory-diagnostic.tar'
const retained = {
	'tests/native-android-ws/maps-controller-memory-stage.v': carry($embed_file(@FILE))
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
fn exact_profile(base string, manifest string, executable string) ! {
	if base != base_seal || manifest != controller_seal || executable != controller_pin
		|| !stage.valid_pin(manifest) || !stage.valid_pin(executable)
		|| manifest == old_controller_seal || executable == old_controller_pin {
		return error('exact controller memory diagnostic profile differs')
	}
}
fn exact_delta(before map[string]json2.Any, after map[string]json2.Any, changes map[string]json2.Any) ! {
	if before.len != after.len { return error('receipt key set changed') }
	for name, old in before {
		actual := after[name] or { return error('receipt key removed: ' + name) }
		if replacement := changes[name] {
			if actual != replacement || actual == old { return error('expected receipt change differs: ' + name) }
		} else if actual != old { return error('unrelated receipt change: ' + name) }
	}
	for name in changes.keys() { if name !in before { return error('replacement key absent') } }
}
fn repin_deployment(original map[string]json2.Any, pin string) !map[string]json2.Any {
	if !stage.valid_pin(pin) || pin == old_controller_pin { return error('new controller digest required') }
	if stage.text_field(original, 'kind')! != 'vinix-maps-account-deployment-v1'
		|| stage.text_field(original, 'framework_manifest_sha256')! != framework_seal
		|| stage.text_field(original, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(original, 'launch_manifest_sha256')! != launch_seal {
		return error('retained deployment identity differs')
	}
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	if old['/' + controller_path] or { '' } != old_controller_pin
		|| old['/' + alias_path] or { '' } != old_controller_pin { return error('old controller aliases differ') }
	mut updated := old.clone()
	mut changes := map[string]json2.Any{}
	for name in [controller_path, alias_path] {
		updated['/' + name] = pin
		changes['/' + name] = json2.Any(pin)
	}
	exact_delta(as_json(old)!.as_map(), as_json(updated)!.as_map(), changes)!
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	verify_deployment_delta(original, result, pin)!
	return result
}
fn verify_deployment_delta(original map[string]json2.Any, updated map[string]json2.Any, pin string) ! {
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	actual := updated['inputs_sha256'] or { return error('deployment pins removed') }
	exact_delta(as_json(old)!.as_map(), actual.as_map(), {
		'/' + controller_path: json2.Any(pin), '/' + alias_path: json2.Any(pin)
	})!
	exact_delta(original, updated, {'inputs_sha256': actual})!
}
fn exact_regular_names(names []string) ! {
	mut actual := names.clone()
	mut expected := [controller_path, alias_path, deployment_path]
	actual.sort()
	expected.sort()
	if actual != expected { return error('three-file payload allowlist differs') }
}
fn payload_inventory(root string) ![]stage.Entry {
	mut entries := []stage.Entry{}
	mut roots := os.ls(root)!
	roots.sort()
	if roots != ['opt', 'usr'] { return error('payload root set differs') }
	for prefix in roots { stage.inventory(root + '/' + prefix, '', prefix, mut entries)! }
	exact_regular_names(entries.filter(it.kind == 'regular').map(it.name))!
	for entry in entries {
		if entry.kind == 'regular' {
			if entry.name in [controller_path, alias_path] && entry.sha256 != controller_pin {
				return error('payload controller aliases differ from exact executable')
			}
			continue
		}
		if entry.kind != 'directory' || ![controller_path, alias_path, deployment_path].any(it.starts_with(entry.name + '/')) {
			return error('unexpected payload inode or directory')
		}
	}
	return entries
}
// Existing first-inode mode wins across TARs; audit every later occurrence too.
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
		if target.name !in modes { return error('destination absent from original media: ' + target.name) }
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
fn dependencies(base map[string]json2.Any) !map[string]string {
	all := json2.decode[map[string]string](json2.encode(base['inputs_sha256']!))!
	mut selected := map[string]string{}
	for path, pin in all {
		if path.ends_with('/sha256.json') { selected[path.all_before_last('/sha256.json')] = pin }
	}
	if selected.len != 18 || selected[old_controller_root] or { '' } != old_controller_seal
		|| selected[startup_root] or { '' } != startup_seal
		|| selected[controller_stage_root] or { '' } != controller_stage_seal
		|| selected[framework_root] or { '' } != framework_seal {
		return error('exact inherited complete dependency set differs')
	}
	return selected
}
fn run(destination string) ! {
	exact_profile(base_seal, controller_seal, controller_pin)!
	root := stage.external(destination)!
	stage.disjoint(root, [base_root, controller_root, os.getwd()])!
	println('MAPS-CONTROLLER-MEMORY auditing immutable inputs')
	base_files := stage.load_inventory(base_root, base_seal)!
	base := read_json(base_root + '/stage.json')!
	if stage.text_field(base, 'kind')! != 'vinix-maps-service-query-diagnostic-v1'
		|| stage.text_field(base, 'base_root')! != controller_stage_root
		|| stage.text_field(base, 'base_manifest_sha256')! != controller_stage_seal
		|| stage.text_field(base, 'controller_build_root')! != old_controller_root
		|| stage.text_field(base, 'controller_manifest_sha256')! != old_controller_seal
		|| stage.text_field(base, 'controller_sha256')! != old_controller_pin
		|| stage.text_field(base, 'framework_manifest_sha256')! != framework_seal
		|| stage.text_field(base, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(base, 'retained_launch_manifest_sha256')! != launch_seal {
		return error('exact immutable service-query stage identity differs')
	}
	mut inputs := map[string]string{}
	inputs[base_root + '/sha256.json'] = base_seal
	deps := dependencies(base)!
	stage.disjoint(root, deps.keys())!
	for path, pin in deps {
		stage.load_inventory(path, pin)!
		inputs[path + '/sha256.json'] = pin
	}
	old_controller := stage.load_bundle(old_controller_root, old_controller_seal)!
	stage.verify_static_controller(old_controller, 'vinix-maps-account-guest-build-v1', 'maps-account-guest')!
	if old_controller.files['bin/maps-account-guest']! != old_controller_pin { return error('old executable differs') }
	controller := stage.load_bundle(controller_root, controller_seal)!
	stage.verify_static_controller(controller, 'vinix-maps-account-guest-build-v1', 'maps-account-guest')!
	if controller.files['bin/maps-account-guest']! != controller_pin { return error('new executable differs') }
	inputs[controller_root + '/sha256.json'] = controller_seal
	os.mkdir(root, mode: 0o755)!
	os.mkdir(root + '/commands', mode: 0o755)!
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
	original := os.read_file(base_root + '/limine-after.conf')!
	config := stage.configure(original, overlay)!
	mut before := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	before['maps-service-query-diagnostic.tar'] = stage.text_field(base, 'overlay_sha256')!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar',
		'maps372-diagnostics.tar', 'headless-service.tar', 'maps-account.tar', 'protected-storage-diagnostic.tar',
		'maps-controller-diagnostic.tar', 'maps-service-query-diagnostic.tar']
		|| before.len != config.modules.len { return error('exact original ten-module set differs') }
	if stage.command(root, 'original-limine', [root + '/tools/mtype', '-i', base_root + '/boot.img', '::/boot/limine.conf'])! != original {
		return error('source media configuration differs')
	}
	for name in config.modules {
		if stage.module_hash(root, 'original-' + name, base_root + '/boot.img', name)! != before[name]! { return error('original module differs: ' + name) }
	}
	startup := read_json(startup_root + '/stage.json')!
	r5_root := stage.text_field(startup, 'base_root')!
	mut original_entries := json2.decode[[]stage.Entry](os.read_file(r5_root + '/original-module-inventory.json')!)!
	r5 := read_json(r5_root + '/stage.json')!
	original_entries << json2.decode[[]stage.Entry](json2.encode(r5['overlay_inventory']!))!
	original_entries << json2.decode[[]stage.Entry](json2.encode(startup['overlay_inventory']!))!
	controller_stage := read_json(controller_stage_root + '/stage.json')!
	original_entries << json2.decode[[]stage.Entry](json2.encode(controller_stage['overlay_inventory']!))!
	original_entries << json2.decode[[]stage.Entry](json2.encode(base['overlay_inventory']!))!
	for path in [controller_path, alias_path] { copy_file(controller_root + '/bin/maps-account-guest', root + '/payload/' + path, 0o755)! }
	old_deployment := read_json(base_root + '/payload/' + deployment_path)!
	write_json(root + '/payload/' + deployment_path, as_json(repin_deployment(old_deployment, controller_pin)!)!)!
	entries_before := payload_inventory(root + '/payload')!
	modes := inherited_modes(original_entries, entries_before)!
	for entry in entries_before { os.chmod(root + '/payload/' + entry.name, int(modes[entry.name]!))! }
	entries := payload_inventory(root + '/payload')!
	write_json(root + '/overlay-plan.json', as_json(entries)!)!
	write_json(root + '/original-inode-modes.json', as_json(modes)!)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	println('MAPS-CONTROLLER-MEMORY cloning media and appending three files')
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
	println('MAPS-CONTROLLER-MEMORY rechecking complete inputs')
	for path, pin in deps { stage.load_inventory(path, pin)! }
	stage.recheck(controller)!
	if stage.load_inventory(base_root, base_seal)! != base_files { return error('immutable service-query stage changed') }
	for path, pin in inputs { if stage.hash(path)! != pin { return error('source/tool changed: ' + path) } }
	if payload_inventory(root + '/payload')! != entries { return error('payload changed') }
	write_json(root + '/stage.json', {
		'kind': json2.Any('vinix-maps-controller-memory-diagnostic-v1'), 'format': json2.Any(1),
		'scope': json2.Any('Credential-free controller memory diagnostic only; service-query framework/JNI and all original role receipts retained. No Google login proof.'),
		'source_revision': json2.Any(revision), 'base_root': json2.Any(base_root), 'base_manifest_sha256': json2.Any(base_seal),
		'controller_build_root': json2.Any(controller_root), 'controller_manifest_sha256': json2.Any(controller_seal),
		'controller_sha256': json2.Any(controller_pin), 'retained_controller_manifest_sha256': json2.Any(old_controller_seal),
		'framework_manifest_sha256': json2.Any(framework_seal), 'native_manifest_sha256': json2.Any(native_seal),
		'retained_launch_manifest_sha256': json2.Any(launch_seal),
		'deployment_input_delta': as_json({'/' + controller_path: controller_pin, '/' + alias_path: controller_pin})!,
		'deployment_top_level_delta': as_json(['inputs_sha256'])!, 'inputs_sha256': as_json(inputs)!,
		'original_modules_sha256': as_json(before)!, 'preserved_modules_sha256': as_json(after)!,
		'overlay_inventory': as_json(entries)!, 'overlay_sha256': json2.Any(stage.hash(root + '/' + overlay)!),
		'limine_before_sha256': json2.Any(stage.hash(root + '/limine-before.conf')!), 'limine_after_sha256': json2.Any(stage.hash(root + '/limine-after.conf')!),
		'staged_boot_sha256': json2.Any(stage.hash(root + '/boot.img')!), 'staged_efivars_sha256': json2.Any(stage.hash(root + '/efivars.fd')!),
		'guest_terminal_command': json2.Any('/opt/vinix-maps-account/bin/maps-account-guest --broker'),
	})!
	mut files := map[string]string{}
	collect(root, '', mut files)!
	write_json(root + '/sha256.json', as_json(files)!)!
	println('MAPS-CONTROLLER-MEMORY-STAGE PASS ' + root + ' seal=' + stage.hash(root + '/sha256.json')!)
}
fn self_test() ! {
	exact_profile(base_seal, controller_seal, controller_pin)!
	for values in [[old_controller_seal, controller_pin], [controller_seal, old_controller_pin], [native_seal, controller_pin]] {
		if _ := exact_profile(base_seal, values[0], values[1]) { return error('obsolete or mismatched controller profile accepted') }
	}
	if _ := exact_profile(native_seal, controller_seal, controller_pin) { return error('wrong base accepted') }
	old := {'a': json2.Any('old'), 'b': json2.Any('same')}
	exact_delta(old, {'a': json2.Any('new'), 'b': json2.Any('same')}, {'a': json2.Any('new')})!
	for bad in [{'a': json2.Any('new')}, {'a': json2.Any('new'), 'b': json2.Any('bad')},
		{'a': json2.Any('new'), 'b': json2.Any('same'), 'c': json2.Any('extra')}] {
		if _ := exact_delta(old, bad, {'a': json2.Any('new')}) { return error('unsafe receipt delta accepted') }
	}
	if _ := exact_delta(old, old, {'a': json2.Any('old')}) { return error('missing receipt change accepted') }
	mut deployment := {
		'kind': json2.Any('vinix-maps-account-deployment-v1'), 'framework_manifest_sha256': json2.Any(framework_seal),
		'native_manifest_sha256': json2.Any(native_seal), 'launch_manifest_sha256': json2.Any(launch_seal),
		'inputs_sha256': as_json({'/' + controller_path: old_controller_pin, '/' + alias_path: old_controller_pin, '/unchanged': native_seal})!,
	}
	updated := repin_deployment(deployment, controller_pin)!
	for name in [controller_path, alias_path, 'unchanged'] {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		mut pins := json2.decode[map[string]string](json2.encode(bad['inputs_sha256']!))!
		pins['/' + name] = old_controller_pin
		bad['inputs_sha256'] = as_json(pins)!
		if _ := verify_deployment_delta(deployment, bad, controller_pin) { return error('unrelated or missing deployment input delta accepted') }
	}
	mut extra := json2.decode[map[string]json2.Any](json2.encode(updated))!
	extra['extra'] = json2.Any('unexpected')
	if _ := verify_deployment_delta(deployment, extra, controller_pin) { return error('extra deployment key accepted') }
	mut wrong_native := json2.decode[map[string]json2.Any](json2.encode(updated))!
	wrong_native['native_manifest_sha256'] = json2.Any(controller_pin)
	if _ := verify_deployment_delta(deployment, wrong_native, controller_pin) { return error('extra deployment identity delta accepted') }
	if _ := repin_deployment(deployment, old_controller_pin) { return error('old controller accepted') }
	if _ := repin_deployment(deployment, '') { return error('invalid new pin accepted') }
	for path in [controller_path, alias_path] {
		mut pins := json2.decode[map[string]string](json2.encode(deployment['inputs_sha256']!))!
		pins['/' + path] = controller_pin
		mut bad := deployment.clone()
		bad['inputs_sha256'] = as_json(pins)!
		if _ := repin_deployment(bad, controller_pin) { return error('mismatched prior alias accepted') }
	}
	deployment['native_manifest_sha256'] = json2.Any(controller_pin)
	if _ := repin_deployment(deployment, controller_pin) { return error('unrelated native identity accepted') }
	allowed := [controller_path, alias_path, deployment_path]
	exact_regular_names(allowed)!
	for bad in [allowed[..2], []string{}, [controller_path, alias_path, deployment_path, 'opt/escape'], [controller_path, controller_path, deployment_path]] {
		if _ := exact_regular_names(bad) { return error('wrong payload set accepted') }
	}
	plan := [stage.Entry{name: controller_path, kind: 'regular', mode: 0o755}]
	good := [stage.Entry{name: 'opt', kind: 'directory', mode: 0o755}, stage.Entry{name: controller_path, kind: 'regular', mode: 0o755}]
	if inherited_modes(good, plan)![controller_path]! != 0o755 { return error('executable mode lost') }
	for bad in [stage.Entry{name: 'opt', kind: 'symlink', mode: 0o755}, stage.Entry{name: controller_path, kind: 'regular', mode: 0o777},
		stage.Entry{name: controller_path, kind: 'regular', mode: 0o4755}] {
		mut original := good.clone()
		original << bad
		if _ := inherited_modes(original, plan) { return error('unsafe old inode accepted') }
	}
	if _ := inherited_modes([stage.Entry{name: controller_path, kind: 'regular', mode: 0o644}], plan) { return error('nonexecutable original accepted') }
	println('MAPS-CONTROLLER-MEMORY-STAGE SELFTEST PASS exact profile aliases receipt delta three-file payload inherited modes protected ancestors')
}
fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != '--prepare' { eprintln('usage: maps-controller-memory-stage --prepare FRESH_EXTERNAL_OUTPUT | --self-test'); exit(2) }
	run(os.args[2]) or { eprintln(err); exit(1) }
}
