// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the complete Maps257 prelaunch state before its private VM starts.
module main

import crypto.sha256
import compress.gzip
import json2
import os

const expected_pin = '9fda8d49c93cb16a62a40912eff771228fdc9b4b0f16bf35f770f5dd158f8eb7'
const frozen = '/Users/alex/.local/state/vinix/android/maps256-2026-10-24'
const prepared = 'build/android-maps/maps257'
const prelaunch_pin = '8870428fa649fe8c1a9f335328ba0c9c3471210f601034bda02375c2019688a8'
const run_source = 'build/android-maps/attempt257'
const scope = 'Maps257 completed its configured240-second observation and published original outcome startup_failed, functional_passed=null. Four optional gRPC ClassNotFoundException markers are retained; the classifier is unchanged. Manual screenshots show map, live Paris and Eiffel Tower suggestions, Paris details/photos,21min6.1km route, preview and next instruction. GPS, sign-in and voice were not verified. The map polling driver PID23893 was manually stopped around18:01:44UTC after UI readiness; this was not a suite failure. command-37333 stdout/stderr paths were reused by search-ready and paris-query, so their first stream bytes were overwritten; original logs are preserved, screenshots retained, and no complete per-command stream claim is made.\n'

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut h := sha256.new()
	mut b := []u8{len: 1024 * 1024}
	for {
		n := f.read(mut b) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		h.write(b[..n])!
	}
	return h.sum([]u8{}).hex()
}

fn clone(source string, destination string) ! {
	os.mkdir_all(os.dir(destination))!
	result := os.exec(['cp', '-c', '-R', '-P', source, destination])
	if result.exit_code != 0 { return error('clone ' + source + ': ' + result.output) }
}

fn retain(root string) ! {
	if !os.is_abs_path(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		return error('absolute external state directory required')
	}
	if os.exists(root) { return error('fresh external directory required') }
	if hash(prepared + '/prelaunch-sha256.json')! != expected_pin { return error('wrong preparation pin') }
	os.mkdir_all(root + '/prelaunch')!
	clone(prepared, root + '/prelaunch/replica/' + prepared)!
	for source in ['build/android-maps/attempt257.json', 'build/android-maps/maps-interact-bounded',
		'build/android-run', 'build/qemu-horizontal/bin/qemu-system-aarch64',
		'tests/native-android-ws/maps-replay.v', 'tests/native-android-ws/maps-replay-retain.v',
		'build/android-maps/maps-replay', 'build/android-maps/maps257-prepare.log',
		'build/android-maps/maps-replay-prod-guard.log', 'build/android-maps/maps-replay-wrong-pin.log',
		'/Users/alex/code/v/v_old'] {
		clone(source, root + '/prelaunch/replica/' + source.trim_left('/'))!
	}
	clone(frozen + '/frozen-inputs.json', root + '/prelaunch/frozen256/frozen-inputs.json')!
	clone(frozen + '/inputs', root + '/prelaunch/frozen256/inputs')!
	clone(frozen + '/runtime', root + '/prelaunch/runtime')!
	clone(frozen + '/source-revision.txt', root + '/prelaunch/frozen256/source-revision.txt')!
	if hash(root + '/prelaunch/replica/' + prepared + '/prelaunch-sha256.json')! != expected_pin {
		return error('retained preparation pin differs')
	}
	println('MAPS257 PRELAUNCH CLONED ' + root)
}

fn walk_files(root string, relative string, mut entries map[string]string, omit_qmp bool, mut omitted []string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			.directory {
				entries[key] = 'directory'
				walk_files(root, key, mut entries, omit_qmp, mut omitted)!
			}
			.socket {
				if !omit_qmp || key != 'google-maps/qmp.sock' { return error('unexpected socket: ' + path) }
				omitted << key
			}
			else { return error('unexpected special file: ' + path) }
		}
	}
}

fn walk(root string, relative string, mut entries map[string]string) ! {
	mut omitted := []string{}
	walk_files(root, relative, mut entries, false, mut omitted)!
}

