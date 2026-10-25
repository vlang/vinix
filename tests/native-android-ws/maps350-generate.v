// SPDX-License-Identifier: GPL-2.0-or-later
// Historical Maps350 generation, plus pinned native/framework replays of Maps350.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps335-generation-2026-10-25/maps335-run.v'
const original_pin = '6880dc6ac36750d71c1939a87988e6606359cda305b25e1a13548da3c644fe2d'
const work = state + 'maps350-generation-2026-10-25'
const recorded = state + 'maps350-run-build-c-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const launcher_root = state + 'maps334-trace-launcher-build-2026-10-25'
const launcher_manifest = '25855fcb5aa5016d7cc5df659017f66b6f3dc5d96e4935d474d691b59de9fc27'
const launcher_pin = '52e305950821e56d85bb9c4d6ba51a3c5f74ccf2b15b158d1fd47279cb70ef56'
const framework_root = state + 'media-codec-exceptions349-2026-10-25'
const framework_manifest = '0700318453dfb6373ea07587c3f42b09fbdb65930dffd35eda0664deddde8f88'
const framework_pin = '95aabc17c85a5cda0d643dfa5ef9e618955d422d960ffb3bbc2db74c86a9c37d'
const replay_original = state + 'maps350-generation-2026-10-25/maps350-run.v'
const replay_original_pin = 'b2d08a2974764b9925d311a7a025fd10eb339fac30c58aa1e48380cce3835d93'
const replay_baseline_pin = 'dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json(path string, value json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
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

fn full_build(root string, manifest_pin string, payload string, payload_pin string) !int {
	assert os.dir(root) == state.trim_right('/') && os.real_path(root) == root && !os.is_link(root)
	assert hash(root + '/sha256.json')! == manifest_pin
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	assert expected.len > 0 && 'sha256.json' !in expected && expected[payload] == payload_pin
	mut actual := map[string]string{}
	full_inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == expected, 'complete build readback differs: ' + root
	assert hash(root + '/sha256.json')! == manifest_pin
	return actual.len
}

