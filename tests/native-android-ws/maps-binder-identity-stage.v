// SPDX-License-Identifier: GPL-2.0-or-later
// Binder identity restoration over the sealed authenticator worker image.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os
import time
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const state_root = '/Users/alex/.local/state/vinix/android'
const base_root = state_root + '/maps-auth-worker-r1'
const base_seal = '0e90067339cacf85987da7d0cae72a95f2a67b6455f601275ca10ba1af40783b'
const startup_root = state_root + '/maps-startup-r1'
const startup_seal = 'f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332'
const controller_stage_root = state_root + '/maps-controller-r1'
const controller_stage_seal = '3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a'
const controller_root = state_root + '/maps-account-guest-build-2026-10-28-handoff-r2'
const controller_seal = '1cf0e472fb977e705204f06fcad806f0c1ea16d213d469d0174c658c27fb041d'
const controller_pin = '0253f16da634ffef92e1efa2b3102d1ad91af15d1f521081f60e920e78affc6b'
const broker_root = state_root + '/current-account-broker-build-2026-10-28-handoff-r1'
const broker_seal = 'b06d4aadb661eb1ba13ac07e9033d88db1db731d54d2b1685df6dba1e69cd8f6'
const broker_pin = '9f0b8ac37881ab8377e70793609882fb9b07f681b8a79264fc7f95435d8b2823'
const old_framework_root = state_root + '/combined-account-webview-application-restrictions-framework-2026-10-28-r1'
const old_framework_seal = '8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15'
const framework_root = state_root + '/combined-account-webview-binder-identity-framework-2026-10-29-r1'
const framework_seal = '739fc9c17258915b0ce7ee01fa3d9e03f47c9d4f4de05ef0c6178d624f8ff3c5'
const old_framework_build_pin = '51b78458f8da4c0d6598cf3856327111cc3094a489af7ac7e56470bd59dec225'
const framework_build_pin = 'adc6074626f03ff776cc260a17e1594d220e1647e51721d754f3d7c74666b7c2'
const native_seal = '048602ab4aa188111bad295a5af9d1b47c6cceee0fd82f0eb73858689b22a921'
const native_pin = '0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136'
const native_root = state_root + '/current-native-build-2026-10-29-auth-worker-r1'
const successor_native_root = state_root + '/current-native-build-2026-10-29-binder-identity-r1'
// Complete producer and independently reviewed production source identities.
const successor_native_seal = '2a68a45164d830cb2b3cdfcc43b2e3590ff42dc15152041fea166cd6c8f58985'
const successor_native_pin = '6a87d8c2fd003c55cb572ab397342d0c39aa54376ffe7a5a2ba2fa4592099eae'
const successor_native_build_pin = 'e43f3c32c9b410cc03772aeb2554a70881426fa0348e9ba9294ea12693aab452'
const account_source_pin = 'de33aa1ae37bb430942bccd1f28f629519dd9d29da866898d78130fcbf7ae8bf'
const worker_source_pin = 'db0f426089da7b3397662a1dcf93a1de37aa32979e4edfa746a63b01855a1c5c'
const helper_broker_before_pin = 'e6eb478213fe46fd138ec539476996bc47906af62685a36af3eeeca2b529dccc'
const helper_broker_after_pin = '8a2baf5fbfbeffa873a9ee47abf69667b2a3f976c7bacac84f4f82de4be07d41'
const builder_pin = 'a468758d4957f66703836da209b901e1344a2f889b27c2df868630d97adc4d33'
const old_account_source_pin = '7369030274a40f2c9b4abafbd854c61fe9f48b29152dd0de7e78dce1df56bae6'
const old_bindings_pin = '60b590a07c627bd3ff8d57f1edaf5c0bd2e06c44124c7f808c6f5701f5bb3bbe'
const bindings_pin = 'e3fa613993c1ca60aab021ebdbacc93dc71ae68e4bef3d112482f77c8ddeb95b'
const old_generated_pin = '852fbe4ba67832f5cebbf920cffaaed982a6c1fd47ab9ca0a8ad50771f0174a7'
const generated_pin = 'b349742dff2bdcc464e3df011ccf54d0ff546ea36a1feb9cd82b26ec3da67dde'
const old_context_pin = 'ca75d710e0bafe480127a4e796688083cc3fd3384ddcc846c009fe0ebf205e8a'
const context_pin = '90fddf01e6bd8785d64b873aaa5632d2cd15e768de425fd5c91d7b75c4097888'
const old_binder_pin = '83c2e6bd5f1a6604710be9d458dd5f8aeafffe7ea2135c1ceac431ba43c0f5f9'
const binder_pin = 'ce609f4d797c4406d86799a7c70c2581649a067e57a286d9a1ce39076a78711d'
const dex_context_pin = '96f550a8c6dae78e504082b6651b105b98e5d49680311b5220fb0ad13cf364aa'
const dex_binder_pin = 'ed4de6f5d32f5ea1bb0696b0aeb6a93b6d76baeecb51200aa760031460326499'
const generator_framework_root = state_root + '/combined-account-webview-auth-exception-framework-2026-10-29-r1'
const generator_framework_seal = '4aa0c09e05c0d4fe3180a909648ebb344881ec1d2d6e60bba5d959148d93a284'
const browser_seal = 'fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62'
const browser_pin = '16def2047bf7605a23d949ff7b6b56bc56dcece038136553a98a0524b26ded1a'
const old_jar_pin = '0daae54d7755b255ed3335f58d8cafd6da4d03c8c95343ebb0f174d166da6916'
const old_dex_pin = '6cf2173aedc5adbf187aed5db4c37a8a95a413cc35343272cd45c88f2734d615'
const jar_pin = '3f2e3220d6c38feb885044fdb4806d4d3ca7736352bbcc7813e2ee6510463636'
const dex_pin = '2bbe60c766a65daeb09b336ff9bd61c4d4f0c228ddbb97f9584eb44cb2b0e79a'
const launch_seal = '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
const controller_path = 'opt/vinix-maps-account/bin/maps-account-guest'
const broker_path = 'opt/vinix-android-aarch64/usr/bin/native-account-broker'
const alias_path = 'usr/bin/run-android-calculator'
const deployment_path = 'opt/vinix-maps-account/build.json'
const jar_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const dex_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/classes.dex'
const native_path = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const headless = 'opt/vinix-headless-service'
const headless_base = state_root + '/maps-auth-exception-r1/payload/'
const old_headless_pin = '343cbf22322775efa414b0135e3fccf2992afa51a342c6496b03c207403f7fd3'
const overlay = 'maps-binder-identity.tar'
const disk_reserve = u64(1024) * 1024 * 1024
const disk_growth = u64(512) * 1024 * 1024
const digest_receipt_charge = u64(1024) * 1024
const retained = {
	'tests/native-android-ws/maps-binder-identity-stage.v': carry($embed_file(@FILE))
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
struct DiskBudget {
mut:
	available u64
	charged u64
	digest_receipt_charged u64
}
fn disk_blocks(field string) !u64 {
	if field == '' || field.len > 17 { return error('invalid df count') }
	mut value := u64(0)
	limit := u64(0xffffffffffffffff) / 1024
	for digit in field.bytes() {
		if digit < `0` || digit > `9` || value > (limit - u64(digit - `0`)) / 10 { return error('invalid or overflowing df count') }
		value = value * 10 + u64(digit - `0`)
	}
	return value
}
fn available_bytes(output string) !u64 {
	rows := output.trim_space().split_into_lines()
	if output.len > 8192 || rows.len != 2 || rows[0].fields() != ['Filesystem', '1024-blocks', 'Used', 'Available', 'Capacity', 'Mounted', 'on'] { return error('unexpected df output') }
	fields := rows[1].fields()
	if fields.len < 6 || !fields[0].starts_with('/') || !fields[5].starts_with('/') || !fields[4].ends_with('%') { return error('invalid df row') }
	total := disk_blocks(fields[1])!
	used := disk_blocks(fields[2])!
	available := disk_blocks(fields[3])!
	disk_blocks(fields[4][..fields[4].len - 1])!
	if total == 0 || used > total || available > total { return error('inconsistent df count') }
	return available * 1024
}
fn update_budget(available u64, writing bool, mut budget DiskBudget) ! {
	drop := if writing && available < budget.available { budget.available - available } else { u64(0) }
	if available < disk_reserve || budget.charged > disk_growth || drop > disk_growth - budget.charged { return error('1 GiB reserve or cumulative 512 MiB preparation growth budget exceeded') }
	budget.charged += drop
	budget.available = available
}
fn disk_available(path string) !u64 {
	mut child := os.new_process('/usr/bin/env')
	child.set_args(['LC_ALL=C', '/bin/df', '-kP', path])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	mut finished := false
	defer {
		if !finished { child.signal_kill(); child.wait() }
		child.close()
	}
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 2 * time.second
	for {
		out := child.stdout_read()
		errout := child.stderr_read()
		if stdout.len + stderr.len + out.len + errout.len > 8192 { return error('df output exceeds bound') }
		stdout += out
		stderr += errout
		if !child.is_alive() && out == '' && errout == '' { break }
		if time.sys_mono_now() >= deadline { return error('df deadline exceeded') }
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	finished = true
	if child.code != 0 || stderr != '' { return error('df failed') }
	return available_bytes(stdout)
}
fn check_disk(root string, label string, writing bool, mut budget DiskBudget, mut samples map[string]u64) ! {
	available := disk_available(os.dir(root))!
	update_budget(available, writing, mut budget)!
	samples[label] = available
	println('MAPS-BINDER-IDENTITY disk ' + label + ' available_bytes=' + available.str() + ' charged_growth_bytes=' + budget.charged.str())
}
fn charge_audit(count int, mut budget DiskBudget) ! {
	if count < 1 || count > 25 || budget.charged > disk_growth || u64(count) * digest_receipt_charge > disk_growth - budget.charged { return error('module digest receipts exceed preparation budget') }
	budget.charged += u64(count) * digest_receipt_charge
	budget.digest_receipt_charged += u64(count) * digest_receipt_charge
}
fn audit_modules(root string, label string, image string, names []string, expected map[string]string,
	mut budget DiskBudget, mut samples map[string]u64) !map[string]string {
	if names.len < 1 || names.len > 25 || names.len != expected.len { return error('bounded exact module audit required') }
	mut pins := map[string]string{}
	for name in names {
		if name in pins { return error('duplicate module audit member') }
		pin := stage.module_hash(root, label + '-' + name, image, name)!
		if pin != expected[name]! { return error('audited module differs: ' + name) }
		path := root + '/commands/' + label + '-' + name + '.sha256'
		info := os.lstat(path)!
		if info.get_filetype() != .regular || info.mode & 0o7777 != 0o600 || info.size != 68
			|| os.read_file(path)! != pin + '  -\n' { return error('exact bounded digest receipt required') }
		pins[name] = pin
	}
	charge_audit(names.len, mut budget)!
	check_disk(root, label + '-module-audit', false, mut budget, mut samples)!
	return pins
}
fn exact_profile(base string, manifest string, executable string) ! {
	if base != base_seal || manifest != successor_native_seal || executable != successor_native_pin
		|| !stage.valid_pin(manifest) || !stage.valid_pin(executable)
		|| !stage.valid_pin(successor_native_build_pin) || !stage.valid_pin(account_source_pin) || !stage.valid_pin(worker_source_pin)
		|| !stage.valid_pin(helper_broker_after_pin) || !stage.valid_pin(bindings_pin) || !stage.valid_pin(generated_pin)
		|| !stage.valid_pin(framework_seal) || !stage.valid_pin(framework_build_pin) || !stage.valid_pin(context_pin)
		|| !stage.valid_pin(jar_pin) || !stage.valid_pin(dex_pin) || !stage.valid_pin(binder_pin)
		|| manifest == native_seal || executable == native_pin || account_source_pin == old_account_source_pin
		|| framework_seal == generator_framework_seal || jar_pin == old_jar_pin || dex_pin == old_dex_pin
		|| bindings_pin == old_bindings_pin || generated_pin == old_generated_pin || context_pin == old_context_pin || binder_pin == old_binder_pin {
		return error('exact reviewed Binder identity framework/native profile required')
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
fn changed_paths() []string {
	return [jar_path, dex_path, native_path, headless + '/framework-build.json', headless + '/framework-sha256.json', headless + '/guest-inputs.json']
}
fn headless_inputs() map[string]string {
	return {
		'/opt/vinix-android-aarch64/usr/bin/run-android': '1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112'
		'/opt/vinix-android-aarch64/usr/bin/vinix-android-native': 'b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d'
		// This is the retained headless lifecycle role, not the Maps native role.
		'/' + native_path: '3ac3ec1a026a409ec52b7973d9dcc4593bd5d266fc2c6e77fc5d5c1a88e439d9'
		'/' + jar_path: old_jar_pin
		'/' + headless + '/bin/headless-service-controller': '70f23b12fb5a770587bfcebcf33ed1320fe050399f08bd256362a037f24eb0b6'
		'/' + headless + '/bin/headless-service-guest': 'd518cfc5145924479b5ad630aac2a3d3ef7dcea66f53515c03df03735e88ce05'
		'/' + headless + '/fixture.apk': '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
	}
}
fn repin_headless(original map[string]json2.Any) !map[string]json2.Any {
	if original.len != 1 || json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))! != headless_inputs() {
		return error('exact inherited seven-input headless role contract differs')
	}
	mut updated := headless_inputs()
	updated['/' + jar_path] = jar_pin
	return {'inputs_sha256': as_json(updated)!}
}
fn replacement_pins(root string) !map[string]string {
	mut pins := map[string]string{}
	for path in changed_paths() { pins['/' + path] = stage.hash(root + '/' + path)! }
	return pins
}
fn repin_deployment(original map[string]json2.Any, replacements map[string]string) !map[string]json2.Any {
	if stage.text_field(original, 'kind')! != 'vinix-maps-account-deployment-v1'
		|| stage.text_field(original, 'framework_manifest_sha256')! != generator_framework_seal
		|| stage.text_field(original, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(original, 'launch_manifest_sha256')! != launch_seal
		|| stage.text_field(original, 'browser_client_manifest_sha256')! != browser_seal {
		return error('retained deployment identity differs')
	}
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	if old['/' + controller_path] or { '' } != controller_pin
		|| old['/' + alias_path] or { '' } != controller_pin
		|| old['/' + broker_path] or { '' } != broker_pin
		|| old['/' + jar_path] or { '' } != old_jar_pin
		|| old['/' + dex_path] or { '' } != old_dex_pin
		|| old['/' + native_path] or { '' } != native_pin
		|| old['/' + headless + '/framework-build.json'] or { '' } != old_framework_build_pin
		|| old['/' + headless + '/framework-sha256.json'] or { '' } != generator_framework_seal
		|| old['/' + headless + '/guest-inputs.json'] or { '' } != old_headless_pin { return error('retained native/framework or broker/controller aliases differ') }
	mut updated := old.clone()
	mut changes := map[string]json2.Any{}
	mut expected := changed_paths().map('/' + it)
	mut actual := replacements.keys()
	expected.sort(); actual.sort()
	if actual != expected || replacements['/' + native_path]! != successor_native_pin
		|| replacements['/' + jar_path]! != jar_pin || replacements['/' + dex_path]! != dex_pin
		|| replacements['/' + headless + '/framework-build.json']! != framework_build_pin
		|| replacements['/' + headless + '/framework-sha256.json']! != framework_seal { return error('exact six framework/native replacements required') }
	for name, pin in replacements {
		if !stage.valid_pin(pin) { return error('invalid framework replacement pin') }
		updated[name] = pin
		changes[name] = json2.Any(pin)
	}
	exact_delta(as_json(old)!.as_map(), as_json(updated)!.as_map(), changes)!
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	result['native_manifest_sha256'] = json2.Any(successor_native_seal)
	result['framework_manifest_sha256'] = json2.Any(framework_seal)
	verify_deployment_delta(original, result, replacements)!
	return result
}
fn verify_deployment_delta(original map[string]json2.Any, updated map[string]json2.Any, replacements map[string]string) ! {
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	actual := updated['inputs_sha256'] or { return error('deployment pins removed') }
	exact_delta(as_json(old)!.as_map(), actual.as_map(), as_json(replacements)!.as_map())!
	exact_delta(original, updated, {'inputs_sha256': actual, 'native_manifest_sha256': json2.Any(successor_native_seal), 'framework_manifest_sha256': json2.Any(framework_seal)})!
}
fn exact_regular_names(names []string) ! {
	mut actual := names.clone()
	mut expected := changed_paths()
	expected << deployment_path
	actual.sort()
	expected.sort()
	if actual != expected { return error('seven-file payload allowlist differs') }
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
			expected_mode := if entry.name == native_path { u32(0o755) } else { u32(0o644) }
			known := {native_path: successor_native_pin, jar_path: jar_pin, dex_path: dex_pin,
				headless + '/framework-build.json': framework_build_pin, headless + '/framework-sha256.json': framework_seal}
			if entry.mode != expected_mode || (entry.name in known && entry.sha256 != known[entry.name]!) {
				return error('payload mode or framework/native differs from exact producer')
			}
			continue
		}
		mut allowed := changed_paths()
		allowed << deployment_path
		if entry.kind != 'directory' || entry.mode != 0o755 || !allowed.any(it.starts_with(entry.name + '/')) {
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
				// Preserve the first executable inode despite a historical 0644 DSO overlay.
				legacy_native := target.name == native_path && target.mode == 0o755 && old.mode == 0o644
				if old.kind != target.kind || (old.mode != target.mode && !legacy_native) { return error('unsafe existing destination: ' + old.name) }
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
	if selected.len != 47 || selected[controller_root] or { '' } != controller_seal
		|| selected[broker_root] or { '' } != broker_seal
		|| selected[startup_root] or { '' } != startup_seal
		|| selected[controller_stage_root] or { '' } != controller_stage_seal
		|| selected[old_framework_root] or { '' } != old_framework_seal
		|| selected[generator_framework_root] or { '' } != generator_framework_seal
		|| selected[native_root] or { '' } != native_seal {
		return error('exact inherited complete dependency set differs')
	}
	return selected
}
fn original_inodes(deps map[string]string) ![]stage.Entry {
	mut overlays := [][]stage.Entry{}
	mut seen := map[string]bool{}
	mut cursor := base_root
	for _ in 0 .. 32 {
		if cursor in seen || (cursor != base_root && cursor !in deps) { return error('unsealed or cyclic stage ancestry') }
		seen[cursor] = true
		value := read_json(cursor + '/stage.json')!
		overlays << json2.decode[[]stage.Entry](json2.encode(value['overlay_inventory']!))!
		original := cursor + '/original-module-inventory.json'
		if os.exists(original) {
			if os.lstat(original)!.size > 32 * 1024 * 1024 { return error('original inode inventory exceeds bound') }
			mut entries := json2.decode[[]stage.Entry](os.read_file(original)!)!
			for i := overlays.len - 1; i >= 0; i-- { entries << overlays[i] }
			return entries
		}
		cursor = stage.text_field(value, 'base_root')!
	}
	return error('stage ancestry exceeds bound')
}
// Preserve all source membership and unchanged roles while auditing the exact
// reviewed service, binding, broker helper and generated JNI identity delta.
fn normalized_source_origin(root string, origin string) !string {
	if os.norm_path(origin) != origin || origin.contains_any('\\\x00\n') { return error('malformed retained helper origin') }
	if origin.starts_with(root + '/compiler-root/') { return '@compiler/' + origin.all_after(root + '/compiler-root/') }
	if origin.starts_with(os.getwd() + '/') { return origin }
	return error('helper origin outside retained compiler and repository')
}
fn native_source_closure(bundle stage.Bundle, label string) !map[string]string {
	closure := json2.decode[map[string]string](json2.encode(read_json(bundle.root + '/' + label + '-closure.json')!))!
	if closure.len == 0 || closure.len > 2048 { return error('bounded nonempty native helper closure required') }
	mut normalized := map[string]string{}
	mut names := []string{}
	for origin, pin in closure {
		key := normalized_source_origin(bundle.root, origin)!
		path := 'closure/' + label + '/' + origin.trim_left('/')
		if key in normalized || !stage.valid_pin(pin) || (bundle.files[path] or { '' }) != pin { return error('native helper closure member differs') }
		normalized[key] = pin
		names << path
	}
	names.sort()
	if bundle.files.keys().filter(it.starts_with('closure/' + label + '/')).sorted() != names { return error('complete native helper source membership differs') }
	return normalized
}
fn exact_helper_delta(label string, before map[string]string, after map[string]string) ! {
	mut expected := before.clone()
	if label == 'builder' {
		broker := os.getwd() + '/tests/native-android-tools/androidtools/framework_account_broker_context.v'
		if before[broker] or { '' } != helper_broker_before_pin || !stage.valid_pin(helper_broker_after_pin)
			|| helper_broker_before_pin == helper_broker_after_pin {
			return error('exact reviewed broker helper predecessor and successor required')
		}
		expected[broker] = helper_broker_after_pin
	} else if label != 'native-generator' {
		return error('unknown native helper closure')
	}
	if after != expected { return error('unreviewed complete native helper closure change: ' + label) }
}
fn consumed_framework_before() map[string]string {
	return {'smali/android/atl/VinixAccountBrokerContext.smali': old_context_pin}
}
fn consumed_framework_after() map[string]string {
	return {'smali/android/atl/VinixAccountBrokerContext.smali': context_pin}
}
fn exact_consumed_delta(before map[string]string, after map[string]string) ! {
	old := consumed_framework_before()
	new := consumed_framework_after()
	mut expected := before.clone()
	for path, pin in old {
		if before[path] or { '' } != pin { return error('consumed framework predecessor differs') }
		expected[path] = new[path]!
	}
	if after != expected { return error('unreviewed consumed framework source or membership change') }
}
fn identity_jni_additions() map[string]string {
	return {
		'Java_android_atl_VinixAccountBrokerContext_clearCallingIdentity__': '(e voidptr, this voidptr) i64 {\n    unsafe {\n return ws_auth_clear_identity()\n }\n}\n'
		'Java_android_atl_VinixAccountBrokerContext_restoreCallingIdentity__J': '(e voidptr, this voidptr, p0 i64) u8 {\n    unsafe {\n return u8(ws_auth_restore_identity(p0))\n }\n}\n'
	}
}
// The generator numbers functions by binding order. Normalize only that ordinal;
// retained export names, argument/result ABIs and all body bytes remain exact.
fn jni_blocks(source string) !map[string]string {
	if source.len == 0 || source.len > 2 * 1024 * 1024 { return error('generated JNI source exceeds bound') }
	parts := source.split("\n@[export: '")
	if parts.len < 2 || parts.len > 4096 || parts[0] != '@[translated]\nmodule atlframework\n' {
		return error('canonical generated JNI header and exports required')
	}
	mut result := map[string]string{}
	for ordinal, part in parts[1..] {
		marker := "']\nfn ws_binding_"
		at := part.index(marker) or { return error('canonical JNI declaration required') }
		symbol := part[..at]
		body := part[at + marker.len..]
		index := body.all_before('(')
		if !symbol.starts_with('Java_') || symbol.contains_any("'\n\r") || symbol in result
			|| index != ordinal.str() || !body.ends_with('\n }\n}\n') || body.contains('\nfn ') {
			return error('invalid or duplicate generated JNI export or ordinal')
		}
		result[symbol] = body[index.len..]
	}
	return result
}
fn exact_jni_delta(before string, after string) ! {
	mut expected := jni_blocks(before)!
	additions := identity_jni_additions()
	for symbol, body in additions {
		if symbol in expected { return error('identity JNI already existed') }
		expected[symbol] = body
	}
	if jni_blocks(after)! != expected { return error('unreviewed generated JNI export, ABI or body change') }
	before_order := before.split("\n@[export: '")[1..].map(it.all_before("']\nfn ws_binding_"))
	after_order := after.split("\n@[export: '")[1..].map(it.all_before("']\nfn ws_binding_"))
	if after_order.filter(it !in additions) != before_order
		|| after_order.filter(it in additions) != ['Java_android_atl_VinixAccountBrokerContext_clearCallingIdentity__',
			'Java_android_atl_VinixAccountBrokerContext_restoreCallingIdentity__J'] {
		return error('generated JNI retained order or identity addition order differs')
	}
}
fn exact_bindings_delta(before string, after string) ! {
	anchor := 'android/atl/VinixAccountBrokerContext|checkPermission|return ws_auth_permission(e,p0,p1,p2)\n'
	additions := 'android/atl/VinixAccountBrokerContext|clearCallingIdentity|return ws_auth_clear_identity()\n' +
		'android/atl/VinixAccountBrokerContext|restoreCallingIdentity|return u8(ws_auth_restore_identity(p0))\n'
	if before.count(anchor) != 1 || before.contains('|clearCallingIdentity|') || before.contains('|restoreCallingIdentity|')
		|| after != before.replace(anchor, anchor + additions) { return error('exact two identity bindings required') }
}
fn framework_source_delta() map[string]string {
	return {'smali/android/os/Binder.smali': binder_pin, 'smali/android/atl/VinixAccountBrokerContext.smali': context_pin}
}
fn exact_framework_sources(previous stage.Bundle, successor stage.Bundle) ! {
	// Each producer's target raw source precedes assembly; its next producer
	// starts from DEX disassembly. Compare their common canonical representation.
	if previous.files['framework-dex-after.json']! != successor.files['framework-dex-before.json']! {
		return error('exact canonical framework baseline inventory differs')
	}
	before := previous.files.keys().filter(it.starts_with('new-dex/')).sorted()
	after := successor.files.keys().filter(it.starts_with('new-dex/')).sorted()
	if before.len != 2104 || after != before { return error('exact inherited 2104 framework classes required') }
	old := {'new-dex/android/os/Binder.smali': old_binder_pin, 'new-dex/android/atl/VinixAccountBrokerContext.smali': old_context_pin}
	changes := {'new-dex/android/os/Binder.smali': dex_binder_pin, 'new-dex/android/atl/VinixAccountBrokerContext.smali': dex_context_pin}
	for path in before {
		if path in changes {
			if previous.files[path]! != old[path]! || successor.files[path]! != changes[path]! || previous.files[path]! == successor.files[path]! {
				return error('reviewed Binder/context class delta differs')
			}
		} else if successor.files[path]! != previous.files[path]! { return error('unreviewed framework class change: ' + path) }
	}
	for path, pin in framework_source_delta() {
		original := if path.ends_with('/Binder.smali') { old_binder_pin } else { old_context_pin }
		if previous.files[path]! != original || successor.files[path]! != pin { return error('exact Binder/context raw source identity differs') }
	}
	binder := 'android/os/Binder.smali'
	context := 'android/atl/VinixAccountBrokerContext.smali'
	for key, value in {
		'class_count': as_json(2104)!, 'changed_classes': as_json([context, binder])!,
		'added_classes': as_json([]string{})!, 'added_fields': as_json(map[string][]string{})!,
		'changed_method_counts': as_json({binder: 2, context: 0})!, 'added_method_counts': as_json({binder: 2, context: 2})!,
	} {
		if successor.receipt[key] or { json2.Any('absent') } != value { return error('exact Binder framework delta receipt differs: ' + key) }
	}
}
fn exact_native_sources(previous stage.Bundle, successor stage.Bundle, old_framework stage.Bundle, framework stage.Bundle) ! {
	origins_path := 'native/source-origins.json'
	origins := json2.decode[map[string]string](os.read_file(previous.root + '/' + origins_path)!)!
	new_origins := json2.decode[map[string]string](os.read_file(successor.root + '/' + origins_path)!)!
	if origins.len != 88 || new_origins != origins
		|| origins['account_worker.v'] or { '' } != os.getwd() + '/build-support/android/nativews/account_worker.v' { return error('exact retained eighty-eight native origins required') }
	mut expected_previous_inputs := map[string]string{}
	mut expected_inputs := map[string]string{}
	mut names := ['native/atlframework/ws_generated.v']
	mut changed := 0
	for name, origin in new_origins {
		if !name.ends_with('.v') || os.file_name(origin) != name || os.dir(origin) !in [os.getwd() + '/build-support/android/atlframework', os.getwd() + '/build-support/android/nativews'] {
			return error('invalid retained production source origin')
		}
		path := 'native/atlframework/' + name
		after := successor.files[path]!
		if name == 'account_service.v' {
			before := previous.files[path]!
			if origin != os.getwd() + '/build-support/android/nativews/account_service.v' || before != old_account_source_pin || after != account_source_pin || before == after {
				return error('reviewed account service source delta differs')
			}
			changed++
		} else if after != previous.files[path]! { return error('unreviewed native source change: ' + name) }
		if name == 'account_worker.v' && after != worker_source_pin { return error('retained worker source differs') }
		expected_inputs[origin] = after
		expected_previous_inputs[origin] = previous.files[path]!
		names << path
	}
	names.sort()
	if previous.files.keys().filter(it.starts_with('native/atlframework/')).sorted() != names
		|| successor.files.keys().filter(it.starts_with('native/atlframework/')).sorted() != names { return error('exact native copied source membership differs') }
	if previous.files['builder-source.v']! != builder_pin || successor.files['builder-source.v']! != builder_pin { return error('retained checked builder handoff differs') }
	for path in ['tools/find-v.sh',
		'closure/builder/' + os.getwd().trim_left('/') + '/tests/native-android-tools/androidtools/native_ws.v',
		'closure/native-generator/' + os.getwd().trim_left('/') + '/tests/linuxkpi/generate_module.v'] {
		if successor.files[path]! != previous.files[path]! { return error('retained native helper or JNI differs: ' + path) }
	}
	for pair in [['native/bindings.txt', old_bindings_pin, bindings_pin], ['native/atlframework/ws_generated.v', old_generated_pin, generated_pin]] {
		if previous.files[pair[0]]! != pair[1] || successor.files[pair[0]]! != pair[2] { return error('exact reviewed bindings/JNI identity differs') }
	}
	exact_bindings_delta(os.read_file(previous.root + '/native/bindings.txt')!, os.read_file(successor.root + '/native/bindings.txt')!)!
	exact_jni_delta(os.read_file(previous.root + '/native/atlframework/ws_generated.v')!, os.read_file(successor.root + '/native/atlframework/ws_generated.v')!)!
	mut expected_exports := json2.decode[[]string](os.read_file(previous.root + '/native/exports.json')!)!
	for symbol in identity_jni_additions().keys() {
		if symbol in expected_exports { return error('identity native export already existed') }
		expected_exports << symbol
	}
	expected_exports.sort()
	if json2.decode[[]string](os.read_file(successor.root + '/native/exports.json')!)! != expected_exports { return error('exact two native exports required') }
	for label in ['builder', 'native-generator'] {
		exact_helper_delta(label, native_source_closure(previous, label)!, native_source_closure(successor, label)!)!
	}
	consumed_before := json2.decode[map[string]string](os.read_file(previous.root + '/framework/consumed-smali.json')!)!
	consumed_after := json2.decode[map[string]string](os.read_file(successor.root + '/framework/consumed-smali.json')!)!
	exact_consumed_delta(consumed_before, consumed_after)!
	for pair in [[previous, old_framework], [successor, framework]] {
		selected := if pair[0].root == previous.root { consumed_before } else { consumed_after }
		for path, pin in selected {
			if pair[0].files['framework/' + path] or { '' } != pin || pair[1].files[path] or { '' } != pin { return error('consumed source differs from its selected sealed framework') }
		}
		if pair[0].files.keys().filter(it.starts_with('framework/smali/')).sorted() != selected.keys().map('framework/' + it).sorted() { return error('complete consumed framework membership differs') }
	}
	expected_inputs[os.getwd() + '/build-support/android/nativews/bindings.txt'] = successor.files['native/bindings.txt']!
	expected_previous_inputs[os.getwd() + '/build-support/android/nativews/bindings.txt'] = previous.files['native/bindings.txt']!
	actual_inputs := json2.decode[map[string]string](os.read_file(successor.root + '/native/current-inputs.json')!)!
	previous_inputs := json2.decode[map[string]string](os.read_file(previous.root + '/native/current-inputs.json')!)!
	if changed != 1 || actual_inputs != expected_inputs || previous_inputs != expected_previous_inputs { return error('exact native source/input receipt differs') }
	if successor.files['build.json']! != successor_native_build_pin { return error('exact native build receipt differs') }
}
fn audit_native_inputs() ! {
	exact_profile(base_seal, successor_native_seal, successor_native_pin)!
	generator_framework := stage.load_bundle(generator_framework_root, generator_framework_seal)!
	framework := stage.load_bundle(framework_root, framework_seal)!
	exact_framework_sources(generator_framework, framework)!
	previous := stage.load_bundle(native_root, native_seal)!
	successor := stage.load_bundle(successor_native_root, successor_native_seal)!
	stage.verify_native(previous, generator_framework)!
	stage.verify_native(successor, framework)!
	if previous.files['native/libvinix-android-native.so']! != native_pin || successor.files['native/libvinix-android-native.so']! != successor_native_pin {
		return error('selected native binaries differ')
	}
	exact_native_sources(previous, successor, generator_framework, framework)!
	println('MAPS-BINDER-IDENTITY-NATIVE-AUDIT PASS eighty-eight retained origins service/bindings delta two JNI additions exact helper and consumed closure')
}
fn enumerate_native_helpers() ! {
	if !stage.valid_pin(successor_native_seal) { return error('completed native producer seal required') }
	previous := stage.load_bundle(native_root, native_seal)!
	successor := stage.load_bundle(successor_native_root, successor_native_seal)!
	for label in ['builder', 'native-generator'] {
		before := native_source_closure(previous, label)!
		after := native_source_closure(successor, label)!
		mut names := before.keys()
		for name in after.keys() { if name !in before { names << name } }
		names.sort()
		for name in names {
			old := before[name] or { 'absent' }
			new := after[name] or { 'absent' }
			if old != new { println('NATIVE-HELPER-DELTA label=' + label + ' path=' + name + ' before=' + old + ' after=' + new) }
		}
	}
}
fn run(destination string) ! {
	exact_profile(base_seal, successor_native_seal, successor_native_pin)!
	root := stage.external(destination)!
	stage.disjoint(root, [base_root, controller_root, broker_root, framework_root, successor_native_root, os.getwd()])!
	disk_start := disk_available(os.dir(root))!
	if disk_start < disk_reserve + disk_growth { return error('preparation requires 1.5 GiB initial free space') }
	mut disk := DiskBudget{available: disk_start}
	mut disk_samples := {'preflight': disk_start}
	println('MAPS-BINDER-IDENTITY auditing immutable inputs')
	base_files := stage.load_inventory(base_root, base_seal)!
	base := read_json(base_root + '/stage.json')!
	if stage.text_field(base, 'kind')! != 'vinix-maps-auth-worker-v1'
		|| stage.text_field(base, 'base_root')! != state_root + '/maps-auth-exception-r1'
		|| stage.text_field(base, 'base_manifest_sha256')! != 'b8b214ffc061366718511b4d293077e8901d797884e884ebaad84f346d5341e1'
		|| stage.text_field(base, 'controller_build_root')! != controller_root
		|| stage.text_field(base, 'controller_manifest_sha256')! != controller_seal
		|| stage.text_field(base, 'controller_sha256')! != controller_pin
		|| stage.text_field(base, 'broker_build_root')! != broker_root
		|| stage.text_field(base, 'broker_manifest_sha256')! != broker_seal
		|| stage.text_field(base, 'broker_sha256')! != broker_pin
		|| stage.text_field(base, 'framework_manifest_sha256')! != generator_framework_seal
		|| stage.text_field(base, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(base, 'native_sha256')! != native_pin
		|| stage.text_field(base, 'browser_client_manifest_sha256')! != browser_seal
		|| stage.text_field(base, 'browser_client_sha256')! != browser_pin
		|| stage.text_field(base, 'retained_launch_manifest_sha256')! != launch_seal {
		return error('exact immutable authenticator worker stage identity differs')
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
	inputs[controller_root + '/sha256.json'] = controller_seal
	old_framework := stage.load_bundle(old_framework_root, old_framework_seal)!
	framework := stage.load_bundle(framework_root, framework_seal)!
	if framework.files['api-impl.jar']! != jar_pin || framework.files['classes.dex']! != dex_pin
		|| framework.files['build.json']! != framework_build_pin
		|| stage.text_field(framework.receipt, 'profile')! != 'binder-identity-2104'
		|| stage.text_field(framework.receipt, 'baseline_manifest_sha256')! != generator_framework_seal
		|| stage.text_field(framework.receipt, 'baseline_api_impl_sha256')! != old_jar_pin {
		return error('exact Binder identity framework successor differs')
	}
	inputs[framework_root + '/sha256.json'] = framework_seal
	generator_framework := stage.load_bundle(generator_framework_root, generator_framework_seal)!
	exact_framework_sources(generator_framework, framework)!
	native := stage.load_bundle(native_root, native_seal)!
	stage.verify_native(native, generator_framework)!
	if native.files['native/libvinix-android-native.so']! != native_pin { return error('exact retained native differs') }
	successor_native := stage.load_bundle(successor_native_root, successor_native_seal)!
	stage.verify_native(successor_native, framework)!
	if successor_native.files['native/libvinix-android-native.so']! != successor_native_pin { return error('exact worker native differs') }
	exact_native_sources(native, successor_native, generator_framework, framework)!
	inputs[successor_native_root + '/sha256.json'] = successor_native_seal
	broker := stage.load_bundle(broker_root, broker_seal)!
	stage.verify_account_broker(broker, old_framework)!
	if broker.files['bin/native-account-broker']! != broker_pin { return error('new broker differs') }
	inputs[broker_root + '/sha256.json'] = broker_seal
	if inputs.keys().filter(it.ends_with('/sha256.json')).len != 50 { return error('exact fifty complete dependency seals required') }
	check_disk(root, 'inputs-audited', false, mut disk, mut disk_samples)!
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
	for path in ['/usr/bin/env', '/bin/df'] { inputs[path] = stage.hash(path)! }
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
	check_disk(root, 'retained-source-tools', true, mut disk, mut disk_samples)!
	original := os.read_file(base_root + '/limine-after.conf')!
	config := stage.configure(original, overlay)!
	mut before := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	before['maps-auth-worker.tar'] = stage.text_field(base, 'overlay_sha256')!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar',
		'maps372-diagnostics.tar', 'headless-service.tar', 'maps-account.tar', 'protected-storage-diagnostic.tar',
		'maps-controller-diagnostic.tar', 'maps-service-query-diagnostic.tar', 'maps-controller-memory-diagnostic.tar',
		'maps-direct-boot-diagnostic.tar', 'maps-context-storage-diagnostic.tar', 'maps-broadcast-result-diagnostic.tar',
		'maps-onboarding-trace-diagnostic.tar', 'maps-native-onboarding-trace-diagnostic.tar',
		'maps-onboarding-framework-diagnostic.tar', 'maps-native-heartbeat-diagnostic.tar',
		'maps-browser-poll.tar', 'maps-account-pump.tar', 'maps-application-restrictions.tar', 'maps-account-handoff.tar', 'maps-auth-exception.tar', 'maps-auth-worker.tar']
		|| before.len != config.modules.len { return error('exact original twenty-four-module set differs') }
	if stage.command(root, 'original-limine', [root + '/tools/mtype', '-i', base_root + '/boot.img', '::/boot/limine.conf'])! != original {
		return error('source media configuration differs')
	}
	check_disk(root, 'original-limine', true, mut disk, mut disk_samples)!
	audit_modules(root, 'original', base_root + '/boot.img', config.modules, before, mut disk, mut disk_samples)!
	original_entries := original_inodes(deps)!
	copy_file(framework_root + '/api-impl.jar', root + '/payload/' + jar_path, 0o644)!
	copy_file(framework_root + '/classes.dex', root + '/payload/' + dex_path, 0o644)!
	copy_file(successor_native_root + '/native/libvinix-android-native.so', root + '/payload/' + native_path, 0o755)!
	copy_file(framework_root + '/build.json', root + '/payload/' + headless + '/framework-build.json', 0o644)!
	copy_file(framework_root + '/sha256.json', root + '/payload/' + headless + '/framework-sha256.json', 0o644)!
	if stage.hash(headless_base + headless + '/guest-inputs.json')! != old_headless_pin { return error('retained headless input identity differs') }
	old_headless := read_json(headless_base + headless + '/guest-inputs.json')!
	write_json(root + '/payload/' + headless + '/guest-inputs.json', as_json(repin_headless(old_headless)!)!)!
	replacements := replacement_pins(root + '/payload')!
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
	check_disk(root, 'payload', true, mut disk, mut disk_samples)!
	println('MAPS-BINDER-IDENTITY cloning media and appending seven files')
	for name in ['boot.img', 'efivars.fd'] {
		if C.clonefile((base_root + '/' + name).str, (root + '/' + name).str, 0) != 0 { return error('fresh APFS clone failed') }
		check_disk(root, 'clone-' + name + '-created', true, mut disk, mut disk_samples)!
		if stage.hash(root + '/' + name)! != base_files[name]! { return error('fresh APFS media clone differs') }
		check_disk(root, 'clone-' + name + '-verified', false, mut disk, mut disk_samples)!
	}
	stage.command_expected(root, 'overlay-absent', [root + '/tools/mdir', '-i', root + '/boot.img', '::/boot/' + overlay], 1)!
	mut sources := map[string]string{}
	for entry in entries.filter(it.kind == 'regular') { sources[entry.name] = root + '/payload/' + entry.name }
	stage.write_overlay(root + '/' + overlay, sources, entries)!
	stage.verify_overlay(root + '/' + overlay, entries)!
	check_disk(root, 'overlay', true, mut disk, mut disk_samples)!
	stage.command(root, 'install-overlay', [root + '/tools/mcopy', '-i', root + '/boot.img', root + '/' + overlay, '::/boot/' + overlay])!
	check_disk(root, 'install-overlay', true, mut disk, mut disk_samples)!
	stage.command(root, 'install-limine', [root + '/tools/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	check_disk(root, 'install-limine', true, mut disk, mut disk_samples)!
	if stage.command(root, 'readback-limine', [root + '/tools/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated { return error('diagnostic media configuration differs') }
	check_disk(root, 'readback-limine', true, mut disk, mut disk_samples)!
	mut media_pins := before.clone()
	media_pins[overlay] = stage.hash(root + '/' + overlay)!
	mut final_modules := config.modules.clone()
	final_modules << overlay
	mut after := audit_modules(root, 'readback', root + '/boot.img', final_modules, media_pins, mut disk, mut disk_samples)!
	after.delete(overlay)
	println('MAPS-BINDER-IDENTITY rechecking complete inputs')
	for path, pin in deps { stage.load_inventory(path, pin)! }
	stage.recheck(controller)!
	stage.recheck(broker)!
	stage.recheck(framework)!
	stage.recheck(successor_native)!
	if stage.load_inventory(base_root, base_seal)! != base_files { return error('immutable worker stage changed') }
	for path, pin in inputs { if stage.hash(path)! != pin { return error('source/tool changed: ' + path) } }
	if payload_inventory(root + '/payload')! != entries { return error('payload changed') }
	verify_deployment_delta(old_deployment, read_json(root + '/payload/' + deployment_path)!, replacements)!
	if read_json(root + '/payload/' + headless + '/guest-inputs.json')! != repin_headless(old_headless)! { return error('headless role input delta changed') }
	check_disk(root, 'complete-recheck', false, mut disk, mut disk_samples)!
	write_json(root + '/stage.json', {
		'kind': json2.Any('vinix-maps-binder-identity-v1'), 'format': json2.Any(1),
		'scope': json2.Any('Binder clear/restore routes the active authenticator worker identity; retained controller/broker/browser and headless launch roles. No Google login proof.'),
		'source_revision': json2.Any(revision), 'base_root': json2.Any(base_root), 'base_manifest_sha256': json2.Any(base_seal),
		'controller_build_root': json2.Any(controller_root), 'controller_manifest_sha256': json2.Any(controller_seal),
		'controller_sha256': json2.Any(controller_pin), 'retained_controller_manifest_sha256': base['retained_controller_manifest_sha256']!,
		'broker_build_root': json2.Any(broker_root), 'broker_manifest_sha256': json2.Any(broker_seal), 'broker_sha256': json2.Any(broker_pin),
		'retained_broker_manifest_sha256': json2.Any(launch_seal),
		'framework_build_root': json2.Any(framework_root),
		'retained_framework_manifest_sha256': json2.Any(generator_framework_seal),
		'framework_jar_sha256': json2.Any(jar_pin), 'framework_dex_sha256': json2.Any(dex_pin),
		'native_build_root': json2.Any(successor_native_root), 'native_build_sha256': json2.Any(successor_native_build_pin), 'native_sha256': json2.Any(successor_native_pin),
		'retained_native_manifest_sha256': json2.Any(native_seal),
		'native_source_delta': as_json({'build-support/android/nativews/account_service.v': account_source_pin, 'build-support/android/nativews/bindings.txt': bindings_pin})!,
		'framework_source_delta': as_json(framework_source_delta())!, 'generated_jni_sha256': json2.Any(generated_pin),
		'browser_client_build_root': base['browser_client_build_root']!, 'browser_client_manifest_sha256': json2.Any(browser_seal), 'browser_client_sha256': json2.Any(browser_pin),
		'framework_manifest_sha256': json2.Any(framework_seal), 'native_manifest_sha256': json2.Any(successor_native_seal),
		'retained_launch_manifest_sha256': json2.Any(launch_seal),
		'deployment_input_delta': as_json(replacements)!,
		'deployment_top_level_delta': as_json(['inputs_sha256', 'framework_manifest_sha256', 'native_manifest_sha256'])!,
		'headless_input_delta': as_json({'/' + jar_path: jar_pin})!, 'headless_top_level_delta': as_json(['inputs_sha256'])!,
		'inputs_sha256': as_json(inputs)!,
		'original_modules_sha256': as_json(before)!, 'preserved_modules_sha256': as_json(after)!,
		'overlay_inventory': as_json(entries)!, 'overlay_sha256': json2.Any(stage.hash(root + '/' + overlay)!),
		'limine_before_sha256': json2.Any(stage.hash(root + '/limine-before.conf')!), 'limine_after_sha256': json2.Any(stage.hash(root + '/limine-after.conf')!),
		'staged_boot_sha256': json2.Any(stage.hash(root + '/boot.img')!), 'staged_efivars_sha256': json2.Any(stage.hash(root + '/efivars.fd')!),
		'guest_terminal_command': json2.Any('/opt/vinix-maps-account/bin/maps-account-guest --broker --trace-tls'),
		'disk_reserve_bytes': as_json(disk_reserve)!, 'disk_growth_limit_bytes': as_json(disk_growth)!,
		'disk_growth_policy': json2.Any('Cumulative observed volume drops during writable phases plus 1 MiB per exact 68-byte module digest receipt; explicit read-only audits refresh baseline with reserve enforced. No refunds.'),
		'disk_digest_receipt_charge_bytes': as_json(disk.digest_receipt_charged)!, 'disk_charged_growth_bytes': as_json(disk.charged)!,
		'disk_available_samples_bytes': as_json(disk_samples)!,
		'disk_sample_argv': as_json(['/usr/bin/env', 'LC_ALL=C', '/bin/df', '-kP', os.dir(root)])!,
	})!
	check_disk(root, 'receipt-complete', true, mut disk, mut disk_samples)!
	mut files := map[string]string{}
	collect(root, '', mut files)!
	check_disk(root, 'output-inventory', false, mut disk, mut disk_samples)!
	write_json(root + '/sha256.json', as_json(files)!)!
	check_disk(root, 'seal-complete', true, mut disk, mut disk_samples) or {
		os.rm(root + '/sha256.json') or { return error('post-seal disk check failed and completion seal removal failed: ' + err.msg()) }
		return err
	}
	println('MAPS-BINDER-IDENTITY-STAGE PASS ' + root + ' seal=' + stage.hash(root + '/sha256.json')!)
}
fn self_test() ! {
	exact_profile(base_seal, successor_native_seal, successor_native_pin)!
	mut consumed_before := consumed_framework_before()
	mut consumed_after := consumed_framework_after()
	consumed_before['unchanged'] = 'a'.repeat(64)
	consumed_after['unchanged'] = 'a'.repeat(64)
	exact_consumed_delta(consumed_before, consumed_after)!
	for path in consumed_after.keys() {
		mut bad := consumed_after.clone()
		bad[path] = '0'.repeat(64)
		if _ := exact_consumed_delta(consumed_before, bad) { return error('unexpected consumed identity accepted') }
		bad.delete(path)
		if _ := exact_consumed_delta(consumed_before, bad) { return error('missing consumed identity accepted') }
	}
	mut extra_consumed := consumed_after.clone()
	extra_consumed['unreviewed'] = 'b'.repeat(64)
	if _ := exact_consumed_delta(consumed_before, extra_consumed) { return error('unreviewed consumed addition accepted') }
	broker_helper := os.getwd() + '/tests/native-android-tools/androidtools/framework_account_broker_context.v'
	helper_before := {broker_helper: helper_broker_before_pin, '/unchanged': 'a'.repeat(64)}
	helper_after := {broker_helper: helper_broker_after_pin, '/unchanged': 'a'.repeat(64)}
	exact_helper_delta('builder', helper_before, helper_after)!
	exact_helper_delta('native-generator', helper_before, helper_before)!
	if _ := exact_helper_delta('native-generator', helper_before, helper_after) { return error('builder helper changes accepted in native generator') }
	for path in helper_after.keys() {
		mut bad := helper_after.clone()
		bad[path] = '0'.repeat(64)
		if _ := exact_helper_delta('builder', helper_before, bad) { return error('unexpected helper identity accepted') }
		bad.delete(path)
		if _ := exact_helper_delta('builder', helper_before, bad) { return error('missing helper identity accepted') }
	}
	mut extra_helper := helper_after.clone()
	extra_helper['/unreviewed'] = 'b'.repeat(64)
	if _ := exact_helper_delta('builder', helper_before, extra_helper) { return error('unreviewed helper addition accepted') }
	old_jni := '@[translated]\nmodule atlframework\n\n@[export: \'Java_retained__\']\nfn ws_binding_0(e voidptr, this voidptr) i32 {\n    unsafe {\n return 7\n }\n}\n'
	mut new_jni := old_jni
	mut ordinal := 1
	mut symbols := identity_jni_additions().keys()
	symbols.sort()
	for symbol in symbols {
		new_jni += "\n@[export: '" + symbol + "']\nfn ws_binding_" + ordinal.str() + identity_jni_additions()[symbol]!
		ordinal++
	}
	exact_jni_delta(old_jni, new_jni)!
	// Insertion before a retained export shifts its generated ordinal while all
	// retained ABI/body bytes stay exact, matching the real binding insertion.
	shifted_additions := new_jni.all_after(old_jni).replace('ws_binding_1(', 'ws_binding_0(').replace('ws_binding_2(', 'ws_binding_1(')
	retained_export := old_jni.all_after(old_jni.all_before("\n@[export: '")).replace('ws_binding_0(', 'ws_binding_2(')
	shifted_jni := new_jni.all_before("\n@[export: '") + shifted_additions + retained_export
	exact_jni_delta(old_jni, shifted_jni)!
	for bad in [new_jni.replace('return 7', 'return 8'), new_jni.replace(') i64 {', ') i32 {'),
		new_jni.replace('return ws_auth_clear_identity()', 'return 0'),
		new_jni.replace('ws_binding_1(', 'ws_binding_17('), new_jni.replace('Java_retained__', 'Java_replaced__'),
		new_jni + "\n@[export: 'Java_extra__']\nfn ws_binding_3(e voidptr, this voidptr) i32 {\n    unsafe {\n return 9\n }\n}\n"] {
		if _ := exact_jni_delta(old_jni, bad) { return error('unreviewed JNI export ABI body or ordinal accepted') }
	}
	anchor := 'android/atl/VinixAccountBrokerContext|checkPermission|return ws_auth_permission(e,p0,p1,p2)\n'
	added_bindings := anchor + 'android/atl/VinixAccountBrokerContext|clearCallingIdentity|return ws_auth_clear_identity()\n' +
		'android/atl/VinixAccountBrokerContext|restoreCallingIdentity|return u8(ws_auth_restore_identity(p0))\n'
	exact_bindings_delta(anchor, added_bindings)!
	for bad in [anchor, added_bindings.replace('return ws_auth_clear_identity()', 'return 0'), added_bindings + 'unreviewed\n'] {
		if _ := exact_bindings_delta(anchor, bad) { return error('unreviewed binding delta accepted') }
	}
	for values in [[native_seal, successor_native_pin], [successor_native_seal, native_pin], ['', successor_native_pin]] {
		if _ := exact_profile(base_seal, values[0], values[1]) { return error('obsolete or mismatched native accepted') }
	}
	header := 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
	if available_bytes(header + '/dev/disk3s5 1948404040 1912096216 4311392 100% /System/Volumes/Data\n')! != u64(4311392) * 1024 { return error('df value differs') }
	for malformed in ['', header, header + '/dev/disk 100 1 99 bogus /\n', header + '/dev/disk 100 101 1 100% /\n',
		header + '/dev/disk 100 1 -1 100% /\n', header + '/dev/disk 100 1 18014398509481984 100% /\n'] {
		if _ := available_bytes(malformed) { return error('malformed df accepted') }
	}
	if disk_blocks('18014398509481983')! != u64(0xffffffffffffffff) / 1024 { return error('df boundary rejected') }
	start := disk_reserve + disk_growth + 32
	mut budget := DiskBudget{available: start + disk_growth}
	update_budget(start, false, mut budget)!
	if budget.charged != 0 { return error('read-only audit charged unrelated drift') }
	update_budget(start - 31, true, mut budget)!
	if budget.charged != 31 { return error('writable growth not charged') }
	charge_audit(25, mut budget)!
	if budget.charged != 31 + 25 * digest_receipt_charge || budget.digest_receipt_charged != 25 * digest_receipt_charge { return error('audit receipt charge differs') }
	update_budget(start + 100, false, mut budget)!
	if budget.charged != 31 + 25 * digest_receipt_charge { return error('baseline refresh refunded charge') }
	for count in [0, 26, -1] { if _ := charge_audit(count, mut budget) { return error('unbounded audit accepted') } }
	mut full := DiskBudget{available: start, charged: disk_growth - 1}
	update_budget(start - 1, true, mut full)!
	if full.charged != disk_growth { return error('growth boundary differs') }
	if _ := update_budget(start - 2, true, mut full) { return error('cumulative growth bypassed') }
	if _ := update_budget(disk_reserve - 1, false, mut full) { return error('read-only reserve bypassed') }
	if _ := charge_audit(1, mut full) { return error('audit charge bypassed growth ceiling') }
	if _ := exact_profile(native_seal, successor_native_seal, successor_native_pin) { return error('wrong base accepted') }
	old := {'a': json2.Any('old'), 'b': json2.Any('same')}
	exact_delta(old, {'a': json2.Any('new'), 'b': json2.Any('same')}, {'a': json2.Any('new')})!
	for bad in [{'a': json2.Any('new')}, {'a': json2.Any('new'), 'b': json2.Any('bad')},
		{'a': json2.Any('new'), 'b': json2.Any('same'), 'c': json2.Any('extra')}] {
		if _ := exact_delta(old, bad, {'a': json2.Any('new')}) { return error('unsafe receipt delta accepted') }
	}
	if _ := exact_delta(old, old, {'a': json2.Any('old')}) { return error('missing receipt change accepted') }
	mut deployment := {
		'kind': json2.Any('vinix-maps-account-deployment-v1'), 'framework_manifest_sha256': json2.Any(generator_framework_seal),
		'native_manifest_sha256': json2.Any(native_seal), 'launch_manifest_sha256': json2.Any(launch_seal),
		'browser_client_manifest_sha256': json2.Any(browser_seal),
		'inputs_sha256': as_json({'/' + controller_path: controller_pin, '/' + alias_path: controller_pin, '/' + broker_path: broker_pin,
			'/' + jar_path: old_jar_pin, '/' + dex_path: old_dex_pin, '/' + native_path: native_pin, '/unchanged': native_seal,
			'/' + headless + '/framework-build.json': old_framework_build_pin, '/' + headless + '/framework-sha256.json': generator_framework_seal,
			'/' + headless + '/guest-inputs.json': old_headless_pin})!,
	}
	replacements := {'/' + native_path: successor_native_pin, '/' + jar_path: jar_pin, '/' + dex_path: dex_pin,
		'/' + headless + '/framework-build.json': framework_build_pin, '/' + headless + '/framework-sha256.json': framework_seal,
		'/' + headless + '/guest-inputs.json': 'c'.repeat(64)}
	updated := repin_deployment(deployment, replacements)!
	mut checked_paths := changed_paths()
	checked_paths << [controller_path, alias_path, broker_path, jar_path, dex_path, 'unchanged',
		headless + '/framework-build.json', headless + '/framework-sha256.json', headless + '/guest-inputs.json']
	for name in checked_paths {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		mut pins := json2.decode[map[string]string](json2.encode(bad['inputs_sha256']!))!
		pins['/' + name] = '0'.repeat(64)
		bad['inputs_sha256'] = as_json(pins)!
		if _ := verify_deployment_delta(deployment, bad, replacements) { return error('unrelated or missing deployment input delta accepted') }
	}
	mut extra := json2.decode[map[string]json2.Any](json2.encode(updated))!
	extra['extra'] = json2.Any('unexpected')
	if _ := verify_deployment_delta(deployment, extra, replacements) { return error('extra deployment key accepted') }
	mut wrong_native := json2.decode[map[string]json2.Any](json2.encode(updated))!
	wrong_native['framework_manifest_sha256'] = json2.Any(controller_pin)
	if _ := verify_deployment_delta(deployment, wrong_native, replacements) { return error('extra deployment identity delta accepted') }
	for path in [controller_path, alias_path, broker_path, jar_path, dex_path, native_path] {
		mut pins := json2.decode[map[string]string](json2.encode(deployment['inputs_sha256']!))!
		pins['/' + path] = '0'.repeat(64)
		mut bad := deployment.clone()
		bad['inputs_sha256'] = as_json(pins)!
		if _ := repin_deployment(bad, replacements) { return error('mismatched prior input accepted') }
	}
	deployment['native_manifest_sha256'] = json2.Any(controller_pin)
	if _ := repin_deployment(deployment, replacements) { return error('unrelated native identity accepted') }
	old_headless := {'inputs_sha256': as_json(headless_inputs())!}
	mut headless_expected := headless_inputs()
	headless_expected['/' + jar_path] = jar_pin
	if repin_headless(old_headless)! != {'inputs_sha256': as_json(headless_expected)!} { return error('headless JAR replacement differs') }
	for path in headless_inputs().keys() {
		mut bad := headless_inputs()
		bad[path] = '0'.repeat(64)
		if _ := repin_headless({'inputs_sha256': as_json(bad)!}) { return error('changed retained headless role input accepted') }
	}
	mut allowed := changed_paths()
	allowed << deployment_path
	exact_regular_names(allowed)!
	for bad in [allowed[..1], []string{}, [native_path, deployment_path, 'opt/escape'], [native_path, native_path]] {
		if _ := exact_regular_names(bad) { return error('wrong payload set accepted') }
	}
	plan := [stage.Entry{name: native_path, kind: 'regular', mode: 0o755}]
	good := [stage.Entry{name: 'opt', kind: 'directory', mode: 0o755}, stage.Entry{name: native_path, kind: 'regular', mode: 0o755}]
	if inherited_modes(good, plan)![native_path]! != 0o755 { return error('executable mode lost') }
	mut legacy := good.clone()
	legacy << stage.Entry{name: native_path, kind: 'regular', mode: 0o644}
	if inherited_modes(legacy, plan)![native_path]! != 0o755 { return error('first inode lost after historical nonexecutable overlay') }
	for bad in [stage.Entry{name: 'opt', kind: 'symlink', mode: 0o755}, stage.Entry{name: native_path, kind: 'regular', mode: 0o777},
		stage.Entry{name: native_path, kind: 'regular', mode: 0o4755}] {
		mut original := good.clone()
		original << bad
		if _ := inherited_modes(original, plan) { return error('unsafe old inode accepted') }
	}
	if _ := inherited_modes([]stage.Entry{}, plan) { return error('missing original file accepted') }
	if _ := inherited_modes([stage.Entry{name: native_path, kind: 'regular', mode: 0o644}], plan) { return error('nonexecutable first native inode accepted') }
	println('MAPS-BINDER-IDENTITY-STAGE SELFTEST PASS exact seven-file framework/native delta retained roles JNI ABIs helper closure modes disk bounds')
}
fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 2 && os.args[1] == '--audit-native' { audit_native_inputs() or { eprintln(err); exit(1) }; return }
	if os.args.len == 2 && os.args[1] == '--enumerate-native-helpers' { enumerate_native_helpers() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != '--prepare' { eprintln('usage: maps-binder-identity-stage --prepare FRESH_EXTERNAL_OUTPUT | --self-test | --audit-native | --enumerate-native-helpers'); exit(2) }
	run(os.args[2]) or { eprintln(err); exit(1) }
}
