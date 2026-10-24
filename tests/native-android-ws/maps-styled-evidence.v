// SPDX-License-Identifier: GPL-2.0-or-later
// Complete Maps263 retention; the sealed classifier records its actual outcome.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/'
const prepared = base + 'maps263'
const paired = base + 'compound262'
const run_source = base + 'attempt263'
const frozen_pin = '7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64'
const identity_pin = 'd6479d8a49f5d65c3190dfbca6e84f306d9becb4923ca89e93a678b2fe9fa5da'
const unique_pin = 'ccf1c4eeff9011d560bef1bfc1e63929f78f7169d2ac697e98459a8975fb5d95'
const driver_pin = 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208'
const driver_source_pin = 'bd7ee074d8b95ad3671d184ee3ae35072171d2a22bcc476c308e464d90a5dfcc'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const scope = 'Maps263 retains its configured 240-second observation and actual unchanged classifier outcome. Visual chip-icon review is separate from classification and suggestion-circle behavior. GPS, sign-in, voice, 900-second endurance and independent post-drop identity were not measured. Unique258 command streams must be complete and unique. Required screenshots use unique capture names; onboarding/map polling probes may be overwritten and are attributed only to their last successful capture. The unique258 build command record was written after compilation.\n'

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

fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn read_object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }

fn equal_maps(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory lengths differ') }
	for path, value in expected { if actual[path] or { '' } != value { return error('inventory differs: ' + path) } }
}

fn external(root string) ! {
	if !os.is_abs_path(root) || !os.is_dir(root) || os.real_path(root) != root { return error('existing canonical external directory required') }
	repo := os.real_path(os.getwd())
	if root == repo || root.starts_with(repo + '/') { return error('external state must be outside checkout') }
}

fn walk(root string, relative string, mut entries map[string]string, omit_qmp bool, mut omitted []string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			.directory { entries[key] = 'directory'; walk(root, key, mut entries, omit_qmp, mut omitted)! }
			.socket {
				if !omit_qmp || key != 'google-maps/qmp.sock' { return error('unexpected socket: ' + path) }
				omitted << key
			}
			else { return error('unexpected special file: ' + path) }
		}
	}
}

fn inventory(root string) !map[string]string {
	mut entries := map[string]string{}
	mut omitted := []string{}
	walk(root, '', mut entries, false, mut omitted)!
	return entries
}

fn subtree(entries map[string]string, prefix string) map[string]string {
	mut result := map[string]string{}
	for path, value in entries { if path.starts_with(prefix + '/') { result[path.substr(prefix.len + 1, path.len)] = value } }
	return result
}

fn regular(entries map[string]string) map[string]string {
	mut result := map[string]string{}
	for path, value in entries { if value != 'directory' && !value.starts_with('symlink:') { result[path] = value } }
	return result
}

fn clone(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('fresh destination required: ' + to) }
	os.mkdir_all(os.dir(to))!
	r := os.exec(['cp', '-c', '-R', '-P', from, to])
	if r.exit_code != 0 { return error('clone failed: ' + r.output) }
}

fn collect(root string, pin string, frames []string) ! {
	external(root)!
	if hash(root + '/prelaunch-sha256.json')! != pin { return error('wrong prelaunch pin') }
	for name in ['run', 'supplemental', 'media', 'audit'] { if os.exists(root + '/' + name) || os.is_link(root + '/' + name) { return error('fresh run destination required: ' + name) } }
	if frames.len < 3 || 'application' !in frames || 'paris-result' !in frames || 'route-first' !in frames { return error('required frames include application, paris-result and route-first') }
	mut seen := map[string]bool{}
	for name in frames {
		if name == '' || name != os.base(name) || name in ['.', '..'] || name in seen { return error('unique frame basenames required') }
		seen[name] = true
	}
	if !os.read_file(run_source + '-harness.log')!.contains('APK-SUITE result google-maps ') { return error('completed harness log required') }
	mut raw := map[string]string{}
	mut omitted := []string{}
	walk(run_source, '', mut raw, true, mut omitted)!
	for path, value in raw {
		if value == 'directory' { os.mkdir_all(root + '/run/' + path)! }
		else { clone(run_source + '/' + path, root + '/run/' + path)! }
	}
	for name in os.ls(base)! {
		if name.starts_with('attempt263-') && name.ends_with('.log') { clone(base + name, root + '/supplemental/' + name)! }
	}
	for name, output in {'boot.img': 'boot-after-run.img', 'efivars.fd': 'efivars-after-run.fd'} { clone(prepared + '/vm/' + name, root + '/media/' + output)! }
	os.mkdir_all(root + '/audit')!
	clone(@FILE, root + '/audit/maps-styled-evidence.v')!
	clone(os.executable(), root + '/audit/maps-styled-evidence')!
	for name in ['before.json', 'receipt.json', 'selftest.log', 'assertion.log', 'prod-guard.log'] {
		clone(base + 'maps263-checker-' + name, root + '/audit/checker-' + name)!
	}
	write_json(root + '/audit/raw-inventory.json', raw)!
	write_json(root + '/audit/omitted-special-files.json', omitted)!
	write_json(root + '/audit/required-frames.json', frames)!
	write_json(root + '/audit/collection-receipt.json', {'collected_after_run_utc': time.utc().str(), 'prelaunch_pin': pin, 'source_revision': os.exec(['git', 'rev-parse', 'HEAD']).output.trim_space()})!
	os.write_file(root + '/audit/scope.txt', scope)!
	mut after := map[string]string{}
	mut after_omitted := []string{}
	walk(run_source, '', mut after, true, mut after_omitted)!
	equal_maps(after, raw)!
	assert after_omitted == omitted
	println('MAPS263 COLLECTED all ordinary outputs, supplemental logs and stopped private media')
}

