// SPDX-License-Identifier: GPL-2.0-or-later
// Derive a fresh attempt from the reviewed Maps298 runner without copying its source into Git.
module main

import crypto.sha256
import json2
import os
import time

const work = '/Users/alex/.local/state/vinix/android/maps299-generation-2026-10-25'
const build = '/Users/alex/.local/state/vinix/android/maps299-run-build-c-2026-10-25'
const own_source = 'tests/native-android-ws/maps299-generate.v'
const original_source = 'tests/native-android-ws/maps298-run.v'
const original_pin = '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1
	assert !os.exists(work) && !os.is_link(work)
	assert !os.exists(build) && !os.is_link(build)
	assert hash(original_source)! == original_pin
	assert hash(compiler)! == compiler_pin
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.mkdir_all(work)!
	original := os.read_file(original_source)!
	mut derived := original
	mut replacements := map[string]json2.Any{}
	for prefix in ['maps', 'attempt', 'suite', 'MAPS', 'validate_styled', 'fresh'] {
		before := prefix + '298'
		after := prefix + '299'
		assert derived.contains(before)
		replacements[before] = after
		derived = derived.replace(before, after)
	}
	assert !derived.contains('298')
	before := "const source = 'tests/native-android-ws/maps299-run.v'"
	after := "const source = '" + work + "/maps299-run.v'"
	assert derived.count(before) == 1
	replacements[before] = after
	derived = derived.replace(before, after)
	os.write_file(work + '/maps298-input.v', original)!
	os.write_file(work + '/maps299-run.v', derived)!
	os.write_file(work + '/generator.v', os.read_file(own_source)!)!
	os.write_file(work + '/derivation.json', json2.encode({
		'original_path': json2.Any(original_source)
		'original_sha256': json2.Any(original_pin)
		'generator_path': json2.Any(own_source)
		'generator_sha256': json2.Any(hash(own_source)!)
		'generated_sha256': json2.Any(hash(work + '/maps299-run.v')!)
		'replacements': json2.Any(replacements)
		'created_utc': json2.Any(time.utc().str())
	}, prettify: true) + '\n')!
	argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps299-run.v']
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(work + '/bootstrap-build.log', r.output)!
	os.write_file(work + '/bootstrap-build.json', json2.encode({
		'argv': json2.Any(argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'compiler_sha256': json2.Any(hash(compiler)!)
		'source_sha256': json2.Any(hash(work + '/maps299-run.v')!)
	}, prettify: true) + '\n')!
	assert r.exit_code == 0, r.output
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	print(rebuilt.output)
	assert rebuilt.exit_code == 0, rebuilt.output
	assert hash(original_source)! == original_pin
	assert hash(compiler)! == compiler_pin
	cloned := os.exec([os.find_abs_path_of_executable('cp')!, '-c', '-R', '-P', work, build + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	println('MAPS299-GENERATED source=' + hash(work + '/maps299-run.v')! + ' binary=' + hash('build/android-maps/maps299-run-recorded')!)
}
