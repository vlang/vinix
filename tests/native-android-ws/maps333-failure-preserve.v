// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve Maps333's incomplete ENOSPC run without qualifying an application result.
module main

import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const canonical = state + '/maps333-2026-10-25'
const working = repo + '/build/android-maps/maps333'
const attempt = repo + '/build/android-maps/attempt333'
const envelope = state + '/maps333-run-receipt-2026-10-25'
const generation = state + '/maps333-generation-2026-10-25'
const root = state + '/maps333-failure-preserved-2026-10-25'
const source = repo + '/tests/native-android-ws/maps333-failure-preserve.v'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const build_log = state + '/maps333-failure-preserve-build-2026-10-25.log'
const runner_pin = '6a8dbc60fd8d999a477b0419350a80c1aa07ce93850cf6d4fece3a68d5ec1eeb'
const source_pin = 'a2aa42361e7a8433d3fe70415f20d72c02c49436f8a5680af21922c9d3f7dca4'
const launch_pin = '2b2087bd230111f7acf03dcbf20e2d0f9897bb6d4e5741b410ba2b688d68b7c1'
const prelaunch_pin = '55af9e0f9a9f3d2b8479a41800fa9ba120c4a47b17b8703d8ebd8f5a199a7b67'
const wrapper_pin = '30edced25287dcf09502a3db11c7023c2eb56d1cc8bdb84166f35a0303c715ca'
const wrapper_source_pin = 'ef464fa8ea251493bc2e9a907a0635e2412074a6e91a5837f9bf11d7c512aee3'
const panic_text = 'V panic: failed to open file "/Users/alex/.local/state/vinix/android/maps333-run-receipt-2026-10-25/sha256.json"; code: 28\n v hash: b5bcdbb\n    pid: 0xd991\n    tid: 0xd991\n0   maps-replay-receipt332-recorded     0x0000000100b34bb0 main + 1784\n1   dyld                                0x000000018eaf3e00 start + 6992.'

fn hash(path string) !string {
	before := os.lstat(path)!
	assert before.get_filetype() == .regular, 'regular file required: ' + path
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut result := ''
	$if macos {
		mut digest := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &digest }) == 1
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
		}
		mut bytes := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &bytes[0] }, unsafe { &digest }) == 1
		result = bytes[..].hex()
	} $else {
		mut digest := sha256.new()
		defer { unsafe { digest.free() } }
		for {
			n := file.read(mut buffer) or {
				if err is os.Eof { break }
				return err
			}
			if n == 0 { break }
			assert digest.write(buffer[..n])! == n
		}
		mut bytes := []u8{len: 32}
		defer { unsafe { bytes.free() } }
		digest.checksum_into(mut bytes)
		result = bytes.hex()
	}
	after := os.lstat(path)!
	assert before.size == after.size && before.mtime == after.mtime
	assert before.mode == after.mode, 'file changed while hashing: ' + path
	return result
}

fn inventory(base string, relative string, mut entries map[string]string) ! {
	mut names := os.ls(base + '/' + relative)!
	names.sort()
	for name in names {
		key := if relative == '' { name } else { relative + '/' + name }
		path := base + '/' + key
		info := os.lstat(path)!
		match info.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory {
				entries[key] = 'directory'
				inventory(base, key, mut entries)!
			}
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			else { return error('unexpected evidence type: ' + path) }
		}
		assert os.lstat(path)!.mode == info.mode, 'type/mode changed: ' + path
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn tree(base string) !map[string]string {
	assert os.lstat(base)!.get_filetype() == .directory
	mut entries := map[string]string{}
	inventory(base, '', mut entries)!
	return entries
}

fn equal(expected map[string]string, actual map[string]string) ! {
	if expected.len != actual.len { return error('typed inventory entry count differs') }
	for key, value in expected {
		if actual[key]! != value { return error('typed inventory differs: ' + key) }
	}
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + ': ' + r.output) }
	return r.output
}

fn absent(path string) ! {
	if os.exists(path) || os.is_link(path) { return error('expected absent: ' + path) }
}

fn pin(path string, expected string) ! {
	assert expected.len == 64 && hash(path)! == expected, 'wrong pin: ' + path
}