fn observation(log string, id string) map[string]json2.Any {
	begin := log.contains('APK-SUITE-BEGIN id=' + id + ' ')
	ready := log.contains('ANDROID-WS-READY backend=vinix-native')
	exited := log.contains('APK-SUITE-EXIT id=' + id + ' ')
	mut failures := []string{}
	for line in log.split_into_lines() {
		if line.contains('ANDROID-WS-FAIL') || line.contains('APK-SUITE-DEPENDENCY-FAIL')
			|| line.contains('ANDROID-WS-DEPENDENCY-FAIL') || line.contains('ANDROID-WS-PROCESS-FAIL')
			|| line.contains('JNI DETECTED ERROR') || line.contains('NoClassDefFoundError')
			|| line.contains('NoSuchMethodError') || line.contains('UnsatisfiedLinkError')
			|| line.contains('ClassNotFoundException') || line.contains('NoSuchFieldError')
			|| line.contains('APK-SUITE-EXIT id=') {
			failures << line.trim_space()
		}
	}
	return {
		'launcher_entered':     json2.Any(begin)
		'backend_ready':        json2.Any(ready)
		'process_exited':       json2.Any(exited)
		'native_maps_observed': json2.Any(log.contains('APK-SUITE-MAPS id=' + id + ' '))
		'functional_passed':    json2.Any(json2.Null{})
		'outcome':              json2.Any(if !begin {
			'harness_failure'
		} else if exited || failures.len > 0 {
			'startup_failed'
		} else if ready {
			'window_observed'
		} else {
			'startup_timeout'
		})
		'failure_markers':      json2.Any(failures)
	}
}

// Real companion packages

fn observation_source(source string) string {
	return source.all_after('fn observation(').all_before('// Real companion packages')
}