fn replay_pins(path string, pin string) !map[string]string {
	assert os.dir(path) == state.trim_right('/') && os.real_path(path) == path && !os.is_link(path)
	assert hash(path)! == pin
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	assert pins.len == 6
	for label in ['native', 'framework'] {
		for suffix in ['_root', '_manifest_sha256', '_sha256'] { assert label + suffix in pins }
		root := pins[label + '_root']
		assert os.base(root).ends_with('-' + label + '-build-2026-10-25')
		assert os.base(root).bytes().all(it in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_'.bytes())
		for key in [label + '_manifest_sha256', label + '_sha256'] {
			assert pins[key].len == 64 && pins[key].bytes().all(it in '0123456789abcdef'.bytes())
		}
		payload := if label == 'native' { 'native/libvinix-android-native.so' } else { 'framework/api-impl.jar' }
		full_build(root, pins[label + '_manifest_sha256'], payload, pins[label + '_sha256'])!
	}
	return pins
}

fn derive_replay(before string, number string, pins map[string]string) string {
	// Replace labels, never bare digits: historical SHA values remain byte-identical.
	mut text := before
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		text = text.replace(prefix + '350', prefix + number)
	}
	text = once(text, "const previous = '" + state + "maps335-2026-10-25'", "const previous = '" + state + "maps350-2026-10-25'")
	text = once(text, "const previous_pin = '8d493e4588b6b3af87316824809f902bb50aac577b0e58e95d435ae02f2e137a'", "const previous_pin = '" + replay_baseline_pin + "'")
	text = text.replace("previous + '/prelaunch/maps335'", "previous + '/prelaunch/maps350'")
	text = text.replace('baseline335', 'baseline350').replace('maps335_prelaunch', 'maps350_prelaunch')
	old_guard := "\tif native_root != '" + state + "layout-request332-native-build-2026-10-25'\n\t\t|| native_manifest != '40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163'\n\t\t|| native_pin != '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b'\n\t\t|| framework_root != '" + framework_root + "'\n\t\t|| framework_manifest != '" + framework_manifest + "'\n\t\t|| jar_pin != '" + framework_pin + "' { return error('exact Native332 and media-codec-exceptions349 framework required') }"
	new_guard := "\tif native_root != '" + pins['native_root'] + "'\n\t\t|| native_manifest != '" + pins['native_manifest_sha256'] + "'\n\t\t|| native_pin != '" + pins['native_sha256'] + "'\n\t\t|| framework_root != '" + pins['framework_root'] + "'\n\t\t|| framework_manifest != '" + pins['framework_manifest_sha256'] + "'\n\t\t|| jar_pin != '" + pins['framework_sha256'] + "' { return error('exact replay native/framework roots and pins required') }"
	text = once(text, old_guard, new_guard)
	mut qualifier := '\nfn qualify_replay_builds() ! {\n'
	for label in ['native', 'framework'] {
		payload := if label == 'native' { 'native/libvinix-android-native.so' } else { 'framework/api-impl.jar' }
		qualifier += "\tqualify_build(retained + '/" + label + "-replacement-build', '" + pins[label + '_manifest_sha256'] + "', '" + payload + "', '" + pins[label + '_sha256'] + "')!\n"
	}
	qualifier += '}\n\nfn disk_space()'
	text = once(text, '\nfn disk_space()', qualifier)
	text = once(text, "\tclone(framework_root, retained + '/framework-parent-build')!", "\tclone(previous + '/framework-parent-build', retained + '/framework-parent-build')!\n\tclone(native_root, retained + '/native-replacement-build')!\n\tclone(framework_root, retained + '/framework-replacement-build')!")
	text = text.replace('\tqualify_parent_framework()!\n', '\tqualify_parent_framework()!\n\tqualify_replay_builds()!\n')
	text = once(text, "before[native]! != native_pin || before[jar]! != '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca'", "before[native]! != '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b' || before[jar]! != '" + framework_pin + "'")
	text = once(text, 'complete109 qualified335 runtime required', 'complete109 qualified350 runtime required')
	text = once(text, "\tos.cp(framework_root + '/framework/api-impl.jar', target + '/module/' + jar)!", "\tos.cp(native_root + '/native/libvinix-android-native.so', target + '/module/' + native)!\n\tos.cp(framework_root + '/framework/api-impl.jar', target + '/module/' + jar)!")
	text = once(text, '\tafter[jar] = jar_pin', '\tafter[native] = native_pin\n\tafter[jar] = jar_pin')
	text = once(text, '\ttyped[jar] = jar_pin', '\ttyped[native] = native_pin\n\ttyped[jar] = jar_pin')
	text = once(text, "['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar']", "['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar']")
	text = once(text, "old_conf.count('module_path:') != 3 || !old_conf.ends_with('    module_path: boot():/boot/maps335-diagnostics.tar\\n')", "old_conf.count('module_path:') != 4 || !old_conf.ends_with('    module_path: boot():/boot/maps350-diagnostics.tar\\n')")
	text = once(text, 'expected335 initramfs, runtime and diagnostic launcher boot order', 'expected350 initramfs, runtime, launcher and framework boot order')
	text = once(text, "\tclone(target + '/module/' + jar, target + '/overlay/' + jar)!", "\tclone(target + '/module/' + native, target + '/overlay/' + native)!\n\tclone(target + '/module/' + jar, target + '/overlay/' + jar)!")
	text = once(text, "target + '/maps" + number + "-diagnostics.tar', jar]", "target + '/maps" + number + "-diagnostics.tar', native, jar]")
	text = once(text, "!= jar + '\\n' { return error('only one framework JAR tar member allowed') }", "!= native + '\\n' + jar + '\\n' { return error('exact native SO and framework JAR tar members required') }")
	text = once(text, "previous_tree + '/suite335.v'", "previous_tree + '/suite350.v'")
	text = once(text, "original.replace('validate_styled335', 'validate_styled" + number + "').replace('MAPS335', 'MAPS" + number + "').replace('build/android-maps/maps335/', 'build/android-maps/maps" + number + "/')", "original.replace('validate_styled350', 'validate_styled" + number + "').replace('MAPS350', 'MAPS" + number + "').replace('build/android-maps/maps350/', 'build/android-maps/maps" + number + "/')")
	text = once(text, "'unchanged framework/native; explicit diagnostic launcher overlay', 'media-codec-exceptions349 framework; unchanged native and diagnostic launcher'", "'media-codec-exceptions349 framework; unchanged native and diagnostic launcher', 'pinned replacement native/framework; unchanged diagnostic launcher'")
	text = once(text, "config.replace('350', '335')", "config.replace('" + number + "', '350')")
	text = once(text, "\t\t'changed_runtime_entry': jar\n\t\t'unchanged_runtime_entries': '108'", "\t\t'changed_runtime_entries': native + ',' + jar\n\t\t'unchanged_runtime_entries': '107'\n\t\t'native_replacement_manifest_sha256': '" + pins['native_manifest_sha256'] + "'\n\t\t'framework_replacement_manifest_sha256': '" + pins['framework_manifest_sha256'] + "'")
	text = once(text, "'Media-codec-exceptions349 framework JAR only against authenticated335prelaunch109 runtime. Native, diagnostic launcher, identity256 and600second observation unchanged; original335 kernel/initramfs/runtime/diagnostic boot members unchanged.'", "'Pinned native SO and framework JAR against authenticated350prelaunch109 runtime;107 entries, diagnostic launcher, identity256,600second classifier and all350 base boot members unchanged. Complete baseline and replacement builds retained and qualified.'")
	assert text.count('qualify_replay_builds()!') == 3
	assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
	assert text.contains("if classifier(suite_text)! != classifier(original)!")
	assert text.contains("const launcher_root = '" + launcher_root + "'")
	return text
}

