// SPDX-License-Identifier: GPL-2.0-or-later
// Retain and verify the complete 18-case scheduling regression and its failed
// strict-FIFO predecessor. Run from the repository root, without -prod.
module main

import crypto.sha256
import json2
import os

const base = 'build/android-maps/'
const revision = '1f21a7e0e72d5a092bf14b6d682bdf67c470f511'
const source_paths = ['build-support/android/nativeidentity/identity.v',
	'tests/native-android-ws/identity-fixture.v', 'tests/native-android-ws/identity-run.v']

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn inventory_tree(root string, relative string, mut result map[string]string) ! {
	for name in os.ls(os.join_path(root, relative))! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { result[key] = hash(path)! }
			.directory {
				result[key] = 'directory'
				inventory_tree(root, key, mut result)!
			}
			else { return error('unexpected non-regular file: ' + path) }
		}
	}
}

fn inventory(root string) !map[string]string {
	assert os.is_dir(root) && !os.is_link(root), root
	mut result := map[string]string{}
	inventory_tree(root, '', mut result)!
	return result
}

fn equal_maps(actual map[string]string, expected map[string]string) {
	assert actual.len == expected.len, 'bundle file count changed'
	for path, digest in expected { assert actual[path] or { panic('missing: ' + path) } == digest, path }
}

fn copy_file(from string, to string) ! {
	assert os.is_file(from) && !os.is_link(from), from
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	$if macos {
		// Independent APFS inodes; no hardlinks to mutable guest media.
		result := os.exec(['cp', '-c', from, to])
		assert result.exit_code == 0, result.output
	} $else { os.cp(from, to)! }
}

fn copy_tree(from string, to string) ! {
	for path, digest in inventory(from)! {
		if digest == 'directory' { os.mkdir_all(to + '/' + path)!; continue }
		copy_file(from + '/' + path, to + '/' + path)!
		assert hash(to + '/' + path)! == digest, path
	}
}

fn verify_run(root string, kind string) ! {
	run := root + '/runs/' + kind
	inputs := json2.decode[map[string]string](os.read_file(run + '/inputs.json')!)!
	assert inputs.len == 7
	for path in source_paths { assert hash(run + '/sources/' + path)! == inputs[path]!, path }
	for name in ['boot.img', 'efivars.fd'] {
		original := os.abs_path(base + 'identity-check5/' + name)
		assert hash(root + '/inputs/base/' + name)! == inputs[original]!, name
	}
	original := os.abs_path(base + 'identity-priority256-check')
	for name in ['module/sbin/init', 'runtime.tar'] {
		assert hash(run + '/' + name)! == inputs[original + '/' + name]!, name
	}
	assert os.file_size(run + '/boot.img') == u64(4294967296)
	assert os.file_size(run + '/efivars.fd') == u64(67108864)
	for name in ['module/etc/passwd', 'module/etc/group'] { assert os.file_size(run + '/' + name) > 0 }
	execution := json2.decode[map[string]json2.Any](os.read_file(run + '/execution.json')!)!
	assert !execution['recorded_after_run']!.bool()
	argv := execution['compile_argv']!.as_array().map(it.str())
	assert '-prod' !in argv && argv.last() == original + '/sources/' + source_paths[1]
	tools := execution['tool_sha256']!.as_map()
	assert tools.len == 4
	for path, digest in tools {
		assert hash(root + '/toolchain/' + os.file_name(path))! == digest.str(), path
	}
	serial := os.read_file(run + '/serial.log')!
	if kind == 'pass' {
		assert os.read_file(run + '/result.txt')! == 'PASS cases=18\nserial_sha256=' + hash(run + '/serial.log')! + '\n'
		assert serial.count('ANDROID-IDENTITY-DISABLED PASS ') == 1
		assert serial.count('ANDROID-IDENTITY-SCHED PASS ') == 3
		assert serial.count('ANDROID-IDENTITY-EXEC PASS ') == 3
		assert serial.count('ANDROID-IDENTITY-REJECT ') == 15
		assert serial.count('ANDROID-IDENTITY-SUITE PASS cases=18') == 1
		assert serial.count('fifo=unsupported-ENOSYS') == 3
		assert !serial.contains('ANDROID-IDENTITY-SUITE FAIL')
		assert os.read_file(root + '/host/pass.log')!.contains('ANDROID-IDENTITY-VM PASS cases=18')
	} else {
		assert serial.contains('left value: 38')
		assert serial.contains('right value: C.EPERM = 1')
		assert serial.contains('ANDROID-IDENTITY-SUITE FAIL identity fixture failed: fresh status=256')
		assert !serial.contains('ANDROID-IDENTITY-SUITE PASS')
		assert !os.exists(run + '/result.txt')
	}
}