fn verify_prelaunch(root string, pin string, entries map[string]string) !map[string]string {
	assert pin.len == 64 && entries['prelaunch-sha256.json']! == pin
	equal_maps(subtree(entries, 'prelaunch'), read_map(root + '/prelaunch-sha256.json')!)!
	replica := 'prelaunch/replica/'
	prep := replica + prepared + '/'
	pins := read_map(root + '/' + prep + 'prelaunch-sha256.json')!
	for path, digest in pins { assert entries[replica + path.trim_left('/')]! == digest, path }
	assert entries[replica + base + 'run-android-identity256']! == identity_pin
	assert entries[replica + base + 'maps-interact-unique258']! == driver_pin
	assert entries[replica + 'tests/native-android-ws/maps-interact.v']! == driver_source_pin
	assert entries['prelaunch/frozen256/frozen-inputs.json']! == frozen_pin
	inputs := read_map(root + '/prelaunch/frozen256/frozen-inputs.json')!
	assert inputs.len == 73
	for path, digest in inputs { assert entries['prelaunch/frozen256/inputs/' + path.trim_left('/')]! == digest, path }
	assert entries['prelaunch/unique258-evidence/sha256.json']! == unique_pin
	mut unique := subtree(entries, 'prelaunch/unique258-evidence')
	unique.delete('sha256.json')
	equal_maps(unique, read_map(root + '/prelaunch/unique258-evidence/sha256.json')!)!
	original := os.read_file(root + '/prelaunch/frozen256/inputs/' + base + 'suite256-resume.v')!
	suite := os.read_file(root + '/' + prep + 'suite263.v')!
	classifier := observation_source(original)
	assert classifier.len > 1000 && classifier == observation_source(suite)
	assert classifier == observation_source(os.read_file(root + '/audit/maps-styled-evidence.v')!)
	preliminary_at := suite.index('observation-before-capture.json') or { return error('missing preliminary observation') }
	capture_at := suite.index("capture := os.exec(['build/android-maps/maps-interact-unique258'") or { return error('missing bounded capture') }
	assert preliminary_at < capture_at
	stop_at := suite.index('\tif qemu.is_alive() { qemu.signal_term() }\n\tqemu.wait()\n\tserial :=') or { return error('missing stopped serial snapshot') }
	assert capture_at < stop_at
	config := read_object(root + '/' + replica + base + 'attempt263.json')!
	assert config['applications']!.as_array().len == 1
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 240
	before := read_map(root + '/' + prep + 'runtime-before.json')!
	after := read_map(root + '/' + prep + 'runtime-after.json')!
	assert before.len == 109 && after.len == 109
	equal_maps(before, read_map(root + '/prelaunch/frozen256/inputs/' + base + 'maps256/runtime-after.json')!)!
	equal_maps(after, regular(subtree(entries, prep.trim_right('/') + '/module')))!
	mut changed := []string{}
	for path, digest in before { if after[path]! != digest { changed << path } }
	changed.sort()
	mut expected := [jar, native]
	expected.sort()
	assert changed == expected
	assert after[jar]! == entries[replica + paired + '/framework/api-impl.jar']!
	assert after[native]! == entries[replica + paired + '/native/libvinix-android-native.so']!
	for label, manifest in {'before': before, 'after': after} {
		equal_maps(read_map(root + '/' + prep + 'archive-' + label + '-readback.json')!, manifest)!
	}
	for kind, count in {'framework': 125, 'native': 83} {
		sources := read_map(root + '/' + replica + paired + '/' + kind + '/sources.json')!
		assert sources.len == count
		directory := if kind == 'framework' { '/sources/' } else { '/atlframework/' }
		for path, digest in sources { assert entries[replica + paired + '/' + kind + directory + path]! == digest, path }
	}
	for label in ['build-framework-compiler', 'build-framework', 'generate-native', 'build-native', 'fixture-compiler', 'fixture'] {
		prior := read_object(root + '/' + replica + paired + '/' + label + '-before.json')!
		done := read_object(root + '/' + replica + paired + '/' + label + '-receipt.json')!
		assert done['exit_code']!.int() == 0 && done['completed_utc']!.str() >= prior['started_utc']!.str()
		for key in ['argv', 'started_utc', 'compiler_sha256', 'command_binary_sha256', 'input_files', 'sources'] {
			assert json2.encode(done[key]!) == json2.encode(prior[key]!), label + ':' + key
		}
		if label == 'build-framework' { assert done['output_sha256']!.str() == after[jar]! }
		if label == 'build-native' { assert done['output_sha256']!.str() == after[native]! }
	}
	build_before := read_object(root + '/' + prep + 'build-before.json')!
	build_done := read_object(root + '/' + prep + 'build-receipt.json')!
	for key, value in build_before { assert json2.encode(build_done[key]!) == json2.encode(value), key }
	assert build_done['exit_code']!.int() == 0 && build_done['completed_utc']!.str() >= build_before['started_utc']!.str()
	assert build_done['binary_sha256']!.str() == entries[prep + 'suite263']!
	assert build_before['source_sha256']!.str() == entries[prep + 'suite263.v']!
	assert build_before['compiler_sha256']!.str() == pins['/Users/alex/code/v/v_old']!
	assert build_before['cc_sha256']!.str() == pins[build_before['cc_path']!.str()]!
	assert build_before['nativeapk_source_sha256']!.str() == entries[prep + 'sources/nativeapk/install.v']!
	return pins
}

fn shell_quote(value string) string { return "'" + value.replace("'", "'\\''") + "'" }