fn replay(number string, path string, pin string) ! {
	assert number.int().str() == number && number.int() > 350
	assert hash(replay_original)! == replay_original_pin && hash(compiler)! == compiler_pin
	assert hash(state + 'maps350-2026-10-25/prelaunch-sha256.json')! == replay_baseline_pin
	pins := replay_pins(path, pin)!
	before := os.read_file(replay_original)!
	text := derive_replay(before, number, pins)
	replay_work := state + 'maps' + number + '-generation-2026-10-25'
	replay_recorded := state + 'maps' + number + '-run-build-c-2026-10-25'
	for destination in [replay_work, replay_recorded, state + 'maps' + number + '-2026-10-25', 'build/android-maps/maps' + number,
		'build/android-maps/maps' + number + '-run-recorded', 'build/android-maps/attempt' + number, 'build/android-maps/attempt' + number + '.json'] {
		assert !os.exists(destination) && !os.is_link(destination), 'fresh destination required: ' + destination
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(replay_work)!
	os.write_file(replay_work + '/maps350-input.v', before)!
	os.cp(@FILE, replay_work + '/generator.v')!
	os.cp(os.executable(), replay_work + '/generator')!
	os.cp(path, replay_work + '/replacement-pins.json')!
	os.write_file(replay_work + '/disk-before-generation.txt', space.output)!
	os.write_file(replay_work + '/maps' + number + '-run.v', text)!
	write_json(replay_work + '/derivation.json', {
		'original_path': json2.Any(replay_original)
		'original_sha256': json2.Any(replay_original_pin)
		'baseline_prelaunch_sha256': json2.Any(replay_baseline_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(replay_work + '/maps' + number + '-run.v')!)
		'replacement_pins_path': json2.Any(path)
		'replacement_pins_sha256': json2.Any(pin)
		'replacement_pins': json2.decode[json2.Any](json2.encode(pins))!
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'scope': json2.Any('Generation and recorded runner build only. Authenticated350 baseline; complete baseline/replacement build readbacks, two-member final native/framework overlay,109 runtime files,107 unchanged entries, unchanged launcher/base media/classifier and600seconds. No guest.')
	})!
	build_generated(replay_work, replay_recorded, number)!
}

fn derive(before string) string {
	mut text := before.replace('335', '350')
	text = once(text, "const previous = '" + state + "maps333-2026-10-25'", "const previous = '" + state + "maps335-2026-10-25'")
	text = once(text, "const previous_pin = '55af9e0f9a9f3d2b8479a41800fa9ba120c4a47b17b8703d8ebd8f5a199a7b67'", "const previous_pin = '8d493e4588b6b3af87316824809f902bb50aac577b0e58e95d435ae02f2e137a'")
	text = text.replace("previous + '/prelaunch/maps333'", "previous + '/prelaunch/maps335'")
	text = text.replace('baseline333', 'baseline335').replace('maps333_prelaunch', 'maps335_prelaunch')
	text = once(text, "\t\t|| framework_root != '/Users/alex/.local/state/vinix/android/layout-request332-framework-build-2026-10-25'\n\t\t|| framework_manifest != '6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf'\n\t\t|| jar_pin != '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca' { return error('exact unchanged Native332 and Framework332 required') }",
		"\t\t|| framework_root != '" + framework_root + "'\n\t\t|| framework_manifest != '" + framework_manifest + "'\n\t\t|| jar_pin != '" + framework_pin + "' { return error('exact Native332 and media-codec-exceptions349 framework required') }")
	text = once(text, '\nfn disk_space()', "\nfn qualify_parent_framework() ! {\n\tqualify_build(retained + '/framework-parent-build', '" + framework_manifest + "', 'framework/api-impl.jar', '" + framework_pin + "')!\n}\n\nfn disk_space()")
	text = once(text, '\tqualify_builds()!\n\tclone(previous', "\tclone(framework_root, retained + '/framework-parent-build')!\n\tqualify_builds()!\n\tqualify_parent_framework()!\n\tclone(previous")
	text = text.replace('\tqualify_builds()!\n\tqualify_baseline()!', '\tqualify_builds()!\n\tqualify_parent_framework()!\n\tqualify_baseline()!')
	text = once(text, "before[jar]! != jar_pin || before[launcher]! != '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'", "before[jar]! != '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca' || before[launcher]! != launcher_pin")
	text = once(text, "complete109 qualified333 runtime required", "complete109 qualified335 runtime required")
	text = once(text, "\tos.cp(launcher_root + '/run-android-calculator', target + '/module/' + launcher)!\n\tos.chmod(target + '/module/' + launcher, 0o755)!", "\tos.cp(framework_root + '/framework/api-impl.jar', target + '/module/' + jar)!")
	text = text.replace('after[launcher] = launcher_pin', 'after[jar] = jar_pin').replace('typed[launcher] = launcher_pin', 'typed[jar] = jar_pin')
	text = once(text, "for name in ['vinix', 'initramfs.tar', 'qemu-runtime.tar']", "for name in ['vinix', 'initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar']")
	text = once(text, "old_conf.count('module_path:') != 2 || !old_conf.ends_with('    module_path: boot():/boot/qemu-runtime.tar\\n')", "old_conf.count('module_path:') != 3 || !old_conf.ends_with('    module_path: boot():/boot/maps335-diagnostics.tar\\n')")
	text = once(text, "expected initramfs then runtime boot order", "expected335 initramfs, runtime and diagnostic launcher boot order")
	text = once(text, "\tos.mkdir_all(target + '/overlay/usr/bin')!\n\tclone(target + '/module/' + launcher, target + '/overlay/' + launcher)!", "\tclone(target + '/module/' + jar, target + '/overlay/' + jar)!")
	text = once(text, "target + '/maps350-diagnostics.tar', launcher]", "target + '/maps350-diagnostics.tar', jar]")
	text = once(text, "!= launcher + '\\n' { return error('only one launcher tar member allowed') }", "!= jar + '\\n' { return error('only one framework JAR tar member allowed') }")
	text = once(text, "previous_tree + '/suite333.v'", "previous_tree + '/suite335.v'")
	text = once(text, "original.replace('validate_styled333', 'validate_styled350').replace('MAPS333', 'MAPS350').replace('build/android-maps/maps333/', 'build/android-maps/maps350/')", "original.replace('validate_styled335', 'validate_styled350').replace('MAPS335', 'MAPS350').replace('build/android-maps/maps335/', 'build/android-maps/maps350/')")
	text = once(text, "'framework/native/clean launcher overlays', 'unchanged framework/native; explicit diagnostic launcher overlay'", "'unchanged framework/native; explicit diagnostic launcher overlay', 'media-codec-exceptions349 framework; unchanged native and diagnostic launcher'")
	text = once(text, "previous + '/prelaunch/inputs/' + config.replace('350', '333')", "previous + '/prelaunch/inputs/Users/alex/code/vinix/' + config.replace('350', '335')")
	text = once(text, "\t\t'changed_runtime_entry': launcher", "\t\t'changed_runtime_entry': jar")
	text = once(text, "\t\t'scope': 'Diagnostic launcher only; same109 runtime, native/framework, identity256 and600second observation; ordered final boot module, original kernel/initramfs/runtime unchanged.'", "\t\t'framework_parent_manifest_sha256': '" + framework_manifest + "'\n\t\t'scope': 'Media-codec-exceptions349 framework JAR only against authenticated335prelaunch109 runtime. Native, diagnostic launcher, identity256 and600second observation unchanged; original335 kernel/initramfs/runtime/diagnostic boot members unchanged.'")
	text = once(text, "\targv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + 'maps350-run-recorded',", "\tos.mkdir_all(outer_build + '/generated-c')!\n\tos.setenv('VTMP', os.abs_path(outer_build + '/generated-c'), true)\n\targv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-cflags', '-O2', '-o', base + 'maps350-run-recorded',")
	text = once(text, "\tif receipt('suite-build', [compiler, '-nocache',", "\tos.mkdir_all(retained + '/generated-c')!\n\tos.setenv('VTMP', os.abs_path(retained + '/generated-c'), true)\n\tif receipt('suite-build', [compiler, '-nocache', '-keepc', '-showcc',")
	assert text.count('qualify_parent_framework()!') == 3
	assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
	assert text.contains("const launcher_root = '" + launcher_root + "'")
	return text
}
fn main() {
	$if prod { panic('assertions required') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	for key in os.environ().keys() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' { os.unsetenv(key) }
	}
	if os.args.len == 5 && os.args[1] == 'replay' {
		replay(os.args[2], os.args[3], os.args[4])!
		return
	}
	if os.args.len == 4 && os.args[1] == 'rebuild' {
		build_tool(os.args[2], os.args[3])!
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		assert hash(original)! == original_pin && hash(replay_original)! == replay_original_pin
		assert sha256.sum(derive(os.read_file(original)!).bytes()).hex() == replay_original_pin
		pins := {
			'native_root': state + 'test-native-build-2026-10-25'
			'native_manifest_sha256': '1'.repeat(64)
			'native_sha256': '2'.repeat(64)
			'framework_root': state + 'test-framework-build-2026-10-25'
			'framework_manifest_sha256': '3'.repeat(64)
			'framework_sha256': '4'.repeat(64)
		}
		text := derive_replay(os.read_file(replay_original)!, '352', pins)
		assert text.contains("const previous = '" + state + "maps350-2026-10-25'")
		assert text.contains("config.replace('352', '350')")
		assert text.contains("'maps335-diagnostics.tar', 'maps350-diagnostics.tar'")
		println('MAPS350-GENERATOR-SELF-TEST PASS historical generated bytes unchanged; replay uses350 baseline and two payloads')
		return
	}
	assert os.args.len == 1, 'usage: maps350-generate [replay NUMBER PINS_JSON PINS_SHA | rebuild BUILD_ROOT OUTPUT | --self-test]'
	assert hash(original)! == original_pin && hash(compiler)! == compiler_pin
	assert hash(launcher_root + '/sha256.json')! == launcher_manifest
	assert hash(launcher_root + '/run-android-calculator')! == launcher_pin
	checked := os.exec([launcher_root + '/builder', 'check', launcher_root, launcher_manifest])
	assert checked.exit_code == 0, checked.output
	before := os.read_file(original)!
	text := derive(before)
	for path in [work, recorded, state + 'maps350-2026-10-25', 'build/android-maps/maps350',
		'build/android-maps/maps350-run-recorded', 'build/android-maps/attempt350', 'build/android-maps/attempt350.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(work)!
	os.write_file(work + '/maps335-input.v', before)!
	os.write_file(work + '/generator.v', os.read_file(@FILE)!)!
	os.cp(os.executable(), work + '/generator')!
	os.write_file(work + '/disk-before-generation.txt', space.output)!
	os.write_file(work + '/launcher-check.log', checked.output)!
	os.write_file(work + '/maps350-run.v', text)!
	write_json(work + '/derivation.json', {
		'original_path': json2.Any(original)
		'original_sha256': json2.Any(original_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(work + '/maps350-run.v')!)
		'launcher_root': json2.Any(launcher_root)
		'launcher_manifest_sha256': json2.Any(launcher_manifest)
		'launcher_sha256': json2.Any(launcher_pin)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'framework_root': json2.Any(framework_root)
		'framework_manifest_sha256': json2.Any(framework_manifest)
		'framework_sha256': json2.Any(framework_pin)
		'changes': json2.Any('335 to350 identifiers; authenticated335 prelaunch baseline; JAR-only final boot overlay with qualified349 MediaCodec exceptions. Same native, diagnostic launcher, kernel/base media, full qualification/build receipts,1536MiB gates and600second classifier. Generated C retained for runner and suite.')
		'scope': json2.Any('Generation and recorded host runner build only; no preparation, media staging or guest launch.')
	})!
	build_generated(work, recorded, '350')!
}

fn build_generated(work string, recorded string, number string) ! {
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	os.mkdir_all(work + '/generated-c')!
	os.setenv('VTMP', work + '/generated-c', true)
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps' + number + '-run.v']
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(work + '/maps' + number + '-run.v')!)
	}
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(work + '/bootstrap')! }
	write_json(work + '/bootstrap-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(work + '/maps' + number + '-run.v')! == receipt['source_sha256']!.str()
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	assert rebuilt.exit_code == 0, rebuilt.output
	mut pins := map[string]string{}
	if number == '350' {
		for path in os.walk_ext(work, '') { if os.is_file(path) { pins[path.all_after(work + '/')] = hash(path)! } }
	} else { full_inventory(work, '', mut pins)! }
	write_json(work + '/sha256.json', json2.decode[json2.Any](json2.encode(pins))!)!
	cloned := os.exec(['cp', '-c', '-R', '-P', work, recorded + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	assert hash(recorded + '/generation/sha256.json')! == hash(work + '/sha256.json')!
	println('MAPS' + number + '-GENERATED source=' + hash(work + '/maps' + number + '-run.v')! + ' binary=' + hash('build/android-maps/maps' + number + '-run-recorded')! + ' generation-manifest=' + hash(work + '/sha256.json')!)
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
