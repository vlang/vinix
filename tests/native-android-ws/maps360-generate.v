// SPDX-License-Identifier: GPL-2.0-or-later
// Pinned Maps358 derivative with the separately qualified permission framework.
module main

import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps358-generation-2026-10-25/maps358-run.v'
const original_pin = '9ec0bb2b3cdd870edbfdfae1505a01e5230d5570791ed1fd6365fedd15b6a7f7'
const original_generation_pin = '162f542e44517b2a626a938b3bfca5d8dffbd881bafd1eef4d94f904551d5240'
const baseline_pin = 'dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c'
const work = state + 'maps360-generation-2026-10-25'
const recorded = state + 'maps360-run-build-c-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework_payload = 'framework/api-impl.jar'
const framework_before = '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
const framework_before_manifest = '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
const loader_root = state + 'pwrite357-loader-build-2026-10-26'
const loader_manifest = '1aa6d2ad417643229430e3b9b13333b5c0843ed1c81faccc41dde402c0b91561'
const loader_pin = '42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 {
				return error('CC_SHA256_Update failed')
			}
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 {
			return error('CC_SHA256_Final failed')
		}
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free() } }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			if digest.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		digest.checksum_into(mut result)
		return result.hex()
	}
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn write_json(path string, value json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}

fn canonical_pin(pin string) bool {
	return pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
}

fn canonical_root(root string) bool {
	return os.dir(root) == state.trim_right('/') && os.real_path(root) == root
		&& !os.is_link(root) && os.base(root).len > 0
		&& os.base(root).bytes().all(it in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_'.bytes())
}

fn full_inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { full_inventory(root, key, mut entries)! }
			else { return error('unexpected build artifact: ' + path) }
		}
	}
}

fn qualify_build(root string, manifest_pin string, payload string, payload_pin string) !int {
	assert canonical_pin(manifest_pin) && canonical_pin(payload_pin)
	assert hash(root + '/sha256.json')! == manifest_pin
	expected := read_map(root + '/sha256.json')!
	assert expected.len > 0 && 'sha256.json' !in expected && expected[payload] == payload_pin
	mut actual := map[string]string{}
	full_inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == expected, 'complete build readback differs: ' + root
	assert hash(root + '/sha256.json')! == manifest_pin
	return actual.len
}

// BEGIN SHARED FRAMEWORK359 CONTRACT
fn qualify_framework359(root string, manifest_pin string, jar_pin string) !int {
	count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
	qualify_build(root + '/baseline353', '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f', 'framework/api-impl.jar', '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83')!
	delta := object(root + '/framework/dex-delta.json')!
	old := delta['old_classes']!.as_map()
	new := delta['new_classes']!.as_map()
	changed := 'android/content/pm/PackageManager.smali'
	if old.len != 2073 || new.len != 2073
		|| delta['changed_existing_classes']!.as_array().map(it.str()) != [changed]
		|| delta['added_classes']!.as_array().len != 0 || delta['removed_classes']!.as_array().len != 0
		|| delta['old_jar_sha256']!.str() != '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
		|| delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
		|| delta['jar_member_count']!.int() < 1 || changed !in old || changed !in new {
		return error('exact permission359 framework delta required')
	}
	for name, pin in old {
		if name !in new || (name == changed && pin.str() == new[name]!.str())
			|| (name != changed && pin.str() != new[name]!.str()) {
			return error('permission359 DEX class delta differs: ' + name)
		}
	}
	smali := object(root + '/framework/smali-delta.json')!
	before := smali['before']!.as_map()
	after := smali['after']!.as_map()
	if before.len != 2073 || after.len != 2073 || changed !in before || changed !in after
		|| smali['changed']!.as_array().map(it.str()) != [changed] || !smali['duplicate_guard_unchanged']!.bool() {
		return error('exact permission359 source and duplicate guard required')
	}
	for name, pin in before {
		if name !in after || (name == changed && pin.str() == after[name]!.str())
			|| (name != changed && pin.str() != after[name]!.str()) {
			return error('permission359 source class delta differs: ' + name)
		}
	}
	validation := read_map(root + '/validation.json')!
	if validation['baseline_manifest_sha256']! != '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
		|| validation['old_framework_sha256']! != '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
		|| validation['new_framework_sha256']! != jar_pin || validation['changed_class']! != changed
		|| validation['class_count']! != '2073' {
		return error('permission359 validation differs')
	}
	return count
}
// END SHARED FRAMEWORK359 CONTRACT

