// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded independent check of the retained action-recorder build and V closure.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/intent-uri371-action-recorder-build-2026-10-26'
const output = state + '/intent-uri371-action-recorder-peer-readback-2026-10-26'
const baseline = state + '/intent-uri371-run-bootstrap-build-2026-10-26'
const baseline_pin = '0056ca7608c43d61612f24caeb251c502e41c1f6b28db22ba249710084691421'
const source_pin = 'cb0dafd546e714bbeb3157a49f420b758e5d98221e9de1b3891396e722c46819'
const binary_pin = 'b2d0fdd9791b7f25b509b3ac7145759ce2f69076387c7b1f5b2f9d1945a64997'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const builder_source_pin = '9617ec9ed397a0f766853c2ede85c2dd98460a96d8fa0408df591ef34633e9b5'
const builder_binary_pin = 'e3fb13eef493fcf920e29cf2c5e4a32ac1fc73759e6b7430ba3a39b2c1616eae'
const cc_pin = '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'
const cp_pin = '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9'
const source_name = 'tests/native-android-ws/intent-uri371-action-recorder.v'
const builder_name = 'tests/native-android-ws/intent-uri371-action-recorder-build.v'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	mut sum := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &digest }) == 1
	return sum[..].hex()
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && os.getwd() == repo && os.real_path(root) == root
	assert !os.exists(output) && !os.is_link(output), 'fresh adjacent bounded receipt required'
	os.mkdir(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	reader_source_pin := hash(@FILE)!
	reader_binary_pin := hash(os.executable())!
	started := time.utc().str()
	vroot := root + '/frozen/vroot'
	source := vroot + '/source/intent-uri371-action-recorder.v'
	mut evidence := map[string]string{}
	expected := {
		baseline + '/sha256.json': baseline_pin
		repo + '/' + source_name: source_pin
		source: source_pin
		root + '/action-recorder': binary_pin
		vroot + '/v': compiler_pin
		repo + '/' + builder_name: builder_source_pin
		root + '/builder.v': builder_source_pin
		root + '/builder': builder_binary_pin
		'/usr/bin/cc': cc_pin
		'/bin/cp': cp_pin
	}
	for path, pin in expected {
		assert hash(path)! == pin, path
		evidence[path] = pin
	}
	build := object(root + '/build.json')!
	assert build['source_sha256']!.str() == source_pin && build['binary_sha256']!.str() == binary_pin
	assert build['compiler_sha256']!.str() == compiler_pin && build['v_input_count']!.int() == 270
	assert build['baseline_manifest_sha256']!.str() == baseline_pin
	before := object(root + '/closure-before.json')!
	assert before.len == 270 && before == object(root + '/closure-after.json')!
	for path, pin in before {
		assert os.real_path(path) == path && path.starts_with(vroot + '/')
		assert hash(path)! == pin.str(), path
	}
	assert before[source]!.str() == source_pin
	for label in ['clone-vroot', 'closure-before', 'compile', 'closure-after'] {
		command := object(root + '/commands/' + label + '.json')!
		assert command['exit_code']!.int() == 0, label
		expected_argv := match label {
			'clone-vroot' { ['/bin/cp', '-c', '-R', baseline + '/frozen/vroot', vroot] }
			'compile' { [vroot + '/v', '-path', vroot + '/vlib', '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', root + '/action-recorder', source] }
			else { [vroot + '/v', '-path', vroot + '/vlib', '-print-v-files', source] }
		}
		assert command['argv']!.as_array().map(it.str()) == expected_argv, label
		assert command['executable_sha256']!.str() == if label == 'clone-vroot' { cp_pin } else { compiler_pin }
		assert command['started_utc']!.str() <= command['completed_utc']!.str(), label
		evidence[root + '/commands/' + label + '.json'] = hash(root + '/commands/' + label + '.json')!
		evidence[root + '/commands/' + label + '.log'] = hash(root + '/commands/' + label + '.log')!
		if label in ['closure-before', 'closure-after'] {
			listing := os.read_file(root + '/commands/' + label + '.log')!.split_into_lines().filter(it.ends_with('.v'))
			assert listing.len == 270
			mut seen := map[string]bool{}
			for path in listing {
				assert path in before && path !in seen, path
				seen[path] = true
			}
		}
	}
	assert !os.read_file(root + '/commands/compile.log')!.contains('/Users/alex/code/')
	for name in ['build.json', 'closure-before.json', 'closure-after.json'] {
		evidence[root + '/' + name] = hash(root + '/' + name)!
	}
	assert hash(@FILE)! == reader_source_pin && hash(os.executable())! == reader_binary_pin
	assert hash(output + '/reader.v')! == reader_source_pin && hash(output + '/reader')! == reader_binary_pin
	os.write_file(output + '/receipt.json', json2.encode({
		'argv': json2.Any(os.args), 'working_directory': json2.Any(repo),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(0), 'closure_count': json2.Any(270), 'recorded_commands_checked': json2.Any(4),
		'reader_source_sha256': json2.Any(reader_source_pin), 'reader_binary_sha256': json2.Any(reader_binary_pin),
		'original290_invoked': json2.Any(false), 'guest_invoked': json2.Any(false),
		'evidence_sha256': json2.decode[json2.Any](json2.encode(evidence))!
	}, prettify: true) + '\n')!
	println('INTENT371-ACTION-RECORDER-READBACK-PASS closure=270 commands=4')
}