// Independently verify complete FAT archive shape, including directories,
// symlinks and hidden files, against the frozen staging tree.
fn verify_archive(root string, entries map[string]string) ! {
	boot := root + '/media/boot-after-run.img'
	command := 'set -o pipefail; mtype -i ' + shell_quote(boot) + ' ::/boot/qemu-runtime.tar | tar '
	listing := os.exec(['/bin/zsh', '-c', command + '-tf -'])
	if listing.exit_code != 0 { return error('FAT archive listing failed: ' + listing.output) }
	for line in listing.output.split_into_lines() {
		assert !line.starts_with('/')
		for part in line.split('/') { assert part != '..' && !part.starts_with('._'), line }
	}
	scratch := os.temp_dir() + '/maps263-fat-check-' + time.now().unix_micro().str()
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { eprintln(err) } }
	extract := os.exec(['/bin/zsh', '-c', command + '-xf - -C ' + shell_quote(scratch)])
	if extract.exit_code != 0 { return error('FAT archive extraction failed: ' + extract.output) }
	equal_maps(inventory(scratch)!, subtree(entries, 'prelaunch/replica/' + prepared + '/module'))!
}

fn qemu_arguments(config map[string]json2.Any) []string {
	state := os.abs_path(run_source) + '/google-maps'
	return [config['qemu']!.str(), '-qmp', 'unix:' + state + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3',
		'-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object',
		'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + config['firmware']!.str(), '-drive',
		'if=pflash,format=raw,file=' + config['efivars']!.str(), '-drive',
		'format=raw,file=' + config['boot_image']!.str(), '-device', 'virtio-keyboard-device',
		'-device', 'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0', '-object', 'filter-dump,id=capture,netdev=net0,file=' + state + '/network.pcap',
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + state + '/serial.log']
}

fn logical_path(path string) string {
	prefix := os.real_path(os.getwd()) + '/'
	return if path.starts_with(prefix) { path.substr(prefix.len, path.len) } else { path }
}

fn verify_run(root string, entries map[string]string, pins map[string]string) !string {
	equal_maps(subtree(entries, 'run'), read_map(root + '/audit/raw-inventory.json')!)!
	omitted := json2.decode[[]string](os.read_file(root + '/audit/omitted-special-files.json')!)!
	assert omitted.len <= 1 && omitted.all(it == 'google-maps/qmp.sock')
	apps := json2.decode[[]json2.Any](os.read_file(root + '/run/results.json')!)!
	assert apps.len == 1
	app := apps[0].as_map()
	assert app['id']!.str() == 'google-maps' && app['package']!.str() == 'com.google.android.apps.maps'
	assert app['startup_timeout_seconds']!.int() == 240
	assert app['observation_elapsed_seconds']!.int() >= 240 && app['observation_elapsed_seconds']!.int() <= 241
	assert app['qemu_alive_before_capture']!.bool() && !app['process_exited']!.bool()
	assert app['backend_ready']!.bool() && app['native_maps_observed']!.bool() && app['launcher_entered']!.bool()
	state := root + '/run/google-maps'
	preliminary := read_object(state + '/observation-before-capture.json')!
	for key, value in preliminary { assert json2.encode(value) == json2.encode(app[key]!), key }
	serial := os.read_bytes(state + '/serial.log')!
	assert gzip.decompress(os.read_bytes(state + '/serial.log.gz')!)! == serial
	assert entries['run/google-maps/serial.log']! == app['serial_sha256']!.str()
	classified := observation(serial.bytestr(), 'google-maps')
	for key, value in classified { assert json2.encode(value) == json2.encode(app[key]!), key }
	for marker in ['No permission to set thread priority', 'JNI DETECTED ERROR', 'Fatal signal 11'] { assert !serial.bytestr().contains(marker), marker }
	assert entries['run/google-maps/application.png']! == app['screenshot_sha256']!.str() && 'screenshot_error' !in app
	assert os.file_size(state + '/network.pcap') > 24
	harness := os.read_file(root + '/supplemental/attempt263-harness.log')!
	assert harness.contains('MAPS263 observation retained before final capture')
	assert harness.contains('APK-SUITE result google-maps ' + app['outcome']!.str()) && !harness.contains('V panic')
	start := read_object(state + '/start-receipt.json')!
	config := read_object(root + '/prelaunch/replica/' + base + 'attempt263.json')!
	assert start['qemu_argv']!.as_array().map(it.str()) == qemu_arguments(config)
	start_pins := start['sha256']!.as_map()
	assert start_pins.len == 8
	mut normalized := map[string]string{}
	for path, value in start_pins { normalized[logical_path(path)] = value.str() }
	expected_paths := [prepared + '/suite263', base + 'attempt263.json', prepared + '/vm/boot.img', prepared + '/vm/efivars.fd',
		config['qemu']!.str(), config['firmware']!.str(), prepared + '/runtime-after.json', base + 'maps-interact-unique258']
	for path in expected_paths { assert normalized[path]! == pins[path]!, path }
	prep_receipt := read_map(root + '/prelaunch/replica/' + prepared + '/preparation-receipt.json')!
	assert start['recorded_before_qemu_run_utc']!.str() >= prep_receipt['completed_before_launch_utc']!
	assert os.file_size(root + '/media/boot-after-run.img') == u64(4294967296)
	assert os.file_size(root + '/media/efivars-after-run.fd') == u64(67108864)
	assert entries['media/boot-after-run.img']! == pins[prepared + '/vm/boot.img']!
	assert entries['audit/maps-styled-evidence.v']! == hash(@FILE)!
	assert entries['audit/maps-styled-evidence']! == hash(os.executable())!
	checker_before := read_object(root + '/audit/checker-before.json')!
	checker_done := read_object(root + '/audit/checker-receipt.json')!
	for key, value in checker_before { assert json2.encode(checker_done[key]!) == json2.encode(value), key }
	assert checker_done['exit_code']!.int() == 0 && checker_done['completed_utc']!.str() >= checker_before['started_utc']!.str()
	assert checker_before['source_sha256']!.str() == entries['audit/maps-styled-evidence.v']!
	assert checker_done['binary_sha256']!.str() == entries['audit/maps-styled-evidence']!
	assert checker_before['compiler_sha256']!.str() == pins['/Users/alex/code/v/v_old']!
	assert checker_before['cc_sha256']!.str() == pins[checker_before['cc_path']!.str()]!
	assert os.read_file(root + '/audit/checker-selftest.log')!.contains('MAPS263 CHECKER SELF-TEST PASS')
	assert os.read_file(root + '/audit/checker-assertion.log')!.contains('assert false')
	assert os.read_file(root + '/audit/checker-prod-guard.log')!.contains('requires assertions')
	assert os.read_file(root + '/audit/scope.txt')! == scope
	frames := json2.decode[[]string](os.read_file(root + '/audit/required-frames.json')!)!
	assert frames.len >= 3 && 'application' in frames && 'paris-result' in frames && 'route-first' in frames
	verify_interactions(state, frames)!
	return app['outcome']!.str()
}