fn verify(root string) ! {
	assert os.read_file(root + '/source-revision.txt')!.trim_space() == revision
	for kind in ['pass', 'failed-fifo'] { verify_run(root, kind)! }
	assert os.read_file(root + '/host/test.log')!.contains('1 passed, 1 total')
	assert os.read_file(root + '/host/prod-guard.log')!.trim_space() ==
		'ANDROID-IDENTITY-VM FAIL identity runner requires assertions; compile without -prod'
	assert hash(root + '/production/run-android-identity256')! ==
		'd6479d8a49f5d65c3190dfbca6e84f306d9becb4923ca89e93a678b2fe9fa5da'
	receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/production/build/build-receipt.json')!)!
	assert receipt['exit_code']!.int() == 0
	assert receipt['output_sha256']!.str() == hash(root + '/production/run-android-identity256')!
	production_argv := receipt['argv']!.as_array().map(it.str())
	assert '-prod' !in production_argv && production_argv.last().ends_with('/source/native-run.v')
	assert receipt['sources']!.as_map().len == 4
	assert receipt['tools']!.as_map().len == 2
	for path, digest in receipt['sources']!.as_map() {
		assert hash(root + '/production/build/source/' + path.all_after('build-support/android/'))! == digest.str(), path
	}
	for path, digest in receipt['tools']!.as_map() {
		assert hash(root + '/toolchain/' + os.file_name(path))! == digest.str(), path
	}
	legacy := json2.decode[map[string]string](os.read_file(root + '/production/run-android-identity256.receipt.json')!)!
	assert legacy[base + 'native-priority256/build-receipt.json']! == hash(root + '/production/build/build-receipt.json')!
	assert legacy[base + 'native-priority256/before-build.json']! == hash(root + '/production/build/before-build.json')!
	assert legacy[base + 'run-android-identity256']! == hash(root + '/production/run-android-identity256')!
	for path in source_paths {
		assert hash(root + '/runs/pass/sources/' + path)! == hash(root + '/sources/' + path)!, path
	}
}

fn check(root string, pin string) ! {
	assert hash(root + '/sha256.json')! == pin, 'manifest pin mismatch'
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	for path, digest in expected {
		kind := os.lstat(root + '/' + path)!.get_filetype()
		assert kind == if digest == 'directory' { .directory } else { .regular }, path
	}
	mut actual := inventory(root)!
	actual.delete('sha256.json')
	equal_maps(actual, expected)
	verify(root)!
	println('ANDROID-IDENTITY-EVIDENCE PASS files=${expected.len}')
}