fn clone(input string, relative string) ! {
	output := root + '/' + relative
	absent(output)!
	before := tree(input)!
	mode := os.lstat(input)!.mode & 0o7777
	os.mkdir_all(os.dir(output))!
	checked([os.find_abs_path_of_executable('cp')!, '-c', '-R', '-P', '-p', input, output])!
	equal(before, tree(input)!)!
	equal(before, tree(output)!)!
	assert os.lstat(output)!.mode & 0o7777 == mode
	write_json(root + '/inventories/' + relative.replace('/', '--') + '.json', before)!
	println('MAPS333-FAILURE-CLONE-PASS ' + relative + ' typed=' + before.len.str())
}

fn copy_checked(input string, relative string) ! {
	output := root + '/' + relative
	absent(output)!
	before := hash(input)!
	os.mkdir_all(os.dir(output))!
	checked([os.find_abs_path_of_executable('cp')!, '-c', '-P', '-p', input, output])!
	assert hash(input)! == before && hash(output)! == before
	assert os.lstat(input)!.mode & 0o7777 == os.lstat(output)!.mode & 0o7777
}

fn require_incomplete(c string, e string, a string) ! {
	for missing in ['sha256.json', 'launch-receipt.json', 'results', 'postrun-vm',
		'postrun-sha256.json'] { absent(c + '/' + missing)! }
	for missing in ['sha256.json', 'receipt.json'] { absent(e + '/' + missing)! }
	absent(a + '/results.json')!
	absent(a + '/google-maps/application.png')!
	absent(a + '/google-maps/qmp.sock')!
	absent(a + '/google-maps/category-search-recovery.png')!
	failed := a + '/google-maps/command-64239-1792939814396782000-43583'
	assert os.read_file(failed + '.stdout.log')! == ''
	assert os.read_file(failed + '.stderr.log')! == 'No such file or directory\n'
	log := os.read_file(a + '/google-maps/interaction.log')!
	assert log.count('2026-10-25 14:50:14 UTC BEGIN ') == 1
	assert log.count('2026-10-25 14:50:14 UTC END exit=1 ') == 1
}

fn verify(base string, expected_pin string) !int {
	pin(base + '/sha256.json', expected_pin)!
	expected := json2.decode[map[string]string](os.read_file(base + '/sha256.json')!)!
	mut actual := tree(base)!
	actual.delete('sha256.json')
	actual.delete('@mode:sha256.json')
	equal(expected, actual)!
	require_incomplete(base + '/partial-canonical', base + '/incomplete-run-envelope',
		base + '/working-attempt')!
	pin(base + '/working-target/launch-pins.json', launch_pin)!
	pin(base + '/partial-canonical/prelaunch-sha256.json', prelaunch_pin)!
	pin(base + '/tooling/maps333-run-recorded', runner_pin)!
	pin(base + '/generation/maps333-run.v', source_pin)!
	return actual.len
}