fn inventory(root string) !map[string]string {
	mut entries := map[string]string{}
	walk(root, '', mut entries)!
	return entries
}

fn equal_maps(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory lengths differ') }
	for path, value in expected {
		if actual[path] or { '' } != value { return error('inventory differs: ' + path) }
	}
}

fn read_map(path string) !map[string]string {
	return json2.decode[map[string]string](os.read_file(path)!)!
}

fn seal(root string) ! {
	base := root + '/prelaunch'
	if hash(base + '/replica/' + prepared + '/prelaunch-sha256.json')! != expected_pin {
		return error('wrong retained preparation pin')
	}
	pins := json2.decode[map[string]string](os.read_file(base + '/replica/' + prepared + '/prelaunch-sha256.json')!)!
	for path, expected in pins {
		retained := if path == frozen + '/frozen-inputs.json' { base + '/frozen256/frozen-inputs.json' }
			else { base + '/replica/' + path.trim_left('/') }
		if hash(retained)! != expected { return error('retained pin differs: ' + path) }
	}
	inputs := json2.decode[map[string]string](os.read_file(base + '/frozen256/frozen-inputs.json')!)!
	if inputs.len != 73 { return error('incomplete frozen inputs') }
	for path, expected in inputs {
		if hash(base + '/frozen256/inputs/' + path.trim_left('/'))! != expected { return error('frozen input differs: ' + path) }
	}
	runtime := json2.decode[map[string]string](os.read_file(base + '/replica/' + prepared + '/runtime-after.json')!)!
	if runtime.len != 109 { return error('incomplete runtime map') }
	for path, expected in runtime {
		if hash(base + '/runtime/' + path)! != expected { return error('retained runtime differs: ' + path) }
	}
	mut entries := map[string]string{}
	walk(base, '', mut entries)!
	os.write_file(root + '/prelaunch-sha256.json', json2.encode(entries, prettify: true) + '\n')!
	println('MAPS257 PRELAUNCH SEALED files=' + entries.len.str() + ' sha256=' + hash(root + '/prelaunch-sha256.json')!)
}

fn verify_prelaunch(root string) ! {
	assert hash(root + '/prelaunch-sha256.json')! == prelaunch_pin, 'wrong prelaunch inventory pin'
	equal_maps(inventory(root + '/prelaunch')!, read_map(root + '/prelaunch-sha256.json')!)!
	base := root + '/prelaunch'
	suite := os.read_file(base + '/replica/' + prepared + '/suite257.v')!
	original := os.read_file(base + '/frozen256/inputs/build/android-maps/suite256-resume.v')!
	assert suite.all_after('fn observation(').all_before('// Real companion packages') == original.all_after('fn observation(').all_before('// Real companion packages')
	config := json2.decode[map[string]json2.Any](os.read_file(base + '/replica/build/android-maps/attempt257.json')!)!
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 240
}

fn collect_run(root string) ! {
	assert hash(root + '/prelaunch-sha256.json')! == prelaunch_pin
	for name in ['run', 'supplemental', 'media', 'audit'] { assert !os.exists(root + '/' + name) }
	harness := os.read_file(run_source + '-harness.log')!
	assert harness.contains('APK-SUITE result google-maps startup_failed')
	mut raw := map[string]string{}
	mut omitted := []string{}
	walk_files(run_source, '', mut raw, true, mut omitted)!
	for path, value in raw {
		if value == 'directory' { os.mkdir_all(root + '/run/' + path)! }
		else { clone(run_source + '/' + path, root + '/run/' + path)! }
	}
	for name in ['harness', 'onboarding-driver', 'map-driver'] {
		clone(run_source + '-' + name + '.log', root + '/supplemental/' + name + '.log')!
	}
	for name, target in {'boot.img': 'boot-after-run.img', 'efivars.fd': 'efivars-after-run.fd'} {
		clone(prepared + '/vm/' + name, root + '/media/' + target)!
	}
	os.mkdir_all(root + '/audit')!
	clone(@FILE, root + '/audit/maps-replay-retain.v')!
	clone(os.executable(), root + '/audit/maps-replay-retain')!
	os.write_file(root + '/audit/raw-inventory.json', json2.encode(raw, prettify: true) + '\n')!
	os.write_file(root + '/audit/omitted-special-files.json', json2.encode(omitted) + '\n')!
	os.write_file(root + '/audit/scope.txt', scope)!
	mut after := map[string]string{}
	mut after_omitted := []string{}
	walk_files(run_source, '', mut after, true, mut after_omitted)!
	equal_maps(after, raw)!
	assert after_omitted == omitted
	println('MAPS257 RUN COLLECTED complete ordinary outputs, logs and stopped postrun media')
}

