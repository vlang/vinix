// SPDX-License-Identifier: GPL-2.0-or-later
// Derive a fresh350 replay from authenticated347 tools and explicit349 pins.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const root = state + 'maps350-derivation-2026-10-25'
const self_build = state + 'maps350-deriver-build-2026-10-25'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const framework_root = state + 'media-codec-exceptions349-2026-10-25'
const old_manifest = '6d5205fce48faea0c406efb68ec9134c039aa106e591d20e4501f2826d65064b'
const old_jar = 'b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840'

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
	println('MAPS350-TOOL-BUILD path=' + destination + ' seal=' + seal(destination)!)
}
fn derive(manifest string, jar string) ! {
	for pin in [manifest, jar] { assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes()) }
	assert hash(framework_root + '/sha256.json')! == manifest
	assert hash(framework_root + '/framework/api-impl.jar')! == jar
	fresh(root)!
	os.cp(@FILE, root + '/derive.v')!
	os.cp(os.executable(), root + '/derive')!
	inputs := {
		'generate': '768e52869c8107258d02a7933ec1170f92c86a7e09b0cf0f75b56c7ffa361829'
		'receipt-generate': '17be4c65c907fe6b063819e816515a3eec3f759766b82e5267103a7e9a15e4de'
	}
	for label, pin in inputs {
		before := 'tests/native-android-ws/maps347-' + label + '.v'
		after := before.replace('347', '350')
		assert hash(before)! == pin && !os.exists(after) && !os.is_link(after)
		// The qualified346 JAR hash itself contains "347". Protect both pins
		// before relabeling so neither historical nor replacement pins change.
		mut text := once(os.read_file(before)!, old_manifest, '@FRAMEWORK_MANIFEST@')
		text = once(text, old_jar, '@FRAMEWORK_JAR@').replace('347', '350')
		text = once(text, 'superscript-span346-2026-10-25', 'media-codec-exceptions349-2026-10-25')
		text = once(text, '@FRAMEWORK_MANIFEST@', manifest)
		text = once(text, '@FRAMEWORK_JAR@', jar)
		text = text.replace('superscript-span346', 'media-codec-exceptions349').replace('Superscript-span346', 'Media-codec-exceptions349').replace('qualified346 SuperscriptSpan', 'qualified349 MediaCodec exceptions')
		os.write_file(after, text)!
		os.cp(before, root + '/maps347-' + label + '.v')!
		os.cp(after, root + '/maps350-' + label + '.v')!
		build(after, root + '/' + label + '-build', 'build/android-maps/maps350-' + label)!
	}
	write_json(root + '/derivation.json', {
		'created_utc': json2.Any(time.utc().str())
		'framework_root': json2.Any(framework_root)
		'framework_manifest_sha256': json2.Any(manifest)
		'framework_sha256': json2.Any(jar)
		'generator_sha256': json2.Any(hash(@FILE)!)
		'generator_binary_sha256': json2.Any(hash(os.executable())!)
		'scope': json2.Any('347 to350 labels and explicit qualified349 framework pins only. Authenticated335 prelaunch baseline, exact332 native, diagnostic334 launcher, strict109-file runtime and600-second classifier remain unchanged. Generation/build only; no guest launch.')
	})!
	println('MAPS350-DERIVATION seal=' + seal(root)!)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == '/Users/alex/code/vinix'
	assert hash(compiler)! == compiler_pin
	if os.args.len == 2 && os.args[1] == 'rebuild' {
		build(@FILE, self_build, 'build/android-maps/maps350-derive')!
	} else {
		assert os.args.len == 4 && os.args[1] == 'derive', 'usage: maps350-derive rebuild | derive MANIFEST_SHA JAR_SHA'
		derive(os.args[2], os.args[3])!
	}
}
