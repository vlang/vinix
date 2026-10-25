// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh Maps335 replay with the qualified touch-delegate344 framework only.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps335-generation-2026-10-25/maps335-run.v'
const original_pin = '6880dc6ac36750d71c1939a87988e6606359cda305b25e1a13548da3c644fe2d'
const work = state + 'maps345-generation-2026-10-25'
const recorded = state + 'maps345-run-build-c-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const launcher_root = state + 'maps334-trace-launcher-build-2026-10-25'
const launcher_manifest = '25855fcb5aa5016d7cc5df659017f66b6f3dc5d96e4935d474d691b59de9fc27'
const launcher_pin = '52e305950821e56d85bb9c4d6ba51a3c5f74ccf2b15b158d1fd47279cb70ef56'
const framework_root = state + 'touch-delegate344-2026-10-25'
const framework_manifest = 'f900b1506d71bb6d6560a6729031b3965274d5c5a50d3b2cab753c5d110b4501'
const framework_pin = '12c5d03030f5f081415bda5c51e32279e70a17aead822c06925512ed6226ef8f'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json(path string, value json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}

fn derive(before string) string {
	mut text := before.replace('335', '345')
	text = once(text, "const previous = '" + state + "maps333-2026-10-25'", "const previous = '" + state + "maps335-2026-10-25'")
	text = once(text, "const previous_pin = '55af9e0f9a9f3d2b8479a41800fa9ba120c4a47b17b8703d8ebd8f5a199a7b67'", "const previous_pin = '8d493e4588b6b3af87316824809f902bb50aac577b0e58e95d435ae02f2e137a'")
	text = text.replace("previous + '/prelaunch/maps333'", "previous + '/prelaunch/maps335'")
	text = text.replace('baseline333', 'baseline335').replace('maps333_prelaunch', 'maps335_prelaunch')
	text = once(text, "\t\t|| framework_root != '/Users/alex/.local/state/vinix/android/layout-request332-framework-build-2026-10-25'\n\t\t|| framework_manifest != '6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf'\n\t\t|| jar_pin != '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca' { return error('exact unchanged Native332 and Framework332 required') }",
		"\t\t|| framework_root != '" + framework_root + "'\n\t\t|| framework_manifest != '" + framework_manifest + "'\n\t\t|| jar_pin != '" + framework_pin + "' { return error('exact Native332 and touch-delegate344 framework required') }")
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
	text = once(text, "target + '/maps345-diagnostics.tar', launcher]", "target + '/maps345-diagnostics.tar', jar]")
	text = once(text, "!= launcher + '\\n' { return error('only one launcher tar member allowed') }", "!= jar + '\\n' { return error('only one framework JAR tar member allowed') }")
	text = once(text, "previous_tree + '/suite333.v'", "previous_tree + '/suite335.v'")
	text = once(text, "original.replace('validate_styled333', 'validate_styled345').replace('MAPS333', 'MAPS345').replace('build/android-maps/maps333/', 'build/android-maps/maps345/')", "original.replace('validate_styled335', 'validate_styled345').replace('MAPS335', 'MAPS345').replace('build/android-maps/maps335/', 'build/android-maps/maps345/')")
	text = once(text, "'framework/native/clean launcher overlays', 'unchanged framework/native; explicit diagnostic launcher overlay'", "'unchanged framework/native; explicit diagnostic launcher overlay', 'touch-delegate344 framework; unchanged native and diagnostic launcher'")
	text = once(text, "previous + '/prelaunch/inputs/' + config.replace('345', '333')", "previous + '/prelaunch/inputs/Users/alex/code/vinix/' + config.replace('345', '335')")
	text = once(text, "\t\t'changed_runtime_entry': launcher", "\t\t'changed_runtime_entry': jar")
	text = once(text, "\t\t'scope': 'Diagnostic launcher only; same109 runtime, native/framework, identity256 and600second observation; ordered final boot module, original kernel/initramfs/runtime unchanged.'", "\t\t'framework_parent_manifest_sha256': '" + framework_manifest + "'\n\t\t'scope': 'Touch-delegate344 framework JAR only against authenticated335prelaunch109 runtime. Native, diagnostic launcher, identity256 and600second observation unchanged; original335 kernel/initramfs/runtime/diagnostic boot members unchanged.'")
	text = once(text, "\targv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', base + 'maps345-run-recorded',", "\tos.mkdir_all(outer_build + '/generated-c')!\n\tos.setenv('VTMP', os.abs_path(outer_build + '/generated-c'), true)\n\targv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-cflags', '-O2', '-o', base + 'maps345-run-recorded',")
	text = once(text, "\tif receipt('suite-build', [compiler, '-nocache',", "\tos.mkdir_all(retained + '/generated-c')!\n\tos.setenv('VTMP', os.abs_path(retained + '/generated-c'), true)\n\tif receipt('suite-build', [compiler, '-nocache', '-keepc', '-showcc',")
	assert text.count('qualify_parent_framework()!') == 3
	assert text.contains("settings['applications']!.as_array()[0].as_map()['startup_seconds']!.int() != 600")
	assert text.contains("const launcher_root = '" + launcher_root + "'")
	return text
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1, 'usage: maps345-generate (generation and recorded build only)'
	assert hash(original)! == original_pin && hash(compiler)! == compiler_pin
	assert hash(launcher_root + '/sha256.json')! == launcher_manifest
	assert hash(launcher_root + '/run-android-calculator')! == launcher_pin
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	for key in os.environ().keys() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' { os.unsetenv(key) }
	}
	checked := os.exec([launcher_root + '/builder', 'check', launcher_root, launcher_manifest])
	assert checked.exit_code == 0, checked.output
	before := os.read_file(original)!
	text := derive(before)
	for path in [work, recorded, state + 'maps345-2026-10-25', 'build/android-maps/maps345',
		'build/android-maps/maps345-run-recorded', 'build/android-maps/attempt345', 'build/android-maps/attempt345.json'] {
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
	os.write_file(work + '/maps345-run.v', text)!
	write_json(work + '/derivation.json', {
		'original_path': json2.Any(original)
		'original_sha256': json2.Any(original_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(work + '/maps345-run.v')!)
		'launcher_root': json2.Any(launcher_root)
		'launcher_manifest_sha256': json2.Any(launcher_manifest)
		'launcher_sha256': json2.Any(launcher_pin)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'framework_root': json2.Any(framework_root)
		'framework_manifest_sha256': json2.Any(framework_manifest)
		'framework_sha256': json2.Any(framework_pin)
		'changes': json2.Any('335 to345 identifiers; authenticated335 prelaunch baseline; JAR-only final boot overlay with qualified344 TouchDelegate. Same native, diagnostic launcher, kernel/base media, full qualification/build receipts,1536MiB gates and600second classifier. Generated C retained for runner and suite.')
		'scope': json2.Any('Generation and recorded host runner build only; no preparation, media staging or guest launch.')
	})!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	os.mkdir_all(work + '/generated-c')!
	os.setenv('VTMP', work + '/generated-c', true)
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps345-run.v']
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(work + '/maps345-run.v')!)
	}
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(work + '/bootstrap')! }
	write_json(work + '/bootstrap-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(work + '/maps345-run.v')! == receipt['source_sha256']!.str()
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	assert rebuilt.exit_code == 0, rebuilt.output
	mut pins := map[string]string{}
	for path in os.walk_ext(work, '') { if os.is_file(path) { pins[path.all_after(work + '/')] = hash(path)! } }
	write_json(work + '/sha256.json', json2.decode[json2.Any](json2.encode(pins))!)!
	cloned := os.exec(['cp', '-c', '-R', '-P', work, recorded + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	assert hash(recorded + '/generation/sha256.json')! == hash(work + '/sha256.json')!
	println('MAPS345-GENERATED source=' + hash(work + '/maps345-run.v')! + ' binary=' + hash('build/android-maps/maps345-run-recorded')! + ' generation-manifest=' + hash(work + '/sha256.json')!)
}