fn verify_run(root string) ! {
	equal_maps(inventory(root + '/run')!, read_map(root + '/audit/raw-inventory.json')!)!
	omitted := json2.decode[[]string](os.read_file(root + '/audit/omitted-special-files.json')!)!
	assert omitted.len <= 1 && omitted.all(it == 'google-maps/qmp.sock')
	apps := json2.decode[[]json2.Any](os.read_file(root + '/run/results.json')!)!
	assert apps.len == 1
	app := apps[0].as_map()
	assert app['id']!.str() == 'google-maps' && app['package']!.str() == 'com.google.android.apps.maps'
	assert app['outcome']!.str() == 'startup_failed' && json2.encode(app['functional_passed']!) == 'null'
	assert app['startup_timeout_seconds']!.int() == 240 && app['observation_elapsed_seconds']!.int() == 240
	assert app['qemu_alive_before_capture']!.bool() && !app['process_exited']!.bool()
	assert app['backend_ready']!.bool() && app['native_maps_observed']!.bool() && app['launcher_entered']!.bool()
	markers := app['failure_markers']!.as_array()
	assert markers.len == 4
	for marker in markers {
		line := marker.str()
		assert line.contains('ClassNotFoundException') && (line.contains('JndiResourceResolverFactory') || line.contains('ContextStorageOverride'))
	}
	state := root + '/run/google-maps'
	preliminary := json2.decode[map[string]json2.Any](os.read_file(state + '/observation-before-capture.json')!)!
	for key, value in preliminary { assert json2.encode(value) == json2.encode(app[key]!), key }
	serial := os.read_bytes(state + '/serial.log')!
	assert gzip.decompress(os.read_bytes(state + '/serial.log.gz')!)! == serial
	assert sha256.sum(serial).hex() == app['serial_sha256']!.str()
	text := serial.bytestr()
	assert text.contains('APK-SUITE-BEGIN id=google-maps backend=vinix-ws') && text.contains('ANDROID-WS-READY backend=vinix-native')
	for marker in ['APK-SUITE-EXIT id=google-maps', 'No permission to set thread priority', 'JNI DETECTED ERROR', 'Fatal signal 11'] { assert !text.contains(marker), marker }
	assert hash(state + '/application.png')! == app['screenshot_sha256']!.str() && 'screenshot_error' !in app
	for name in ['onboarding', 'map-probe', 'search-ready', 'paris-query', 'paris-result', 'directions-open', 'origin-suggestions', 'route-first', 'route-ready', 'route-preview', 'next-step', 'application'] {
		bytes := os.read_bytes(state + '/' + name + '.png')!
		assert bytes.len > 1000 && bytes[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10], name
	}
	assert os.file_size(state + '/network.pcap') > 24
	harness := os.read_file(root + '/supplemental/harness.log')!
	assert harness.contains('MAPS257 observation retained before final capture') && harness.contains('APK-SUITE result google-maps startup_failed') && !harness.contains('V panic')
	interaction := os.read_file(state + '/interaction.log')!
	assert !interaction.contains('timed_out=true') && !interaction.contains('output_drain_capped=true')
	mut stream_counts := map[string]int{}
	for line in interaction.split_into_lines() {
		if !line.contains(' BEGIN [') { continue }
		for stream in ['stdout', 'stderr'] {
			path := line.all_after(stream + '=').all_before(' ')
			assert path.starts_with(os.getwd() + '/' + run_source + '/google-maps/')
			name := os.file_name(path)
			assert os.is_file(state + '/' + name)
			stream_counts[name]++
		}
	}
	for path, count in stream_counts {
		assert count == if path.starts_with('command-37333.') { 2 } else { 1 }, path
	}
	assert stream_counts['command-37333.stdout.log'] == 2 && stream_counts['command-37333.stderr.log'] == 2
	assert os.read_file(root + '/supplemental/onboarding-driver.log')!.contains('SKIP-CLICK')
	assert os.file_size(root + '/media/boot-after-run.img') == u64(4294967296)
	assert os.file_size(root + '/media/efivars-after-run.fd') == u64(67108864)
	pins := read_map(root + '/prelaunch/replica/' + prepared + '/prelaunch-sha256.json')!
	assert hash(root + '/media/boot-after-run.img')! == pins[prepared + '/vm/boot.img']!, 'postrun FAT media differs from sealed prelaunch media'
	assert os.read_file(root + '/audit/scope.txt')! == scope
	assert os.read_file(root + '/audit/maps-replay-retain.v')! == os.read_file(@FILE)!
}

