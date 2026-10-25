// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve complete working Maps attempts and late interactions separately from sealed runs.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const unit = repo + '/tests/native-android-ws/maps-postrun-supplement.v'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn inventory(root string, relative string, mut entries map[string]string, mut omitted map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		info := os.lstat(path)!
		match info.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory {
				entries[key] = 'directory'
				inventory(root, key, mut entries, mut omitted)!
			}
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			.socket {
				assert key == 'google-maps/qmp.sock', 'only the attempt QMP socket may be omitted'
				omitted[key] = (info.mode & 0o7777).str()
				continue
			}
			else { return error('unsupported artifact: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}
fn entries(root string) !map[string]string {
	mut result := map[string]string{}
	mut omitted := map[string]string{}
	inventory(root, '', mut result, mut omitted)!
	assert omitted.len == 0, 'unexpected socket in sealed evidence'
	return result
}
fn equal(actual map[string]string, expected map[string]string) ! {
	assert actual.len == expected.len, 'complete inventory count differs'
	for key, value in expected { assert actual[key] or { '' } == value, key }
}
fn fresh(path string) ! {
	assert os.abs_path(path) == path && os.dir(path) == state.trim_right('/'), 'direct external state child required'
	assert os.real_path(os.dir(path)) == os.real_path(state), 'canonical external parent required'
	assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	os.mkdir_all(path)!
}
fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to)
	os.mkdir_all(os.dir(to))!
	result := os.exec(['/bin/cp', '-c', '-p', '-R', '-P', from, to])
	assert result.exit_code == 0, result.output
}
fn copy_attempt(from string, to string) ! {
	os.mkdir(to)!
	for name in os.ls(from)! {
		input := from + '/' + name
		output := to + '/' + name
		info := os.lstat(input)!
		match info.get_filetype() {
			.directory { copy_attempt(input, output)! }
			.regular, .symbolic_link { clone(input, output)! }
			.socket { assert name == 'qmp.sock' && os.base(from) == 'google-maps' }
			else { return error('unsupported artifact while copying: ' + input) }
		}
	}
	os.chmod(to, int(os.lstat(from)!.mode & 0o7777))!
}
fn verify(root string, pin string) !int {
	assert hash(root + '/sha256.json')! == pin
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := entries(root)!
	actual.delete('sha256.json')
	actual.delete('@mode:sha256.json')
	equal(actual, expected)!
	assert hash(root + '/sha256.json')! == pin
	return actual.len
}
fn seal(root string) !string {
	all := entries(root)!
	assert 'sha256.json' !in all
	write_json(root + '/sha256.json', all)!
	pin := hash(root + '/sha256.json')!
	verify(root, pin)!
	return pin
}
fn verify_run(root string, pin string) ! {
	assert hash(root + '/sha256.json')! == pin
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	for key, value in entries(root)! {
		if key.starts_with('@mode:') { continue }
		assert value != 'directory' && !value.starts_with('symlink:'), 'flat regular run receipt required'
		if key != 'sha256.json' { actual[key] = value }
	}
	equal(actual, expected)!
	assert hash(root + '/sha256.json')! == pin
}
fn build(root string) ! {
	fresh(root)!
	assert hash(compiler)! == compiler_pin && hash(unit)! == hash(@FILE)!
	clone(unit, root + '/source.v')!
	clone(compiler, root + '/v_old276')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.mkdir(root + '/generated-c')!
	os.setenv('VTMP', root + '/generated-c', true)
	list_argv := [compiler, '-print-v-files', unit]
	listing := os.exec(list_argv)
	os.write_file(root + '/closure-v-files.txt', listing.output)!
	assert listing.exit_code == 0, listing.output
	mut before := map[string]string{}
	for source in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[source] = hash(source)!
		clone(source, root + '/closure/' + os.abs_path(source).trim_left('/'))!
	}
	assert unit in before && before.len >= 10
	write_json(root + '/closure-before.json', before)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', root + '/preserve', unit]
	mut receipt := {
		'argv': json2.Any(argv)
		'closure_argv': json2.Any(list_argv)
		'closure_exit_code': json2.Any(listing.exit_code)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(unit)!)
		'closure_before_sha256': json2.Any(hash(root + '/closure-before.json')!)
	}
	write_json(root + '/build-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(root + '/build.log', result.output)!
	mut after := map[string]string{}
	for source, pin in before {
		after[source] = hash(source)!
		assert hash(root + '/closure/' + os.abs_path(source).trim_left('/'))! == pin
	}
	equal(after, before)!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	write_json(root + '/closure-after.json', after)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	receipt['closure_after_sha256'] = hash(root + '/closure-after.json')!
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(root + '/preserve')! }
	write_json(root + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	println('MAPS-POSTRUN-BUILD-PASS seal=' + seal(root)!)
}
fn preserve(number string, canonical_pin string, run_pin string, build_root string, build_pin string, root string) ! {
	assert number.u64().str() == number && number.u64() > 0
	verify(build_root, build_pin)!
	assert os.executable() == build_root + '/preserve'
	assert hash(os.executable())! == hash(build_root + '/preserve')!
	assert hash(unit)! == hash(build_root + '/source.v')!
	canonical := state + 'maps' + number + '-2026-10-25'
	run := state + 'maps' + number + '-run-receipt-2026-10-25'
	live := repo + '/build/android-maps/attempt' + number
	captured := canonical + '/results/attempt' + number
	assert hash(canonical + '/sha256.json')! == canonical_pin
	verify_run(run, run_pin)!
	canonical_all := json2.decode[map[string]string](os.read_file(canonical + '/sha256.json')!)!
	original := entries(captured)!
	mut expected := map[string]string{}
	prefix := 'results/attempt' + number + '/'
	for key, value in canonical_all {
		if key.starts_with(prefix) { expected[key[prefix.len..]] = value }
		if key.starts_with('@mode:' + prefix) { expected['@mode:' + key[6 + prefix.len..]] = value }
	}
	equal(original, expected)!
	mut before := map[string]string{}
	mut omitted := map[string]string{}
	inventory(live, '', mut before, mut omitted)!
	old_log := os.read_file(captured + '/google-maps/interaction.log')!
	new_log := os.read_file(live + '/google-maps/interaction.log')!
	assert new_log.starts_with(old_log), 'exact sealed interaction prefix required'
	appended := new_log[old_log.len..]
	mut changed := []string{}
	mut added := []string{}
	mut deleted := []string{}
	for key, value in before {
		if key.starts_with('@mode:') { continue }
		if key !in original { added << key }
		else if original[key]! != value || original['@mode:' + key]! != before['@mode:' + key]! { changed << key }
	}
	for key, _ in original { if !key.starts_with('@mode:') && key !in before { deleted << key } }
	changed.sort()
	added.sort()
	deleted.sort()
	fresh(root)!
	clone(build_root, root + '/build')!
	clone(canonical + '/sha256.json', root + '/canonical-sha256.json')!
	clone(run, root + '/run-receipt')!
	verify(root + '/build', build_pin)!
	assert hash(root + '/canonical-sha256.json')! == canonical_pin
	verify_run(root + '/run-receipt', run_pin)!
	copy_attempt(live, root + '/attempt' + number)!
	equal(entries(root + '/attempt' + number)!, before)!
	mut after := map[string]string{}
	mut omitted_after := map[string]string{}
	inventory(live, '', mut after, mut omitted_after)!
	equal(after, before)!
	equal(omitted_after, omitted)!
	equal(entries(captured)!, original)!
	assert hash(canonical + '/sha256.json')! == canonical_pin && hash(run + '/sha256.json')! == run_pin
	os.write_file(root + '/appended-interaction.log', appended)!
	write_json(root + '/canonical-attempt-inventory.json', original)!
	write_json(root + '/working-attempt-inventory.json', before)!
	write_json(root + '/omitted-sockets.json', omitted)!
	write_json(root + '/scope.json', {
		'created_utc': json2.Any(time.utc().str())
		'canonical_root': json2.Any(canonical)
		'canonical_manifest_sha256': json2.Any(canonical_pin)
		'run_receipt_root': json2.Any(run)
		'run_receipt_manifest_sha256': json2.Any(run_pin)
		'live_source': json2.Any(live)
		'preservation_build_manifest_sha256': json2.Any(build_pin)
		'added_paths': json2.Any(added)
		'changed_paths': json2.Any(changed)
		'deleted_paths': json2.Any(deleted)
		'appended_interaction_lines': json2.Any(appended.trim_space().split_into_lines())
		'scope': json2.Any('Complete working attempt preserved after automatic collection, with an exact canonical interaction prefix and explicit late delta. Only a QMP socket may be omitted and every omission is logged. Source attempt and sealed canonical evidence remain unchanged. This supplement does not qualify any additional application behavior.')
	})!
	pin := seal(root)!
	println('MAPS-POSTRUN-PRESERVATION-PASS manifest=' + pin + ' typed=' + verify(root, pin)!.str())
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo
	if os.args.len == 3 && os.args[1] == 'build' { build(os.args[2])!; return }
	if os.args.len == 8 && os.args[1] == 'preserve' {
		preserve(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7])!
		return
	}
	if os.args.len == 4 && os.args[1] == 'verify' {
		println('MAPS-POSTRUN-READBACK-PASS typed=' + verify(os.args[2], os.args[3])!.str())
		return
	}
	panic('usage: build BUILD_ROOT | preserve NUMBER CANONICAL_SHA RUN_RECEIPT_SHA BUILD_ROOT BUILD_SHA OUTPUT | verify ROOT SHA')
}