fn verify(root string, prelaunch_pin string, entries map[string]string) !string {
	external(root)!
	pins := verify_prelaunch(root, prelaunch_pin, entries)!
	outcome := verify_run(root, entries, pins)!
	verify_archive(root, entries)!
	return outcome
}

fn seal(root string, pin string) ! {
	external(root)!
	if os.exists(root + '/sha256.json') || os.is_link(root + '/sha256.json') { return error('fresh final manifest required') }
	entries := inventory(root)!
	outcome := verify(root, pin, entries)!
	write_json(root + '/sha256.json', entries)!
	println('MAPS263 SEALED outcome=' + outcome + ' entries=' + entries.len.str() + ' sha256=' + hash(root + '/sha256.json')!)
}

fn check(root string, pin string) ! {
	external(root)!
	if pin.len != 64 || hash(root + '/sha256.json')! != pin { return error('wrong completed inventory pin') }
	mut entries := inventory(root)!
	entries.delete('sha256.json')
	equal_maps(entries, read_map(root + '/sha256.json')!)!
	receipt := read_map(root + '/audit/collection-receipt.json')!
	outcome := verify(root, receipt['prelaunch_pin']!, entries)!
	println('MAPS263 CHECK PASS outcome=' + outcome + ' functional_passed=null entries=' + entries.len.str())
}

fn negative(root string, pin string) ! {
	external(root)!
	assert hash(root + '/sha256.json')! == pin
	fixture := os.temp_dir() + '/maps263-partial-' + time.now().unix_micro().str()
	os.mkdir_all(fixture)!
	clone(root + '/sha256.json', fixture + '/sha256.json')!
	for label, destination in {'wrong-pin': root, 'partial': fixture} {
		argument := if label == 'wrong-pin' { '0'.repeat(64) } else { pin }
		result := os.exec([os.executable(), 'check', destination, argument])
		os.write_file(fixture + '-' + label + '.log', result.output)!
		assert result.exit_code != 0, label
	}
	println('MAPS263 NEGATIVE PASS wrong pin and incomplete bundle; logs=' + fixture)
}