fn framework_contract() !string {
	return os.read_file(@FILE)!.all_after('\n// BEGIN SHARED FRAMEWORK359 CONTRACT\n').all_before('\n// END SHARED FRAMEWORK359 CONTRACT\n')
}

fn derive(before string, framework_root string, manifest_pin string, jar_pin string) !string {
	mut text := before
	// Restrict renaming to replay labels; historical hashes and baseline350 stay intact.
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		text = text.replace(prefix + '358', prefix + '360')
	}
	text = once(text, "const driver = base + 'maps-interact-unique258'", "const framework359_root = '" + framework_root + "'\nconst framework359_manifest = '" + manifest_pin + "'\nconst framework359_pin = '" + jar_pin + "'\nconst driver = base + 'maps-interact-unique258'")
	text = once(text, "\nfn qualify_loader_build() ! {", '\n' + framework_contract()! + "\n\nfn qualify_loader_build() ! {")
	text = once(text, "\tqualify_build(retained + '/framework-replacement-build', '" + framework_before_manifest + "', 'framework/api-impl.jar', '" + framework_before + "')!", "\tqualify_framework359(retained + '/framework-replacement-build', framework359_manifest, framework359_pin)!")
	text = once(text, "|| framework_root != '/Users/alex/.local/state/vinix/android/screen-reader-focusable353-framework-build-2026-10-25'", '|| framework_root != framework359_root')
	text = once(text, "|| framework_manifest != '" + framework_before_manifest + "'", '|| framework_manifest != framework359_manifest')
	text = once(text, "|| jar_pin != '" + framework_before + "'", '|| jar_pin != framework359_pin')
	text = once(text, "'framework_replacement_manifest_sha256': '" + framework_before_manifest + "'", "'framework_replacement_manifest_sha256': framework359_manifest")
	text = once(text, "'pinned replacement native/framework/loader; unchanged diagnostic launcher'", "'permission359 framework; pinned native351 and fortified loader357; unchanged diagnostic launcher'")
	text = once(text, "config.replace('358', '350')", "config.replace('360', '350')")
	text = once(text, "'Pinned native SO, framework JAR and fortified loader against authenticated350prelaunch109 runtime;106 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'", "'Permission359 framework with pinned native351 and fortified loader357 against authenticated350prelaunch109 runtime;106 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'")
	assert text.count('qualify_replay_builds()!') == 3 && text.count('qualify_loader_build()!') == 3
	assert text.count('qualify_framework359(retained + ') == 1
	assert text.contains("const loader_root = '" + loader_root + "'")
	assert text.contains("const loader_manifest = '" + loader_manifest + "'")
	assert text.contains("const loader_pin = '" + loader_pin + "'")
	assert text.contains("const previous_pin = '" + baseline_pin + "'")
	assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
	assert text.contains('if classifier(suite_text)! != classifier(original)!')
	assert text.contains("if os.args.len == 8 && os.args[1] == 'prepare'")
	return text
}

