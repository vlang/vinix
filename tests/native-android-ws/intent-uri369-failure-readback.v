module main

import os
import json2
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/intent-uri369-fixture-2026-10-26'
const output = '/Users/alex/.local/state/vinix/android/intent-uri369-failure-readback-b-2026-10-26'
const action_prefix = '/Users/alex/.local/state/vinix/android/intent-uri369-fixture-'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut context := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &context }) == 1
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) == 1
	}
	mut digest := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &digest[0] }, unsafe { &context }) == 1
	return digest[..].hex()
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn inventory(prefix string, mut files map[string]string) ! {
	for name in os.ls(state + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(state + '/' + key)!.get_filetype() {
			.directory { inventory(key, mut files)! }
			.regular { files[key] = hash(state + '/' + key)! }
			else { return error('nonregular evidence: ' + key) }
		}
	}
}

fn main() {
	assert os.args.len == 1 && !os.exists(output) && !os.is_link(output)
	assert !os.exists(state + '/sha256.json') && !os.exists(state + '/new-semantic-check.json')
	started := time.utc().str()
	os.mkdir_all(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	mut files := map[string]string{}
	inventory('', mut files)!
	shared := json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
	for key, pin in shared { assert files[key]! == pin, key }
	mut adjacent := map[string]string{}
	for label in ['prepare', 'old', 'new'] {
		prefix := action_prefix + label + '-2026-10-26'
		for suffix in ['-before.json', '-command.json', '.log'] {
			path := prefix + suffix
			dest := output + '/' + label + suffix
			os.cp(path, dest)!
			adjacent[path] = hash(path)!
			assert hash(dest)! == adjacent[path]!
		}
		receipt := object(prefix + '-command.json')!
		assert receipt['exit_code']!.int() == if label == 'new' { 1 } else { 0 }
		assert receipt['executable_sha256_before']! == receipt['executable_sha256_after']!
		assert receipt['output_sha256']!.str() == hash(prefix + '.log')!
	}
	for kind in ['old', 'new'] {
		assert object(state + '/commands/suite-' + kind + '.json')!['exit_code']!.int() == 0
		raw := json2.decode[[]map[string]json2.Any](os.read_file(state + '/run-' + kind + '/results.json')!)!
		assert raw.len == 1 && raw[0]['outcome']!.str() == 'startup_failed'
		assert raw[0]['process_exited']!.bool() && raw[0]['functional_passed']! is json2.Null
		assert raw[0]['container_sha256']!.str() == files['apk/probe.apk']!
	}
	assert object(state + '/old-semantic-check.json')!['status']!.str() == 'expected-result-pass'
	serial := os.read_file(state + '/run-new/bootstrap-fixture/serial.log')!
	lines := serial.split_into_lines().map(it.trim_space())
	assert lines.filter(it.starts_with('INTENT-URI')) == ['INTENT-URI-BEGIN',
		'INTENT-URI-ORDINARY-PASS', 'INTENT-URI-MODERN-PASS',
		'INTENT-URI-EXTRAS-PASS', 'INTENT-URI-FLAGS-PASS']
	assert lines.filter(it == 'java.lang.AssertionError: android-app package has no data').len == 1
	assert lines.filter(it == 'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true').len == 1
	assert os.read_file(action_prefix + 'new-2026-10-26.log')!.contains('single INTENT-URI-ANDROID-APP-PASS')
	os.write_file(output + '/files.json', json2.encode(files, prettify: true) + '\n')!
	os.write_file(output + '/adjacent.json', json2.encode(adjacent, prettify: true) + '\n')!
	os.write_file(output + '/receipt.json', json2.encode({
		'argv': json2.Any(os.args), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'original_root': json2.Any(state), 'original_file_count': json2.Any(files.len),
		'original_files_sha256': json2.Any(hash(output + '/files.json')!),
		'adjacent_inventory_sha256': json2.Any(hash(output + '/adjacent.json')!),
		'reader_source_sha256': json2.Any(hash(output + '/reader.v')!),
		'reader_binary_sha256': json2.Any(hash(output + '/reader')!),
		'status': json2.Any('preserved-real-new-art-failure'),
		'scope': json2.Any('Read-only failed369 inventory and actual outcome receipt. Original root untouched; success-only seal uninvoked. This does not claim a successful semantic result or an original290 complete audit.')
	}, prettify: true) + '\n')!
	println('INTENT369-FAILURE-PRESERVED files=' + files.len.str() +
		' inventory=' + hash(output + '/files.json')! + ' receipt=' + hash(output + '/receipt.json')!)
}
