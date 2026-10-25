// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh diagnostic replay derived from the authenticated Maps333 runner.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps333-generation-2026-10-25/maps333-run.v'
const original_pin = 'a2aa42361e7a8433d3fe70415f20d72c02c49436f8a5680af21922c9d3f7dca4'
const work = state + 'maps334-generation-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}
fn derive(root string, pin string) !(string, string, string) {
	before := os.read_file(original)!
	mut text := before.replace('333', '334')
	text = once(text, "const previous = '" + state + "maps285-2026-10-25-prelaunch'", "const previous = '" + state + "maps333-2026-10-25'")
	text = once(text, "const previous_pin = 'e69637746f704240c9c9e19ecd85aa421df786c55931cf1ca361c51dbb07e895'", "const previous_pin = '55af9e0f9a9f3d2b8479a41800fa9ba120c4a47b17b8703d8ebd8f5a199a7b67'")
	text = once(text, "const previous_tree = previous + '/prelaunch/maps285'", "const previous_tree = previous + '/prelaunch/maps333'")
	old_builds := text.all_after('fn qualify_builds(').all_before('fn qualify_comparison295(')
	text = once(text, 'fn qualify_builds(' + old_builds, '')
	old_qualifier := text.all_after('fn qualify_comparison295(').all_before('fn equal(')
	text = once(text, 'fn qualify_comparison295(' + old_qualifier, '')
	fragment := os.read_file('tests/native-android-ws/maps334-overlay-prepare.v')!
	body := fragment.all_after('module main\n')
	old_prepare := text.all_after('fn prepare(').all_before('fn results(')
	text = once(text, 'fn prepare(' + old_prepare, body + '\n')
	text = text.replace('qualify_comparison295()!', 'qualify_baseline()!')
	text = text.replace("path.starts_with(target + '/vm/')", "path.starts_with(os.abs_path(target) + '/vm/')")
	text = once(text, "\tstatus := receipt('launch'", "\tos.write_file(retained + '/disk-before-launch.txt', disk_space()!)!\n\tstatus := receipt('launch'")
	text = once(text, "\twrite_json(retained + '/sha256.json'", "\tqualify_launcher()!\n\twrite_json(retained + '/sha256.json'")
	text += "\nconst launcher = 'usr/bin/run-android-calculator'\nconst launcher_root = '" + root + "'\nconst launcher_manifest = '" + pin + "'\nconst launcher_pin = '" + hash(root + '/run-android-calculator')! + "'\n"
	return before, fragment, text
}

fn clean_environment() {
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	for key in os.environ().keys() { if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' { os.unsetenv(key) } }
}

// Compile exactly the same derived source without creating replay destinations,
// staging media or entering the real generation/preparation/launch path.
fn check_source(destination string, before string, fragment string, text string) ! {
	assert os.is_abs_path(destination) && destination.starts_with(state)
	assert !os.exists(destination) && !os.is_link(destination), 'fresh check destination required'
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 128 * 1024, '128 MiB free required for source check'
	os.mkdir_all(destination + '/inputs')!
	os.write_file(destination + '/maps333-input.v', before)!
	os.write_file(destination + '/prepare-input.v', fragment)!
	os.write_file(destination + '/generator.v', os.read_file(@FILE)!)!
	os.write_file(destination + '/maps334-run.v', text)!
	os.write_file(destination + '/disk-before.txt', space.output)!
	listing := os.exec([compiler, '-print-v-files', destination + '/maps334-run.v'])
	os.write_file(destination + '/closure.txt', listing.output)!
	assert listing.exit_code == 0, listing.output
	mut inputs := map[string]string{}
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		inputs[path] = hash(path)!
		os.write_file(destination + '/inputs/' + inputs.len.str() + '.v', os.read_file(path)!)!
	}
	assert inputs.len >= 10
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-cc', cc, '-cflags', '-O2', '-o', destination + '/runner', destination + '/maps334-run.v']
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(destination + '/build.log', r.output)!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	for path, pin in inputs { assert hash(path)! == pin, path }
	os.write_file(destination + '/receipt.json', json2.encode({
		'argv': json2.Any(argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'inputs_before_and_after': json2.decode[json2.Any](json2.encode(inputs))!
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'scope': json2.Any('Source compilation only; no replay generation, preparation, media staging or guest launch. Real replay1536MiB gates unchanged.')
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	mut pins := map[string]string{}
	for path in os.walk_ext(destination, '') { if os.is_file(path) { pins[path.all_after(destination + '/')] = hash(path)! } }
	os.write_file(destination + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('MAPS334 SOURCE CHECK PASS source=' + hash(destination + '/maps334-run.v')! + ' binary=' + hash(destination + '/runner')! + ' manifest=' + hash(destination + '/sha256.json')!)
}

fn main() {
	$if prod { panic('assertions required') }
	source_only := os.args.len == 5 && os.args[1] == '--check-source'
	assert os.args.len == 3 || source_only, 'usage: maps334-generate LAUNCHER_BUILD_ROOT MANIFEST_SHA256 | --check-source LAUNCHER_BUILD_ROOT MANIFEST_SHA256 FRESH_CHECK_ROOT'
	index := if source_only { 2 } else { 1 }
	root := os.abs_path(os.args[index])
	assert root == state + 'maps334-trace-launcher-build-2026-10-25'
	pin := os.args[index + 1]
	assert pin.len == 64 && hash(root + '/sha256.json')! == pin
	checked := os.exec([root + '/builder', 'check', root, pin])
	assert checked.exit_code == 0, checked.output
	assert hash(original)! == original_pin && hash(compiler)! == compiler_pin
	clean_environment()
	before, fragment, text := derive(root, pin)!
	if source_only { check_source(os.args[4], before, fragment, text)!; return }
	for path in [work, state + 'maps334-run-build-c-2026-10-25', state + 'maps334-2026-10-25',
		'build/android-maps/maps334', 'build/android-maps/maps334-run-recorded', 'build/android-maps/attempt334', 'build/android-maps/attempt334.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(work)!
	os.write_file(work + '/maps333-input.v', before)!
	os.write_file(work + '/prepare-input.v', fragment)!
	os.write_file(work + '/generator.v', os.read_file(@FILE)!)!
	os.write_file(work + '/disk-before-generation.txt', space.output)!
	os.write_file(work + '/maps334-run.v', text)!
	os.write_file(work + '/derivation.json', json2.encode({
		'original_sha256': json2.Any(original_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'prepare_sha256': json2.Any(sha256.sum(fragment.bytes()).hex())
		'generated_sha256': json2.Any(sha256.sum(text.bytes()).hex())
		'launcher_manifest_sha256': json2.Any(pin)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'estimated_additional_peak_mib': json2.Any(384)
		'disk_policy': json2.Any('Same1536MiB gate at generation, preparation and launch. Tiny final module avoids907648000byte runtime rewrite. Budget256MiB guest writes+128MiB build/log; no evidence removed and no historical checker changed.')
		'changes': json2.Any('333 to334 labels; authenticated prelaunch333 baseline; launcher-only final boot overlay; full baseline/build checks; additional disk gates. Original600second classifier unchanged.')
	}, prettify: true) + '\n')!
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps334-run.v']
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	assert result.exit_code == 0, result.output
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	assert rebuilt.exit_code == 0, rebuilt.output
	cloned := os.exec(['cp', '-c', '-R', '-P', work, state + 'maps334-run-build-c-2026-10-25/generation'])
	assert cloned.exit_code == 0, cloned.output
	println('MAPS334-GENERATED source=' + hash(work + '/maps334-run.v')! + ' binary=' + hash('build/android-maps/maps334-run-recorded')!)
}
