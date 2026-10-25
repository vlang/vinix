// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve late Maps341 interaction receipts without changing its sealed replay.
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
const root = state + 'maps341-postrun-interactions-2026-10-25'
const build_root = state + 'maps341-interactions-preserve-build-2026-10-25'
const unit = repo + '/tests/native-android-ws/maps341-interactions-preserve.v'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const canonical = state + 'maps341-2026-10-25'
const canonical_pin = 'a94fe6dcf84d7104ad767e5173b183629519a9b271a7bc6a94209b9e58a724bb'
const envelope = state + 'maps341-launch-receipt-2026-10-25'
const envelope_pin = '3481188c5ea7eb2fdc666fdaeebe7acc11b7e1b310ca207e19e9e8726895f852'
const runner = repo + '/build/android-maps/maps341-run-recorded'
const runner_pin = '510307806f3453ec28fff359343da2fa1a871ea427406f8c8442840a807fee69'
const live = repo + '/build/android-maps/attempt341/google-maps'
const captured = canonical + '/results/attempt341/google-maps'
const late = 'command-31697-1792947828378140000-15208'

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
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', build_root + '/preserve', unit]
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
		'scope': json2.Any('Recorded build of the preservation tool before preservation; bootstrap only invokes this build mode.')
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
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(build_root + '/preserve')! }
	write_json(build_root + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	println('MAPS341-INTERACTIONS-BUILD seal=' + seal(build_root)!)
}
fn preserve(build_pin string) ! {
	build_files := authenticate(build_root, build_pin)!
	assert os.executable() == build_root + '/preserve'
	assert hash(os.executable())! == build_files['preserve']!
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
	before := files(live)!
	original := files(captured)!
	mut delta := []string{}
	for name, pin in before {
		if name !in original || original[name]! != pin { delta << name }
	}
	for name, _ in original { assert name in before, 'deleted canonical file: ' + name }
	delta.sort()
	mut expected := ['interaction.log', late + '.stdout.log', late + '.stderr.log']
	expected.sort()
	assert delta == expected, 'only the three known late interaction files may differ'
	original_log := os.read_file(captured + '/interaction.log')!
	live_log := os.read_file(live + '/interaction.log')!
	assert live_log.starts_with(original_log)
	appended := live_log.substr(original_log.len, live_log.len)
	lines := appended.trim_space().split_into_lines()
	assert lines.len == 2 && lines[0].starts_with('2026-10-25 17:03:48 UTC BEGIN ')
	assert lines[1].starts_with('2026-10-25 17:03:48 UTC END exit=1 timed_out=false ')
	assert lines[0].contains('/attraction-place.png') && lines.all(it.contains(late))
	assert !os.exists(live + '/attraction-place.png') && !os.is_link(live + '/attraction-place.png')
	mut modes := map[string]string{}
	for name in delta {
		clone(live + '/' + name, root + '/files/' + name)!
		assert hash(root + '/files/' + name)! == before[name]!
		mode := (os.lstat(live + '/' + name)!.mode & 0o7777).str()
		assert (os.lstat(root + '/files/' + name)!.mode & 0o7777).str() == mode
		modes[name] = mode
	}
	equal(files(live)!, before)!
	equal(files(captured)!, original)!
	assert hash(canonical + '/sha256.json')! == canonical_pin
	assert hash(envelope + '/sha256.json')! == envelope_pin
	write_json(root + '/canonical-files.json', original)!
	write_json(root + '/live-files.json', before)!
	write_json(root + '/file-modes.json', modes)!
	write_json(root + '/scope.json', {
		'created_utc': json2.Any(time.utc().str())
		'canonical_root': json2.Any(canonical)
		'canonical_manifest_sha256': json2.Any(canonical_pin)
		'launch_envelope_root': json2.Any(envelope)
		'launch_envelope_manifest_sha256': json2.Any(envelope_pin)
		'live_source': json2.Any(live)
		'preservation_build_manifest_sha256': json2.Any(build_pin)
		'delta_files': json2.Any(delta)
		'appended_interaction_lines': json2.Any(lines)
		'late_command_utc': json2.Any('2026-10-25 17:03:48')
		'late_command_exit_code': json2.Any(1)
		'late_capture_created_png': json2.Any(false)
		'original_paths_modified': json2.Any(false)
		'scope': json2.Any('Separate supplement after automatic Maps341 collection. Complete live interaction.log replaces its prefix copy only within this supplement; two late command logs are absent from canonical. The original canonical bundle and envelope remain unchanged.')
	})!
	println('MAPS341-POSTRUN-INTERACTIONS seal=' + seal(root)!)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo
	if os.args.len == 2 && os.args[1] == 'build' { build()!; return }
	if os.args.len == 3 && os.args[1] == 'preserve' { preserve(os.args[2])!; return }
	panic('usage: maps341-interactions-preserve build | preserve BUILD_MANIFEST_SHA256')
}