fn self_test() ! {
	fixture := os.temp_dir() + '/maps263-checker-selftest-' + time.now().unix_micro().str()
	os.mkdir_all(fixture + '/empty')!
	os.write_file(fixture + '/file', 'evidence')!
	os.symlink('file', fixture + '/link')!
	expected := inventory(fixture)!
	assert expected.len == 3 && expected['empty']! == 'directory' && expected['link']! == 'symlink:file'
	os.write_file(fixture + '/file', 'changed')!
	mut rejected := false
	equal_maps(inventory(fixture)!, expected) or { rejected = true }
	assert rejected
	assert observation('no application launch', 'a')['outcome']!.str() == 'harness_failure'
	assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws\nANDROID-WS-READY backend=vinix-native', 'a')['outcome']!.str() == 'window_observed'
	assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws\nClassNotFoundException optional', 'a')['outcome']!.str() == 'startup_failed'
	assert observation('APK-SUITE-BEGIN id=a backend=vinix-ws', 'a')['outcome']!.str() == 'startup_timeout'
	original := os.read_file('/Users/alex/.local/state/vinix/android/maps256-2026-10-24/inputs/' + base + 'suite256-resume.v')!
	assert observation_source(original) == observation_source(os.read_file(@FILE)!)
	interaction_evidence_selftest()!
	println('MAPS263 CHECKER SELF-TEST PASS inventory, changed bytes and original classifier')
}

fn main() {
	$if prod { eprintln('styled evidence requires assertions; compile without -prod'); exit(2) }
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 2 && os.args[1] == '--assertion-probe' { assert false, 'assertion probe must fail'; return }
	if os.args.len >= 5 && os.args[1] == 'collect' { collect(os.args[2], os.args[3], os.args[4..]) or { eprintln(err); exit(1) }; return }
	if os.args.len != 4 { eprintln('usage: maps-styled-evidence collect ROOT PRELAUNCH_PIN FRAME...; seal ROOT PRELAUNCH_PIN; check ROOT PIN; negative ROOT PIN'); exit(2) }
	match os.args[1] {
		'seal' { seal(os.args[2], os.args[3]) or { eprintln(err); exit(1) } }
		'check' { check(os.args[2], os.args[3]) or { eprintln(err); exit(1) } }
		'negative' { negative(os.args[2], os.args[3]) or { eprintln(err); exit(1) } }
		else { eprintln('unknown evidence command'); exit(2) }
	}
}


struct InteractionEvidenceCommand {
	stderr string
	frame  string
}

fn interaction_evidence_regular(path string) ! {
	if os.lstat(path)!.get_filetype() != .regular {
		return error('interaction evidence is not a regular file: ' + path)
	}
}

fn interaction_evidence_png(path string) ! {
	interaction_evidence_regular(path)!
	bytes := os.read_bytes(path)!
	if bytes.len <= 1000 || bytes[..8] != [u8(137), 80, 78, 71, 13, 10, 26, 10] {
		return error('missing or invalid retained screenshot: ' + path)
	}
}

fn interaction_evidence_argv(text string) ![]string {
	// The frozen driver renders a V string array. Its fixed command/path
	// vocabulary has no quotes or escapes; reject ambiguous representations.
	if !text.starts_with("['") || !text.ends_with("']") || text.len < 4 {
		return error('invalid interaction argv representation')
	}
	args := text[2..text.len - 2].split("', '")
	for arg in args {
		if arg.contains("'") || arg.contains('\\') || arg.contains('\n') || arg.contains('\r') {
			return error('unsupported interaction argv quoting')
		}
	}
	if args.str() != text { return error('noncanonical interaction argv') }
	return args
}

fn interaction_evidence_stream_pair(out_path string, err_path string, prefix string) !string {
	if !out_path.starts_with(prefix) || !out_path.ends_with('.stdout.log') {
		return error('interaction stdout escaped original run directory')
	}
	name := out_path[prefix.len..]
	if name != os.file_name(name) || !name.starts_with('command-') {
		return error('invalid interaction stdout basename')
	}
	stem := name[..name.len - '.stdout.log'.len]
	parts := stem['command-'.len..].split('-')
	if parts.len != 3 { return error('interaction stream is not a unique258 identity') }
	for part in parts {
		if part.len == 0 { return error('empty unique258 identity component') }
		mut nonzero := false
		for ch in part.bytes() {
			if ch < `0` || ch > `9` { return error('invalid unique258 identity component') }
			if ch != `0` { nonzero = true }
		}
		if !nonzero { return error('zero unique258 identity component') }
	}
	if err_path != prefix + stem + '.stderr.log' {
		return error('interaction stdout/stderr identity mismatch')
	}
	return stem
}

