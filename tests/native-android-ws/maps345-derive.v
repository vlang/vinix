// SPDX-License-Identifier: GPL-2.0-or-later
// Derive a fresh345 replay from authenticated343 tools and explicit344 pins.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const root = state + 'maps345-derivation-2026-10-25'
const self_build = state + 'maps345-deriver-build-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework_root = state + 'touch-delegate344-2026-10-25'
const old_manifest = 'a48ee29feb4c34adfc1558117cf3c3db4ce1d3cb95d5f22f1a5c0e13cdeaaf9a'
const old_jar = '79023bd51618bc54f069fe6fd85c812679a81f6db70268f78bca38053b2d1972'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn once(text string, before string, after string) string {
	assert text.count(before) == 1, 'unique replacement required: ' + before
	return text.replace(before, after)
}
fn fresh(path string) ! {
	assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	os.mkdir_all(path)!
}
fn seal(path string) !string {
	mut pins := map[string]string{}
	for file in os.walk_ext(path, '') {
		assert !os.is_link(file)
		if os.is_file(file) { pins[file.all_after(path + '/')] = hash(file)! }
	}
	assert 'sha256.json' !in pins
	write_json(path + '/sha256.json', pins)!
	return hash(path + '/sha256.json')!
}
fn build(unit string, destination string, output string) ! {
	fresh(destination)!
	assert hash(compiler)! == compiler_pin && !os.exists(output)
	os.cp(unit, destination + '/source.v')!
	os.cp(compiler, destination + '/v_old276')!
	os.mkdir(destination + '/generated-c')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', destination + '/generated-c', true)
	listing_argv := [compiler, '-print-v-files', unit]
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
		copy := destination + '/closure/' + os.abs_path(path).trim_left('/')
		os.mkdir_all(os.dir(copy))!
		os.cp(path, copy)!
	}
	assert before.len >= 10
	write_json(destination + '/closure-before.json', before)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', output, unit]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(unit)!)
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
	write_json(destination + '/closure-after.json', after)!
	receipt['closure_after_sha256'] = hash(destination + '/closure-after.json')!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	if result.exit_code == 0 {
		receipt['binary_sha256'] = hash(output)!
		os.cp(output, destination + '/program')!
	}
	write_json(destination + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	println('MAPS345-TOOL-BUILD path=' + destination + ' seal=' + seal(destination)!)
}
fn derive(manifest string, jar string) ! {
	for pin in [manifest, jar] { assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes()) }
	assert hash(framework_root + '/sha256.json')! == manifest
	assert hash(framework_root + '/framework/api-impl.jar')! == jar
	fresh(root)!
	os.cp(@FILE, root + '/derive.v')!
	os.cp(os.executable(), root + '/derive')!
	inputs := {
		'generate': 'd658cffa88e224d065d036a42f52d2cf395180ab38a392bf573cf1fd1271d9b5'
		'receipt-generate': 'a19419c1e1e4dd6e7643101ab3aee7991d4edf4352142b8f7250e689fee3299c'
	}
	for label, pin in inputs {
		before := 'tests/native-android-ws/maps343-' + label + '.v'
		after := before.replace('343', '345')
		assert hash(before)! == pin && !os.exists(after) && !os.is_link(after)
		mut text := os.read_file(before)!.replace('343', '345')
		text = once(text, 'locale-span342-2026-10-25', 'touch-delegate344-2026-10-25')
		text = once(text, old_manifest, manifest)
		text = once(text, old_jar, jar)
		text = text.replace('locale-span342', 'touch-delegate344').replace('Locale-span342', 'Touch-delegate344').replace('qualified342 LocaleSpan', 'qualified344 TouchDelegate')
		os.write_file(after, text)!
		os.cp(before, root + '/maps343-' + label + '.v')!
		os.cp(after, root + '/maps345-' + label + '.v')!
		build(after, root + '/' + label + '-build', 'build/android-maps/maps345-' + label)!
	}
	write_json(root + '/derivation.json', {
		'created_utc': json2.Any(time.utc().str())
		'framework_root': json2.Any(framework_root)
		'framework_manifest_sha256': json2.Any(manifest)
		'framework_sha256': json2.Any(jar)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'scope': json2.Any('343 to345 labels and explicit qualified344 framework pins only. Authenticated335 prelaunch baseline, exact332 native, diagnostic334 launcher, strict109-file runtime and600-second classifier remain unchanged. Generation/build only; no guest launch.')
	})!
	println('MAPS345-DERIVATION seal=' + seal(root)!)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == '/Users/alex/code/vinix'
	assert hash(compiler)! == compiler_pin
	if os.args.len == 2 && os.args[1] == 'rebuild' {
		build(@FILE, self_build, 'build/android-maps/maps345-derive')!
	} else {
		assert os.args.len == 4 && os.args[1] == 'derive', 'usage: maps345-derive rebuild | derive MANIFEST_SHA JAR_SHA'
		derive(os.args[2], os.args[3])!
	}
}
