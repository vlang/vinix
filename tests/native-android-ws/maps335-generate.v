// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh retry of authenticated Maps334; its launcher, payloads and gates stay pinned.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps334-generation-2026-10-25/maps334-run.v'
const original_pin = '8a6c887a56a45066ab97174b7d6f5f72868840923f9a00acd38cbb63e15e9307'
const work = state + 'maps335-generation-2026-10-25'
const recorded = state + 'maps335-run-build-c-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const launcher_root = state + 'maps334-trace-launcher-build-2026-10-25'
const launcher_manifest = '25855fcb5aa5016d7cc5df659017f66b6f3dc5d96e4935d474d691b59de9fc27'
const launcher_pin = '52e305950821e56d85bb9c4d6ba51a3c5f74ccf2b15b158d1fd47279cb70ef56'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json(path string, value json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1, 'usage: maps335-generate (generation and recorded build only)'
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
	assert !before.contains('335'), 'input must not already name Maps335'
	mut text := before.replace('334', '335')
	text = once(text, "const launcher_root = '" + state + "maps335-trace-launcher-build-2026-10-25'",
		"const launcher_root = '" + launcher_root + "'")
	assert text.count("config.replace('335', '333')") == 1, 'baseline config must still come from333'
	assert text.replace('335', '334') == before, 'only retry identifiers may change'
	assert text.count('334') == 1 && text.contains("const launcher_root = '" + launcher_root + "'")
	assert text.contains("const previous = '" + state + "maps333-2026-10-25'")
	for path in [work, recorded, state + 'maps335-2026-10-25', 'build/android-maps/maps335',
		'build/android-maps/maps335-run-recorded', 'build/android-maps/attempt335', 'build/android-maps/attempt335.json'] {
		assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	}
	space := os.exec(['/bin/df', '-k', state])
	assert space.exit_code == 0 && space.output.trim_space().split_into_lines().last().fields()[3].u64() >= 1536 * 1024, '1536 MiB free required'
	os.mkdir(work)!
	os.write_file(work + '/maps334-input.v', before)!
	os.write_file(work + '/generator.v', os.read_file(@FILE)!)!
	os.cp(os.executable(), work + '/generator')!
	os.write_file(work + '/disk-before-generation.txt', space.output)!
	os.write_file(work + '/launcher-check.log', checked.output)!
	os.write_file(work + '/maps335-run.v', text)!
	write_json(work + '/derivation.json', {
		'original_path': json2.Any(original)
		'original_sha256': json2.Any(original_pin)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'generated_sha256': json2.Any(hash(work + '/maps335-run.v')!)
		'launcher_root': json2.Any(launcher_root)
		'launcher_manifest_sha256': json2.Any(launcher_manifest)
		'launcher_sha256': json2.Any(launcher_pin)
		'created_utc': json2.Any(time.utc().str())
		'minimum_free_mib': json2.Any(1536)
		'changes': json2.Any('334 to335 replay identifiers only, except retained launcher334 root; baseline config lookup335 to333. Inverse substitution exactly reproduces authenticated334 source. Same overlay, Native332/Framework332, kernel, full qualification/build receipts,1536MiB gates and600second classifier.')
		'scope': json2.Any('Generation and recorded host runner build only; no preparation, media staging or guest launch.')
	})!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-cc', cc, '-cflags', '-O2', '-o', work + '/bootstrap', work + '/maps335-run.v']
	mut receipt := {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'working_directory': json2.Any(os.getwd())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(work + '/maps335-run.v')!)
	}
	result := os.exec(argv)
	os.write_file(work + '/bootstrap.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(work + '/bootstrap')! }
	write_json(work + '/bootstrap-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	assert hash(work + '/maps335-run.v')! == receipt['source_sha256']!.str()
	rebuilt := os.exec([work + '/bootstrap', 'rebuild'])
	os.write_file(work + '/recorded-build.log', rebuilt.output)!
	assert rebuilt.exit_code == 0, rebuilt.output
	mut pins := map[string]string{}
	for path in os.walk_ext(work, '') { if os.is_file(path) { pins[path.all_after(work + '/')] = hash(path)! } }
	write_json(work + '/sha256.json', json2.decode[json2.Any](json2.encode(pins))!)!
	cloned := os.exec(['cp', '-c', '-R', '-P', work, recorded + '/generation'])
	assert cloned.exit_code == 0, cloned.output
	assert hash(recorded + '/generation/sha256.json')! == hash(work + '/sha256.json')!
	println('MAPS335-GENERATED source=' + hash(work + '/maps335-run.v')! + ' binary=' + hash('build/android-maps/maps335-run-recorded')! + ' generation-manifest=' + hash(work + '/sha256.json')!)
}
