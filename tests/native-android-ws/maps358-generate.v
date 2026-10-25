// SPDX-License-Identifier: GPL-2.0-or-later
// Pinned Maps356 derivative with the separately qualified fortified loader.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps356-generation-2026-10-25/maps356-run.v'
const original_pin = 'ad0e102894effec9e569b86fdc5ad150d9fc84385f5367a2062904aae38fcc6b'
const baseline_pin = 'dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c'
const work = state + 'maps358-generation-2026-10-25'
const recorded = state + 'maps358-run-build-c-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const loader = 'opt/vinix-android-aarch64/usr/lib/art/native-ws/libdl_bio.so.0'
const loader_before = '206bc086ab1579b59eec865756e7d4ab8e0db5a2537b5fea3df3503de08dc5d4'
const loader_payload = 'loader/libdl_bio.so.0'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

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

fn full_build(root string, manifest_pin string, payload_pin string) !int {
	assert os.dir(root) == state.trim_right('/') && os.real_path(root) == root && !os.is_link(root)
	assert os.base(root).bytes().all(it in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_'.bytes())
	assert canonical_pin(manifest_pin) && canonical_pin(payload_pin) && payload_pin != loader_before
	assert hash(root + '/sha256.json')! == manifest_pin
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	assert expected.len > 0 && 'sha256.json' !in expected && expected[loader_payload] == payload_pin
	mut actual := map[string]string{}
	full_inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == expected, 'complete loader build readback differs: ' + root
	assert hash(root + '/sha256.json')! == manifest_pin
	return actual.len
}

fn derive(before string, loader_root string, manifest_pin string, payload_pin string) string {
	mut text := before
	// Restrict renaming to labels so every historical checksum stays intact.
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		text = text.replace(prefix + '356', prefix + '358')
	}
	text = once(text, "const driver = base + 'maps-interact-unique258'", "const loader = '" + loader + "'\nconst loader_root = '" + loader_root + "'\nconst loader_manifest = '" + manifest_pin + "'\nconst loader_pin = '" + payload_pin + "'\nconst loader_payload = '" + loader_payload + "'\nconst driver = base + 'maps-interact-unique258'")
	text = once(text, "\nfn disk_space()", "\nfn qualify_loader_build() ! {\n\tqualify_build(retained + '/loader-replacement-build', loader_manifest, loader_payload, loader_pin)!\n}\n\nfn disk_space()")
	assert text.count('\tqualify_replay_builds()!\n') == 3
	text = text.replace('\tqualify_replay_builds()!\n', '\tqualify_replay_builds()!\n\tqualify_loader_build()!\n')
	text = once(text, "\tclone(framework_root, retained + '/framework-replacement-build')!", "\tclone(framework_root, retained + '/framework-replacement-build')!\n\tclone(loader_root, retained + '/loader-replacement-build')!")
	text = once(text, "|| before[launcher]! != launcher_pin { return error('complete109 qualified350 runtime required') }", "|| before[launcher]! != launcher_pin || before[loader]! != '" + loader_before + "' { return error('complete109 qualified350 runtime required') }\n\tbaseline_typed := read_map(previous_tree + '/module-after-typed.json')!\n\tif baseline_typed['@mode:' + loader]! != '493' { return error('qualified350 loader mode0755 required') }")
	text = once(text, "\tos.cp(framework_root + '/framework/api-impl.jar', target + '/module/' + jar)!", "\tos.cp(framework_root + '/framework/api-impl.jar', target + '/module/' + jar)!\n\tos.cp(retained + '/loader-replacement-build/' + loader_payload, target + '/module/' + loader)!\n\tos.chmod(target + '/module/' + loader, 0o755)!")
	text = once(text, '\tafter[jar] = jar_pin', '\tafter[jar] = jar_pin\n\tafter[loader] = loader_pin')
	text = once(text, '\ttyped[jar] = jar_pin', '\ttyped[jar] = jar_pin\n\ttyped[loader] = loader_pin')
	text = once(text, "\tclone(target + '/module/' + jar, target + '/overlay/' + jar)!", "\tclone(target + '/module/' + jar, target + '/overlay/' + jar)!\n\tclone(target + '/module/' + loader, target + '/overlay/' + loader)!")
	text = once(text, "target + '/maps358-diagnostics.tar', native, jar]", "target + '/maps358-diagnostics.tar', native, jar, loader]")
	text = once(text, "!= native + '\\n' + jar + '\\n' { return error('exact native SO and framework JAR tar members required') }", "!= native + '\\n' + jar + '\\n' + loader + '\\n' { return error('exact native SO, framework JAR and loader tar members required') }")
	text = once(text, "'pinned replacement native/framework; unchanged diagnostic launcher'", "'pinned replacement native/framework/loader; unchanged diagnostic launcher'")
	text = once(text, "config.replace('356', '350')", "config.replace('358', '350')")
	text = once(text, "retained + '/launcher-build/sha256.json', retained + '/launcher-build/builder', retained + '/baseline350/prelaunch-sha256.json']", "retained + '/launcher-build/sha256.json', retained + '/launcher-build/builder', retained + '/baseline350/prelaunch-sha256.json',\n\t\tretained + '/loader-replacement-build/sha256.json', retained + '/loader-replacement-build/' + loader_payload]")
	text = once(text, "'changed_runtime_entries': native + ',' + jar", "'changed_runtime_entries': native + ',' + jar + ',' + loader")
	text = once(text, "'unchanged_runtime_entries': '107'", "'unchanged_runtime_entries': '106'\n\t\t'loader_replacement_build_root': loader_root\n\t\t'loader_replacement_manifest_sha256': loader_manifest\n\t\t'loader_replacement_payload': loader_payload\n\t\t'loader_sha256': loader_pin")
	text = once(text, "'Pinned native SO and framework JAR against authenticated350prelaunch109 runtime;107 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'", "'Pinned native SO, framework JAR and fortified loader against authenticated350prelaunch109 runtime;106 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'")
	assert text.count('qualify_loader_build()!') == 3
	assert text.count('qualify_replay_builds()!') == 3
	assert text.contains("const previous_pin = '" + baseline_pin + "'")
	assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
	assert text.contains("if classifier(suite_text)! != classifier(original)!")
	assert text.contains("if os.args.len == 8 && os.args[1] == 'prepare'")
	return text
}