fn verify_interactions(state string, frames []string) ! {
	prefix := os.abs_path('build/android-maps/attempt263/google-maps') + '/'
	interaction_evidence_regular(state + '/interaction.log')!
	mut commands := map[string]InteractionEvidenceCommand{}
	mut finished := map[string]bool{}
	mut streams := map[string]bool{}
	mut captures := map[string]int{}
	for line in os.read_file(state + '/interaction.log')!.split_into_lines() {
		if line == '' { continue }
		separator := line.index(' UTC ') or { return error('interaction line lacks UTC prefix') }
		message := line[separator + 5..]
		if message.starts_with('BEGIN ') {
			delimiter := '] timeout_seconds=30 stdout='
			if message.count(delimiter) != 1 {
				return error('invalid interaction BEGIN or timeout')
			}
			end := message.index(delimiter) or { return error('missing interaction BEGIN delimiter') }
			args := interaction_evidence_argv(message['BEGIN '.len..end + 1])!
			paths := message[end + delimiter.len..].split(' ')
			if paths.len != 2 || !paths[1].starts_with('stderr=') {
				return error('invalid interaction BEGIN stream fields')
			}
			out_path := paths[0]
			err_path := paths[1]['stderr='.len..]
			stem := interaction_evidence_stream_pair(out_path, err_path, prefix)!
			if stem in commands { return error('reused interaction command identity: ' + stem) }
			for suffix in ['.stdout.log', '.stderr.log'] {
				name := stem + suffix
				if name in streams { return error('reused interaction stream: ' + name) }
				interaction_evidence_regular(state + '/' + name)!
				streams[name] = true
			}
			if args.len < 2 || args[0] != 'build/android-run' {
				return error('unexpected interaction executable')
			}
			mut frame := ''
			if args[1] == 'screenshot' {
				if args.len != 6 || args[2] != '--socket' || args[3] != prefix + 'qmp.sock'
					|| args[4] != '--destination' || !args[5].starts_with(prefix)
					|| !args[5].ends_with('.png') {
					return error('invalid screenshot argv')
				}
				name := args[5][prefix.len..]
				if name != os.file_name(name) || name.len <= '.png'.len {
					return error('screenshot destination escaped run directory')
				}
				frame = name[..name.len - '.png'.len]
			} else if args[1] == 'input' {
				if args.len < 7 || args[args.len - 4..] != ['--socket', prefix + 'qmp.sock', '--settle', '0.15'] {
					return error('invalid interaction input suffix')
				}
			} else {
				return error('unexpected interaction operation')
			}
			commands[stem] = InteractionEvidenceCommand{stderr: err_path, frame: frame}
		} else if message.starts_with('END ') {
			fields := message.split(' ')
			if fields.len != 6 || fields[0] != 'END' || fields[1] != 'exit=0'
				|| fields[2] != 'timed_out=false' || fields[3] != 'output_drain_capped=false'
				|| !fields[4].starts_with('stdout=') || !fields[5].starts_with('stderr=') {
				return error('unsuccessful or malformed interaction END')
			}
			out_path := fields[4]['stdout='.len..]
			err_path := fields[5]['stderr='.len..]
			stem := interaction_evidence_stream_pair(out_path, err_path, prefix)!
			if stem !in commands || stem in finished {
				return error('orphan or repeated interaction END: ' + stem)
			}
			command := commands[stem]
			if command.stderr != err_path { return error('interaction END stderr changed') }
			finished[stem] = true
			if command.frame != '' { captures[command.frame]++ }
		} else if message !in ['SKIP-CLICK',
			'PIXEL-PROBE-PRESENTED onboarding; screenshot requires visual review',
			'PIXEL-PROBE-PRESENTED map; screenshot requires visual review'] {
			return error('unexpected interaction log record')
		}
	}
	if commands.len == 0 || finished.len != commands.len {
		return error('missing completed interactions')
	}
	for frame, count in captures {
		if count != 1 && frame !in ['onboarding-probe', 'map-probe'] {
			return error('screenshot destination reused: ' + frame)
		}
		interaction_evidence_png(state + '/' + frame + '.png')!
	}
	mut requested := map[string]bool{}
	for frame in frames {
		if frame == '' || frame != os.file_name(frame) || frame in ['.', '..'] || frame in requested {
			return error('invalid or duplicate required screenshot basename')
		}
		requested[frame] = true
		if captures[frame] != 1 && !(frame in ['onboarding-probe', 'map-probe'] && captures[frame] > 0) {
			return error('required screenshot was not captured exactly once: ' + frame)
		}
	}
	for name in os.ls(state)! {
		if name.starts_with('command-') && (name.ends_with('.stdout.log') || name.ends_with('.stderr.log')) {
			if name !in streams { return error('orphan retained interaction stream: ' + name) }
			interaction_evidence_regular(state + '/' + name)!
		}
	}
}