fn negative(root string, pin string) ! {
	assert hash(root + '/sha256.json')! == pin, 'original manifest pin mismatch'
	wrong := os.exec([os.executable(), 'check', root, '0'.repeat(64)])
	assert wrong.exit_code != 0 && wrong.output.contains('manifest pin mismatch'), wrong.output
	scratch := root + '-negative'
	assert !os.exists(scratch) && !os.is_link(scratch), 'fresh negative scratch required'
	os.mkdir(scratch)!
	copy_file(root + '/sha256.json', scratch + '/sha256.json')!
	copy_file(root + '/source-revision.txt', scratch + '/source-revision.txt')!
	partial := os.exec([os.executable(), 'check', scratch, pin])
	assert partial.exit_code != 0 && partial.output.contains('ANDROID-IDENTITY-EVIDENCE FAIL'), partial.output
	os.write_file(scratch + '/wrong-pin.log', wrong.output)!
	os.write_file(scratch + '/partial.log', partial.output)!
	println('ANDROID-IDENTITY-EVIDENCE NEGATIVE PASS wrong-pin and authentic partial bundle rejected')
}

fn execute() ! {
	$if prod { return error('evidence checker requires assertions; compile without -prod') }
	assert os.args.len in [3, 4], 'usage: identity-priority-evidence retain EXTERNAL_DIR | check|negative EXTERNAL_DIR MANIFEST_SHA256'
	root := os.args[2].trim_right('/')
	assert os.is_abs_path(root) && os.abs_path(root) == root, 'canonical absolute directory required'
	assert !os.is_link(root), 'bundle directory must not be a symlink'
	assert os.real_path(os.dir(root)) == os.dir(root), 'bundle parent directory must be canonical'
	assert root != os.getwd() && !root.starts_with(os.getwd() + '/'), 'external state storage required'
	if os.args[1] == 'retain' {
		assert os.args.len == 3 && !os.exists(root) && !os.is_link(root), 'fresh directory required'
		for kind, from in {'pass': 'identity-priority256-check', 'failed-fifo': 'identity-priority256-failed-fifo'} {
			copy_tree(base + from, root + '/runs/' + kind)!
		}
		for name in ['boot.img', 'efivars.fd'] { copy_file(base + 'identity-check5/' + name, root + '/inputs/base/' + name)! }
		for name, from in {'pass.log': 'identity-priority256-run.log', 'test.log': 'nativeidentity-priority256-host-test.log',
			'prod-guard.log': 'identity-priority256-prod-guard.log', 'prod-guard-build.log': 'identity-priority256-prod-guard-build.log',
			'runner': 'identity-priority256-run', 'prod-guard': 'identity-priority256-prod-guard'} {
			copy_file(base + from, root + '/host/' + name)!
		}
		copy_tree(base + 'native-priority256', root + '/production/build')!
		for name in ['run-android-identity256', 'run-android-identity256.receipt.json'] { copy_file(base + name, root + '/production/' + name)! }
		execution := json2.decode[map[string]json2.Any](os.read_file(root + '/runs/pass/execution.json')!)!
		for path, digest in execution['tool_sha256']!.as_map() {
			assert hash(path)! == digest.str(), 'tool changed since the regression run: ' + path
			copy_file(os.real_path(path), root + '/toolchain/' + os.file_name(path))!
		}
		for path in source_paths {
			result := os.exec(['git', 'show', revision + ':' + path])
			assert result.exit_code == 0, result.output
			os.mkdir_all(os.dir(root + '/sources/' + path))!
			os.write_file(root + '/sources/' + path, result.output)!
		}
		os.write_file(root + '/source-revision.txt', revision + '\n')!
		copy_file('tests/native-android-ws/identity-priority-evidence.v', root + '/audit/identity-priority-evidence.v')!
		verify(root)!
		os.write_file(root + '/sha256.json', json2.encode(inventory(root)!, prettify: true) + '\n')!
		println('ANDROID-IDENTITY-EVIDENCE SEALED manifest_sha256=' + hash(root + '/sha256.json')!)
	} else if os.args[1] == 'negative' {
		assert os.args.len == 4
		negative(root, os.args[3])!
	} else {
		assert os.args[1] == 'check' && os.args.len == 4
		check(root, os.args[3])!
	}
}

fn main() { execute() or { eprintln('ANDROID-IDENTITY-EVIDENCE FAIL ${err}'); exit(1) } }
