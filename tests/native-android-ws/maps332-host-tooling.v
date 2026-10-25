// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze the Maps332 receipt tool and write its fresh six-key replacement pins.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps-replay-receipt332-build-2026-10-25'
const source = root + '/receipt.v'
const wrapper = repo + '/tests/native-android-ws/maps-replay-receipt.v'
const binary = repo + '/build/android-maps/maps-replay-receipt332-recorded'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const pin_path = state + '/maps332-replacement-build-pins-2026-10-25.json'
const test_root = state + '/maps-replay-receipt332-recorded-selftest-2026-10-25'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn require_pin(path string, pin string) ! {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular && hash(path)! == pin, path
}

fn command(label string, argv []string) !string {
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'program_sha256_before': json2.Any(hash(argv[0])!)
		'host_tooling_source_sha256': json2.Any(hash(@FILE)!)
		'host_tooling_binary_sha256': json2.Any(hash(os.executable())!)
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VTMP': json2.Any(os.getenv('VTMP'))
	}
	write_json(root + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.log', r.output)!
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['completed_utc'] = time.utc().str()
	receipt['program_sha256_after'] = json2.Any(hash(argv[0])!)
	write_json(root + '/' + label + '.json', receipt)!
	assert receipt['program_sha256_before']! == receipt['program_sha256_after']!
	assert r.exit_code == 0, r.output
	return r.output
}

fn closure(label string) !map[string]string {
	listing := command(label, [compiler, '-print-v-files', '-nocache', '-cc', 'cc', source])!
	mut files := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if path.ends_with('.v') {
			assert path.starts_with('/') && path !in files
			files[path] = hash(path)!
		}
	}
	assert files.len > 10
	write_json(root + '/' + label + '-hashes.json', files)!
	return files
}

fn inventory(path string, prefix string, mut files map[string]string) ! {
	for name in os.ls(path)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		if key == 'sha256.json' { continue }
		file := path + '/' + name
		assert !os.is_link(file)
		match os.lstat(file)!.get_filetype() {
			.regular { files[key] = hash(file)! }
			.directory { inventory(file, key, mut files)! }
			else { panic('ordinary receipt entries required') }
		}
	}
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && os.getwd() == repo
	for path in [root, binary, pin_path, test_root] { assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path }
	require_pin(compiler, compiler_pin)!
	require_pin(wrapper, 'ef464fa8ea251493bc2e9a907a0635e2412074a6e91a5837f9bf11d7c512aee3')!
	pins := {
		'native_root': state + '/layout-request332-native-build-2026-10-25'
		'native_manifest_sha256': '40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163'
		'native_sha256': '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b'
		'framework_root': state + '/layout-request332-framework-build-2026-10-25'
		'framework_manifest_sha256': '6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf'
		'framework_sha256': '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca'
	}
	for label in ['native', 'framework'] {
		build_root := pins[label + '_root']
		assert os.is_dir(build_root) && !os.is_link(build_root) && os.real_path(build_root) == build_root
		require_pin(build_root + '/sha256.json', pins[label + '_manifest_sha256'])!
		manifest := json2.decode[map[string]string](os.read_file(build_root + '/sha256.json')!)!
		payload := if label == 'native' { 'native/libvinix-android-native.so' } else { 'framework/api-impl.jar' }
		assert manifest[payload] == pins[label + '_sha256']
		require_pin(build_root + '/' + payload, pins[label + '_sha256'])!
	}
	os.mkdir(root)!
	os.cp(@FILE, root + '/host-tooling.v')!
	os.cp(os.executable(), root + '/bootstrap')!
	os.cp(wrapper, source)!
	space := command('disk-before', ['/bin/df', '-k', state])!
	assert space.trim_space().split_into_lines().last().fields()[3].u64() >= u64(1536 * 1024)
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/generated-c', true)
	os.mkdir(root + '/generated-c')!
	before := closure('v-closure-before')!
	command('recorded-build', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-o', binary, source])!
	after := closure('v-closure-after')!
	assert before == after
	require_pin(compiler, compiler_pin)!
	os.cp(binary, root + '/receipt-tool')!
	command('self-test', [binary, 'self-test', test_root])!
	write_json(pin_path, pins)!
	os.cp(pin_path, root + '/replacement-build-pins.json')!
	write_json(root + '/outputs.json', {
		'wrapper_source_sha256': json2.Any(hash(source)!)
		'wrapper_binary_sha256': json2.Any(hash(binary)!)
		'replacement_pins_path': json2.Any(pin_path)
		'replacement_pins_sha256': json2.Any(hash(pin_path)!)
		'self_test_root': json2.Any(test_root)
		'self_test_manifest_sha256': json2.Any(hash(test_root + '/sha256.json')!)
		'policy': json2.Any('Tool build, host self-test and fresh replacement pins only; no Maps generation, preparation or guest launch.')
	})!
	mut files := map[string]string{}
	inventory(root, '', mut files)!
	write_json(root + '/sha256.json', files)!
	println('MAPS332-HOST-TOOLING-PASS seal=' + hash(root + '/sha256.json')! + ' pins=' + hash(pin_path)!)
}