fn interaction_evidence_fixture(state string, frames []string) !string {
	os.mkdir_all(state)!
	mut png := []u8{len: 1001}
	for i, value in [u8(137), 80, 78, 71, 13, 10, 26, 10] { png[i] = value }
	prefix := os.abs_path('build/android-maps/attempt263/google-maps') + '/'
	mut records := ''
	for i, frame in frames {
		os.write_file_array(state + '/' + frame + '.png', png)!
		stem := 'command-' + (100 + i).str() + '-' + (1000 + i).str() + '-' + (10000 + i).str()
		for suffix in ['.stdout.log', '.stderr.log'] { os.write_file(state + '/' + stem + suffix, '')! }
		out_path := prefix + stem + '.stdout.log'
		err_path := prefix + stem + '.stderr.log'
		args := ['build/android-run', 'screenshot', '--socket', prefix + 'qmp.sock', '--destination', prefix + frame + '.png']
		records += '2026-10-24 18:00:59 UTC BEGIN ' + args.str() + ' timeout_seconds=30 stdout=' + out_path + ' stderr=' + err_path + '\n'
		records += '2026-10-24 18:01:00 UTC END exit=0 timed_out=false output_drain_capped=false stdout=' + out_path + ' stderr=' + err_path + '\n'
	}
	os.write_file(state + '/interaction.log', records)!
	return records
}

fn interaction_evidence_expect_rejection(state string, frames []string, label string) ! {
	mut rejected := false
	verify_interactions(state, frames) or { rejected = true }
	if !rejected { return error('interaction self-test accepted ' + label) }
}

fn interaction_evidence_selftest() ! {
	root := 'build/android-maps/interaction-evidence-fixture-' + os.getpid().str()
	if os.exists(root) || os.is_link(root) { return error('interaction self-test fixture already exists') }
	defer { os.rmdir_all(root) or {} }
	state := root + '/valid'
	frames := ['search-ready', 'route-ready', 'application']
	valid := interaction_evidence_fixture(state, [...frames, 'onboarding-probe', 'onboarding-probe'])!
	verify_interactions(state, frames)!
	verify_interactions(state, ['onboarding-probe'])!
	os.write_file(state + '/interaction.log', valid + valid)!
	interaction_evidence_expect_rejection(state, frames, 'repeated stream identity')!
	missing_end := valid.split_into_lines().filter(!it.contains(' UTC END ')).join('\n') + '\n'
	os.write_file(state + '/interaction.log', missing_end)!
	interaction_evidence_expect_rejection(state, frames, 'missing END')!
	for bad, original in {
		'END exit=1': 'END exit=0'
		'timed_out=true': 'timed_out=false'
		'output_drain_capped=true': 'output_drain_capped=false'
	} {
		os.write_file(state + '/interaction.log', valid.replace(original, bad))!
		interaction_evidence_expect_rejection(state, frames, bad)!
	}
	os.write_file(state + '/interaction.log', valid)!
	orphan := state + '/command-999-9999-99999.stdout.log'
	os.write_file(orphan, '')!
	interaction_evidence_expect_rejection(state, frames, 'orphan stream')!
	os.rm(orphan)!
	stream := state + '/command-100-1000-10000.stdout.log'
	os.rm(stream)!
	os.symlink(os.abs_path(state + '/command-100-1000-10000.stderr.log'), stream)!
	interaction_evidence_expect_rejection(state, frames, 'symlink stream')!
	os.rm(stream)!
	os.write_file(stream, '')!
	verify_interactions(state, frames)!
	interaction_evidence_expect_rejection(state, ['not-captured'], 'missing required screenshot')!
	interaction_evidence_fixture(root + '/duplicate-destination', ['application', 'application'])!
	interaction_evidence_expect_rejection(root + '/duplicate-destination', ['application'], 'duplicate screenshot destination')!
	os.write_file(state + '/application.png', '')!
	interaction_evidence_expect_rejection(state, frames, 'short PNG')!
	println('INTERACTION EVIDENCE SELFTEST PASS positive=3-frames+repeated-probe negatives=10')
}
