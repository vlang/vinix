// SPDX-License-Identifier: GPL-2.0-or-later
// Derive a fresh347 replay from authenticated345 tools and explicit346 pins.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const root = state + 'maps347-derivation-2026-10-25'
const self_build = state + 'maps347-deriver-build-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework_root = state + 'superscript-span346-2026-10-25'
const old_manifest = 'f900b1506d71bb6d6560a6729031b3965274d5c5a50d3b2cab753c5d110b4501'
const old_jar = '12c5d03030f5f081415bda5c51e32279e70a17aead822c06925512ed6226ef8f'

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
	println('MAPS347-TOOL-BUILD path=' + destination + ' seal=' + seal(destination)!)
}
fn derive(manifest string, jar string) ! {
	for pin in [manifest, jar] { assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes()) }
	assert hash(framework_root + '/sha256.json')! == manifest
	assert hash(framework_root + '/framework/api-impl.jar')! == jar
	fresh(root)!
	os.cp(@FILE, root + '/derive.v')!
	os.cp(os.executable(), root + '/derive')!
	inputs := {
		'generate': 'ad429f6eb34a22d155e3c0545588c5dfb852818bbbea435def093e00779d63b1'
		'receipt-generate': '41edd37cef1b1f60a6164ef37bfe1fcb26815a6093da74e4117e671c02cbe604'
	}
	for label, pin in inputs {
		before := 'tests/native-android-ws/maps345-' + label + '.v'
		after := before.replace('345', '347')
		assert hash(before)! == pin && !os.exists(after) && !os.is_link(after)
		mut text := os.read_file(before)!.replace('345', '347')
		text = once(text, 'touch-delegate344-2026-10-25', 'superscript-span346-2026-10-25')
		text = once(text, old_manifest, manifest)
		text = once(text, old_jar, jar)
		text = text.replace('touch-delegate344', 'superscript-span346').replace('Touch-delegate344', 'Superscript-span346').replace('qualified344 TouchDelegate', 'qualified346 SuperscriptSpan')
		os.write_file(after, text)!
		os.cp(before, root + '/maps345-' + label + '.v')!
		os.cp(after, root + '/maps347-' + label + '.v')!
		build(after, root + '/' + label + '-build', 'build/android-maps/maps347-' + label)!
	}
	write_json(root + '/derivation.json', {
		'created_utc': json2.Any(time.utc().str())
		'framework_root': json2.Any(framework_root)
		'framework_manifest_sha256': json2.Any(manifest)
		'framework_sha256': json2.Any(jar)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'scope': json2.Any('345 to347 labels and explicit qualified346 framework pins only. Authenticated335 prelaunch baseline, exact332 native, diagnostic334 launcher, strict109-file runtime and600-second classifier remain unchanged. Generation/build only; no guest launch.')
	})!
	println('MAPS347-DERIVATION seal=' + seal(root)!)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == '/Users/alex/code/vinix'
	assert hash(compiler)! == compiler_pin
	if os.args.len == 2 && os.args[1] == 'rebuild' {
		build(@FILE, self_build, 'build/android-maps/maps347-derive')!
	} else {
		assert os.args.len == 4 && os.args[1] == 'derive', 'usage: maps347-derive rebuild | derive MANIFEST_SHA JAR_SHA'
		derive(os.args[2], os.args[3])!
	}
}
