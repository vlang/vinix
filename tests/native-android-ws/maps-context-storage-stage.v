// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic-only credential storage Context replacement over sealed direct-boot metadata.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const state_root = '/Users/alex/.local/state/vinix/android'
const base_root = state_root + '/maps-direct-boot-r1'
const base_seal = 'fa9e552f7faf4aabfcf17821efc442918bab5576ea230d25eb9dcd6788d62285'
const memory_root = state_root + '/maps-controller-memory-r1'
const memory_seal = '944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21'
const startup_root = state_root + '/maps-startup-r1'
const startup_seal = 'f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332'
const controller_stage_root = state_root + '/maps-controller-r1'
const controller_stage_seal = '3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a'
const service_query_root = state_root + '/maps-service-query-r1'
const service_query_seal = '4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b'
// Exact complete controller producer sealed after the polling lifetime correction.
const controller_root = state_root + '/maps-account-guest-build-2026-10-27-r7'
const controller_seal = '680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890'
const controller_pin = '9c213a85235b802fc3b068ff2d195ea207ba82ded7fe6cdee408e0bd55921c0c'
const old_framework_root = state_root + '/combined-account-webview-direct-boot-framework-2026-10-27-r1'
const old_framework_seal = 'a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552'
const framework_root = state_root + '/combined-account-webview-credential-storage-framework-2026-10-27-r1'
const framework_seal = 'cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691'
const jar_pin = '9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352'
const dex_pin = 'b96a441b6eca36e0a6fa7a6da01d9e4508136e64ec0f0f3850cf15e2d90ff132'
const old_jar_pin = 'bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d'
const old_dex_pin = '3742f3915d4989ced425914e1fe4f6f662bd32566183534a849f8ad8ccd07213'
const native_seal = 'a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20'
const launch_seal = '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
const controller_path = 'opt/vinix-maps-account/bin/maps-account-guest'
const alias_path = 'usr/bin/run-android-calculator'
const deployment_path = 'opt/vinix-maps-account/build.json'
const runtime = 'opt/vinix-android-aarch64'
const jar_path = runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const dex_path = runtime + '/usr/lib/java/dex/android_translation_layer/classes.dex'
const headless = 'opt/vinix-headless-service'
const overlay = 'maps-context-storage-diagnostic.tar'
const disk_reserve_bytes = u64(1024) * 1024 * 1024
const disk_growth_limit_bytes = u64(512) * 1024 * 1024
const retained = {
	'tests/native-android-ws/maps-context-storage-stage.v': carry($embed_file(@FILE))
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
fn disk_budget(start u64, available u64) ! {
	if start < disk_reserve_bytes + disk_growth_limit_bytes || available < disk_reserve_bytes
		|| (available < start && start - available > disk_growth_limit_bytes) {
		return error('preparation disk budget exceeded: 1 GiB reserve and 512 MiB growth limit required')
	}
}
fn disk_sample(root string, label string, start u64, mut samples map[string]u64) ! {
	available := os.disk_usage(os.dir(root))!.available
	samples[label] = available
	println('MAPS-CONTEXT-STORAGE disk ' + label + ' available_bytes=' + available.str())
	disk_budget(start, available)!
}
fn exact_profile(base string, manifest string, jar string, dex string) ! {
	if base != base_seal || manifest != framework_seal || jar != jar_pin || dex != dex_pin
		|| !stage.valid_pin(base) || !stage.valid_pin(manifest) || !stage.valid_pin(jar) || !stage.valid_pin(dex)
		|| manifest == old_framework_seal || jar == old_jar_pin || dex == old_dex_pin {
		return error('exact credential storage Context diagnostic profile differs')
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
fn pins(value map[string]json2.Any) !map[string]string {
	return json2.decode[map[string]string](json2.encode(value['inputs_sha256']!))!
}
fn changed_paths() []string {
	return [jar_path, dex_path, headless + '/framework-build.json', headless + '/framework-sha256.json', headless + '/guest-inputs.json']
}
fn all_paths() []string {
	mut result := changed_paths()
	result << deployment_path
	return result
}
fn repin_headless(original map[string]json2.Any) !map[string]json2.Any {
	old := pins(original)!
	if original.len != 1 || old.len != 7 || old['/' + jar_path] or { '' } != old_jar_pin {
		return error('retained headless seven-path contract differs')
	}
	mut updated := old.clone()
	updated['/' + jar_path] = jar_pin
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	verify_headless_delta(original, result)!
	return result
}
fn verify_headless_delta(original map[string]json2.Any, updated map[string]json2.Any) ! {
	exact_delta(as_json(pins(original)!)!.as_map(), as_json(pins(updated)!)!.as_map(), {'/' + jar_path: json2.Any(jar_pin)})!
	exact_delta(original, updated, {'inputs_sha256': updated['inputs_sha256']!})!
}
fn repin_deployment(original map[string]json2.Any, replacements map[string]string) !map[string]json2.Any {
	if stage.text_field(original, 'kind')! != 'vinix-maps-account-deployment-v1'
		|| stage.text_field(original, 'framework_manifest_sha256')! != old_framework_seal
		|| stage.text_field(original, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(original, 'launch_manifest_sha256')! != launch_seal {
		return error('retained deployment identity differs')
	}
	old := pins(original)!
	if old['/' + controller_path] or { '' } != controller_pin
		|| old['/' + alias_path] or { '' } != controller_pin
		|| old['/' + jar_path] or { '' } != old_jar_pin || old['/' + dex_path] or { '' } != old_dex_pin {
		return error('retained controller/framework inputs differ')
	}
	mut updated := old.clone()
	for name, pin in replacements {
		if !stage.valid_pin(pin) { return error('invalid replacement digest') }
		updated[name] = pin
	}
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	result['framework_manifest_sha256'] = json2.Any(framework_seal)
	verify_deployment_delta(original, result, replacements)!
	return result
}
fn verify_deployment_delta(original map[string]json2.Any, updated map[string]json2.Any, replacements map[string]string) ! {
	mut expected := changed_paths().map('/' + it)
	mut actual_paths := replacements.keys()
	expected.sort()
	actual_paths.sort()
	if actual_paths != expected || replacements['/' + jar_path]! != jar_pin || replacements['/' + dex_path]! != dex_pin {
		return error('exact five deployment input changes required')
	}
	old := pins(original)!
	actual := updated['inputs_sha256'] or { return error('deployment pins removed') }
	mut changes := map[string]json2.Any{}
	for path, pin in replacements { changes[path] = json2.Any(pin) }
	exact_delta(as_json(old)!.as_map(), actual.as_map(), changes)!
	exact_delta(original, updated, {'inputs_sha256': actual, 'framework_manifest_sha256': json2.Any(framework_seal)})!
}
fn exact_regular_names(names []string) ! {
	mut actual := names.clone()
	mut expected := changed_paths()
	expected << deployment_path
	actual.sort()
	expected.sort()
	if actual != expected { return error('six-file payload allowlist differs') }
}
fn payload_inventory(root string) ![]stage.Entry {
	mut entries := []stage.Entry{}
	mut roots := os.ls(root)!
	roots.sort()
	if roots != ['opt'] { return error('payload root set differs') }
	for prefix in roots { stage.inventory(root + '/' + prefix, '', prefix, mut entries)! }
	exact_regular_names(entries.filter(it.kind == 'regular').map(it.name))!
	for entry in entries {
		if entry.kind == 'regular' {
			if (entry.name == jar_path && entry.sha256 != jar_pin) || (entry.name == dex_path && entry.sha256 != dex_pin) {
				return error('payload framework differs from exact producer')
			}
			continue
		}
		if entry.kind != 'directory' || !all_paths().any(it.starts_with(entry.name + '/')) {
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
	if selected.len != 22 || selected[startup_root] or { '' } != startup_seal
		|| selected[controller_stage_root] or { '' } != controller_stage_seal
		|| selected[service_query_root] or { '' } != service_query_seal
		|| selected[memory_root] or { '' } != memory_seal
		|| selected[controller_root] or { '' } != controller_seal
		|| selected[old_framework_root] or { '' } != old_framework_seal {
		return error('exact inherited complete dependency set differs')
	}
	return selected
}
fn verify_framework(value map[string]json2.Any) ! {
	if stage.text_field(value, 'profile')! != 'credential-storage-2104'
		|| stage.text_field(value, 'baseline_path')! != old_framework_root
		|| stage.text_field(value, 'baseline_manifest_sha256')! != old_framework_seal
		|| stage.text_field(value, 'baseline_api_impl_sha256')! != old_jar_pin
		|| stage.text_field(value, 'api_impl_sha256')! != jar_pin
		|| stage.text_field(value, 'classes_dex_sha256')! != dex_pin
		|| value['class_count']! != as_json(2104)!
		|| value['changed_classes']! != as_json(['android/app/ContextImpl.smali', 'android/content/Context.smali', 'android/content/ContextWrapper.smali'])!
		|| value['added_classes']! != as_json([]string{})!
		|| value['changed_method_counts']! != as_json({'android/app/ContextImpl.smali': 0, 'android/content/Context.smali': 0, 'android/content/ContextWrapper.smali': 0})!
		|| value['added_method_counts']! != as_json({'android/app/ContextImpl.smali': 2, 'android/content/Context.smali': 2, 'android/content/ContextWrapper.smali': 2})!
		|| value['added_fields']! != as_json(map[string][]string{})! {
		return error('exact credential storage Context framework audit differs')
	}
}
fn framework_fixture() !map[string]json2.Any {
	return {
		'profile': json2.Any('credential-storage-2104'), 'baseline_path': json2.Any(old_framework_root),
		'baseline_manifest_sha256': json2.Any(old_framework_seal), 'baseline_api_impl_sha256': json2.Any(old_jar_pin),
		'api_impl_sha256': json2.Any(jar_pin), 'classes_dex_sha256': json2.Any(dex_pin), 'class_count': as_json(2104)!,
		'changed_classes': as_json(['android/app/ContextImpl.smali', 'android/content/Context.smali', 'android/content/ContextWrapper.smali'])!, 'added_classes': as_json([]string{})!,
		'changed_method_counts': as_json({'android/app/ContextImpl.smali': 0, 'android/content/Context.smali': 0, 'android/content/ContextWrapper.smali': 0})!,
		'added_method_counts': as_json({'android/app/ContextImpl.smali': 2, 'android/content/Context.smali': 2, 'android/content/ContextWrapper.smali': 2})!,
		'added_fields': as_json(map[string][]string{})!,
	}
}
fn run(destination string) ! {
	exact_profile(base_seal, framework_seal, jar_pin, dex_pin)!
	root := stage.external(destination)!
	stage.disjoint(root, [base_root, framework_root, os.getwd()])!
	disk_start := os.disk_usage(os.dir(root))!.available
	disk_budget(disk_start, disk_start)!
	mut disk_samples := {'preflight': disk_start}
	println('MAPS-CONTEXT-STORAGE auditing immutable inputs')
	base_files := stage.load_inventory(base_root, base_seal)!
	base := read_json(base_root + '/stage.json')!
	if stage.text_field(base, 'kind')! != 'vinix-maps-direct-boot-diagnostic-v1'
		|| stage.text_field(base, 'base_root')! != memory_root
		|| stage.text_field(base, 'base_manifest_sha256')! != memory_seal
		|| stage.text_field(base, 'framework_manifest_sha256')! != old_framework_seal
		|| stage.text_field(base, 'controller_manifest_sha256')! != controller_seal
		|| stage.text_field(base, 'controller_sha256')! != controller_pin
		|| stage.text_field(base, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(base, 'retained_launch_manifest_sha256')! != launch_seal {
		return error('exact immutable direct-boot stage identity differs')
	}
	mut inputs := map[string]string{}
	inputs[base_root + '/sha256.json'] = base_seal
	deps := dependencies(base)!
	stage.disjoint(root, deps.keys())!
	for path, pin in deps {
		stage.load_inventory(path, pin)!
		inputs[path + '/sha256.json'] = pin
	}
	controller := stage.load_bundle(controller_root, controller_seal)!
	stage.verify_static_controller(controller, 'vinix-maps-account-guest-build-v1', 'maps-account-guest')!
	if controller.files['bin/maps-account-guest']! != controller_pin { return error('retained executable differs') }
	framework_files := stage.load_inventory(framework_root, framework_seal)!
	if framework_files['api-impl.jar']! != jar_pin || framework_files['classes.dex']! != dex_pin {
		return error('exact framework outputs differ')
	}
	verify_framework(read_json(framework_root + '/build.json')!)!
	inputs[framework_root + '/sha256.json'] = framework_seal
	disk_sample(root, 'inputs-audited', disk_start, mut disk_samples)!
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
	disk_sample(root, 'retained-source-tools', disk_start, mut disk_samples)!
	original := os.read_file(base_root + '/limine-after.conf')!
	config := stage.configure(original, overlay)!
	mut before := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	before['maps-direct-boot-diagnostic.tar'] = stage.text_field(base, 'overlay_sha256')!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar',
		'maps372-diagnostics.tar', 'headless-service.tar', 'maps-account.tar', 'protected-storage-diagnostic.tar',
		'maps-controller-diagnostic.tar', 'maps-service-query-diagnostic.tar', 'maps-controller-memory-diagnostic.tar',
		'maps-direct-boot-diagnostic.tar']
		|| before.len != config.modules.len { return error('exact original twelve-module set differs') }
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
	service_query := read_json(service_query_root + '/stage.json')!
	original_entries << json2.decode[[]stage.Entry](json2.encode(service_query['overlay_inventory']!))!
	memory := read_json(memory_root + '/stage.json')!
	original_entries << json2.decode[[]stage.Entry](json2.encode(memory['overlay_inventory']!))!
	original_entries << json2.decode[[]stage.Entry](json2.encode(base['overlay_inventory']!))!
	for pair in [[framework_root + '/api-impl.jar', jar_path], [framework_root + '/classes.dex', dex_path],
		[framework_root + '/build.json', headless + '/framework-build.json'], [framework_root + '/sha256.json', headless + '/framework-sha256.json']] {
		copy_file(pair[0], root + '/payload/' + pair[1], 0o644)!
	}
	old_headless := read_json(base_root + '/payload/' + headless + '/guest-inputs.json')!
	write_json(root + '/payload/' + headless + '/guest-inputs.json', as_json(repin_headless(old_headless)!)!)!
	mut replacements := map[string]string{}
	for path in changed_paths() { replacements['/' + path] = stage.hash(root + '/payload/' + path)! }
	old_deployment := read_json(base_root + '/payload/' + deployment_path)!
	write_json(root + '/payload/' + deployment_path, as_json(repin_deployment(old_deployment, replacements)!)!)!
	entries_before := payload_inventory(root + '/payload')!
	modes := inherited_modes(original_entries, entries_before)!
	for entry in entries_before { os.chmod(root + '/payload/' + entry.name, int(modes[entry.name]!))! }
	entries := payload_inventory(root + '/payload')!
	write_json(root + '/overlay-plan.json', as_json(entries)!)!
	write_json(root + '/original-inode-modes.json', as_json(modes)!)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	disk_sample(root, 'payload', disk_start, mut disk_samples)!
	println('MAPS-CONTEXT-STORAGE cloning media and appending six files')
	for name in ['boot.img', 'efivars.fd'] {
		if C.clonefile((base_root + '/' + name).str, (root + '/' + name).str, 0) != 0
			|| stage.hash(root + '/' + name)! != base_files[name]! { return error('fresh APFS media clone differs') }
		disk_sample(root, 'clone-' + name, disk_start, mut disk_samples)!
	}
	stage.command_expected(root, 'overlay-absent', [root + '/tools/mdir', '-i', root + '/boot.img', '::/boot/' + overlay], 1)!
	mut sources := map[string]string{}
	for entry in entries.filter(it.kind == 'regular') { sources[entry.name] = root + '/payload/' + entry.name }
	stage.write_overlay(root + '/' + overlay, sources, entries)!
	stage.verify_overlay(root + '/' + overlay, entries)!
	disk_sample(root, 'overlay', disk_start, mut disk_samples)!
	stage.command(root, 'install-overlay', [root + '/tools/mcopy', '-i', root + '/boot.img', root + '/' + overlay, '::/boot/' + overlay])!
	disk_sample(root, 'install-overlay', disk_start, mut disk_samples)!
	stage.command(root, 'install-limine', [root + '/tools/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	disk_sample(root, 'install-limine', disk_start, mut disk_samples)!
	if stage.command(root, 'readback-limine', [root + '/tools/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated
		|| stage.module_hash(root, 'readback-overlay', root + '/boot.img', overlay)! != stage.hash(root + '/' + overlay)! {
		return error('diagnostic media readback differs')
	}
	mut after := map[string]string{}
	for name in config.modules {
		after[name] = stage.module_hash(root, 'preserved-' + name, root + '/boot.img', name)!
		if after[name] != before[name] { return error('existing module changed') }
	}
	println('MAPS-CONTEXT-STORAGE rechecking complete inputs')
	for path, pin in deps { stage.load_inventory(path, pin)! }
	stage.recheck(controller)!
	if stage.load_inventory(framework_root, framework_seal)! != framework_files { return error('new framework changed') }
	if stage.load_inventory(base_root, base_seal)! != base_files { return error('immutable direct-boot stage changed') }
	for path, pin in inputs { if stage.hash(path)! != pin { return error('source/tool changed: ' + path) } }
	if payload_inventory(root + '/payload')! != entries { return error('payload changed') }
	disk_sample(root, 'complete-recheck', disk_start, mut disk_samples)!
	write_json(root + '/stage.json', {
		'kind': json2.Any('vinix-maps-context-storage-diagnostic-v1'), 'format': json2.Any(1),
		'scope': json2.Any('Credential-free credential storage Context framework diagnostic only; JNI/memory controller and all original role receipts retained. No Google login proof.'),
		'source_revision': json2.Any(revision), 'base_root': json2.Any(base_root), 'base_manifest_sha256': json2.Any(base_seal),
		'controller_build_root': json2.Any(controller_root), 'controller_manifest_sha256': json2.Any(controller_seal),
		'controller_sha256': json2.Any(controller_pin),
		'framework_build_root': json2.Any(framework_root), 'framework_manifest_sha256': json2.Any(framework_seal),
		'framework_jar_sha256': json2.Any(jar_pin), 'framework_dex_sha256': json2.Any(dex_pin),
		'retained_framework_manifest_sha256': json2.Any(old_framework_seal), 'native_manifest_sha256': json2.Any(native_seal),
		'retained_launch_manifest_sha256': json2.Any(launch_seal),
		'headless_input_delta': as_json({'/' + jar_path: jar_pin})!,
		'headless_top_level_delta': as_json(['inputs_sha256'])!,
		'deployment_input_delta': as_json(replacements)!,
		'deployment_top_level_delta': as_json(['inputs_sha256', 'framework_manifest_sha256'])!, 'inputs_sha256': as_json(inputs)!,
		'original_modules_sha256': as_json(before)!, 'preserved_modules_sha256': as_json(after)!,
		'overlay_inventory': as_json(entries)!, 'overlay_sha256': json2.Any(stage.hash(root + '/' + overlay)!),
		'limine_before_sha256': json2.Any(stage.hash(root + '/limine-before.conf')!), 'limine_after_sha256': json2.Any(stage.hash(root + '/limine-after.conf')!),
		'staged_boot_sha256': json2.Any(stage.hash(root + '/boot.img')!), 'staged_efivars_sha256': json2.Any(stage.hash(root + '/efivars.fd')!),
		'guest_terminal_command': json2.Any('/opt/vinix-maps-account/bin/maps-account-guest --broker'),
		'disk_reserve_bytes': as_json(disk_reserve_bytes)!, 'disk_growth_limit_bytes': as_json(disk_growth_limit_bytes)!,
		'disk_available_samples_bytes': as_json(disk_samples)!,
	})!
	mut files := map[string]string{}
	collect(root, '', mut files)!
	write_json(root + '/sha256.json', as_json(files)!)!
	println('MAPS-CONTEXT-STORAGE-STAGE PASS ' + root + ' seal=' + stage.hash(root + '/sha256.json')!)
}
fn self_test() ! {
	disk_start := disk_reserve_bytes + disk_growth_limit_bytes + 32
	disk_budget(disk_start, disk_start)!
	disk_budget(disk_start, disk_start - disk_growth_limit_bytes)!
	disk_budget(disk_start, disk_start + 32)!
	for bad in [[disk_reserve_bytes, disk_reserve_bytes], [disk_start, disk_reserve_bytes - 1],
		[disk_start, disk_start - disk_growth_limit_bytes - 1]] {
		if _ := disk_budget(bad[0], bad[1]) { return error('disk reserve or growth violation accepted') }
	}
	exact_profile(base_seal, framework_seal, jar_pin, dex_pin)!
	for values in [[old_framework_seal, jar_pin, dex_pin], [framework_seal, old_jar_pin, dex_pin],
		[framework_seal, jar_pin, old_dex_pin], [native_seal, jar_pin, dex_pin], [framework_seal, '', dex_pin]] {
		if _ := exact_profile(base_seal, values[0], values[1], values[2]) { return error('obsolete or mismatched framework accepted') }
	}
	if _ := exact_profile(startup_seal, framework_seal, jar_pin, dex_pin) { return error('wrong base accepted') }
	framework := framework_fixture()!
	verify_framework(framework)!
	for name in framework.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(framework))!
		bad[name] = json2.Any('unexpected')
		if _ := verify_framework(bad) { return error('invalid framework audit accepted: ' + name) }
	}
	old := {'a': json2.Any('old'), 'b': json2.Any('same')}
	exact_delta(old, {'a': json2.Any('new'), 'b': json2.Any('same')}, {'a': json2.Any('new')})!
	for bad in [{'a': json2.Any('new')}, {'a': json2.Any('new'), 'b': json2.Any('bad')},
		{'a': json2.Any('new'), 'b': json2.Any('same'), 'c': json2.Any('extra')}] {
		if _ := exact_delta(old, bad, {'a': json2.Any('new')}) { return error('unsafe receipt delta accepted') }
	}
	if _ := exact_delta(old, old, {'a': json2.Any('old')}) { return error('missing receipt change accepted') }
	mut old_inputs := {'/' + controller_path: controller_pin, '/' + alias_path: controller_pin, '/unchanged': native_seal}
	mut replacements := map[string]string{}
	for path in changed_paths() {
		old_inputs['/' + path] = old_framework_seal
		replacements['/' + path] = framework_seal
	}
	old_inputs['/' + jar_path] = old_jar_pin
	old_inputs['/' + dex_path] = old_dex_pin
	replacements['/' + jar_path] = jar_pin
	replacements['/' + dex_path] = dex_pin
	deployment := {
		'kind': json2.Any('vinix-maps-account-deployment-v1'), 'framework_manifest_sha256': json2.Any(old_framework_seal),
		'native_manifest_sha256': json2.Any(native_seal), 'launch_manifest_sha256': json2.Any(launch_seal),
		'inputs_sha256': as_json(old_inputs)!,
	}
	updated := repin_deployment(deployment, replacements)!
	for name in old_inputs.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		mut altered := pins(bad)!
		altered[name] = if name in replacements { old_inputs[name]! } else { framework_seal }
		bad['inputs_sha256'] = as_json(altered)!
		if _ := verify_deployment_delta(deployment, bad, replacements) { return error('unrelated or missing input delta accepted') }
	}
	for name in ['extra', 'native_manifest_sha256', 'launch_manifest_sha256', 'framework_manifest_sha256'] {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		bad[name] = json2.Any(controller_pin)
		if _ := verify_deployment_delta(deployment, bad, replacements) { return error('extra deployment identity/key accepted') }
	}
	for path in changed_paths() {
		mut bad := replacements.clone()
		bad.delete('/' + path)
		if _ := repin_deployment(deployment, bad) { return error('incomplete replacement set accepted') }
	}
	mut excess := replacements.clone()
	excess['/extra'] = native_seal
	if _ := repin_deployment(deployment, excess) { return error('extra replacement path accepted') }
	mut invalid_pin := replacements.clone()
	invalid_pin['/' + headless + '/framework-build.json'] = ''
	if _ := repin_deployment(deployment, invalid_pin) { return error('invalid replacement digest accepted') }
	mut original_headless := map[string]string{}
	for i in 0 .. 6 { original_headless['/unchanged' + i.str()] = native_seal }
	original_headless['/' + jar_path] = old_jar_pin
	headless_receipt := {'inputs_sha256': as_json(original_headless)!}
	headless_updated := repin_headless(headless_receipt)!
	for name in original_headless.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(headless_updated))!
		mut changed := pins(bad)!
		changed[name] = if name == '/' + jar_path { old_jar_pin } else { framework_seal }
		bad['inputs_sha256'] = as_json(changed)!
		if _ := verify_headless_delta(headless_receipt, bad) { return error('unsafe headless delta accepted') }
	}
	mut extra_headless := headless_updated.clone()
	extra_headless['extra'] = json2.Any('unexpected')
	if _ := verify_headless_delta(headless_receipt, extra_headless) { return error('extra headless top key accepted') }
	allowed := all_paths()
	exact_regular_names(allowed)!
	for bad in [allowed[..5], []string{}, [jar_path, dex_path, deployment_path, 'opt/escape'], [jar_path, jar_path, deployment_path]] {
		if _ := exact_regular_names(bad) { return error('wrong payload set accepted') }
	}
	plan := [stage.Entry{name: jar_path, kind: 'regular', mode: 0o644}]
	good := [stage.Entry{name: 'opt', kind: 'directory', mode: 0o755}, stage.Entry{name: jar_path, kind: 'regular', mode: 0o644}]
	if inherited_modes(good, plan)![jar_path]! != 0o644 { return error('inherited framework mode lost') }
	for bad in [stage.Entry{name: 'opt', kind: 'symlink', mode: 0o755}, stage.Entry{name: jar_path, kind: 'regular', mode: 0o666},
		stage.Entry{name: jar_path, kind: 'regular', mode: 0o4644}] {
		mut original := good.clone()
		original << bad
		if _ := inherited_modes(original, plan) { return error('unsafe old inode accepted') }
	}
	if _ := inherited_modes([stage.Entry{name: jar_path, kind: 'regular', mode: 0o600}], plan) { return error('unreadable original accepted') }
	println('MAPS-CONTEXT-STORAGE-STAGE SELFTEST PASS disk reserve/growth boundaries exact profile five-input deployment delta one-input headless delta six-file payload inherited modes protected ancestors')
}
fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != '--prepare' { eprintln('usage: maps-context-storage-stage --prepare FRESH_EXTERNAL_OUTPUT | --self-test'); exit(2) }
	run(os.args[2]) or { eprintln(err); exit(1) }
}