fn generate(loader_root string, manifest_pin string, payload_pin string) ! {
	assert hash(original)! == original_pin && hash(compiler)! == compiler_pin
	assert hash(state + 'maps350-2026-10-25/prelaunch-sha256.json')! == baseline_pin
	count := full_build(loader_root, manifest_pin, payload_pin)!
	before := os.read_file(original)!
	text := derive(before, loader_root, manifest_pin, payload_pin)
	for path in [work, recorded, state + 'maps358-2026-10-25', 'build/android-maps/maps358',
		'build/android-maps/maps358-run-recorded', 'build/android-maps/attempt358', 'build/android-maps/attempt358.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(work)!
	os.write_file(work + '/maps356-input.v', before)!
	os.cp(@FILE, work + '/generator.v')!
	os.cp(os.executable(), work + '/generator')!
	os.write_file(work + '/disk-before-generation.txt', space.output)!
	os.write_file(work + '/maps358-run.v', text)!
	write_json(work + '/derivation.json', {
		'original_path': json2.Any(original)
		'original_sha256': json2.Any(original_pin)
		'baseline_prelaunch_sha256': json2.Any(baseline_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(work + '/maps358-run.v')!)
		'loader_build_root': json2.Any(loader_root)
		'loader_build_manifest_sha256': json2.Any(manifest_pin)
		'loader_payload': json2.Any(loader_payload)
		'loader_sha256': json2.Any(payload_pin)
		'loader_build_files_checked': json2.Any(count)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'scope': json2.Any('Generation and recorded runner build only. Pinned Maps356 source, authenticated350 baseline, unchanged native351/framework353 and third fortified-loader overlay.109 runtime files,106 unchanged; exact three-member final archive; unchanged launcher/base media/classifier and600seconds. No guest.')
	})!
	build_generated()!
}

fn build_generated() ! {
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	os.mkdir_all(work + '/generated-c')!
	os.setenv('VTMP', work + '/generated-c', true)
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps358-run.v']
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(work + '/maps358-run.v')!)
	}
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(work + '/bootstrap')! }
	write_json(work + '/bootstrap-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(work + '/maps358-run.v')! == receipt['source_sha256']!.str()
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
	println('MAPS358-GENERATED source=' + hash(work + '/maps358-run.v')! + ' binary=' + hash('build/android-maps/maps358-run-recorded')! + ' generation-manifest=' + hash(work + '/sha256.json')!)
}

fn main() {
	if os.args.len == 4 && os.args[1] == 'rebuild' {
		build_tool(os.abs_path(os.args[2]), os.args[3])!
		return
	}
	if os.args.len in [2, 3] && os.args[1] == '--self-test' {
		assert hash(original)! == original_pin
		before := os.read_file(original)!
		text := derive(before, state + 'test-loader-build', 'a'.repeat(64), 'b'.repeat(64))
		assert text.contains("const target = base + 'maps358'")
		assert text.contains("const previous_tree = previous + '/prelaunch/maps350'")
		assert text.contains("config.replace('358', '350')")
		assert !text.contains('maps356') && !text.contains('MAPS356')
		assert text.contains("'unchanged_runtime_entries': '106'")
		assert text.contains("'d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'")
		assert text.contains("'1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'")
		if os.args.len == 3 {
			path := os.abs_path(os.args[2])
			assert os.dir(path) == state.trim_right('/') && !os.exists(path) && !os.is_link(path)
			os.write_file(path, text)!
		}
		println('MAPS358-GENERATOR-SELF-TEST-PASS')
		return
	}
	assert os.args.len == 4, 'usage: maps358-generate LOADER_ROOT MANIFEST_SHA LOADER_SHA | rebuild BUILD_ROOT OUTPUT | --self-test [CHECK_SOURCE]'
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
