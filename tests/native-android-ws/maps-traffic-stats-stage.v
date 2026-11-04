// SPDX-License-Identifier: GPL-2.0-or-later
// SDK-only TrafficStats UID overlay with retained native and frozen kernel.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import modulestream
import os
import time
import v.embed_file

#include <sys/clonefile.h>
fn C.clonefile(&char, &char, int) int

const state_root = '/Users/alex/.local/state/vinix/android'
const base_root = state_root + '/maps-framework-jni-load-r8'
const base_seal = '31cf35f40e606d6c08d7b6e4daaad3d8b935d2afccfb5971199819456eadbfdb'
const base_stage_pin = '1253d40b75878fd444946a55c86d4f48521d6756b5d1f427d99ca9615335769f'
const old_framework_root = state_root + '/combined-account-webview-framework-boot-framework-2026-11-03-r1'
const old_framework_seal = 'af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91'
const old_framework_build_pin = '031a22b17d85b79adee0ca93776ead247fee47fa6f3b3d48376242969c7baee4'
const old_jar_pin = 'd9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974'
const old_dex_pin = 'c59bc24f43fcd5c40a18b118872186795127fbe309cd1a523823f01136f6f30b'
const framework_root = state_root + '/combined-account-webview-traffic-stats-framework-2026-11-04-r1'
const framework_seal = 'bffa5dedc87d80979b09d517fcfb752b470d7f9e76a8e44bc24452f152d42025'
const framework_build_pin = '85da0dfe7da000decdb80655d5b0069e050bcf2d867fe1858c6af935e968db31'
const jar_pin = 'dd3af0444459410f28d20f04928e37a19eb6b076d433498b05eac9a922b49f0e'
const dex_pin = '64c472412e52f91e5f40277f8077d251ee8de9b61558ecf8eec709227d97bde3'
const native_root = state_root + '/current-native-build-2026-11-04-framework-jni-load-r1'
const native_seal = '2d9c97030ab7367b487b4a7b3a6b4ed27b1cf4e68cf6567054c7ea03cc667fa0'
const native_build_pin = '16cb572c43e56af969757b9c3296637c5007bf46bab842291fadfe746dc99318'
const native_pin = '13cf020729373ad8d20cfa4c5588c0878eee4be4fdf85700f2cf911ded08e81e'
const generated_pin = 'd054fd51235e1893db9f5d78a747660abb69f185a803a6caa01c0dfc206d7a6c'
const bindings_pin = '2264b7af0bf4a5b39da876e2ef82a291983d7ea9bd2c5f7374d8448b4f1a03ba'
const exports_pin = '8ca376443ae60e8324646f967220d753a1f23d732b7aa1eddb5488f1fb43cc1b'
const builder_pin = 'b307f9afc36f19aefdf160c51c528f6bf7b157b4cfcced7d625fc697dfe55eeb'
const native_c_pin = '6a5f5a0dd13a56041aa9d6edac05cf18fc4fb40e8b5c439088993d2bf1c46e04'
const kernel_base_root = state_root + '/maps-framework-jni-load-kernel-base-2026-11-04-r1'
const kernel_base_seal = 'fb0b4431319d4905fde60abddfb7dfff18b0bf06ff3de2f6fe21ba6137308d8c'
const kernel_checkpoint_pin = '26e74c87fa5c4ebebbb752a7d45740d6090559daa356a5bf9d5a9e9ee51012f0'
const kernel_prepared_root = state_root + '/maps-framework-boot-r1'
const kernel_prepared_seal = '43309208792e5ce55ed9c4b8af9e0ae5b6ff1f849f43b27a04948659224dd499'
const kernel_original_stage_pin = 'a87760cf0daef526558da7b2b24068b868fe16f194e2f8692da8548eed8f465b'
const compatibility_receipt_path = state_root + '/traffic-stats-uid-native-proof-2026-11-04-r1/readback.json'
const compatibility_receipt_pin = '8dae9ac93397b331a0ca0d6f0771080b56ad5078d90b614db1025455f802955c'
const kernel_build_root = state_root + '/pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2'
const kernel_build_seal = '32a134cc1ee3d02bfb56d91ee429ac3f5fb9895ba525021eb7aa84a7ec64f6ee'
const kernel_build_pin = '1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d'
const kernel_pin = 'a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151'
const kernel_patcher_pin = '864cd44a611fc4e2f0a5ecb5bc85f2fecaed4ef0768e598a2769b817cc481542'
const prepared_efivars_pin = 'd3b3f7afddb44de7020b8544270a67791fca44a48864dcd550cefee633463cbf'
const old_headless_pin = '3ab8c4301a3a23e0d6f6487d4d677c0cd6f2f8a9f086329cf064c376cb748a70'
const old_deployment_pin = '93dee7d7fd9a5dd785c5682f3c7e422e8d5bdff471cfd02a914f0dfa44f98e73'
const headless = 'opt/vinix-headless-service'
const native_path = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const jar_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const dex_path = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/classes.dex'
const deployment_path = 'opt/vinix-maps-account/build.json'
const overlay = 'maps-traffic-stats.tar'
const disk_reserve = u64(1024) * 1024 * 1024
const disk_growth = u64(512) * 1024 * 1024
const digest_receipt_charge = u64(1024) * 1024
const retained = {
	'tests/native-android-ws/maps-traffic-stats-stage.v': carry($embed_file(@FILE))
	'tests/native-android-ws/mapsaccountstage/bundle.v': carry($embed_file('mapsaccountstage/bundle.v'))
	'tests/native-android-ws/mapsaccountstage/hostsha.v': carry($embed_file('mapsaccountstage/hostsha.v'))
	'tests/native-android-ws/mapsaccountstage/parallel.v': carry($embed_file('mapsaccountstage/parallel.v'))
	'tests/native-android-ws/mapsaccountstage/batches.v': carry($embed_file('mapsaccountstage/batches.v'))
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
fn read_json(path string) !map[string]json2.Any {
	if os.lstat(path)!.size > 8 * 1024 * 1024 { return error('bounded receipt required') }
	return json2.decode[map[string]json2.Any](os.read_file(path)!)
}
fn write_json(path string, value json2.Any) ! {
	os.mkdir_all(os.dir(path), mode: 0o755)!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn copy_file(source string, destination string, mode u32) ! {
	if os.real_path(source) != source || os.lstat(source)!.get_filetype() != .regular
		|| os.exists(destination) || os.is_link(destination) { return error('canonical regular input and fresh destination required') }
	os.mkdir_all(os.dir(destination), mode: 0o755)!
	os.cp(source, destination)!
	os.chmod(destination, int(mode))!
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
	total, used, available := disk_blocks(fields[1])!, disk_blocks(fields[2])!, disk_blocks(fields[3])!
	percent := disk_blocks(fields[4][..fields[4].len - 1])!
	if total == 0 || used > total || available > total || percent > 100 { return error('inconsistent df count') }
	return available * 1024
}
fn update_budget(available u64, writing bool, mut budget DiskBudget) ! {
	drop := if writing && available < budget.available { budget.available - available } else { u64(0) }
	if available < disk_reserve || budget.charged > disk_growth || drop > disk_growth - budget.charged { return error('1 GiB reserve or cumulative 512 MiB preparation growth exceeded') }
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
	defer { if !finished { child.signal_kill(); child.wait() }; child.close() }
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 2 * time.second
	for {
		out, errout := child.stdout_read(), child.stderr_read()
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
	println('MAPS-TRAFFIC-STATS disk ' + label + ' available_bytes=' + available.str() + ' charged_growth_bytes=' + budget.charged.str())
}
fn charge_audit(count int, mut budget DiskBudget) ! {
	if count < 1 || count > 61 || budget.charged > disk_growth || u64(count) * digest_receipt_charge > disk_growth - budget.charged { return error('module digest receipts exceed budget') }
	budget.charged += u64(count) * digest_receipt_charge
	budget.digest_receipt_charged += u64(count) * digest_receipt_charge
}
fn audit_modules(root string, label string, image string, names []string, expected map[string]string,
	mut budget DiskBudget, mut samples map[string]u64) !map[string]string {
	if names.len < 1 || names.len > 61 || names.len != expected.len { return error('bounded exact module audit required') }
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

fn exact_native_profile() ! {
	for pin in [base_seal, base_stage_pin, old_framework_seal, old_framework_build_pin, old_jar_pin, old_dex_pin,
		framework_seal, framework_build_pin, jar_pin, dex_pin,
		native_seal, native_build_pin, native_pin, generated_pin, bindings_pin, exports_pin, builder_pin, native_c_pin] {
		if !stage.valid_pin(pin) { return error('completed exact native production pins required') }
	}
	if old_framework_root == framework_root || old_framework_seal == framework_seal
		|| old_jar_pin == jar_pin || old_dex_pin == dex_pin { return error('distinct SDK and exactly retained native required') }
}
fn exact_profile() ! {
	exact_native_profile()!
	for pin in [kernel_base_seal, kernel_checkpoint_pin, kernel_build_seal, kernel_build_pin,
		kernel_pin, kernel_patcher_pin, prepared_efivars_pin, kernel_prepared_seal,
		kernel_original_stage_pin, compatibility_receipt_pin] {
		if !stage.valid_pin(pin) { return error('completed exact kernel checkpoint pins required') }
	}
}
fn dependencies(base map[string]json2.Any) !map[string]string {
	all := json2.decode[map[string]string](json2.encode(base['inputs_sha256']!))!
	mut selected := map[string]string{}
	for path, pin in all {
		if path.ends_with('/sha256.json') { selected[path.all_before_last('/sha256.json')] = pin }
	}
	if selected.len != 141 || selected[old_framework_root] or { '' } != old_framework_seal
		|| selected[native_root] or { '' } != native_seal
		|| selected[kernel_build_root] or { '' } != kernel_build_seal
		|| selected[kernel_base_root] or { '' } != kernel_base_seal
		|| framework_root in selected || base_root in selected { return error('exact inherited 140 flat and one typed kernel inventory required') }
	selected.delete(kernel_build_root)
	if selected.len != 140 { return error('exact flat inventory count required') }
	return selected
}
fn original_inodes(deps map[string]string) ![]stage.Entry {
	mut overlays := [][]stage.Entry{}
	mut seen := map[string]bool{}
	mut cursor := base_root
	for _ in 0 .. 54 {
		if cursor in seen || (cursor != base_root && cursor !in deps) { return error('unsealed or cyclic stage ancestry') }
		seen[cursor] = true
		value := read_json(cursor + '/stage.json')!
		overlays << json2.decode[[]stage.Entry](json2.encode(value['overlay_inventory']!))!
		original := cursor + '/original-module-inventory.json'
		if os.exists(original) {
			if seen.len != 54 || os.lstat(original)!.size > 32 * 1024 * 1024 { return error('exact bounded 54-stage ancestry required') }
			mut entries := json2.decode[[]stage.Entry](os.read_file(original)!)!
			for i := overlays.len - 1; i >= 0; i-- { entries << overlays[i] }
			return entries
		}
		cursor = stage.text_field(value, 'base_root')!
	}
	return error('stage ancestry exceeds bound')
}
fn base_modules(base map[string]json2.Any) !map[string]string {
	mut modules := json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
	if modules.len != 59 || 'maps-framework-jni-load.tar' in modules { return error('exact 59 inherited modules required') }
	modules['maps-framework-jni-load.tar'] = stage.text_field(base, 'overlay_sha256')!
	return modules
}
struct ModeTree {
mut:
	regular map[string]u32
	directories map[string]u32
}
fn mode_tree_walk(root string, relative string, depth int, mut result ModeTree) ! {
	if depth > 128 || result.regular.len + result.directories.len > 20000 { return error('bounded complete mode tree required') }
	path := if relative == '' { root } else { root + '/' + relative }
	info := os.lstat(path)!
	if info.mode & 0o7022 != 0 { return error('unsafe checkpoint mode: ' + path) }
	match info.get_filetype() {
		.regular {
			if info.nlink != 1 { return error('single-linked checkpoint regular inode required') }
			result.regular[relative] = info.mode & 0o777
		}
		.directory {
			result.directories[relative] = info.mode & 0o777
			for child in os.ls(path)! {
				next := if relative == '' { child } else { relative + '/' + child }
				if !stage.relative_file(next) { return error('unsafe checkpoint mode path') }
				mode_tree_walk(root, next, depth + 1, mut result)!
			}
		}
		else { return error('checkpoint mode tree contains a link or special inode') }
	}
}
fn mode_tree(root string) !ModeTree {
	mut result := ModeTree{}
	mode_tree_walk(root, '', 0, mut result)!
	return result
}
fn expected_checkpoint_modes(files []string, preserved map[string]u32, added map[string]u32,
	prepared_dirs map[string]u32, new_dirs map[string]u32, manifest_mode u32) !ModeTree {
	if preserved.len == 0 || added.len == 0 || prepared_dirs.len == 0 || new_dirs.len == 0
		|| manifest_mode != 0o644 { return error('complete recorded checkpoint mode maps required') }
	mut regular := map[string]u32{}
	for modes in [preserved, added] {
		for name, mode in modes {
			if !stage.relative_file(name) || name == 'sha256.json' || mode > 0o777 || mode & 0o7022 != 0
				|| name in regular { return error('invalid or overlapping recorded regular mode') }
			regular[name] = mode
		}
	}
	if regular.keys().sorted() != files.sorted() { return error('complete recorded regular mode membership differs') }
	regular['sha256.json'] = manifest_mode
	mut directories := prepared_dirs.clone()
	for name in ['kernel-patch-build', 'kernel-patch-commands'] {
		if name in directories { return error('kernel-only directory already present in prepared parent') }
		directories[name] = 0o755
	}
	for name, mode in new_dirs {
		if !stage.relative_file(name) || mode > 0o777 || mode & 0o7022 != 0 || name in directories {
			return error('invalid or overlapping recorded checkpoint directory mode')
		}
		directories[name] = mode
	}
	return ModeTree{regular: regular, directories: directories}
}
fn check_checkpoint_modes(files map[string]string, receipt map[string]json2.Any) ! {
	preserved := json2.decode[map[string]u32](json2.encode(receipt['preserved_regular_modes']!))!
	added := json2.decode[map[string]u32](json2.encode(receipt['new_output_modes']!))!
	new_dirs := json2.decode[map[string]u32](json2.encode(receipt['new_output_directory_modes']!))!
	if json2.encode(receipt['manifest_mode']!) != '420' { return error('exact recorded 0644 manifest mode required') }
	prepared := mode_tree(kernel_prepared_root)!
	expected := expected_checkpoint_modes(files.keys(), preserved, added, prepared.directories,
		new_dirs, 0o644)!
	if mode_tree(kernel_base_root)! != expected { return error('actual complete checkpoint inode modes differ from recorded contract') }
}
fn check_kernel_checkpoint(files map[string]string, expected_modules map[string]string) !map[string]json2.Any {
	if files['checkpoint.json'] or { '' } != kernel_checkpoint_pin
		|| files['prepared-sha256.json'] or { '' } != kernel_prepared_seal { return error('kernel checkpoint provenance differs') }
	value := read_json(kernel_base_root + '/checkpoint.json')!
	check_checkpoint_modes(files, value)!
	for key, expected in {'kind': 'vinix-framework-jni-load-kernel-checkpoint-v1',
		'prepared_root': kernel_prepared_root, 'prepared_manifest_sha256': kernel_prepared_seal,
		'original_stage_sha256': kernel_original_stage_pin, 'kernel_build_root': kernel_build_root,
		'kernel_build_manifest_sha256': kernel_build_seal, 'kernel_build_receipt_sha256': kernel_build_pin,
		'kernel_sha256': kernel_pin, 'kernel_patch_tool_sha256': kernel_patcher_pin,
		'prepared_efivars_sha256': prepared_efivars_pin} {
		if stage.text_field(value, key)! != expected { return error('kernel checkpoint field differs: ' + key) }
	}
	for key, path in {'staged_boot_sha256': 'boot.img', 'stage_sha256': 'stage.json',
		'kernel_patch_receipt_sha256': 'kernel-patch.json'} {
		if stage.text_field(value, key)! != files[path]! { return error('kernel checkpoint sealed member differs: ' + path) }
	}
	if json2.decode[map[string]string](json2.encode(value['preserved_modules_sha256']!))! != expected_modules
		|| expected_modules.len != 59 || files['efivars.fd'] or { '' } != prepared_efivars_pin { return error('complete kernel checkpoint payload preservation differs') }
	patch := read_json(kernel_base_root + '/kernel-patch.json')!
	for key, expected in {'profile': 'maps-framework-boot', 'original_stage_sha256': kernel_original_stage_pin,
		'kernel_build_root': kernel_build_root, 'kernel_build_receipt_sha256': kernel_build_pin,
		'kernel_sha256': kernel_pin, 'tool_sha256': kernel_patcher_pin, 'efivars_sha256': prepared_efivars_pin,
		'staged_boot_sha256': files['boot.img']!} {
		if stage.text_field(patch, key)! != expected { return error('qualified kernel patch receipt differs: ' + key) }
	}
	if stage.text_field(patch, 'kernel_member')! != 'vinix'
		|| json2.decode[map[string]string](json2.encode(patch['preserved_modules_sha256']!))! != expected_modules {
		return error('complete qualified kernel preservation differs')
	}
	for path in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock', 'serial.log',
		'network.pcap', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if path in files || os.exists(kernel_base_root + '/' + path) || os.is_link(kernel_base_root + '/' + path) { return error('kernel checkpoint must be unlaunched') }
	}
	return value
}
fn audit_kernel(root string, label string, image string, mut budget DiskBudget, mut samples map[string]u64) ! {
	path := root + '/commands/' + label + '-kernel.sha256'
	result := modulestream.hash_member(image, 'vinix', path)!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 || result.sha256 != kernel_pin { return error('inherited frozen kernel readback differs') }
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.mode & 0o7777 != 0o600 || info.size != 68
		|| os.read_file(path)! != kernel_pin + '  -\n' { return error('exact bounded kernel digest receipt required') }
	charge_audit(1, mut budget)!
	check_disk(root, label + '-kernel', false, mut budget, mut samples)!
}
struct KernelInventory {
	files map[string]string
	links map[string]string
}
fn kernel_tree(relative string, depth int, mut files map[string]string, mut links map[string]string) ! {
	if depth > 128 || files.len + links.len > 20000 { return error('bounded complete frozen kernel tree required') }
	path := if relative == '' { kernel_build_root } else { kernel_build_root + '/' + relative }
	info := os.lstat(path)!
	match info.get_filetype() {
		.regular {
			if info.nlink != 1 || info.mode & 0o7022 != 0 { return error('unsafe frozen kernel regular inode') }
			if relative != 'sha256.json' { files[relative] = stage.hash(path)! }
		}
		.directory {
			if info.mode & 0o7022 != 0 { return error('unsafe frozen kernel directory') }
			for name in os.ls(path)! {
				next := if relative == '' { name } else { relative + '/' + name }
				if !stage.relative_file(next) { return error('unsafe frozen kernel relative path') }
				kernel_tree(next, depth + 1, mut files, mut links)!
			}
		}
		.symbolic_link { links[relative] = os.readlink(path)! }
		else { return error('unexpected frozen kernel special inode') }
	}
}
fn kernel_inventory() !KernelInventory {
	if stage.hash(kernel_build_root + '/sha256.json')! != kernel_build_seal
		|| stage.hash(kernel_build_root + '/build.json')! != kernel_build_pin { return error('exact frozen kernel metadata required') }
	manifest := json2.decode[KernelInventory](os.read_file(kernel_build_root + '/sha256.json')!)!
	if manifest.files.len == 0 || manifest.files.len + manifest.links.len > 20000 { return error('bounded nonempty typed kernel inventory required') }
	for name, pin in manifest.files {
		if !stage.relative_file(name) || !stage.valid_pin(pin) { return error('invalid frozen kernel file entry') }
	}
	for name, target in manifest.links {
		if !stage.relative_file(name) || target == '' || target.contains_any('\x00\r\n') { return error('invalid frozen kernel link entry') }
	}
	mut files := map[string]string{}
	mut links := map[string]string{}
	kernel_tree('', 0, mut files, mut links)!
	if files != manifest.files || links != manifest.links { return error('complete typed frozen kernel inventory differs') }
	build := read_json(kernel_build_root + '/build.json')!
	for key, pin in {'architecture': 'aarch64', 'source_revision': 'ecbd3964aff243304e16df45271c7de8dee4d2da',
		'kernel_path': kernel_build_root + '/source/kernel/bin/vinix', 'kernel_sha256': kernel_pin,
		'kernel_unix_source_sha256': '287c78126cda7407f91494297494e029fef35aa93ada1dedd216cf9305d1013c',
		'compiler_sha256': '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'} {
		if stage.text_field(build, key)! != pin { return error('typed frozen kernel build differs: ' + key) }
	}
	if build['format']!.int() != 1 || build['guest_executed']!.bool() || build['link_seed']!.int() != 20261026
		|| !stage.valid_pin(stage.text_field(build, 'generated_c_sha256')!)
		|| manifest.files['source/kernel/bin/vinix'] or { '' } != kernel_pin { return error('exact frozen AArch64 kernel contract required') }
	return manifest
}
fn source_closure(bundle stage.Bundle, label string) !map[string]string {
	pins := json2.decode[map[string]string](os.read_file(bundle.root + '/' + label + '-closure.json')!)!
	mut result := map[string]string{}
	mut members := []string{}
	for origin, pin in pins {
		name := if origin.starts_with(bundle.root + '/compiler-root/') {
			'@compiler/' + origin.all_after(bundle.root + '/compiler-root/')
		} else if origin.starts_with(os.getwd() + '/') { origin } else { return error('native helper origin outside exact roots') }
		copy := 'closure/' + label + '/' + origin.trim_left('/')
		if name in result || bundle.files[copy] or { '' } != pin { return error('native helper closure copy differs') }
		result[name] = pin
		members << copy
	}
	if bundle.files.keys().filter(it.starts_with('closure/' + label + '/')).sorted() != members.sorted() { return error('complete native helper closure membership differs') }
	return result
}
fn canonical_classes(bundle stage.Bundle) !map[string]string {
	mut result := map[string]string{}
	for path, pin in bundle.files {
		if !path.starts_with('new-dex/') { continue }
		name := path.all_after('new-dex/')
		if !name.ends_with('.smali') || !stage.relative_file(name) { return error('unexpected canonical SDK member') }
		result[name] = pin
	}
	if result.len != 2117 { return error('complete 2117 canonical classes required') }
	return result
}
fn exact_sdk_delta(before map[string]string, after map[string]string) ! {
	if before.len != 2117 || before.keys().sorted() != after.keys().sorted() { return error('same complete SDK class membership required') }
	mut changed := []string{}
	for path, pin in before { if after[path]! != pin { changed << path } }
	if changed != ['android/net/TrafficStats.smali'] { return error('only the TrafficStats canonical class may change') }
}
fn formatting_pairs() map[string][]string {
	return {
		'smali/android/content/res/Resources.smali': ['f7cd9fbce3ddbb6e59580065ae7fb93f36bf17875054710ea5386648101e1e1d', '43bff6c257c83e7a79894eb2ac32b3e927cb213e2c744376d62ea8df628f0d18']
		'smali/android/atl/ATLLoadedApp.smali': ['644d12ccd65fb6ff5d6cb245b0168f8efc9f28e7fad3957519fc1c1a2926f08a', '69b03bab991dc30d5808a4e970ad3dc13203f4e8e14b1404d818de1c33387b9b']
	}
}
fn verify_sdk_native(native stage.Bundle, previous stage.Bundle, successor stage.Bundle) !map[string]json2.Any {
	if native.root != native_root || native.seal != native_seal || previous.root != old_framework_root
		|| previous.seal != old_framework_seal || successor.root != framework_root || successor.seal != framework_seal
		|| native.files['build.json']! != native_build_pin || native.files['native/libvinix-android-native.so']! != native_pin
		|| previous.files['build.json']! != old_framework_build_pin || previous.files['api-impl.jar']! != old_jar_pin
		|| previous.files['classes.dex']! != old_dex_pin || successor.files['build.json']! != framework_build_pin
		|| successor.files['api-impl.jar']! != jar_pin || successor.files['classes.dex']! != dex_pin { return error('exact retained native and SDK pair required') }
	// Keep original native producer coupling strict; compatibility with the new
	// SDK is a separate complete proof and never a rewritten native receipt.
	stage.verify_native(native, previous)!
	exact_sdk_delta(canonical_classes(previous)!, canonical_classes(successor)!)!
	for key, pin in {'profile': 'traffic-stats-2117', 'baseline_path': old_framework_root,
		'baseline_manifest_sha256': old_framework_seal, 'baseline_api_impl_sha256': old_jar_pin,
		'api_impl_sha256': jar_pin, 'classes_dex_sha256': dex_pin, 'compiler_sha256': stage.compiler_seal} {
		if stage.text_field(successor.receipt, key)! != pin { return error('exact TrafficStats SDK receipt differs: ' + key) }
	}
	if successor.receipt['class_count']!.int() != 2117
		|| json2.decode[[]string](json2.encode(successor.receipt['changed_classes']!))! != ['android/net/TrafficStats.smali']
		|| json2.decode[[]string](json2.encode(successor.receipt['added_classes']!))!.len != 0
		|| json2.decode[map[string]int](json2.encode(successor.receipt['changed_method_counts']!))! != {'android/net/TrafficStats.smali': 2}
		|| json2.decode[map[string]int](json2.encode(successor.receipt['added_method_counts']!))! != {'android/net/TrafficStats.smali': 2}
		|| json2.decode[map[string][]string](json2.encode(successor.receipt['added_fields']!))! != {'android/net/TrafficStats.smali': ['.field private static uids:Ljava/lang/ThreadLocal;']} { return error('exact TrafficStats declaration delta required') }
	consumed := json2.decode[map[string]string](os.read_file(native.root + '/framework/consumed-smali.json')!)!
	if consumed.len != 70 || 'smali/android/net/TrafficStats.smali' in consumed
		|| native.files.keys().filter(it.starts_with('framework/smali/')).sorted() != consumed.keys().map('framework/' + it).sorted() { return error('exact complete 70 native classes excluding TrafficStats required') }
	mut raw_delta := map[string][]string{}
	for path, pin in consumed {
		canonical := 'new-dex/' + path.all_after('smali/')
		if native.files['framework/' + path]! != pin || previous.files[path]! != pin
			|| previous.files[canonical]! != successor.files[canonical]!
			|| successor.files[path]! != successor.files[canonical]! { return error('native canonical compatibility differs') }
		if pair := formatting_pairs()[path] {
			if pin != pair[0] || previous.files[canonical]! != pair[1] || successor.files[path]! != pair[1] { return error('fixed historical raw formatting pair differs') }
		} else if pin != previous.files[canonical]! { return error('unreviewed native raw formatting difference') }
		if pin != successor.files[path]! { raw_delta[path] = [pin, successor.files[path]!] }
	}
	if raw_delta != formatting_pairs() { return error('both and only fixed native formatting pairs required') }
	for path, pin in {'native/atlframework/ws_generated.v': generated_pin, 'native/bindings.txt': bindings_pin,
		'native/exports.json': exports_pin, 'native/android-native.c': native_c_pin, 'builder-source.v': builder_pin} {
		if native.files[path]! != pin { return error('retained native producer member differs') }
	}
	proof_info := os.lstat(compatibility_receipt_path)!
	if os.real_path(compatibility_receipt_path) != compatibility_receipt_path || proof_info.get_filetype() != .regular
		|| proof_info.nlink != 1 || proof_info.mode & 0o7022 != 0 || proof_info.size > 8 * 1024 * 1024
		|| stage.hash(compatibility_receipt_path)! != compatibility_receipt_pin { return error('bounded canonical qualified native compatibility proof required') }
	proof := read_json(compatibility_receipt_path)!
	for key, pin in {'kind': 'vinix-traffic-stats-uid-native-readback-v1', 'native_root': native_root,
		'native_manifest_sha256': native_seal, 'native_build_sha256': native_build_pin, 'native_dso_sha256': native_pin,
		'original_framework_root': old_framework_root, 'original_framework_manifest_sha256': old_framework_seal,
		'framework_root': framework_root, 'framework_manifest_sha256': framework_seal, 'framework_jar_sha256': jar_pin,
		'framework_dex_sha256': dex_pin, 'native_bindings_sha256': bindings_pin, 'generated_jni_sha256': generated_pin,
		'generated_c_sha256': native_c_pin, 'exports_sha256': exports_pin,
		'consumed_headers_sha256': native.files['native/consumed-headers.json']!} {
		if stage.text_field(proof, key)! != pin { return error('qualified compatibility proof field differs: ' + key) }
	}
	if !proof['native_unchanged']!.bool() || !proof['complete_inventory_rechecks']!.bool()
		|| proof['canonical_native_class_count']!.int() != 70 || proof['unchanged_other_canonical_class_count']!.int() != 2116 { return error('complete qualified compatibility proof required') }
	return proof
}
fn exact_delta(before map[string]json2.Any, after map[string]json2.Any, changes map[string]json2.Any) ! {
	if before.len != after.len { return error('receipt key set changed') }
	for key, old in before {
		actual := after[key] or { return error('receipt key removed') }
		if replacement := changes[key] {
			if actual != replacement || actual == old { return error('required receipt change differs') }
		} else if actual != old { return error('unrelated receipt change') }
	}
	for key in changes.keys() { if key !in before { return error('replacement key absent') } }
}
fn headless_inputs() map[string]string {
	return {
		'/opt/vinix-android-aarch64/usr/bin/run-android': '1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112'
		'/opt/vinix-android-aarch64/usr/bin/vinix-android-native': 'b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d'
		'/' + native_path: native_pin
		'/' + jar_path: old_jar_pin
		'/' + headless + '/bin/headless-service-controller': '70f23b12fb5a770587bfcebcf33ed1320fe050399f08bd256362a037f24eb0b6'
		'/' + headless + '/bin/headless-service-guest': 'd518cfc5145924479b5ad630aac2a3d3ef7dcea66f53515c03df03735e88ce05'
		'/' + headless + '/fixture.apk': '4df9e3cd757b463259c73dc038eb84d149d7ec1461a1889bc8f2d531f6980634'
	}
}
fn repin_headless(original map[string]json2.Any) !map[string]json2.Any {
	if original.len != 1 || json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))! != headless_inputs() { return error('exact inherited seven-input headless contract required') }
	mut updated := headless_inputs()
	updated['/' + jar_path] = jar_pin
	return {'inputs_sha256': as_json(updated)!}
}
fn changed_paths() []string {
	return [jar_path, dex_path, headless + '/framework-build.json', headless + '/framework-sha256.json', headless + '/guest-inputs.json']
}
fn replacement_pins(root string) !map[string]string {
	mut pins := map[string]string{}
	for path in changed_paths() { pins['/' + path] = stage.hash(root + '/' + path)! }
	return pins
}
fn repin_deployment(original map[string]json2.Any, replacements map[string]string) !map[string]json2.Any {
	if stage.text_field(original, 'kind')! != 'vinix-maps-account-deployment-v1'
		|| stage.text_field(original, 'framework_manifest_sha256')! != old_framework_seal
		|| stage.text_field(original, 'native_manifest_sha256')! != native_seal
		|| replacements.keys().sorted() != changed_paths().map('/' + it).sorted()
		|| replacements['/' + jar_path]! != jar_pin || replacements['/' + dex_path]! != dex_pin
		|| replacements['/' + headless + '/framework-build.json']! != framework_build_pin
		|| replacements['/' + headless + '/framework-sha256.json']! != framework_seal { return error('exact SDK-only deployment transition required') }
	old := json2.decode[map[string]string](json2.encode(original['inputs_sha256']!))!
	for path, pin in {'/' + native_path: native_pin, '/' + jar_path: old_jar_pin, '/' + dex_path: old_dex_pin,
		'/' + headless + '/framework-build.json': old_framework_build_pin,
		'/' + headless + '/framework-sha256.json': old_framework_seal,
		'/' + headless + '/native-build.json': native_build_pin,
		'/' + headless + '/native-sha256.json': native_seal,
		'/' + headless + '/guest-inputs.json': old_headless_pin} {
		if old[path] or { '' } != pin { return error('retained deployment input differs') }
	}
	mut updated := old.clone()
	for path, pin in replacements {
		if !stage.valid_pin(pin) || path !in old || old[path] == pin { return error('exact changed deployment pin required') }
		updated[path] = pin
	}
	mut result := original.clone()
	result['inputs_sha256'] = as_json(updated)!
	result['framework_manifest_sha256'] = json2.Any(framework_seal)
	verify_deployment_delta(original, result, replacements)!
	return result
}
fn verify_deployment_delta(original map[string]json2.Any, updated map[string]json2.Any, replacements map[string]string) ! {
	exact_delta(original['inputs_sha256']!.as_map(), updated['inputs_sha256']!.as_map(), as_json(replacements)!.as_map())!
	exact_delta(original, updated, {'inputs_sha256': updated['inputs_sha256']!, 'framework_manifest_sha256': json2.Any(framework_seal)})!
}
fn exact_regular_names(names []string) ! {
	mut expected := changed_paths()
	expected << deployment_path
	if names.sorted() != expected.sorted() { return error('exact six-file payload required') }
}
fn payload_inventory(root string) ![]stage.Entry {
	if os.ls(root)!.sorted() != ['opt'] { return error('exact payload root required') }
	mut entries := []stage.Entry{}
	stage.inventory(root + '/opt', '', 'opt', mut entries)!
	exact_regular_names(entries.filter(it.kind == 'regular').map(it.name))!
	mut allowed := changed_paths()
	allowed << deployment_path
	for entry in entries {
		if entry.kind == 'regular' {
			if entry.mode != 0o644 { return error('payload regular mode differs') }
			if entry.name == jar_path && entry.sha256 != jar_pin { return error('payload JAR differs') }
			if entry.name == dex_path && entry.sha256 != dex_pin { return error('payload DEX differs') }
			if entry.name == headless + '/framework-build.json' && entry.sha256 != framework_build_pin { return error('payload framework build differs') }
			if entry.name == headless + '/framework-sha256.json' && entry.sha256 != framework_seal { return error('payload framework manifest differs') }
		} else if entry.kind != 'directory' || entry.mode != 0o755 || !allowed.any(it.starts_with(entry.name + '/')) { return error('unexpected payload inode') }
	}
	return entries
}
fn inherited_modes(original []stage.Entry, planned []stage.Entry) !map[string]u32 {
	mut modes := map[string]u32{}
	for target in planned {
		if !stage.relative(target.name) || target.kind !in ['regular', 'directory'] || target.mode & 0o7022 != 0 { return error('unsafe diagnostic destination') }
		for old in original {
			if old.name == target.name {
				if old.kind != target.kind || old.mode != target.mode { return error('unsafe existing destination') }
				if target.name !in modes {
					if old.mode & (target.mode & ~u32(0o222)) != target.mode & ~u32(0o222) { return error('insufficient original mode') }
					modes[target.name] = old.mode
				}
			} else if target.name.starts_with(old.name + '/') && (old.kind != 'directory' || old.mode & 0o7022 != 0) { return error('unsafe original ancestor') }
		}
		if target.name !in modes { return error('original destination absent') }
	}
	return modes
}
fn audit_framework_inputs() ! {
	exact_profile()!
	framework := stage.load_bundle(framework_root, framework_seal)!
	previous := stage.load_bundle(old_framework_root, old_framework_seal)!
	native := stage.load_bundle(native_root, native_seal)!
	verify_sdk_native(native, previous, framework)!
	for bundle in [framework, previous, native] { stage.recheck(bundle)! }
	if stage.hash(compatibility_receipt_path)! != compatibility_receipt_pin { return error('qualified compatibility proof changed during audit') }
	println('MAPS-TRAFFIC-STATS-AUDIT PASS canonical2117 deltaTrafficStats1 consumed70 unchanged-native original-SDK-coupling exact-raw-formatting-pairs2')
}
fn enumerate_native_helpers() ! {
	exact_native_profile()!
	native := stage.load_bundle(native_root, native_seal)!
	for row in [['native-generator', '340'], ['builder', '660']] {
		closure := source_closure(native, row[0])!
		if closure.len != row[1].int() { return error('native helper closure differs') }
		println('MAPS-TRAFFIC-STATS-HELPERS ' + row[0] + ' retained=' + closure.len.str())
	}
}
fn run(destination string) ! {
	exact_profile()!
	root := stage.external(destination)!
	stage.disjoint(root, [base_root, old_framework_root, framework_root, native_root,
		kernel_base_root, kernel_prepared_root, kernel_build_root, os.dir(compatibility_receipt_path), os.getwd()])!
	disk_start := disk_available(os.dir(root))!
	if disk_start < u64(5) * 1024 * 1024 * 1024 { return error('preparation requires 5 GiB initial free space') }
	mut disk := DiskBudget{available: disk_start}
	mut samples := {'preflight': disk_start}
	println('MAPS-TRAFFIC-STATS auditing immutable inputs')
	base_files := stage.load_inventory(base_root, base_seal)!
	prepared_modes := mode_tree(base_root)!
	if base_files['stage.json']! != base_stage_pin || base_files['efivars.fd']! != prepared_efivars_pin
		|| base_files['payload/' + headless + '/guest-inputs.json']! != old_headless_pin
		|| base_files['payload/' + deployment_path]! != old_deployment_pin { return error('exact JNI-load parent required') }
	base := read_json(base_root + '/stage.json')!
	for key, pin in {'kind': 'vinix-maps-framework-jni-load-v1', 'framework_build_root': old_framework_root,
		'framework_manifest_sha256': old_framework_seal, 'framework_jar_sha256': old_jar_pin,
		'framework_dex_sha256': old_dex_pin, 'native_build_root': native_root,
		'native_manifest_sha256': native_seal, 'native_build_sha256': native_build_pin,
		'native_sha256': native_pin, 'generated_jni_sha256': generated_pin,
		'native_c_sha256': native_c_pin, 'kernel_image_source_root': kernel_base_root,
		'kernel_image_source_manifest_sha256': kernel_base_seal, 'kernel_checkpoint_receipt_sha256': kernel_checkpoint_pin,
		'kernel_sha256': kernel_pin, 'kernel_build_root': kernel_build_root, 'kernel_build_receipt_sha256': kernel_build_pin} {
		if stage.text_field(base, key)! != pin { return error('immutable parent identity differs: ' + key) }
	}
	deps := dependencies(base)!
	stage.disjoint(root, deps.keys())!
	stage.audit_one_hundred_forty_inventories(deps)!
	modules := base_modules(base)!
	checkpoint_modules := json2.decode[map[string]string](json2.encode(base['original_modules_sha256']!))!
	if checkpoint_modules != json2.decode[map[string]string](json2.encode(base['preserved_modules_sha256']!))!
		|| checkpoint_modules.len != 59 { return error('original checkpoint module lineage differs') }
	kernel_files := stage.load_inventory(kernel_base_root, kernel_base_seal)!
	kernel_checkpoint := check_kernel_checkpoint(kernel_files, checkpoint_modules)!
	kernel_modes := mode_tree(kernel_base_root)!
	kernel_prepared_modes := mode_tree(kernel_prepared_root)!
	kernel_build_files := kernel_inventory()!
	if kernel_build_files.files['build.json']! != kernel_build_pin { return error('frozen kernel build receipt differs') }
	framework := stage.load_bundle(framework_root, framework_seal)!
	previous := stage.load_bundle(old_framework_root, old_framework_seal)!
	native := stage.load_bundle(native_root, native_seal)!
	compatibility_proof := verify_sdk_native(native, previous, framework)!
	mut inputs := map[string]string{}
	for path, pin in deps { inputs[path + '/sha256.json'] = pin }
	for path, pin in {base_root: base_seal, framework_root: framework_seal,
		kernel_build_root: kernel_build_seal} { inputs[path + '/sha256.json'] = pin }
	if inputs.len != 143 { return error('exact 142 flat and one typed dependency inventories required') }
	inputs[compatibility_receipt_path] = compatibility_receipt_pin
	check_disk(root, 'inputs-audited', false, mut disk, mut samples)!
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
	for path in ['/usr/bin/git', '/usr/bin/env', '/bin/df'] { inputs[path] = stage.hash(path)! }
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
	check_disk(root, 'retained-source-tools', true, mut disk, mut samples)!
	original := os.read_file(base_root + '/limine-after.conf')!
	config := stage.configure(original, overlay)!
	if config.modules.len != 60 || config.modules.sorted() != modules.keys().sorted()
		|| stage.command(root, 'parent-limine', [root + '/tools/mtype', '-i', base_root + '/boot.img', '::/boot/limine.conf'])! != original { return error('exact inherited 60-module boot configuration required') }
	check_disk(root, 'source-limine', true, mut disk, mut samples)!
	audit_modules(root, 'original', base_root + '/boot.img', config.modules, modules, mut disk, mut samples)!
	audit_kernel(root, 'original', base_root + '/boot.img', mut disk, mut samples)!
	original_entries := original_inodes(deps)!
	copy_file(framework_root + '/api-impl.jar', root + '/payload/' + jar_path, 0o644)!
	copy_file(framework_root + '/classes.dex', root + '/payload/' + dex_path, 0o644)!
	copy_file(framework_root + '/build.json', root + '/payload/' + headless + '/framework-build.json', 0o644)!
	copy_file(framework_root + '/sha256.json', root + '/payload/' + headless + '/framework-sha256.json', 0o644)!
	old_headless := read_json(base_root + '/payload/' + headless + '/guest-inputs.json')!
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
	check_disk(root, 'payload', true, mut disk, mut samples)!
	println('MAPS-TRAFFIC-STATS cloning current parent media and appending six SDK files')
	for row in [['boot.img', base_root, base_files['boot.img']!], ['efivars.fd', base_root, prepared_efivars_pin]] {
		if C.clonefile((row[1] + '/' + row[0]).str, (root + '/' + row[0]).str, 0) != 0 { return error('fresh APFS media clone failed') }
		check_disk(root, 'clone-' + row[0] + '-created', true, mut disk, mut samples)!
		if stage.hash(root + '/' + row[0])! != row[2] { return error('fresh exact media clone differs') }
		check_disk(root, 'clone-' + row[0] + '-verified', false, mut disk, mut samples)!
	}
	stage.command_expected(root, 'overlay-absent', [root + '/tools/mdir', '-i', root + '/boot.img', '::/boot/' + overlay], 1)!
	mut sources := map[string]string{}
	for entry in entries.filter(it.kind == 'regular') { sources[entry.name] = root + '/payload/' + entry.name }
	stage.write_overlay(root + '/' + overlay, sources, entries)!
	stage.verify_overlay(root + '/' + overlay, entries)!
	check_disk(root, 'overlay', true, mut disk, mut samples)!
	stage.command(root, 'install-overlay', [root + '/tools/mcopy', '-i', root + '/boot.img', root + '/' + overlay, '::/boot/' + overlay])!
	check_disk(root, 'install-overlay', true, mut disk, mut samples)!
	stage.command(root, 'install-limine', [root + '/tools/mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	check_disk(root, 'install-limine', true, mut disk, mut samples)!
	if stage.command(root, 'readback-limine', [root + '/tools/mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != config.updated { return error('new boot configuration differs') }
	check_disk(root, 'readback-limine', true, mut disk, mut samples)!
	mut expected_modules := modules.clone()
	expected_modules[overlay] = stage.hash(root + '/' + overlay)!
	mut final_modules := config.modules.clone()
	final_modules << overlay
	if final_modules.len != 61 { return error('exact 61-module successor required') }
	mut after := audit_modules(root, 'readback', root + '/boot.img', final_modules, expected_modules, mut disk, mut samples)!
	audit_kernel(root, 'readback', root + '/boot.img', mut disk, mut samples)!
	after.delete(overlay)
	for bundle in [framework, previous, native] { stage.recheck(bundle)! }
	if stage.load_inventory(base_root, base_seal)! != base_files
		|| stage.load_inventory(kernel_base_root, kernel_base_seal)! != kernel_files
		|| kernel_inventory()! != kernel_build_files { return error('complete original/kernel provenance changed') }
	if mode_tree(base_root)! != prepared_modes || mode_tree(kernel_base_root)! != kernel_modes
		|| mode_tree(kernel_prepared_root)! != kernel_prepared_modes { return error('prepared or kernel checkpoint inode modes changed during staging') }
	check_kernel_checkpoint(kernel_files, checkpoint_modules)!
	stage.audit_one_hundred_forty_inventories(deps)!
	for path, pin in inputs {
		if stage.hash(path)! != pin { return error('final input hash differs: ' + path) }
	}
	check_disk(root, 'complete-recheck', false, mut disk, mut samples)!
	mut receipt := base.clone()
	receipt['kind'] = json2.Any('vinix-maps-traffic-stats-v1')
	receipt['scope'] = json2.Any('TrafficStats per-thread UID SDK correction only; retained native producer and inherited frozen kernel with complete module readbacks; no ARM, GMS, Maps or authentication proof.')
	receipt['source_revision'] = json2.Any(revision)
	receipt['base_root'] = json2.Any(base_root)
	receipt['base_manifest_sha256'] = json2.Any(base_seal)
	receipt['framework_build_root'] = json2.Any(framework_root)
	receipt['framework_build_sha256'] = json2.Any(framework_build_pin)
	receipt['framework_manifest_sha256'] = json2.Any(framework_seal)
	receipt['framework_jar_sha256'] = json2.Any(jar_pin)
	receipt['framework_dex_sha256'] = json2.Any(dex_pin)
	receipt['retained_native_manifest_sha256'] = json2.Any(native_seal)
	receipt['retained_framework_manifest_sha256'] = json2.Any(old_framework_seal)
	receipt['native_framework_manifest_sha256'] = json2.Any(old_framework_seal)
	receipt['retained_native_framework_manifest_sha256'] = json2.Any(old_framework_seal)
	receipt['native_compatibility_framework_manifest_sha256'] = json2.Any(framework_seal)
	receipt['native_c_sha256'] = json2.Any(native_c_pin)
	receipt['native_consumed_headers_before_sha256'] = json2.Any(native.files['native/consumed-headers.json']!)
	receipt['native_consumed_headers_sha256'] = json2.Any(native.files['native/consumed-headers.json']!)
	for key in ['native_source_delta', 'native_c_delta', 'native_bindings_delta', 'native_generated_jni_delta',
		'native_builder_helper_delta', 'native_consumed_canonical_delta'] { receipt[key] = as_json(map[string][]string{})! }
	receipt['native_consumed_raw_delta'] = as_json(formatting_pairs())!
	receipt['framework_builder_helper_delta'] = as_json({'tests/native-android-ws/combined-account-webview-build.v': [previous.files['builder-source.v']!, framework.files['builder-source.v']!]})!
	receipt['framework_source_delta'] = as_json({'smali/android/net/TrafficStats.smali': [previous.files['smali/android/net/TrafficStats.smali']!, framework.files['smali/android/net/TrafficStats.smali']!]})!
	receipt['framework_canonical_delta'] = as_json({'new-dex/android/net/TrafficStats.smali': [previous.files['new-dex/android/net/TrafficStats.smali']!, framework.files['new-dex/android/net/TrafficStats.smali']!]})!
	receipt['framework_changed_method_counts'] = framework.receipt['changed_method_counts']!
	receipt['framework_added_method_counts'] = framework.receipt['added_method_counts']!
	receipt['framework_added_fields'] = framework.receipt['added_fields']!
	receipt['framework_added_classes'] = as_json([]string{})!
	receipt['native_compatibility_receipt_path'] = json2.Any(compatibility_receipt_path)
	receipt['native_compatibility_receipt_sha256'] = json2.Any(compatibility_receipt_pin)
	receipt['native_compatibility_proof'] = as_json(compatibility_proof)!
	receipt['kernel_image_source_root'] = json2.Any(base_root)
	receipt['kernel_image_source_manifest_sha256'] = json2.Any(base_seal)
	receipt['kernel_checkpoint_root'] = json2.Any(kernel_base_root)
	receipt['kernel_checkpoint_manifest_sha256'] = json2.Any(kernel_base_seal)
	receipt['kernel_checkpoint_receipt_sha256'] = json2.Any(kernel_checkpoint_pin)
	receipt['inherited_kernel_checkpoint'] = as_json(kernel_checkpoint)!
	receipt['kernel_sha256'] = json2.Any(kernel_pin)
	receipt['kernel_build_root'] = json2.Any(kernel_build_root)
	receipt['kernel_build_receipt_sha256'] = json2.Any(kernel_build_pin)
	receipt['deployment_input_delta'] = as_json(replacements)!
	receipt['deployment_top_level_delta'] = as_json(['inputs_sha256', 'framework_manifest_sha256'])!
	receipt['headless_input_delta'] = as_json({'/' + jar_path: jar_pin})!
	receipt['headless_top_level_delta'] = as_json(['inputs_sha256'])!
	receipt['inputs_sha256'] = as_json(inputs)!
	receipt['original_modules_sha256'] = as_json(modules)!
	receipt['preserved_modules_sha256'] = as_json(after)!
	receipt['overlay_inventory'] = as_json(entries)!
	receipt['overlay_sha256'] = json2.Any(expected_modules[overlay]!)
	receipt['limine_before_sha256'] = json2.Any(stage.hash(root + '/limine-before.conf')!)
	receipt['limine_after_sha256'] = json2.Any(stage.hash(root + '/limine-after.conf')!)
	receipt['staged_boot_sha256'] = json2.Any(stage.hash(root + '/boot.img')!)
	receipt['staged_efivars_sha256'] = json2.Any(stage.hash(root + '/efivars.fd')!)
	receipt['disk_digest_receipt_charge_bytes'] = as_json(disk.digest_receipt_charged)!
	receipt['disk_charged_growth_bytes'] = as_json(disk.charged)!
	receipt['disk_available_samples_bytes'] = as_json(samples)!
	receipt['disk_sample_argv'] = as_json(['/usr/bin/env', 'LC_ALL=C', '/bin/df', '-kP', os.dir(root)])!
	receipt['disk_growth_policy'] = json2.Any('Cumulative observed volume drops during writable phases plus 1 MiB per exact 68-byte module/kernel digest receipt; explicit complete read-only audits refresh baseline with reserve enforced. No refunds.')
	write_json(root + '/stage.json', as_json(receipt)!)!
	check_disk(root, 'receipt-complete', true, mut disk, mut samples)!
	mut files := map[string]string{}
	collect(root, '', mut files)!
	check_disk(root, 'output-inventory', false, mut disk, mut samples)!
	write_json(root + '/sha256.json', as_json(files)!)!
	check_disk(root, 'seal-complete', true, mut disk, mut samples) or { os.rm(root + '/sha256.json') or {}; return err }
	println('MAPS-TRAFFIC-STATS PREPARED ' + root + ' manifest=' + stage.hash(root + '/sha256.json')!)
}
fn self_test() ! {
	mut refusals := 0
	mut dependency_pins := map[string]string{}
	for i in 0 .. 137 { dependency_pins['/fixture/' + i.str() + '/sha256.json'] = 'a'.repeat(64) }
	for path, pin in {old_framework_root: old_framework_seal, native_root: native_seal,
		kernel_base_root: kernel_base_seal, kernel_build_root: kernel_build_seal} {
		dependency_pins[path + '/sha256.json'] = pin
	}
	flat := dependencies({'inputs_sha256': as_json(dependency_pins)!})!
	if flat.len != 140 || kernel_build_root in flat || flat[kernel_base_root]! != kernel_base_seal { return error('exact typed kernel separation differs') }
	for mutation in 0 .. 6 {
		mut bad := dependency_pins.clone()
		match mutation {
			0 { bad.delete('/fixture/0/sha256.json') }
			1 { bad['/fixture/extra/sha256.json'] = 'a'.repeat(64) }
			2 { bad[kernel_build_root + '/sha256.json'] = 'b'.repeat(64) }
			3 { bad[native_root + '/sha256.json'] = 'b'.repeat(64) }
			4 { bad.delete('/fixture/0/sha256.json'); bad[framework_root + '/sha256.json'] = framework_seal }
			else { bad.delete('/fixture/0/sha256.json'); bad[base_root + '/sha256.json'] = base_seal }
		}
		if _ := dependencies({'inputs_sha256': as_json(bad)!}) { return error('invalid inherited inventory split accepted') }
		refusals++
	}
	mode_files := ['old', 'new']
	old_modes := {'old': u32(0o644)}
	new_modes := {'new': u32(0o600)}
	prepared_dirs := {'': u32(0o755), 'source': u32(0o755)}
	new_dirs := {'checkpoint': u32(0o700)}
	mode_plan := expected_checkpoint_modes(mode_files, old_modes, new_modes, prepared_dirs, new_dirs, 0o644)!
	if mode_plan.regular != {'old': u32(0o644), 'new': u32(0o600), 'sha256.json': u32(0o644)}
		|| mode_plan.directories != {'': u32(0o755), 'source': u32(0o755), 'kernel-patch-build': u32(0o755),
		'kernel-patch-commands': u32(0o755), 'checkpoint': u32(0o700)} { return error('exact checkpoint mode plan differs') }
	for bad in [map[string]u32{}, {'old': u32(0o600)}, {'new': u32(0o600), 'extra': u32(0o644)},
		{'../new': u32(0o600)}, {'new': u32(0o666)}, {'new': u32(0o4600)}] {
		if _ := expected_checkpoint_modes(mode_files, old_modes, bad, prepared_dirs, new_dirs, 0o644) { return error('invalid recorded checkpoint regular modes accepted') }
		refusals++
	}
	for bad in [map[string]u32{}, {'source': u32(0o700)}, {'../checkpoint': u32(0o700)},
		{'checkpoint': u32(0o777)}, {'checkpoint': u32(0o4700)}] {
		if _ := expected_checkpoint_modes(mode_files, old_modes, new_modes, prepared_dirs, bad, 0o644) { return error('invalid recorded checkpoint directory modes accepted') }
		refusals++
	}
	for bad in [u32(0), u32(0o600), u32(0o666), u32(0o4644)] {
		if _ := expected_checkpoint_modes(mode_files, old_modes, new_modes, prepared_dirs, new_dirs, bad) { return error('invalid checkpoint manifest mode accepted') }
		refusals++
	}
	mut before_classes := map[string]string{}
	for i in 0 .. 2116 { before_classes['kept/' + i.str() + '.smali'] = 'a'.repeat(64) }
	before_classes['android/net/TrafficStats.smali'] = 'a'.repeat(64)
	mut after_classes := before_classes.clone()
	after_classes['android/net/TrafficStats.smali'] = 'b'.repeat(64)
	exact_sdk_delta(before_classes, after_classes)!
	for mutation in 0 .. 4 {
		mut bad := after_classes.clone()
		match mutation {
			0 { bad['kept/0.smali'] = 'c'.repeat(64) }
			1 { bad.delete('kept/0.smali') }
			2 { bad['extra.smali'] = 'c'.repeat(64) }
			else { bad['android/net/TrafficStats.smali'] = 'a'.repeat(64) }
		}
		if _ := exact_sdk_delta(before_classes, bad) { return error('unrelated, missing or absent TrafficStats delta accepted') }
		refusals++
	}
	old_headless := {'inputs_sha256': as_json(headless_inputs())!}
	mut expected_headless := headless_inputs()
	expected_headless['/' + jar_path] = jar_pin
	if repin_headless(old_headless)! != {'inputs_sha256': as_json(expected_headless)!} { return error('headless SDK-only update differs') }
	for path in headless_inputs().keys() {
		mut bad := headless_inputs()
		bad[path] = '0'.repeat(64)
		if _ := repin_headless({'inputs_sha256': as_json(bad)!}) { return error('changed protected headless input accepted') }
		refusals++
	}
	protected := {'/' + native_path: native_pin, '/' + jar_path: old_jar_pin, '/' + dex_path: old_dex_pin,
		'/' + headless + '/framework-build.json': old_framework_build_pin,
		'/' + headless + '/framework-sha256.json': old_framework_seal,
		'/' + headless + '/native-build.json': native_build_pin,
		'/' + headless + '/native-sha256.json': native_seal,
		'/' + headless + '/guest-inputs.json': old_headless_pin, '/unchanged': 'a'.repeat(64)}
	original := {'kind': json2.Any('vinix-maps-account-deployment-v1'),
		'framework_manifest_sha256': json2.Any(old_framework_seal), 'native_manifest_sha256': json2.Any(native_seal),
		'inputs_sha256': as_json(protected)!, 'unrelated': json2.Any('fixed')}
	replacements := {'/' + jar_path: jar_pin, '/' + dex_path: dex_pin,
		'/' + headless + '/framework-build.json': framework_build_pin,
		'/' + headless + '/framework-sha256.json': framework_seal,
		'/' + headless + '/guest-inputs.json': 'b'.repeat(64)}
	updated := repin_deployment(original, replacements)!
	verify_deployment_delta(original, updated, replacements)!
	for path in protected.keys() {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		mut pins := json2.decode[map[string]string](json2.encode(updated['inputs_sha256']!))!
		pins[path] = '0'.repeat(64)
		bad['inputs_sha256'] = as_json(pins)!
		if _ := verify_deployment_delta(original, bad, replacements) { return error('missing or unrelated deployment update accepted') }
		refusals++
	}
	for key in ['framework_manifest_sha256', 'native_manifest_sha256', 'unrelated', 'extra'] {
		mut bad := json2.decode[map[string]json2.Any](json2.encode(updated))!
		bad[key] = json2.Any('wrong')
		if _ := verify_deployment_delta(original, bad, replacements) { return error('unrelated deployment field change accepted') }
		refusals++
	}
	mut allowed := changed_paths()
	allowed << deployment_path
	exact_regular_names(allowed)!
	mut duplicate := allowed.clone()
	duplicate[5] = jar_path
	for bad in [allowed[..5], []string{}, [jar_path, deployment_path, 'opt/escape'], duplicate] {
		if _ := exact_regular_names(bad) { return error('wrong payload membership accepted') }
		refusals++
	}
	plan := [stage.Entry{name: jar_path, kind: 'regular', mode: 0o644}]
	good := [stage.Entry{name: 'opt', kind: 'directory', mode: 0o755}, stage.Entry{name: jar_path, kind: 'regular', mode: 0o644}]
	if inherited_modes(good, plan)![jar_path]! != 0o644 { return error('first JAR mode lost') }
	for bad in [stage.Entry{name: 'opt', kind: 'symlink', mode: 0o755},
		stage.Entry{name: jar_path, kind: 'regular', mode: 0o666}, stage.Entry{name: jar_path, kind: 'regular', mode: 0o4644}] {
		mut old := good.clone()
		old << bad
		if _ := inherited_modes(old, plan) { return error('unsafe prior inode accepted') }
		refusals++
	}
	if _ := inherited_modes([]stage.Entry{}, plan) { return error('missing original inode accepted') }
	refusals++
	mut budget := DiskBudget{available: disk_reserve + disk_growth}
	charge_audit(60, mut budget)!
	charge_audit(1, mut budget)!
	charge_audit(61, mut budget)!
	charge_audit(1, mut budget)!
	if budget.charged != 123 * digest_receipt_charge || budget.digest_receipt_charged != budget.charged { return error('complete kernel/module receipt charge differs') }
	for count in [0, 62] {
		if _ := charge_audit(count, mut budget) { return error('unbounded digest charge accepted') }
		refusals++
	}
	update_budget(disk_reserve + disk_growth, false, mut budget)!
	if _ := update_budget(disk_reserve - 1, false, mut budget) { return error('reserve violation accepted') }
	refusals++
	df := 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk1 4000000 2000000 1048576 66% /System/Volumes/Data\n'
	if available_bytes(df)! != disk_reserve { return error('df byte count differs') }
	for bad in [df.replace('1048576', '18446744073709551615'), df.replace('66%', '101%'), df + df,
		df.replace('1048576', '-1'), df.replace('1024-blocks', 'other')] {
		if _ := available_bytes(bad) { return error('malformed disk report accepted') }
		refusals++
	}
	println('MAPS-TRAFFIC-STATS-STAGE SELFTEST PASS refusals=' + refusals.str() + ' exact-six-file-SDK-only canonical2117 headless-deployment-preservation modes disk123-receipts')
}
fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 2 && os.args[1] == '--audit-framework' { audit_framework_inputs() or { eprintln(err); exit(1) }; return }
	if os.args.len == 2 && os.args[1] == '--enumerate-native-helpers' { enumerate_native_helpers() or { eprintln(err); exit(1) }; return }
	if os.args.len != 3 || os.args[1] != '--prepare' { eprintln('usage: maps-traffic-stats-stage --prepare FRESH_EXTERNAL_OUTPUT | --self-test | --audit-framework | --enumerate-native-helpers'); exit(2) }
	run(os.args[2]) or { eprintln(err); exit(1) }
}