fn generate(framework_root string, manifest_pin string, jar_pin string) ! {
	assert canonical_root(framework_root) && canonical_pin(manifest_pin) && canonical_pin(jar_pin)
	assert jar_pin != framework_before
	assert hash(original)! == original_pin && hash(compiler)! == compiler_pin
	assert hash(state + 'maps358-generation-2026-10-25/sha256.json')! == original_generation_pin
	assert hash(state + 'maps350-2026-10-25/prelaunch-sha256.json')! == baseline_pin
	count := qualify_framework359(framework_root, manifest_pin, jar_pin)!
	loader_count := qualify_build(loader_root, loader_manifest, 'loader/libdl_bio.so.0', loader_pin)!
	before := os.read_file(original)!
	text := derive(before, framework_root, manifest_pin, jar_pin)!
	for path in [work, recorded, state + 'maps360-2026-10-25', 'build/android-maps/maps360',
		'build/android-maps/maps360-run-recorded', 'build/android-maps/attempt360', 'build/android-maps/attempt360.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(work)!
	os.write_file(work + '/maps358-input.v', before)!
	os.cp(@FILE, work + '/generator.v')!
	os.cp(os.executable(), work + '/generator')!
	os.write_file(work + '/disk-before-generation.txt', space.output)!
	os.write_file(work + '/maps360-run.v', text)!
	write_json(work + '/derivation.json', {
		'original_path': json2.Any(original)
		'original_sha256': json2.Any(original_pin)
		'original_generation_manifest_sha256': json2.Any(original_generation_pin)
		'baseline_prelaunch_sha256': json2.Any(baseline_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(work + '/maps360-run.v')!)
		'framework_build_root': json2.Any(framework_root)
		'framework_build_manifest_sha256': json2.Any(manifest_pin)
		'framework_payload': json2.Any(framework_payload)
		'framework_sha256': json2.Any(jar_pin)
		'framework_build_files_checked': json2.Any(count)
		'loader_build_manifest_sha256': json2.Any(loader_manifest)
		'loader_sha256': json2.Any(loader_pin)
		'loader_build_files_checked': json2.Any(loader_count)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'scope': json2.Any('Generation and recorded runner build only. Pinned Maps358 source and authenticated350 baseline; permission359 framework with complete353 baseline and sole PackageManager source/DEX delta retained. Unchanged native351 and fortified loader357;109 runtime files,106 unchanged; exact three-member final archive; unchanged launcher/base media/APK/classifier and600seconds. No guest.')
	})!
	build_generated()!
}

fn build_generated() ! {
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	os.mkdir_all(work + '/generated-c')!
	os.setenv('VTMP', work + '/generated-c', true)
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps360-run.v']
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(work + '/maps360-run.v')!)
	}
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(work + '/bootstrap')! }
	write_json(work + '/bootstrap-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(work + '/maps360-run.v')! == receipt['source_sha256']!.str()
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	assert rebuilt.exit_code == 0, rebuilt.output
	mut pins := map[string]string{}
	full_inventory(work, '', mut pins)!
	write_json(work + '/sha256.json', json2.decode[json2.Any](json2.encode(pins))!)!
	cloned := os.exec(['cp', '-c', '-R', '-P', work, recorded + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	mut cloned_inventory := map[string]string{}
	full_inventory(recorded + '/generation', '', mut cloned_inventory)!
	cloned_inventory.delete('sha256.json')
	assert cloned_inventory == pins
	assert hash(recorded + '/generation/sha256.json')! == hash(work + '/sha256.json')!
	println('MAPS360-GENERATED source=' + hash(work + '/maps360-run.v')! + ' binary=' + hash('build/android-maps/maps360-run-recorded')! + ' generation-manifest=' + hash(work + '/sha256.json')!)
}

fn self_test(output string) ! {
	for pin in [original_pin, original_generation_pin, baseline_pin, compiler_pin,
		framework_before, framework_before_manifest, loader_manifest, loader_pin] {
		assert canonical_pin(pin)
	}
	assert hash(original)! == original_pin
	before := os.read_file(original)!
	text := derive(before, state + 'test-framework359-build', 'a'.repeat(64), 'b'.repeat(64))!
	assert text.contains("const target = base + 'maps360'")
	assert text.contains("const previous_tree = previous + '/prelaunch/maps350'")
	assert text.contains("config.replace('360', '350')")
	assert !text.contains('maps358') && !text.contains('MAPS358')
	assert text.contains("'unchanged_runtime_entries': '106'")
	assert text.contains("'d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'")
	assert text.contains("const framework359_manifest = '" + 'a'.repeat(64) + "'")
	assert text.contains("const framework359_pin = '" + 'b'.repeat(64) + "'")
	assert text.contains('equal(actual, read_map(retained + \'/sha256.json\')!)!')
	assert text.contains('equal(tree(target + \'/module\', true)!, read_map(target + \'/module-after-typed.json\')!)!')
	assert text.contains("['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar']")
	assert text.contains("for name, pin in media { if media_hash(name)! != pin")
	assert text.contains("exact native SO, framework JAR and loader tar members required")
	mut normalized := text
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		normalized = normalized.replace(prefix + '360', prefix + '358')
	}
	for name in ['hash', 'inventory', 'tree', 'build_inventory', 'qualify_build', 'equal',
		'receipt', 'classifier', 'qualify_runner_build', 'qualify_builds', 'qualify_parent_framework',
		'qualify_loader_build', 'disk_space', 'qualify_launcher', 'qualify_baseline', 'media_hash',
		'gate', 'results', 'run', 'verify'] {
		start := '\nfn ' + name + '('
		assert before.count(start) == 1 && normalized.count(start) == 1
		assert before.all_after(start).all_before('\nfn ') == normalized.all_after(start).all_before('\nfn '),
			'inherited replay function changed: ' + name
	}
	if output != '' {
		path := os.abs_path(output)
		assert os.dir(path) == state.trim_right('/') && !os.exists(path) && !os.is_link(path)
		os.write_file(path, text)!
	}
	println('MAPS360-GENERATOR-SELF-TEST-PASS')
}

fn main() {
	$if prod { panic('requires assertions') }
	if os.args.len == 4 && os.args[1] == 'rebuild' {
		build_tool(os.abs_path(os.args[2]), os.args[3])!
		return
	}
	if os.args.len in [2, 3] && os.args[1] == '--self-test' {
		self_test(if os.args.len == 3 { os.args[2] } else { '' })!
		return
	}
	assert os.args.len == 4, 'usage: maps360-generate FRAMEWORK_ROOT MANIFEST_SHA FRAMEWORK_SHA | rebuild BUILD_ROOT OUTPUT | --self-test [CHECK_SOURCE]'
	generate(os.abs_path(os.args[1]), os.args[2], os.args[3])!
}

fn build_tool(destination string, output string) ! {
	assert os.dir(destination) == state.trim_right('/') && os.abs_path(destination) == destination
	assert os.dir(output) == 'build/android-maps' && !os.exists(output) && !os.is_link(output)
	assert !os.exists(destination) && !os.is_link(destination) && hash(compiler)! == compiler_pin
	os.mkdir(destination)!
	os.cp(@FILE, destination + '/source.v')!
	os.cp(compiler, destination + '/v_old276')!
	os.mkdir(destination + '/generated-c')!
	os.setenv('VTMP', destination + '/generated-c', true)
	listing_argv := [compiler, '-print-v-files', @FILE]
	started := time.utc().str()
	listing := os.exec(listing_argv)
	os.write_file(destination + '/closure-v-files.txt', listing.output)!
	write_json(destination + '/closure-receipt.json', {
		'argv': json2.Any(listing_argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(listing.exit_code)
		'compiler_sha256': json2.Any(compiler_pin)
	})!
	assert listing.exit_code == 0, listing.output
	mut before := map[string]string{}
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[path] = hash(path)!
		copy_path := destination + '/closure/' + os.abs_path(path).trim_left('/')
		os.mkdir_all(os.dir(copy_path))!
		os.cp(path, copy_path)!
	}
	assert before.len >= 10
	write_json(destination + '/closure-before.json', json2.decode[json2.Any](json2.encode(before))!)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', output, @FILE]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(@FILE)!)
		'closure_before_sha256': json2.Any(hash(destination + '/closure-before.json')!)
	}
	write_json(destination + '/build-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(destination + '/build.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	mut after := map[string]string{}
	for path, pin in before {
		after[path] = hash(path)!
		assert after[path] == pin && hash(destination + '/closure/' + os.abs_path(path).trim_left('/'))! == pin
	}
	write_json(destination + '/closure-after.json', json2.decode[json2.Any](json2.encode(after))!)!
	receipt['closure_after_sha256'] = hash(destination + '/closure-after.json')!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	if result.exit_code == 0 {
		receipt['binary_sha256'] = hash(output)!
		os.cp(output, destination + '/program')!
	}
	write_json(destination + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	mut inventory := map[string]string{}
	full_inventory(destination, '', mut inventory)!
	write_json(destination + '/sha256.json', json2.decode[json2.Any](json2.encode(inventory))!)!
	println('MAPS-REPLAY-GENERATOR-BUILD source=' + hash(@FILE)! + ' binary=' + hash(output)! + ' seal=' + hash(destination + '/sha256.json')!)
}
