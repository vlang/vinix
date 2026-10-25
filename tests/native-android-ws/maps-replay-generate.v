// SPDX-License-Identifier: GPL-2.0-or-later
// Derive fresh replays from Maps298, optionally pinning two sealed build overlays.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const own_source = 'tests/native-android-ws/maps-replay-generate.v'
const original_source = 'tests/native-android-ws/maps298-run.v'
const original_pin = '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn disk_space(minimum_mib u64) !string {
	r := os.exec(['/bin/df', '-k', state])
	assert r.exit_code == 0, r.output
	assert r.output.trim_space().split_into_lines().last().fields()[3].u64() >= minimum_mib * 1024, 'at least ' + minimum_mib.str() + ' MiB free required'
	return r.output
}

fn replace_once(text string, before string, after string, mut replacements map[string]json2.Any) string {
	assert text.count(before) == 1, 'one replacement required: ' + before
	replacements[before] = after
	return text.replace(before, after)
}

fn pinned_overlays(input string, path string, mut replacements map[string]json2.Any) !string {
	mut text := input
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	assert pins.len == 6, 'exact six replacement build pins required'
	for label in ['native', 'framework'] {
		root := pins[label + '_root']!
		assert root.starts_with(state) && os.dir(root) + '/' == state
		assert os.is_dir(root) && !os.is_link(root) && os.real_path(root) == root, 'ordinary canonical build root under the external state directory required'
		assert os.base(root).ends_with('-' + label + '-build-2026-10-25'), 'labelled sealed build root required'
		for suffix in ['_manifest_sha256', '_sha256'] {
			pin := pins[label + suffix]!
			assert pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		}
		assert hash(root + '/sha256.json')! == pins[label + '_manifest_sha256']!
		payload := if label == 'native' {
			'native/libvinix-android-native.so'
		} else {
			'framework/api-impl.jar'
		}
		inventory := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
		assert inventory[payload]! == pins[label + '_sha256']!
		assert hash(root + '/' + payload)! == pins[label + '_sha256']!
	}
	text = replace_once(text, state + 'path-ops296-native-build-2026-10-25', pins['native_root']!, mut replacements)
	text = replace_once(text, state + 'path-ops296b-framework-build-2026-10-25', pins['framework_root']!, mut replacements)
	before := '\tqualify_runner_build()!\n\tnative_path :='
	after := "\tif native_manifest != '" + pins['native_manifest_sha256']! + "' || native_pin != '" + pins['native_sha256']! +
		"' || framework_manifest != '" + pins['framework_manifest_sha256']! + "' || jar_pin != '" + pins['framework_sha256']! +
		"' { return error('exact sealed replacement build pins required') }\n" + before
	text = replace_once(text, before, after, mut replacements)
	// Keep the original302 labels for existing callers. Other pinned bundles use
	// neutral labels: their precise root and four hashes are guarded above.
	original302 := pins['native_root']! == state + 'text-hint302-native-build-2026-10-25'
		&& pins['framework_root']! == state + 'text-hint302-framework-build-2026-10-25'
	for label in ['native296', 'framework296b', 'qualified296'] {
		after_label := if original302 {
			if label == 'framework296b' { 'framework302' } else { label.replace('296', '302') }
		} else {
			match label {
				'native296' { 'native-pinned' }
				'framework296b' { 'framework-pinned' }
				else { 'qualified-pinned' }
			}
		}
		assert text.contains(label)
		replacements[label] = after_label
		text = text.replace(label, after_label)
	}
	return text
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	if os.args.len !in [2, 3, 4] || os.args[1].int() < 300 || os.args[1].int().str() != os.args[1] {
		panic('usage: maps-replay-generate FRESH_ATTEMPT_NUMBER (at least 300) [SEALED_BUILD_PINS_JSON [--minimum-free-mib=1536]]')
	}
	number := os.args[1]
	mut minimum_mib := u64(5120)
	if os.args.len == 4 {
		assert number.int() >= 308, 'measured disk policy is limited to fresh attempts 308 or later'
		assert os.args[3].starts_with('--minimum-free-mib=')
		amount := os.args[3].all_after('--minimum-free-mib=')
		assert amount.u64().str() == amount && amount.u64() >= 1536 && amount.u64() <= 5120, 'canonical minimum between 1536 and 5120 MiB required'
		minimum_mib = amount.u64()
	}
	name := 'maps' + number
	work := state + name + '-generation-2026-10-25'
	build := state + name + '-run-build-c-2026-10-25'
	for path in [work, build, 'build/android-maps/' + name + '-run-recorded',
		'build/android-maps/' + name, 'build/android-maps/attempt' + number,
		'build/android-maps/attempt' + number + '.json', state + name + '-2026-10-25'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	assert hash(original_source)! == original_pin
	assert hash(compiler)! == compiler_pin
	space := disk_space(minimum_mib)!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	original := os.read_file(original_source)!
	mut derived := original
	mut replacements := map[string]json2.Any{}
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		before := prefix + '298'
		after := prefix + number
		assert derived.contains(before)
		replacements[before] = after
		derived = derived.replace(before, after)
	}
	assert !derived.contains('298')
	before := "const source = 'tests/native-android-ws/" + name + "-run.v'"
	after := "const source = '" + work + '/' + name + "-run.v'"
	assert derived.count(before) == 1
	replacements[before] = after
	derived = derived.replace(before, after)
	if os.args.len >= 3 {
		derived = pinned_overlays(derived, os.args[2], mut replacements)!
	}
	os.mkdir_all(work)!
	if os.args.len >= 3 {
		os.write_file(work + '/replacement-build-pins.json', os.read_file(os.args[2])!)!
	}
	generated := work + '/' + name + '-run.v'
	os.write_file(work + '/disk-space-before.txt', space)!
	os.write_file(work + '/disk-policy.json', json2.encode({
		'minimum_free_mib':              json2.Any(minimum_mib)
		'default_minimum_free_mib':      json2.Any(5120)
		'estimated_additional_peak_mib': json2.Any(1229)
		'estimate_basis':                json2.Any('Maps304 APFS clone replay: 0.85 GiB archive rewrite +0.22 GiB guest writes +0.10 GiB compile/log; explicit new-attempt policy retains at least 0.3 GiB reserve at 1536 MiB')
		'checked_utc':                   json2.Any(time.utc().str())
	}, prettify: true) + '\n')!
	os.write_file(work + '/maps298-input.v', original)!
	os.write_file(generated, derived)!
	os.write_file(work + '/generator.v', os.read_file(own_source)!)!
	os.write_file(work + '/derivation.json', json2.encode({
		'original_path':           json2.Any(original_source)
		'original_sha256':         json2.Any(original_pin)
		'generator_path':          json2.Any(own_source)
		'generator_sha256':        json2.Any(hash(own_source)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'replacement_pins_path':   json2.Any(if os.args.len >= 3 { os.args[2] } else { '' })
		'replacement_pins_sha256': json2.Any(if os.args.len >= 3 { hash(os.args[2])! } else { '' })
		'generated_sha256':        json2.Any(hash(generated)!)
		'replacements':            json2.Any(replacements)
		'created_utc':             json2.Any(time.utc().str())
	}, prettify: true) + '\n')!
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', work + '/bootstrap', generated]
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(work + '/bootstrap-build.log', r.output)!
	os.write_file(work + '/bootstrap-build.json', json2.encode({
		'argv':            json2.Any(argv)
		'started_utc':     json2.Any(started)
		'completed_utc':   json2.Any(time.utc().str())
		'exit_code':       json2.Any(r.exit_code)
		'compiler_sha256': json2.Any(hash(compiler)!)
		'source_sha256':   json2.Any(hash(generated)!)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	disk_space(minimum_mib)!
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	print(rebuilt.output)
	assert rebuilt.exit_code == 0, rebuilt.output
	assert hash(original_source)! == original_pin
	assert hash(compiler)! == compiler_pin
	cloned := os.exec([os.find_abs_path_of_executable('cp')!, '-c', '-R', '-P', work,
		build + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	println('MAPS' + number + '-GENERATED source=' + hash(generated)! + ' binary=' + hash('build/android-maps/' + name + '-run-recorded')!)
}
