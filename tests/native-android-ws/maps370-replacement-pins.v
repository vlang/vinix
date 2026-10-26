// SPDX-License-Identifier: GPL-2.0-or-later
// Write only the fresh Maps370 pin configuration; no replay or guest calls.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const target = state + '/maps370-replacement-pins-2026-10-26.json'
const audit = state + '/maps370-replacement-pins-write-2026-10-26'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn regular(path string) ! { assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular, path }
fn fresh(path string) { assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path }

fn pins() map[string]string {
	return {
		'native_root': state + '/text-size351-native-build-2026-10-25'
		'native_manifest_sha256': 'eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9'
		'native_sha256': 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
		'framework_root': state + '/intent-uri369-framework-build-2026-10-26'
		'framework_manifest_sha256': '9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93'
		'framework_sha256': '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'
	}
}

fn verify_inputs() ! {
	assert os.real_path(state) == state
	values := pins()
	for label in ['native', 'framework'] {
		root := values[label + '_root']
		assert os.is_dir(root) && !os.is_link(root) && os.real_path(root) == root
		manifest := root + '/sha256.json'
		regular(manifest)!
		assert hash(manifest)! == values[label + '_manifest_sha256']
		entries := json2.decode[map[string]string](os.read_file(manifest)!)!
		payload := if label == 'native' { 'native/libvinix-android-native.so' } else { 'framework/api-impl.jar' }
		assert entries[payload] == values[label + '_sha256']
		regular(root + '/' + payload)!
		assert hash(root + '/' + payload)! == values[label + '_sha256']
	}
}

fn command(label string, argv []string) !int {
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(audit + '/' + label + '.log', result.output)!
	write_json(audit + '/' + label + '.json', {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(result.exit_code)
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VTMP': json2.Any(os.getenv('VTMP'))
	})!
	print(result.output)
	return result.exit_code
}

fn inventory(root string, prefix string, mut files map[string]string) ! {
	for name in os.ls(root)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + name
		assert !os.is_link(path)
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(path, key, mut files)! }
			.regular { files[key] = hash(path)! }
			else { return error('ordinary audit entries required: ' + path) }
		}
	}
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo
	fresh(target)
	verify_inputs()!
	if os.args.len == 2 && os.args[1] == 'write' {
		assert os.executable() == audit + '/writer' && @FILE == audit + '/writer.v'
		write_json(target, pins())!
		regular(target)!
		readback := json2.decode[map[string]string](os.read_file(target)!)!
		assert readback.len == 6 && readback == pins()
		os.cp(target, audit + '/replacement-pins.json')!
		write_json(audit + '/output.json', {
			'path': target
			'sha256': hash(target)!
			'source_sha256': hash(@FILE)!
			'binary_sha256': hash(os.executable())!
			'scope': 'Exact six-field configuration only. Already qualified351/369 manifest and payload identities checked; no repeated full traversal, Maps generation, preparation or guest launch.'
		})!
		return
	}
	assert os.args.len == 1
	fresh(audit)
	regular(compiler)!
	assert hash(compiler)! == compiler_pin
	os.mkdir(audit)!
	os.cp(@FILE, audit + '/writer.v')!
	os.cp(os.executable(), audit + '/bootstrap')!
	os.mkdir(audit + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', audit + '/generated-c', true)
	compile_exit := command('compile', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-o', audit + '/writer', audit + '/writer.v'])!
	assert hash(compiler)! == compiler_pin && hash(@FILE)! == hash(audit + '/writer.v')!
	assert compile_exit == 0
	write_exit := command('write', [audit + '/writer', 'write'])!
	assert write_exit == 0
	write_json(audit + '/build-inputs.json', {
		'compiler_path': compiler
		'compiler_sha256': compiler_pin
		'source_path': @FILE
		'source_sha256': hash(@FILE)!
		'bootstrap_sha256': hash(os.executable())!
		'binary_sha256': hash(audit + '/writer')!
		'compile_log_sha256': hash(audit + '/compile.log')!
		'output_sha256': hash(target)!
	})!
	mut files := map[string]string{}
	inventory(audit, '', mut files)!
	write_json(audit + '/sha256.json', files)!
	println('MAPS370-REPLACEMENT-PINS-PASS pins=' + hash(target)! + ' manifest=' + hash(audit + '/sha256.json')!)
}
