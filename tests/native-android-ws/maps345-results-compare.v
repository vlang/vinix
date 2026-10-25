// SPDX-License-Identifier: GPL-2.0-or-later
// Check that Maps345 collection retained every completed interaction artifact.
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
const state = '/Users/alex/.local/state/vinix/android/'
const root = state + 'maps345-results-comparison-2026-10-25'
const build_root = state + 'maps345-results-compare-build-2026-10-25'
const unit = repo + '/tests/native-android-ws/maps345-results-compare.v'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const canonical = state + 'maps345-2026-10-25'
const canonical_pin = '68fd3029c52f90e4ad3616084bb827225db5ab8fe595736bde5c61d898fdae57'
const envelope = state + 'maps345-launch-receipt-2026-10-25'
const envelope_pin = 'ee04d21b2397313c6d8eb56e7116ca53e87e69d69abd1d60582de1e8b597338f'
const runner = repo + '/build/android-maps/maps345-run-recorded'
const runner_pin = '9084d8c5d67dd2143cb27570ca811aaf1dcae9f3aa641dd5a928232511ac49e9'
const live = repo + '/build/android-maps/attempt345/google-maps'
const captured = canonical + '/results/attempt345/google-maps'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	$if macos {
		mut digest := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &digest }) == 1
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) == 1
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			digest.write(buffer[..n])!
		}
		return digest.sum([]u8{}).hex()
	}
}
fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn inventory(path string, relative string, mut files map[string]string) ! {
	for name in os.ls(path + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		file := path + '/' + key
		assert !os.is_link(file), 'symlinks are not accepted: ' + file
		match os.lstat(file)!.get_filetype() {
			.regular { files[key] = hash(file)! }
			.directory { inventory(path, key, mut files)! }
			else { return error('unsupported artifact: ' + file) }
		}
	}
}
fn files(path string) !map[string]string {
	mut result := map[string]string{}
	inventory(path, '', mut result)!
	return result
}
fn equal(actual map[string]string, expected map[string]string) ! {
	assert actual.len == expected.len, 'complete file count differs'
	for key, value in expected { assert actual[key] or { '' } == value, key }
}
fn fresh(path string) ! {
	assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	os.mkdir_all(path)!
}
fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to)
	os.mkdir_all(os.dir(to))!
	result := os.exec(['/bin/cp', '-c', '-R', '-P', from, to])
	assert result.exit_code == 0, result.output
}
fn seal(path string) !string {
	entries := files(path)!
	assert 'sha256.json' !in entries
	write_json(path + '/sha256.json', entries)!
	return hash(path + '/sha256.json')!
}
fn authenticate(path string, pin string) !map[string]string {
	assert hash(path + '/sha256.json')! == pin
	expected := json2.decode[map[string]string](os.read_file(path + '/sha256.json')!)!
	mut actual := files(path)!
	actual.delete('sha256.json')
	equal(actual, expected)!
	assert hash(path + '/sha256.json')! == pin
	return expected
}
fn build() ! {
	fresh(build_root)!
	assert hash(compiler)! == compiler_pin && hash(unit)! == hash(@FILE)!
	clone(unit, build_root + '/source.v')!
	clone(compiler, build_root + '/v_old276')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.mkdir(build_root + '/generated-c')!
	os.setenv('VTMP', build_root + '/generated-c', true)
	list_argv := [compiler, '-print-v-files', unit]
	started := time.utc().str()
	listing := os.exec(list_argv)
	os.write_file(build_root + '/closure-v-files.txt', listing.output)!
	write_json(build_root + '/closure-receipt.json', {
		'argv': json2.Any(list_argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(listing.exit_code)
		'compiler_sha256': json2.Any(compiler_pin)
	})!
	assert listing.exit_code == 0, listing.output
	mut before := map[string]string{}
	for source in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[source] = hash(source)!
		clone(source, build_root + '/closure/' + os.abs_path(source).trim_left('/'))!
	}
	assert unit in before && before.len >= 10
	write_json(build_root + '/closure-before.json', before)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', build_root + '/compare', unit]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(unit)!)
		'closure_before_sha256': json2.Any(hash(build_root + '/closure-before.json')!)
		'scope': json2.Any('Recorded build of the comparison tool before comparison; bootstrap only invokes this build mode.')
	}
	write_json(build_root + '/build-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(build_root + '/build.log', result.output)!
	mut after := map[string]string{}
	for source, source_pin in before {
		after[source] = hash(source)!
		assert hash(build_root + '/closure/' + os.abs_path(source).trim_left('/'))! == source_pin
	}
	equal(after, before)!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	write_json(build_root + '/closure-after.json', after)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	receipt['closure_after_sha256'] = hash(build_root + '/closure-after.json')!
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(build_root + '/compare')! }
	write_json(build_root + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	println('MAPS345-RESULTS-COMPARE-BUILD seal=' + seal(build_root)!)
}
fn result_inventory(path string, relative string, mut entries map[string]string, mut sockets []string) ! {
	for name in os.ls(path + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		file := path + '/' + key
		status := os.lstat(file)!
		match status.get_filetype() {
			.regular { entries[key] = hash(file)! }
			.directory {
				entries[key] = 'directory'
				result_inventory(path, key, mut entries, mut sockets)!
			}
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(file)! }
			.socket {
				assert key == 'qmp.sock', 'only the application QMP socket may be omitted'
				sockets << key
				continue
			}
			else { return error('unsupported result: ' + file) }
		}
		entries['@mode:' + key] = (status.mode & 0o7777).str()
	}
}
fn result_tree(path string, mut sockets []string) !map[string]string {
	mut entries := map[string]string{}
	result_inventory(path, '', mut entries, mut sockets)!
	return entries
}
fn compare(build_pin string) ! {
	build_files := authenticate(build_root, build_pin)!
	assert os.executable() == build_root + '/compare'
	assert hash(os.executable())! == build_files['compare']!
	assert hash(unit)! == build_files['source.v']!
	assert hash(canonical + '/sha256.json')! == canonical_pin
	authenticate(envelope, envelope_pin)!
	assert hash(runner)! == runner_pin
	fresh(root)!
	clone(build_root, root + '/build')!
	verify_argv := [runner, 'verify', canonical_pin]
	started := time.utc().str()
	checked := os.exec(verify_argv)
	os.write_file(root + '/canonical-readback.log', checked.output)!
	write_json(root + '/canonical-readback.json', {
		'argv': json2.Any(verify_argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(checked.exit_code)
		'runner_sha256': json2.Any(runner_pin)
	})!
	assert checked.exit_code == 0 && hash(runner)! == runner_pin, checked.output
	mut live_sockets := []string{}
	mut canonical_sockets := []string{}
	before := result_tree(live, mut live_sockets)!
	original := result_tree(captured, mut canonical_sockets)!
	assert canonical_sockets.len == 0
	equal(before, original)!
	mut after_live_sockets := []string{}
	mut after_canonical_sockets := []string{}
	equal(result_tree(live, mut after_live_sockets)!, before)!
	equal(result_tree(captured, mut after_canonical_sockets)!, original)!
	assert live_sockets == after_live_sockets && canonical_sockets == after_canonical_sockets
	assert hash(canonical + '/sha256.json')! == canonical_pin
	assert hash(envelope + '/sha256.json')! == envelope_pin
	write_json(root + '/canonical-results-typed.json', original)!
	write_json(root + '/live-results-typed.json', before)!
	write_json(root + '/scope.json', {
		'created_utc': json2.Any(time.utc().str())
		'canonical_root': json2.Any(canonical)
		'canonical_manifest_sha256': json2.Any(canonical_pin)
		'launch_envelope_root': json2.Any(envelope)
		'launch_envelope_manifest_sha256': json2.Any(envelope_pin)
		'live_source': json2.Any(live)
		'comparison_build_manifest_sha256': json2.Any(build_pin)
		'typed_entries': json2.Any(before.len)
		'live_omitted_sockets': json2.Any(live_sockets)
		'canonical_sockets': json2.Any(canonical_sockets)
		'delta_entries': json2.Any([]string{})
		'late_interaction_supplement_needed': json2.Any(false)
		'original_paths_modified': json2.Any(false)
		'scope': json2.Any('Read-only comparison after completed Maps345 collection. Complete application result inventories agree, including hashes, directories, modes and symlink targets; only a live qmp.sock may be omitted. No late interaction supplement is needed. Original canonical, envelope and live paths remain unchanged.')
	})!
	println('MAPS345-RESULTS-COMPARISON entries=' + before.len.str() + ' seal=' + seal(root)!)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo
	if os.args.len == 2 && os.args[1] == 'build' { build()!; return }
	if os.args.len == 3 && os.args[1] == 'compare' { compare(os.args[2])!; return }
	panic('usage: maps345-results-compare build | compare BUILD_MANIFEST_SHA256')
}