fn seal_run(root string) ! {
	verify_prelaunch(root)!
	verify_run(root)!
	manifest := inventory(root)!
	assert 'sha256.json' !in manifest
	os.write_file(root + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS257 RUN SEALED entries=' + manifest.len.str() + ' sha256=' + hash(root + '/sha256.json')!)
}

fn check(root string, pin string) ! {
	assert pin.len == 64 && hash(root + '/sha256.json')! == pin, 'manifest differs from report'
	mut actual := inventory(root)!
	actual.delete('sha256.json')
	equal_maps(actual, read_map(root + '/sha256.json')!)!
	verify_prelaunch(root)!
	verify_run(root)!
	println('MAPS257-EVIDENCE PASS complete configured observation; original startup_failed classification preserved; manual UI review documented')
}

fn negative(root string, pin string) ! {
	assert hash(root + '/sha256.json')! == pin
	directory := root + '-negative'
	assert !os.exists(directory), 'fresh negative audit directory required'
	clone(root + '/sha256.json', directory + '/partial/sha256.json')!
	partial := os.exec([os.executable(), 'check', directory + '/partial', pin])
	assert partial.exit_code != 0 && partial.output.contains('inventory lengths differ'), partial.output
	os.write_file(directory + '/partial.log', partial.output)!
	wrong := os.exec([os.executable(), 'check', root, '0'.repeat(64)])
	assert wrong.exit_code != 0 && wrong.output.contains('manifest differs from report'), wrong.output
	os.write_file(directory + '/wrong-pin.log', wrong.output)!
	println('MAPS257-NEGATIVE PASS authentic partial bundle and wrong pin rejected')
}

fn main() {
	$if prod { eprintln('retention requires assertions; compile without -prod'); exit(2) }
	if os.args.len < 3 { eprintln('usage: maps-replay-retain clone|seal|collect-run|seal-run EXTERNAL_DIRECTORY; check|negative EXTERNAL_DIRECTORY PIN'); exit(2) }
	if os.args[1] == 'clone' { retain(os.args[2]) or { eprintln(err); exit(1) } }
	else if os.args[1] == 'seal' { seal(os.args[2]) or { eprintln(err); exit(1) } }
	else if os.args[1] == 'collect-run' { collect_run(os.args[2]) or { eprintln(err); exit(1) } }
	else if os.args[1] == 'seal-run' { seal_run(os.args[2]) or { eprintln(err); exit(1) } }
	else if os.args[1] == 'check' && os.args.len == 4 { check(os.args[2], os.args[3]) or { eprintln(err); exit(1) } }
	else if os.args[1] == 'negative' && os.args.len == 4 { negative(os.args[2], os.args[3]) or { eprintln(err); exit(1) } }
	else { eprintln('unknown operation'); exit(2) }
}