fn main() {
	$if prod { panic('assertions required') }
	if os.args.len >= 3 && os.args[1] == 'hash' {
		for path in os.args[2..] { println(hash(path)! + '  ' + path) }
		return
	}
	if os.args.len == 4 && os.args[1] == 'verify' {
		count := verify(os.args[2], os.args[3])!
		println('MAPS333-FAILURE-READBACK-PASS typed=' + count.str())
		return
	}
	assert os.args.len == 2 && os.args[1] == 'preserve', 'preserve | verify ROOT SHA256 | hash PATH...'
	os.setenv('COPYFILE_DISABLE', '1', true)
	absent(root)!
	absent(root + '-receipt.json')!
	require_incomplete(canonical, envelope, attempt)!
	pin(working + '/launch-pins.json', launch_pin)!
	pin(canonical + '/prelaunch-sha256.json', prelaunch_pin)!
	pin(repo + '/build/android-maps/maps333-run-recorded', runner_pin)!
	pin(generation + '/maps333-run.v', source_pin)!
	pin(repo + '/build/android-maps/maps-replay-receipt332-recorded', wrapper_pin)!
	pin(repo + '/tests/native-android-ws/maps-replay-receipt.v', wrapper_source_pin)!
	pin(compiler, compiler_pin)!
	// The canonical copy already retains the complete outer build and its closure.
	equal(tree(canonical + '/runner-build')!,
		tree(state + '/maps333-run-build-c-2026-10-25')!)!
	os.mkdir(root)!
	os.mkdir(root + '/inventories')!
	clone(canonical, 'partial-canonical')!
	clone(working, 'working-target')!
	clone(attempt, 'working-attempt')!
	clone(envelope, 'incomplete-run-envelope')!
	clone(generation, 'generation')!
	for stage in ['generation', 'preparation', 'check'] {
		name := 'maps333-' + stage + '-receipt-2026-10-25'
		clone(state + '/' + name, 'completed-receipts/' + stage)!
		for suffix in ['readback', 'root-readback'] {
			file := 'maps333-' + stage + '-receipt-' + suffix + '-2026-10-25.json'
			copy_checked(state + '/' + file, 'completed-receipts/' + file)!
		}
	}
	for item in [
		[repo + '/build/android-maps/attempt333.json', 'attempt333.json'],
		[repo + '/build/android-maps/maps333-run-recorded', 'tooling/maps333-run-recorded'],
		[repo + '/build/android-maps/maps-replay-receipt332-recorded', 'tooling/maps-replay-receipt332-recorded'],
		[repo + '/tests/native-android-ws/maps-replay-receipt.v', 'tooling/maps-replay-receipt.v'],
		[source, 'tooling/preserve.v'],
		[os.executable(), 'tooling/preserve'],
		[build_log, 'tooling/preserve-build.log'],
	] { copy_checked(item[0], item[1])! }
	write_json(root + '/tooling/build.json', {
		'source_sha256': json2.Any(hash(source)!)
		'binary_sha256': json2.Any(hash(os.executable())!)
		'compiler_path': json2.Any(compiler)
		'compiler_sha256': json2.Any(compiler_pin)
		'vroot': json2.Any('/Users/alex/code/v')
		'argv': json2.Any([compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', os.executable(), source])
		'build_log_sha256': json2.Any(hash(build_log)!)
	})!
	os.write_file(root + '/terminal-origin-panic.txt', panic_text + '\n')!
	write_json(root + '/failure-observation.json', {
		'observation_origin': json2.Any('Parent terminal tool write_stdin session 91894; not a guest or wrapper log')
		'terminal_observed_utc': json2.Any('2026-10-25 14:50:22')
		'process_exit_timestamp': json2.Any('not recorded')
		'wrapper_exit_code': json2.Any(1)
		'wrapper_panic_errno': json2.Any(28)
		'wrapper_panic_text_sha256': json2.Any(hash(root + '/terminal-origin-panic.txt')!)
		'wrapper_log_panic_recorded': json2.Any(false)
		'no_processes_confirmed_by_parent_utc': json2.Any('2026-10-25 14:52')
		'failed_post_stop_capture_utc': json2.Any('2026-10-25 14:50:14')
		'failed_post_stop_capture_exit_code': json2.Any(1)
		'failed_post_stop_capture_reason': json2.Any('QMP socket absent; No such file or directory')
		'application_final_classification': json2.Any('not recorded')
		'application_result_qualified': json2.Any(false)
		'canonical_complete_seal_present': json2.Any(false)
		'wrapper_complete_seal_present': json2.Any(false)
		'canonical_runner_build_equals_external_original': json2.Any(true)
		'launch_pins_sha256': json2.Any(launch_pin)
		'prelaunch_manifest_sha256': json2.Any(prelaunch_pin)
		'runner_binary_sha256': json2.Any(runner_pin)
		'runner_source_sha256': json2.Any(source_pin)
	})!
	entries := tree(root)!
	write_json(root + '/sha256.json', entries)!
	manifest_pin := hash(root + '/sha256.json')!
	count := verify(root, manifest_pin)!
	require_incomplete(canonical, envelope, attempt)!
	write_json(root + '-receipt.json', {
		'completed_utc': json2.Any(time.utc().str())
		'preserved_root': json2.Any(root)
		'manifest_sha256': json2.Any(manifest_pin)
		'typed_entries': json2.Any(count)
		'preserver_source_sha256': json2.Any(hash(source)!)
		'preserver_binary_sha256': json2.Any(hash(os.executable())!)
		'original_canonical_seal_absent': json2.Any(true)
		'application_result_qualified': json2.Any(false)
	})!
	println('MAPS333-FAILURE-PRESERVATION-PASS manifest=' + manifest_pin + ' typed=' + count.str())
}
