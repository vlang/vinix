// SPDX-License-Identifier: GPL-2.0-or-later
// Exact UserManager API repair over the sealed account pump diagnostic image.
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
const base_root = state_root + '/maps-account-pump-r2'
const base_seal = 'd432d4cf4fa1522b07cb2b7ada498a32d375d44cf7830e50858681fcf118035c'
const browser_stage_root = state_root + '/maps-browser-poll-r3'
const browser_stage_seal = 'f27b08e45994fb2e9cf2c2aac695e73c62f17e0b4785fdb310cbebb1f54ac297'
const heartbeat_root = state_root + '/maps-native-heartbeat-r1'
const heartbeat_seal = '70ea9f41ad045541066dec75a1ddcdc1e44efefd8d35ffb2e4414a77e2235b32'
const framework_stage_root = state_root + '/maps-onboarding-framework-r1'
const framework_stage_seal = 'fcba5511b0cc2d305ee6e3ba48081bf6bc40fd6117cd91abc691fb2fd7ad01cf'
const native_stage_root = state_root + '/maps-native-onboarding-trace-r3'
const native_stage_seal = '96b90172e338080ff50bf0e1188bdefc1f50e61fe3ad654593dfbac4d918d741'
const onboarding_root = state_root + '/maps-onboarding-trace-r2'
const onboarding_seal = 'de315f3f5f0120efbd1368a47e11db945aa9212160fc7e1ff351e522e9435be5'
const broadcast_root = state_root + '/maps-broadcast-result-r2'
const broadcast_seal = '98522d60a7627927b7ee6b861db502b6574e3d6ab14fdecb09e2da38b2f441de'
const startup_root = state_root + '/maps-startup-r1'
const startup_seal = 'f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332'
const controller_stage_root = state_root + '/maps-controller-r1'
const controller_stage_seal = '3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a'
const controller_root = state_root + '/maps-account-guest-build-2026-10-27-r8'
const controller_seal = 'c2c08ed987052e5170f9b90cd4af7f9de6fcb4e98684def4dc5e28f058409b4f'
const controller_pin = 'e15e14d135de930f29caf6b8708adc83390c3e12fdb37d368edb6d5cb1899bcf'
const generator_framework_root = state_root + '/combined-account-webview-broadcast-result-framework-2026-10-27-r1'
const generator_framework_seal = '21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046'
const old_framework_root = state_root + '/combined-account-webview-onboarding-framework-2026-10-27-r1'
const old_framework_seal = 'bfd56090052ec6612179741c5ad88ecfe7fad83027a38cc5949c13892abd1c42'
const old_framework_build_pin = '8ec80f25e35edd176ae333fd78d5e5503ba3f83eac3bf4d7191eacf33120ac60'
const framework_root = state_root + '/combined-account-webview-application-restrictions-framework-2026-10-28-r1'
// Exact one-class producer, complete seal and independent delta checks passed.
const framework_seal = '8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15'
const framework_build_pin = 'a2a31c49975032e4051a2cb9a737d5bdd31a57e7472bafc60411f723c2ebea3a'
const service_query_root = state_root + '/maps-service-query-r1'
const memory_root = state_root + '/maps-controller-memory-r1'
const direct_boot_root = state_root + '/maps-direct-boot-r1'
const context_root = state_root + '/maps-context-storage-r1'
const old_native_root = state_root + '/current-native-build-2026-10-27-onboarding-r5'
const old_native_seal = '05baf5d011337d54aab26f6cc3c535f801221d51aceb966ebc9442d88b5fd6b8'
const heartbeat_native_root = state_root + '/current-native-build-2026-10-27-heartbeat-r1'
const heartbeat_native_seal = '6619a4cd8dcc7e30aa43120494b874f230d1e9b8ee5c5b756e25fcf5e5148eae'
const heartbeat_native_pin = '3ac3ec1a026a409ec52b7973d9dcc4593bd5d266fc2c6e77fc5d5c1a88e439d9'
const native_root = state_root + '/current-native-build-2026-10-28-account-pump-r1'
const native_seal = 'a6a7f207b07083726b9708eea2c67290bcf8baced755651c50bdc205cd7097cd'
const native_pin = 'cce3eb926d3bc8b2b3c9e9a4f0d42cc4ab6bfdc23b0532beb2c42f5f9b384791'
const native_build_pin = '2802af6636568126359765ac00d09b0771f0b4d22a09c45db55dfe21ba557924'
const browser_root = state_root + '/current-browser-build-2026-10-27-poll-r1'
const browser_seal = 'fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62'
const browser_pin = '16def2047bf7605a23d949ff7b6b56bc56dcece038136553a98a0524b26ded1a'
const old_browser_root = state_root + '/current-browser-build-2026-10-26-r2'
const old_browser_seal = 'af2373af972966cc72b2b8eb8ba90d73063fad5d24a4a76b29ce8daff78062f3'
const webkit_seal = 'bc9f6e776d0c81bb1bca160ab1e4289e31db9f2a05983e00ba0fcb42be86244d'
const browser_path = 'opt/vinix-android-aarch64/usr/lib/libvinix-android-browser.so'
const launch_root = state_root + '/current-launch-build-2026-10-26-r13'
const launch_seal = '920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be'
const headless = 'opt/vinix-headless-service'
const native_path = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const dex_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/classes.dex'
const old_jar_pin = 'e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd'
const old_dex_pin = '12e4ad659e61941f0f37ea46dbe1bae8b97bc4ca874bbeaa4841e8832d2cc854'
const jar_pin = 'd4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32'
const dex_pin = '45c25a081702f299ae3f8a883347d624cae6ab4bda3b5f2538be89421cdf32ab'
const controller_path = 'opt/vinix-maps-account/bin/maps-account-guest'
const alias_path = 'usr/bin/run-android-calculator'
const deployment_path = 'opt/vinix-maps-account/build.json'
const overlay = 'maps-application-restrictions.tar'
const disk_reserve_bytes = u64(1024) * 1024 * 1024
const disk_growth_limit_bytes = u64(512) * 1024 * 1024
// Charge a full MiB for each exact 68-byte receipt; this is a budget allocation,
// not a claim to measure APFS physical allocation.
const digest_receipt_charge_bytes = u64(1024) * 1024
const retained = {
	'tests/native-android-ws/maps-application-restrictions-stage.v': carry($embed_file(@FILE))
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
fn disk_budget(start u64, available u64, charged u64) !u64 {
	drop := if available < start { start - available } else { u64(0) }
	if available < disk_reserve_bytes || charged > disk_growth_limit_bytes
		|| drop > disk_growth_limit_bytes - charged {
		return error('preparation disk budget exceeded: 1 GiB reserve and 512 MiB growth limit required')
	}
	return charged + drop
}
fn disk_blocks(value string) !u64 {
	if value == '' || value.len > 17 { return error('invalid df block count') }
	mut result := u64(0)
	limit := u64(0xffff_ffff_ffff_ffff) / 1024
	for digit in value.bytes() {
		if digit < `0` || digit > `9` || result > (limit - u64(digit - `0`)) / 10 {
			return error('invalid or overflowing df block count')
		}
		result = result * 10 + u64(digit - `0`)
	}
	return result
}
fn parse_disk_available(output string) !u64 {
	lines := output.trim_space().split_into_lines()
	if output.len > 8192 || lines.len != 2
		|| lines[0].fields() != ['Filesystem', '1024-blocks', 'Used', 'Available', 'Capacity', 'Mounted', 'on'] {
		return error('unexpected df -kP output')
	}
	fields := lines[1].fields()
	if fields.len < 6 || !fields[0].starts_with('/') || !fields[5].starts_with('/')
		|| !fields[4].ends_with('%') { return error('invalid df filesystem row') }
	total := disk_blocks(fields[1])!
	used := disk_blocks(fields[2])!
	available := disk_blocks(fields[3])!
	if total == 0 || used > total || available > total { return error('inconsistent df counts') }
	disk_blocks(fields[4][..fields[4].len - 1])!
	return available * 1024
}
fn disk_available(path string) !u64 {
	// Bootstrap os.disk_usage uses an incompatible Darwin statvfs layout.
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
	if child.code != 0 || stderr != '' { return error('df failed: ' + stderr) }
	return parse_disk_available(stdout)
}
struct DiskBudget {
mut:
	available u64
	charged u64
	digest_receipt_charged u64
}
fn disk_update(available u64, writing bool, mut budget DiskBudget) ! {
	budget.charged = disk_budget(if writing { budget.available } else { available }, available, budget.charged)!
	budget.available = available
}
fn disk_sample(root string, label string, writing bool, mut budget DiskBudget, mut samples map[string]u64) ! {
	available := disk_available(os.dir(root))!
	samples[label] = available
	// Only these explicitly read-only audits may refresh the volume baseline.
	// Drops during writable phases stay cumulatively charged, including other writers.
	disk_update(available, writing, mut budget)!
	println('MAPS-APPLICATION-RESTRICTIONS disk ' + label + ' available_bytes=' + available.str() + ' charged_growth_bytes=' + budget.charged.str())
}
fn charge_digest_receipts(count int, mut budget DiskBudget) ! {
	if count < 1 || count > 21 { return error('bounded digest audit requires one to twenty-one receipts') }
	charge := u64(count) * digest_receipt_charge_bytes
	if budget.charged > disk_growth_limit_bytes || charge > disk_growth_limit_bytes - budget.charged {
		return error('digest receipts exceed cumulative write budget')
	}
	budget.charged += charge
	budget.digest_receipt_charged += charge
}
fn audit_modules(root string, label string, image string, names []string, expected map[string]string,
	mut budget DiskBudget, mut samples map[string]u64) !map[string]string {
	if names.len < 1 || names.len > 21 || names.len != expected.len { return error('bounded exact module audit required') }
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
	// These operations read media and write only the validated digest receipts.
	// Charge those writes independently, excluding unrelated volume drift.
	charge_digest_receipts(names.len, mut budget)!
	disk_sample(root, label + '-module-audit', false, mut budget, mut samples)!
	return pins
}
fn exact_profile(base string, manifest string, jar string, dex string) ! {
	if base != base_seal || manifest != framework_seal || jar != jar_pin || dex != dex_pin
		|| !stage.valid_pin(base) || !stage.valid_pin(manifest) || !stage.valid_pin(jar) || !stage.valid_pin(dex)
		|| !stage.valid_pin(framework_build_pin)
		|| manifest == old_framework_seal || jar == old_jar_pin || dex == old_dex_pin {
		return error('exact application restrictions framework profile differs; reviewed producer pins required')
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
	return [jar_path, dex_path, headless + '/framework-build.json', headless + '/framework-sha256.json', headless + '/guest-inputs.json']
}
fn headless_inputs() map[string]string {
	return {
		'/opt/vinix-android-aarch64/usr/bin/run-android': '1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112'
		'/opt/vinix-android-aarch64/usr/bin/vinix-android-native': 'b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d'
		// The account-pump overlay deliberately retained this role receipt.
		'/' + native_path: heartbeat_native_pin
		'/' + jar_path: old_jar_pin
		'/' + headless + '/bin/headless-service-controller': '70f23b12fb5a770587bfcebcf33ed1320fe050399f08bd256362a037f24eb0b6'
		'/' + headless + '/bin/headless-service-guest': 'd518cfc5145924479b5ad630aac2a3d3ef7dcea66f53515c03df03735e88ce05'
		'/' + headless + '/fixture.apk': '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
	}
}
fn repin_headless(original map[string]json2.Any, pin string) !map[string]json2.Any {
	if !stage.valid_pin(pin) || pin != jar_pin || pin == old_jar_pin || original.len != 1 { return error('exact framework headless replacement required') }
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	if old != headless_inputs() { return error('exact inherited seven-input headless contract differs') }
	mut updated := old.clone()
	updated['/' + jar_path] = pin
	exact_delta(as_json(old)!.as_map(), as_json(updated)!.as_map(), {'/' + jar_path: json2.Any(pin)})!
	return {'inputs_sha256': as_json(updated)!}
}
// Preserve the audited startup ABI pair while replacing only framework inputs.
fn exact_service_abi(launch string, native string, manifest string, library string) ! {
	if launch != 'c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57'
		|| native != 'e2be36f866ac321a7d681112e3514d8b1c8ac06553538758d7c1c220b9f3c72f'
		|| manifest != native_seal || library != native_pin { return error('exact retained seven-argument service ABI differs') }
}
fn service_abi(entry string, implementation string) ! {
	if !entry.contains('type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32')
		|| !entry.contains('launch.action.str, i32(control_fd), i32(ui_fd))')
		|| !implementation.contains('fn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {') {
		return error('native service entry and implementation must use the seven-argument UI ABI')
	}
}
fn repin_deployment(original map[string]json2.Any, replacements map[string]string) !map[string]json2.Any {
	if stage.text_field(original, 'kind')! != 'vinix-maps-account-deployment-v1'
		|| stage.text_field(original, 'framework_manifest_sha256')! != old_framework_seal
		|| stage.text_field(original, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(original, 'launch_manifest_sha256')! != launch_seal
		|| stage.text_field(original, 'browser_client_manifest_sha256')! != browser_seal
		|| stage.text_field(original, 'browser_manifest_sha256')! != webkit_seal {
		return error('retained deployment identity differs')
	}
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	if old['/' + controller_path] or { '' } != controller_pin || old['/' + alias_path] or { '' } != controller_pin
		|| old['/' + native_path] or { '' } != native_pin || old['/' + jar_path] or { '' } != old_jar_pin
		|| old['/' + dex_path] or { '' } != old_dex_pin
		|| old['/' + browser_path] or { '' } != browser_pin { return error('inherited runtime/controller/browser pins differ') }
	mut actual := replacements.keys()
	mut expected := changed_paths().map('/' + it)
	actual.sort()
	expected.sort()
	if actual != expected || replacements['/' + jar_path]! != jar_pin || replacements['/' + dex_path]! != dex_pin
		|| replacements['/' + headless + '/framework-build.json']! != framework_build_pin
		|| replacements['/' + headless + '/framework-sha256.json']! != framework_seal { return error('exact five framework deployment replacements required') }
	mut updated := old.clone()
	mut changes := map[string]json2.Any{}
	for name, pin in replacements {
		if !stage.valid_pin(pin) { return error('invalid deployment input pin') }
		updated[name] = pin
		changes[name] = json2.Any(pin)
	}
	exact_delta(as_json(old)!.as_map(), as_json(updated)!.as_map(), changes)!
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	result['framework_manifest_sha256'] = json2.Any(framework_seal)
	verify_deployment_delta(original, result, replacements)!
	return result
}
fn verify_deployment_delta(original map[string]json2.Any, updated map[string]json2.Any, replacements map[string]string) ! {
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	actual := updated['inputs_sha256'] or { return error('deployment pins removed') }
	exact_delta(as_json(old)!.as_map(), actual.as_map(), as_json(replacements)!.as_map())!
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
			if entry.mode != 0o644 || (entry.name == jar_path && entry.sha256 != jar_pin)
				|| (entry.name == dex_path && entry.sha256 != dex_pin)
				|| (entry.name == headless + '/framework-build.json' && entry.sha256 != framework_build_pin)
				|| (entry.name == headless + '/framework-sha256.json' && entry.sha256 != framework_seal) { return error('payload framework differs from exact producer') }
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
				// An earlier diagnostic TAR used 0644 for this DSO. The first
				// inode must still supply 0755; later regular members only replace bytes.
				legacy_native := target.name == native_path && target.mode == 0o755 && old.mode == 0o644
				if old.kind != target.kind || (old.mode != target.mode && !legacy_native) { return error('unexpected existing destination mode: ' + old.name) }
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
	if selected.len != 38 || selected[controller_root] or { '' } != controller_seal
		|| selected[broadcast_root] or { '' } != broadcast_seal
		|| selected[old_native_root] or { '' } != old_native_seal
		|| selected[launch_root] or { '' } != launch_seal
		|| selected[startup_root] or { '' } != startup_seal
		|| selected[controller_stage_root] or { '' } != controller_stage_seal
		|| selected[old_framework_root] or { '' } != old_framework_seal
		|| selected[onboarding_root] or { '' } != onboarding_seal
		|| selected[native_root] or { '' } != native_seal
		|| selected[generator_framework_root] or { '' } != generator_framework_seal
		|| selected[heartbeat_native_root] or { '' } != heartbeat_native_seal
		|| selected[heartbeat_root] or { '' } != heartbeat_seal
		|| selected[browser_stage_root] or { '' } != browser_stage_seal
		|| selected[native_stage_root] or { '' } != native_stage_seal
		|| selected[framework_stage_root] or { '' } != framework_stage_seal
		|| selected[browser_root] or { '' } != browser_seal
		|| selected[old_browser_root] or { '' } != old_browser_seal
		|| selected[context_root] or { '' } != '6296bcff89e1a6555c803b0ee94f435cbae1f01c37ce97451080612a95fdde2c'
		|| selected[direct_boot_root] or { '' } != 'fa9e552f7faf4aabfcf17821efc442918bab5576ea230d25eb9dcd6788d62285'
		|| selected[memory_root] or { '' } != '944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21'
		|| selected[service_query_root] or { '' } != '4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b' {
		return error('exact inherited complete dependency set differs')
	}
	return selected
}
fn framework_fixture() !map[string]json2.Any {
	return {
		'profile': json2.Any('application-restrictions-2104'), 'baseline_path': json2.Any(old_framework_root),
		'baseline_manifest_sha256': json2.Any(old_framework_seal), 'baseline_api_impl_sha256': json2.Any(old_jar_pin),
		'api_impl_sha256': json2.Any(jar_pin), 'classes_dex_sha256': json2.Any(dex_pin), 'class_count': as_json(2104)!,
		'changed_classes': as_json(['android/os/UserManager.smali'])!,
		'added_classes': as_json([]string{})!,
		'changed_method_counts': as_json({'android/os/UserManager.smali': 0})!,
		'added_method_counts': as_json({'android/os/UserManager.smali': 1})!,
		'added_fields': as_json(map[string][]string{})!,
	}
}
fn verify_framework(value map[string]json2.Any) ! {
	for name, expected in framework_fixture()! {
		if value[name] or { return error('missing application restrictions framework audit field: ' + name) } != expected {
			return error('exact application restrictions framework audit differs: ' + name)
		}
	}
}
fn run(destination string) ! {
	exact_profile(base_seal, framework_seal, jar_pin, dex_pin)!
	root := stage.external(destination)!
	stage.disjoint(root, [base_root, framework_root, os.getwd()])!
	disk_start := disk_available(os.dir(root))!
	if disk_start < disk_reserve_bytes + disk_growth_limit_bytes { return error('preparation requires 1.5 GiB initial free space') }
	mut disk := DiskBudget{available: disk_start}
	mut disk_samples := {'preflight': disk_start}
	println('MAPS-APPLICATION-RESTRICTIONS auditing immutable inputs')
	base_files := stage.load_inventory(base_root, base_seal)!
	base := read_json(base_root + '/stage.json')!
	if stage.text_field(base, 'kind')! != 'vinix-maps-account-pump-v1'
		|| stage.text_field(base, 'base_root')! != browser_stage_root
		|| stage.text_field(base, 'base_manifest_sha256')! != browser_stage_seal
		|| stage.text_field(base, 'controller_build_root')! != controller_root
		|| stage.text_field(base, 'controller_manifest_sha256')! != controller_seal
		|| stage.text_field(base, 'controller_sha256')! != controller_pin
		|| stage.text_field(base, 'framework_manifest_sha256')! != old_framework_seal
		|| stage.text_field(base, 'framework_build_root')! != old_framework_root
		|| stage.text_field(base, 'native_manifest_sha256')! != native_seal
		|| stage.text_field(base, 'native_build_root')! != native_root
		|| stage.text_field(base, 'native_sha256')! != native_pin
		|| stage.text_field(base, 'native_build_sha256')! != native_build_pin
		|| stage.text_field(base, 'browser_client_build_root')! != browser_root
		|| stage.text_field(base, 'browser_client_manifest_sha256')! != browser_seal
		|| stage.text_field(base, 'browser_client_sha256')! != browser_pin
		|| stage.text_field(base, 'retained_launch_manifest_sha256')! != launch_seal {
		return error('exact immutable account pump stage identity differs')
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
	old_framework := stage.load_bundle(old_framework_root, old_framework_seal)!
	if old_framework.files['api-impl.jar']! != old_jar_pin || old_framework.files['classes.dex']! != old_dex_pin
		|| old_framework.files['build.json']! != old_framework_build_pin { return error('retained framework differs') }
	framework := stage.load_bundle(framework_root, framework_seal)!
	verify_framework(framework.receipt)!
	if framework.files['api-impl.jar']! != jar_pin || framework.files['classes.dex']! != dex_pin
		|| framework.files['build.json']! != framework_build_pin { return error('exact successor framework differs') }
	native := stage.load_bundle(native_root, native_seal)!
	generator_framework := stage.load_bundle(generator_framework_root, generator_framework_seal)!
	stage.verify_native(native, generator_framework)!
	if native.files['native/libvinix-android-native.so']! != native_pin
		|| native.files['build.json']! != native_build_pin { return error('exact retained native differs') }
	browser := stage.load_bundle(browser_root, browser_seal)!
	stage.verify_browser_client(browser, map[string]string{})!
	if browser.files['lib/libvinix-android-browser.so']! != browser_pin { return error('exact retained browser differs') }
	launch := stage.load_bundle(launch_root, launch_seal)!
	exact_service_abi(launch.files['abi/headless.v']!, native.files['native/atlframework/headless.v']!, native.seal, native.files['native/libvinix-android-native.so']!)!
	service_abi(os.read_file(launch.root + '/abi/native-entry.v')!, os.read_file(native.root + '/native/atlframework/headless.v')!)!
	inputs[framework_root + '/sha256.json'] = framework_seal
	disk_sample(root, 'inputs-audited', false, mut disk, mut disk_samples)!
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
	inputs['/usr/bin/env'] = stage.hash('/usr/bin/env')!
	inputs['/bin/df'] = stage.hash('/bin/df')!
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
	disk_sample(root, 'retained-source-tools', true, mut disk, mut disk_samples)!
	original := os.read_file(base_root + '/limine-after.conf')!
	config := stage.configure(original, overlay)!
	mut before := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	before['maps-account-pump.tar'] = stage.text_field(base, 'overlay_sha256')!
	if config.modules != ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar',
		'maps372-diagnostics.tar', 'headless-service.tar', 'maps-account.tar', 'protected-storage-diagnostic.tar',
		'maps-controller-diagnostic.tar', 'maps-service-query-diagnostic.tar', 'maps-controller-memory-diagnostic.tar',
		'maps-direct-boot-diagnostic.tar', 'maps-context-storage-diagnostic.tar', 'maps-broadcast-result-diagnostic.tar',
		'maps-onboarding-trace-diagnostic.tar', 'maps-native-onboarding-trace-diagnostic.tar', 'maps-onboarding-framework-diagnostic.tar',
		'maps-native-heartbeat-diagnostic.tar', 'maps-browser-poll.tar', 'maps-account-pump.tar']
		|| before.len != config.modules.len { return error('exact original twenty-module set differs') }
	if stage.command(root, 'original-limine', [root + '/tools/mtype', '-i', base_root + '/boot.img', '::/boot/limine.conf'])! != original {
		return error('source media configuration differs')
	}
	disk_sample(root, 'original-limine', true, mut disk, mut disk_samples)!
	audit_modules(root, 'original', base_root + '/boot.img', config.modules, before, mut disk, mut disk_samples)!
	startup := read_json(startup_root + '/stage.json')!
	r5_root := stage.text_field(startup, 'base_root')!
	mut original_entries := json2.decode[[]stage.Entry](os.read_file(r5_root + '/original-module-inventory.json')!)!
	r5 := read_json(r5_root + '/stage.json')!
	original_entries << json2.decode[[]stage.Entry](json2.encode(r5['overlay_inventory']!))!
	original_entries << json2.decode[[]stage.Entry](json2.encode(startup['overlay_inventory']!))!
	controller_stage := read_json(controller_stage_root + '/stage.json')!
	original_entries << json2.decode[[]stage.Entry](json2.encode(controller_stage['overlay_inventory']!))!
	for ancestor in [service_query_root, memory_root, direct_boot_root, context_root, broadcast_root, onboarding_root,
		native_stage_root, framework_stage_root, heartbeat_root, browser_stage_root] {
		ancestor_stage := read_json(ancestor + '/stage.json')!
		original_entries << json2.decode[[]stage.Entry](json2.encode(ancestor_stage['overlay_inventory']!))!
	}
	original_entries << json2.decode[[]stage.Entry](json2.encode(base['overlay_inventory']!))!
	copy_file(framework_root + '/api-impl.jar', root + '/payload/' + jar_path, 0o644)!
	copy_file(framework_root + '/classes.dex', root + '/payload/' + dex_path, 0o644)!
	for name in ['build.json', 'sha256.json'] { copy_file(framework_root + '/' + name, root + '/payload/' + headless + '/framework-' + name, 0o644)! }
	old_deployment := read_json(base_root + '/payload/' + deployment_path)!
	old_pins := json2.decode[map[string]string](json2.encode(old_deployment['inputs_sha256']!))!
	// Neither browser-poll nor account-pump replaced this role receipt.
	old_headless_path := heartbeat_root + '/payload/' + headless + '/guest-inputs.json'
	if stage.hash(old_headless_path)! != old_pins['/' + headless + '/guest-inputs.json']! { return error('latest sealed headless receipt differs from deployment') }
	write_json(root + '/payload/' + headless + '/guest-inputs.json', as_json(repin_headless(read_json(old_headless_path)!, jar_pin)!)!)!
	mut replacements := map[string]string{}
	for path in changed_paths() { replacements['/' + path] = stage.hash(root + '/payload/' + path)! }
	write_json(root + '/payload/' + deployment_path, as_json(repin_deployment(old_deployment, replacements)!)!)!
	entries_before := payload_inventory(root + '/payload')!
	modes := inherited_modes(original_entries, entries_before)!
	for entry in entries_before { os.chmod(root + '/payload/' + entry.name, int(modes[entry.name]!))! }
	entries := payload_inventory(root + '/payload')!
	write_json(root + '/overlay-plan.json', as_json(entries)!)!
	write_json(root + '/original-inode-modes.json', as_json(modes)!)!
	os.write_file(root + '/limine-before.conf', original)!
	os.write_file(root + '/limine-after.conf', config.updated)!
	disk_sample(root, 'payload', true, mut disk, mut disk_samples)!
	println('MAPS-APPLICATION-RESTRICTIONS cloning media and appending six files')
	for name in ['boot.img', 'efivars.fd'] {
		if C.clonefile((base_root + '/' + name).str, (root + '/' + name).str, 0) != 0 { return error('fresh APFS media clone failed') }
		disk_sample(root, 'clone-' + name + '-created', true, mut disk, mut disk_samples)!
		if stage.hash(root + '/' + name)! != base_files[name]! { return error('fresh APFS media clone differs') }
		disk_sample(root, 'clone-' + name + '-verified', false, mut disk, mut disk_samples)!
	}
	stage.command_expected(root, 'overlay-absent', [root + '/tools/mdir', '-i', root + '/boot.img', '::/boot/' + overlay], 1)!
	mut sources := map[string]string{}
	for entry in entries.filter(it.kind == 'regular') { sources[entry.name] = root + '/payload/' + entry.name }
	stage.write_overlay(root + '/' + overlay, sources, entries)!
	stage.verify_overlay(root + '/' + overlay, entries)!
	disk_sample(root, 'overlay', true, mut disk, mut disk_samples)!
	stage.command(root, 'install-overlay', [root + '/tools/mcopy', '-i', root + '/boot.img', root + '/' + overlay, '::/boot/' + overlay])!
	disk_sample(root, 'install-overlay', true, mut disk, mut disk_samples)!
	stage.command(root, 'install-limine', [root + '/tools/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	disk_sample(root, 'install-limine', true, mut disk, mut disk_samples)!
	if stage.command(root, 'readback-limine', [root + '/tools/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated {
		return error('diagnostic media readback differs')
	}
	disk_sample(root, 'readback-limine', true, mut disk, mut disk_samples)!
	mut media_pins := before.clone()
	media_pins[overlay] = stage.hash(root + '/' + overlay)!
	mut media_modules := config.modules.clone()
	media_modules << overlay
	mut after := audit_modules(root, 'readback', root + '/boot.img', media_modules, media_pins, mut disk, mut disk_samples)!
	after.delete(overlay)
	println('MAPS-APPLICATION-RESTRICTIONS rechecking complete inputs')
	for path, pin in deps { stage.load_inventory(path, pin)! }
	stage.recheck(controller)!
	stage.recheck(native)!
	stage.recheck(old_framework)!
	stage.recheck(generator_framework)!
	stage.recheck(browser)!
	stage.recheck(launch)!
	stage.recheck(framework)!
	if stage.load_inventory(base_root, base_seal)! != base_files { return error('immutable account pump stage changed') }
	for path, pin in inputs { if stage.hash(path)! != pin { return error('source/tool changed: ' + path) } }
	if payload_inventory(root + '/payload')! != entries { return error('payload changed') }
	// Hashing the media reads several GiB; finish it before charging receipt writes.
	overlay_pin := stage.hash(root + '/' + overlay)!
	limine_before_pin := stage.hash(root + '/limine-before.conf')!
	limine_after_pin := stage.hash(root + '/limine-after.conf')!
	boot_pin := stage.hash(root + '/boot.img')!
	efivars_pin := stage.hash(root + '/efivars.fd')!
	disk_sample(root, 'complete-recheck', false, mut disk, mut disk_samples)!
	write_json(root + '/stage.json', {
		'kind': json2.Any('vinix-maps-application-restrictions-v1'), 'format': json2.Any(1),
		'scope': json2.Any('Exact UserManager.getApplicationRestrictions framework API repair; browser polling, account pump native, controllers and launcher retained. No Google login proof.'),
		'source_revision': json2.Any(revision), 'base_root': json2.Any(base_root), 'base_manifest_sha256': json2.Any(base_seal),
		'controller_build_root': json2.Any(controller_root), 'controller_manifest_sha256': json2.Any(controller_seal),
		'controller_sha256': json2.Any(controller_pin), 'native_build_root': json2.Any(native_root),
		'native_sha256': json2.Any(native_pin), 'native_build_sha256': json2.Any(native_build_pin),
		'browser_client_build_root': json2.Any(browser_root),
		'browser_client_manifest_sha256': json2.Any(browser_seal), 'browser_client_sha256': json2.Any(browser_pin),
		'framework_build_root': json2.Any(framework_root),
		'retained_framework_manifest_sha256': json2.Any(old_framework_seal),
		'framework_manifest_sha256': json2.Any(framework_seal), 'native_manifest_sha256': json2.Any(native_seal),
		'retained_launch_manifest_sha256': json2.Any(launch_seal),
		'deployment_input_delta': as_json(replacements)!,
		'deployment_top_level_delta': as_json(['inputs_sha256', 'framework_manifest_sha256'])!,
		'headless_input_delta': as_json({'/' + jar_path: jar_pin})!, 'inputs_sha256': as_json(inputs)!,
		'headless_top_level_delta': as_json(['inputs_sha256'])!,
		'original_modules_sha256': as_json(before)!, 'preserved_modules_sha256': as_json(after)!,
		'overlay_inventory': as_json(entries)!, 'overlay_sha256': json2.Any(overlay_pin),
		'limine_before_sha256': json2.Any(limine_before_pin), 'limine_after_sha256': json2.Any(limine_after_pin),
		'staged_boot_sha256': json2.Any(boot_pin), 'staged_efivars_sha256': json2.Any(efivars_pin),
		'guest_terminal_command': json2.Any('/opt/vinix-maps-account/bin/maps-account-guest --broker --trace-onboarding'),
		'disk_reserve_bytes': as_json(disk_reserve_bytes)!, 'disk_growth_limit_bytes': as_json(disk_growth_limit_bytes)!,
		'disk_growth_policy': json2.Any('Cumulative observed volume drops during writable phases plus 1 MiB per exact 68-byte module digest receipt; explicit read-only media/input audits and output inventory refresh baseline with reserve enforced. No refunds.'),
		'disk_digest_receipt_charge_bytes': as_json(disk.digest_receipt_charged)!,
		'disk_charged_growth_bytes': as_json(disk.charged)!,
		'disk_available_samples_bytes': as_json(disk_samples)!,
		'disk_sample_argv': as_json(['/usr/bin/env', 'LC_ALL=C', '/bin/df', '-kP', os.dir(root)])!,
	})!
	disk_sample(root, 'receipt-complete', true, mut disk, mut disk_samples)!
	mut files := map[string]string{}
	collect(root, '', mut files)!
	disk_sample(root, 'output-inventory', false, mut disk, mut disk_samples)!
	write_json(root + '/sha256.json', as_json(files)!)!
	disk_sample(root, 'seal-complete', true, mut disk, mut disk_samples)!
	println('MAPS-APPLICATION-RESTRICTIONS-STAGE PASS ' + root + ' seal=' + stage.hash(root + '/sha256.json')!)
}
fn self_test() ! {
	header := 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
	if parse_disk_available(header + '/dev/disk3s5 1948404040 1912096216 4311392 100% /System/Volumes/Data\n')! != u64(4311392) * 1024 {
		return error('df sample parsed incorrectly')
	}
	for bad in ['', header, header + '/dev/disk 10 1 -1 1% /data\n',
		header + '/dev/disk 10 1 11 1% /data\n', header + '/dev/disk 10 11 1 1% /data\n',
		header + '/dev/disk 10 1 1x 1% /data\n', header + '/dev/disk 18014398509481984 1 1 1% /data\n',
		header + '/dev/disk 10 1 1 1% /data\nextra\n', header.replace('1024-blocks', '512-blocks') + '/dev/disk 10 1 1 1% /data\n'] {
		if _ := parse_disk_available(bad) { return error('malformed or overflowing df output accepted') }
	}
	if disk_blocks('18014398509481983')! != u64(0xffff_ffff_ffff_ffff) / 1024 { return error('df upper boundary rejected') }
	disk_start := disk_reserve_bytes + disk_growth_limit_bytes + 32
	if disk_budget(disk_start, disk_start, 0)! != 0
		|| disk_budget(disk_start, disk_start - disk_growth_limit_bytes, 0)! != disk_growth_limit_bytes
		|| disk_budget(disk_start, disk_start + 32, 17)! != 17
		|| disk_budget(disk_start, disk_start - 31, 17)! != 48 { return error('disk budget boundary differs') }
	// Read-only volume drift rebases the available count, retaining all charged writes.
	if disk_budget(disk_reserve_bytes, disk_reserve_bytes, 48)! != 48 { return error('read-only baseline lost charged writes') }
	mut budget := DiskBudget{available: disk_start + 2 * disk_growth_limit_bytes}
	disk_update(disk_start + disk_growth_limit_bytes / 2, false, mut budget)!
	if budget.charged != 0 { return error('read-only drop charged as a write') }
	disk_update(disk_start, true, mut budget)!
	if budget.charged != disk_growth_limit_bytes / 2 { return error('writable drop not charged') }
	disk_update(disk_start + 32, false, mut budget)!
	if budget.charged != disk_growth_limit_bytes / 2 { return error('read-only refresh lost charge') }
	disk_update(disk_start + 32 - disk_growth_limit_bytes / 2, true, mut budget)!
	if budget.charged != disk_growth_limit_bytes { return error('writable phase did not accumulate charge') }
	if _ := disk_update(budget.available - 1, true, mut budget) { return error('cumulative phase growth limit reset') }
	if _ := disk_update(disk_reserve_bytes - 1, false, mut budget) { return error('read-only audit bypassed disk reserve') }
	mut audit_budget := DiskBudget{available: disk_start + 4 * disk_growth_limit_bytes, charged: 17}
	charge_digest_receipts(21, mut audit_budget)!
	disk_update(disk_start, false, mut audit_budget)!
	if audit_budget.charged != 17 + 21 * digest_receipt_charge_bytes { return error('audit drift changed cumulative receipt charge') }
	disk_update(disk_start - 31, true, mut audit_budget)!
	if audit_budget.charged != 48 + 21 * digest_receipt_charge_bytes
		|| audit_budget.digest_receipt_charged != 21 * digest_receipt_charge_bytes { return error('writable drop or receipt charge lost') }
	for count in [0, 22, -1] {
		if _ := charge_digest_receipts(count, mut audit_budget) { return error('unbounded receipt count accepted') }
	}
	mut full_budget := DiskBudget{available: disk_start, charged: disk_growth_limit_bytes - digest_receipt_charge_bytes}
	charge_digest_receipts(1, mut full_budget)!
	if full_budget.charged != disk_growth_limit_bytes { return error('receipt charge boundary differs') }
	if _ := charge_digest_receipts(1, mut full_budget) { return error('receipt charge bypassed cumulative limit') }
	for bad in [[disk_start, disk_reserve_bytes - 1, u64(0)],
		[disk_start, disk_start - disk_growth_limit_bytes - 1, u64(0)],
		[disk_start, disk_start - 1, disk_growth_limit_bytes],
		[disk_start, disk_start, disk_growth_limit_bytes + 1]] {
		if _ := disk_budget(bad[0], bad[1], bad[2]) { return error('disk reserve or cumulative growth violation accepted') }
	}
	exact_profile(base_seal, framework_seal, jar_pin, dex_pin)!
	for values in [[old_framework_seal, jar_pin, dex_pin], [framework_seal, old_jar_pin, dex_pin],
		[framework_seal, jar_pin, old_dex_pin], [native_seal, jar_pin, dex_pin]] {
		if _ := exact_profile(base_seal, values[0], values[1], values[2]) { return error('obsolete or mismatched framework profile accepted') }
	}
	if _ := exact_profile(onboarding_seal, framework_seal, jar_pin, dex_pin) { return error('wrong base accepted') }
	framework := framework_fixture()!
	verify_framework(framework)!
	for name in framework.keys() {
		mut bad := framework_fixture()!
		bad[name] = json2.Any('wrong')
		if _ := verify_framework(bad) { return error('mutated framework audit field accepted: ' + name) }
		bad = framework_fixture()!
		bad.delete(name)
		if _ := verify_framework(bad) { return error('missing framework audit field accepted: ' + name) }
	}
	old := {'a': json2.Any('old'), 'b': json2.Any('same')}
	exact_delta(old, {'a': json2.Any('new'), 'b': json2.Any('same')}, {'a': json2.Any('new')})!
	for bad in [{'a': json2.Any('new')}, {'a': json2.Any('new'), 'b': json2.Any('bad')},
		{'a': json2.Any('new'), 'b': json2.Any('same'), 'c': json2.Any('extra')}] {
		if _ := exact_delta(old, bad, {'a': json2.Any('new')}) { return error('unsafe receipt delta accepted') }
	}
	if _ := exact_delta(old, old, {'a': json2.Any('old')}) { return error('missing receipt change accepted') }
	headless_before := {'inputs_sha256': as_json(headless_inputs())!}
	headless_after := repin_headless(headless_before, jar_pin)!
	mut headless_pins := headless_inputs()
	headless_pins['/' + jar_path] = jar_pin
	if headless_after != {'inputs_sha256': as_json(headless_pins)!} { return error('headless receipt replacement differs') }
	for path in headless_inputs().keys() {
		mut wrong := headless_inputs()
		wrong[path] = controller_pin
		if _ := repin_headless({'inputs_sha256': as_json(wrong)!}, jar_pin) { return error('changed inherited headless input accepted') }
	}
	if _ := repin_headless(headless_before, old_jar_pin) { return error('old framework headless input accepted') }
	if _ := repin_headless(headless_before, '') { return error('invalid framework headless input accepted') }
	mut fixture_pins := {'/' + controller_path: controller_pin, '/' + alias_path: controller_pin,
		'/' + native_path: native_pin, '/' + browser_path: browser_pin}
	mut replacements := map[string]string{}
	for path in changed_paths() { fixture_pins['/' + path] = heartbeat_native_pin; replacements['/' + path] = native_pin }
	fixture_pins['/' + jar_path] = old_jar_pin
	fixture_pins['/' + dex_path] = old_dex_pin
	replacements['/' + jar_path] = jar_pin
	replacements['/' + dex_path] = dex_pin
	replacements['/' + headless + '/framework-build.json'] = framework_build_pin
	replacements['/' + headless + '/framework-sha256.json'] = framework_seal
	mut deployment := {
		'kind': json2.Any('vinix-maps-account-deployment-v1'), 'framework_manifest_sha256': json2.Any(old_framework_seal),
		'native_manifest_sha256': json2.Any(native_seal), 'launch_manifest_sha256': json2.Any(launch_seal),
		'browser_client_manifest_sha256': json2.Any(browser_seal), 'browser_manifest_sha256': json2.Any(webkit_seal),
		'inputs_sha256': as_json(fixture_pins)!,
	}
	updated := repin_deployment(deployment, replacements)!
	for name in fixture_pins.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		mut pins := json2.decode[map[string]string](json2.encode(bad['inputs_sha256']!))!
		pins[name] = controller_seal
		bad['inputs_sha256'] = as_json(pins)!
		if _ := verify_deployment_delta(deployment, bad, replacements) { return error('unrelated or missing deployment input delta accepted') }
	}
	mut extra := json2.decode[map[string]json2.Any](json2.encode(updated))!
	extra['extra'] = json2.Any('unexpected')
	if _ := verify_deployment_delta(deployment, extra, replacements) { return error('extra deployment key accepted') }
	for name in ['native_manifest_sha256', 'framework_manifest_sha256', 'launch_manifest_sha256',
		'browser_client_manifest_sha256', 'browser_manifest_sha256'] {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		bad[name] = json2.Any(controller_pin)
		if _ := verify_deployment_delta(deployment, bad, replacements) { return error('wrong deployment identity accepted') }
	}
	for path in changed_paths() {
		mut missing := replacements.clone()
		missing.delete('/' + path)
		if _ := repin_deployment(deployment, missing) { return error('partial replacement set accepted') }
	}
	mut wrong_pin := replacements.clone()
	wrong_pin['/' + jar_path] = ''
	if _ := repin_deployment(deployment, wrong_pin) { return error('invalid new pin accepted') }
	for name in ['native_manifest_sha256', 'framework_manifest_sha256', 'launch_manifest_sha256',
		'browser_client_manifest_sha256', 'browser_manifest_sha256'] {
		mut bad := deployment.clone()
		bad[name] = json2.Any(controller_pin)
		if _ := repin_deployment(bad, replacements) { return error('wrong inherited deployment identity accepted') }
	}
	mut allowed := changed_paths()
	allowed << deployment_path
	exact_regular_names(allowed)!
	for bad in [allowed[..5], []string{}, [jar_path, jar_path, headless + '/framework-build.json', headless + '/framework-sha256.json', headless + '/guest-inputs.json', deployment_path]] {
		if _ := exact_regular_names(bad) { return error('wrong payload set accepted') }
	}
	allowed << 'opt/escape'
	if _ := exact_regular_names(allowed) { return error('extra payload accepted') }
	launch_abi := 'c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57'
	native_abi := 'e2be36f866ac321a7d681112e3514d8b1c8ac06553538758d7c1c220b9f3c72f'
	exact_service_abi(launch_abi, native_abi, native_seal, native_pin)!
	for values in [[native_abi, native_abi, native_seal, native_pin], [launch_abi, launch_abi, native_seal, native_pin],
		[launch_abi, native_abi, old_native_seal, native_pin], [launch_abi, native_abi, native_seal, heartbeat_native_pin]] {
		if _ := exact_service_abi(values[0], values[1], values[2], values[3]) { return error('wrong ABI profile accepted') }
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
	native_plan := [stage.Entry{name: native_path, kind: 'regular', mode: 0o755}]
	legacy := [stage.Entry{name: native_path, kind: 'regular', mode: 0o755},
		stage.Entry{name: native_path, kind: 'regular', mode: 0o644}]
	if inherited_modes(legacy, native_plan)![native_path]! != 0o755 { return error('historical native changed first inode mode') }
	if _ := inherited_modes([stage.Entry{name: native_path, kind: 'regular', mode: 0o644}], native_plan) {
		return error('non-executable first native inode accepted')
	}
	println('MAPS-APPLICATION-RESTRICTIONS-STAGE SELFTEST PASS disk parser reserve growth twenty-one modules exact UserManager framework native ABI browser receipt delta six-file payload inherited modes protected ancestors')
}
fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != '--prepare' { eprintln('usage: maps-application-restrictions-stage --prepare FRESH_EXTERNAL_OUTPUT | --self-test'); exit(2) }
	run(os.args[2]) or { eprintln(err); exit(1) }
}
