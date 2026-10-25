// SPDX-License-Identifier: GPL-2.0-or-later
// Retain one fresh Maps replay. Historical complete bundles stay independent.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/'
const frozen_pin = '7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64'
const classifier_pin = '47f1d9a78bfb2991f9802ebebc95436505160f7e551e1e77d4d95a171c63946b'
const jar = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const native = 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
const qualified276_root = '/Users/alex/.local/state/vinix/android/compound276-2026-10-24'
const qualified276_pin = '37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4'
const prepared278_root = '/Users/alex/.local/state/vinix/android/compound278-2026-10-25'
const prepared278_pin = 'aa10e659faf39ab1a9b4bf01d2dde791f4ab1fbb9eff007d71e8226fce370995'
const prepared278_jar = 'a1b839c77a575a40ddab8d6e264e92c9abcc9de54ae6c3dcefcc0e725c938eba'
const prepared282_root = '/Users/alex/.local/state/vinix/android/compound282-2026-10-25'
const prepared282_pin = '2d9a307a57f3ffd5f07170a61cb6fb42361cc65ab260e78c158be2c9b05edefc'
const prepared282_jar = '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
const clean_launcher = 'usr/bin/run-android-calculator'
const clean_launcher_manifest_pin = '9e8256b31be97aa97c7bf8b4b353624514ea9cd7d9acfb7f7315d24c26670f10'
const clean_launcher_pin = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const historical_launcher_pin = '052bcaf5f663d3743d7712964e38e75c6c2500350ad3d431874e68123113d264'
const tooltip277 = "java.lang.NoSuchMethodError: No virtual method getTooltipText()Ljava/lang/CharSequence; in class Lcom/google/android/material/floatingactionbutton/ExtendedFloatingActionButton; or its super classes (declaration of 'com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton' appears in /opt/android-test/application.apk!classes8.dex)"
const exit277 = 'APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true'

struct Frame {
	path string
	width int
	height int
	sha256 string
}

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
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + ': ' + r.output) }
	return r.output
}
fn clone(from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('fresh destination required: ' + to) }
	os.mkdir_all(os.dir(to))!
	checked(['cp', '-c', '-R', '-P', from, to])!
}

// lstat preserves links and empty directories without following either. Only
// the stopped raw run's QMP socket has no archival contents.
fn walk(root string, relative string, copy_to string, raw bool, mut entries map[string]string, mut omitted []string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if !raw && relative == '' && name == 'sha256.json' { continue }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)!; if copy_to != '' { clone(path, copy_to + '/' + key)! } }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)!; if copy_to != '' { clone(path, copy_to + '/' + key)! } }
			.directory {
				entries[key] = 'directory'
				if copy_to != '' { os.mkdir_all(copy_to + '/' + key)! }
				walk(root, key, copy_to, raw, mut entries, mut omitted)!
			}
			.socket {
				if !raw || key != 'google-maps/qmp.sock' { return error('unexpected socket: ' + path) }
				omitted << key
			}
			else { return error('unexpected special file: ' + path) }
		}
	}
}
fn inventory(root string) !map[string]string {
	mut entries := map[string]string{}
	mut omitted := []string{}
	walk(root, '', '', false, mut entries, mut omitted)!
	return entries
}
fn equal_maps(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len { return error('inventory lengths differ') }
	for path, value in expected { if actual[path] or { '' } != value { return error('inventory differs: ' + path) } }
}
fn subtree(entries map[string]string, prefix string) map[string]string {
	mut result := map[string]string{}
	for path, digest in entries { if path.starts_with(prefix + '/') { result[path.all_after(prefix + '/')] = digest } }
	return result
}
fn regular_files(entries map[string]string, paths []string) ! {
	for path in paths {
		value := entries[path] or { '' }
		if value.len != 64 || value.bytes().any((it < `0` || it > `9`) && (it < `a` || it > `f`)) { return error('regular retained file required: ' + path) }
	}
}
fn ids(run string, build string) ! {
	if run.len != 3 || build.len != 3 || run.bytes().any(it < `0` || it > `9`) || build.bytes().any(it < `0` || it > `9`)
		|| run.int() <= 271 || run.int() != build.int() + 1 { return error('fresh consecutive replay/build IDs required') }
}
fn external_path(root string) ! {
	if !os.is_abs_path(root) || os.is_link(root) || os.exists(root) || !os.is_dir(os.dir(root)) { return error('fresh absolute external destination with existing parent required') }
	resolved := os.real_path(os.dir(root)) + '/' + os.file_name(root)
	repo := os.real_path(os.getwd())
	if resolved == repo || resolved.starts_with(repo + '/') { return error('state directory must be outside checkout') }
}
fn supplemental_logs(run string, to string) !map[string]string {
	mut entries := map[string]string{}
	for name in os.ls(base)! {
		if name.starts_with('attempt' + run + '-') && name.ends_with('.log') {
			assert os.lstat(base + name)!.get_filetype() == .regular
			key := if name == 'attempt' + run + '-harness.log' { 'harness.log' } else { name }
			entries[key] = hash(base + name)!
			if to != '' { clone(base + name, to + '/' + key)! }
		}
	}
	return entries
}
fn observation(source string) string { return source.all_after('fn observation(').all_before('// Real companion packages') }
fn classifier_equal(original string, suite string) ! {
	if observation(original).len <= 1000 || observation(original) != observation(suite)
		|| sha256.sum(observation(original).bytes()).hex() != classifier_pin { return error('original observation classifier differs') }
}

// Maps277/279 exited before their configured windows. Retain those exact failures,
// without changing the application classifier or other replays' live window.
fn observation_window(run string, build string, app map[string]json2.Any, serial string) ! {
	if app['startup_timeout_seconds']!.int() != 420 { return error('configured observation window differs') }
	if (run == '277' && build == '276') || (run == '279' && build == '278') {
		elapsed := if run == '277' { 262 } else { 280 }
		if app['observation_elapsed_seconds']!.int() != elapsed || !app['process_exited']!.bool()
			|| !app['qemu_alive_before_capture']!.bool() || !app['backend_ready']!.bool()
			|| !app['native_maps_observed']!.bool() || app['outcome']!.str() != 'startup_failed'
			|| app['functional_passed']! !is json2.Null {
			return error('Maps' + run + ' failed-run observation differs')
		}
		markers := app['failure_markers']!.as_array().map(it.str())
		for marker in ['ANDROID-WS-FAIL main looper', tooltip277, exit277] {
			if marker !in markers || marker !in serial.split_into_lines() {
				return error('Maps' + run + ' missing exact failure marker: ' + marker)
			}
		}
		return
	}
	if app['observation_elapsed_seconds']!.int() < 420 || !app['qemu_alive_before_capture']!.bool()
		|| app['process_exited']!.bool() { return error('complete live observation window required') }
}
fn logical(path string, repo string) string { return if path.starts_with(repo + '/') { path.all_after(repo + '/') } else { path } }
fn verify_start(start map[string]string, pins map[string]string, expected []string) ! {
	if start.len != expected.len { return error('start receipt input count differs') }
	for path in expected { if start[path] or { '' } != pins[path]! { return error('start receipt input differs: ' + path) } }
}
fn png_frame(path string, relative string, digest string) !Frame {
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 24}
	if file.read(mut header)! != 24 || header[..8] != [u8(137), 80, 78, 71, 13, 10, 26, 10]
		|| header[8..16] != [u8(0), 0, 0, 13, 73, 72, 68, 82] { return error('invalid PNG header: ' + relative) }
	width := int(u32(header[16]) << 24 | u32(header[17]) << 16 | u32(header[18]) << 8 | u32(header[19]))
	height := int(u32(header[20]) << 24 | u32(header[21]) << 16 | u32(header[22]) << 8 | u32(header[23]))
	if width <= 0 || height <= 0 || width > 16384 || height > 16384 { return error('invalid PNG dimensions: ' + relative) }
	return Frame{relative, width, height, digest}
}
fn qemu_arguments(config map[string]json2.Any, repo string) []string {
	state := repo + '/' + config['output']!.str() + '/google-maps'
	return [config['qemu']!.str(), '-qmp', 'unix:' + state + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3',
		'-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng',
		'-device', 'virtio-rng-device', '-drive', 'if=pflash,format=raw,readonly=on,file=' + config['firmware']!.str(),
		'-drive', 'if=pflash,format=raw,file=' + config['efivars']!.str(), '-drive', 'format=raw,file=' + config['boot_image']!.str(),
		'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0',
		'-device', 'virtio-net-device,netdev=net0', '-object', 'filter-dump,id=capture,netdev=net0,file=' + state + '/network.pcap',
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + state + '/serial.log']
}

fn build_labels(build string) []string {
	return if build == '276' { ['generate-native', 'build-native'] }
		else if build in ['278', '282'] { ['build-framework-compiler', 'build-framework', 'fixture-compiler', 'fixture'] }
		else { ['build-framework-compiler', 'build-framework', 'generate-native', 'build-native', 'fixture-compiler', 'fixture'] }
}

fn nondirectories(entries map[string]string) map[string]string {
	mut result := map[string]string{}
	for path, digest in entries { if digest != 'directory' { result[path] = digest } }
	return result
}

// This reference binds a completed build, not the separate278 guest outcome.
fn prepared278(root string, entries map[string]string, paired string) ! {
	prepared_framework(root, entries, paired, prepared278_root, prepared278_pin, prepared278_jar)!
}
fn prepared282(root string, entries map[string]string, paired string) ! {
	prepared_framework(root, entries, paired, prepared282_root, prepared282_pin, prepared282_jar)!
}
fn prepared_framework(root string, entries map[string]string, paired string, prepared_root string, prepared_pin string, jar_pin string) ! {
	prefix := 'prelaunch/prelaunch/'
	regular_files(entries, [prefix + 'prepared-build-sha256.json', prefix + 'prepared-build-reference.json',
		prefix + 'qualified276-sha256.json', prefix + 'qualified276-reference.json'])!
	if entries[prefix + 'prepared-build-sha256.json']! != prepared_pin { return error('wrong prepared framework manifest pin') }
	archived := read_map(root + '/' + prefix + 'prepared-build-sha256.json')!
	reference := object(root + '/' + prefix + 'prepared-build-reference.json')!
	assert reference['root']!.str() == prepared_root && reference['manifest_sha256']!.str() == prepared_pin
	assert reference['scope']!.str().contains('runtime qualification is separate')
	copy_prefix := prefix + 'replica/' + paired + '/'
	for name in ['framework', 'native'] {
		equal_maps(nondirectories(subtree(entries, copy_prefix + name)), subtree(archived, 'prelaunch/' + name))!
	}
	for label in build_labels('278') {
		for suffix in ['-before.json', '-receipt.json', '.log'] {
			path := label + suffix
			assert entries[copy_prefix + path]! == archived['prelaunch/' + path]!, path
		}
	}
	for name in ['qualified276-reference.json', 'qualified276-sha256.json'] {
		assert entries[prefix + name]! == archived['prelaunch/' + name]!, name
	}
	assert entries[prefix + 'qualified276-sha256.json']! == qualified276_pin
	native_reference := object(root + '/' + prefix + 'qualified276-reference.json')!
	assert native_reference['root']!.str() == qualified276_root && native_reference['manifest_sha256']!.str() == qualified276_pin
	sealed := read_map(root + '/' + prefix + 'qualified276-sha256.json')!
	for name in ['sources.json', 'bindings.txt', 'libvinix-android-native.so', 'androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		assert entries[copy_prefix + 'native/' + name]! == sealed['prelaunch/native/' + name]!, name
	}
	assert entries[copy_prefix + 'framework/api-impl.jar']! == jar_pin
	assert entries[copy_prefix + 'native/libvinix-android-native.so']! == '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
}

fn runtime_delta(build string, before map[string]string, after map[string]string) ! {
	if before.len != after.len { return error('runtime inventory lengths differ') }
	mut changes := []string{}
	for path, digest in before { if after[path]! != digest { changes << path } }
	changes.sort()
	mut overlays := [jar, native]
	if build == '282' {
		overlays << clean_launcher
		if before[clean_launcher]! != historical_launcher_pin || after[clean_launcher]! != clean_launcher_pin {
			return error('clean launcher overlay identity differs')
		}
	}
	overlays.sort()
	if changes != overlays { return error('unexpected runtime overlay differences: ' + changes.str()) }
}
fn clean_environment(root string, expected map[string]string) ! {
	if expected.len != 6 { return error('exact launcher environment chain required') }
	for name in ['usr/bin/vinix-session', 'usr/bin/vinix-desktop', 'usr/bin/run-android', 'usr/bin/run-android-identity', 'usr/bin/run-android-original', clean_launcher] {
		if hash(root + '/' + name)! != expected[name]! { return error('launcher environment file differs: ' + name) }
		if os.read_file(root + '/' + name)!.contains('VINIX_ANDROID_TRACE_') { return error('inherited launcher trace export/string present: ' + name) }
	}
}
fn clean_build(root string, entries map[string]string, after map[string]string) ! {
	prefix := 'prelaunch/prelaunch/'
	launcher := root + '/' + prefix + 'clean-launcher'
	regular_files(entries, [prefix + 'clean-launcher/sha256.json', prefix + 'clean-launcher/builder', prefix + 'launcher-environment.json'])!
	if entries[prefix + 'clean-launcher/sha256.json']! != clean_launcher_manifest_pin { return error('wrong fresh launcher build pin') }
	checked([launcher + '/builder', 'check', launcher])!
	if entries[prefix + 'clean-launcher/run-android-calculator']! != clean_launcher_pin { return error('wrong clean launcher output') }
	environment := read_map(root + '/' + prefix + 'launcher-environment.json')!
	equal_maps(nondirectories(subtree(entries, prefix + 'launcher-environment-files')), environment)!
	for name, pin in environment { if after[name]! != pin { return error('launcher environment runtime identity differs: ' + name) } }
	clean_environment(root + '/' + prefix + 'launcher-environment-files', environment)!
}

// Complete276 qualification stays independently sealed. Verify the exact
// source/artifact/receipt subset consumed by this fresh Maps replay.
fn qualified276(root string, entries map[string]string, paired string) ! {
	prefix := 'prelaunch/prelaunch/'
	regular_files(entries, [prefix + 'qualified-build-sha256.json', prefix + 'qualified-build-reference.json'])!
	if entries[prefix + 'qualified-build-sha256.json']! != qualified276_pin { return error('wrong qualified276 manifest pin') }
	archived := read_map(root + '/' + prefix + 'qualified-build-sha256.json')!
	reference := object(root + '/' + prefix + 'qualified-build-reference.json')!
	assert reference['root']!.str() == qualified276_root && reference['manifest_sha256']!.str() == qualified276_pin
	copy_prefix := prefix + 'replica/' + paired + '/'
	for name in ['framework', 'native'] {
		equal_maps(subtree(entries, copy_prefix + name), subtree(archived, 'prelaunch/' + name))!
	}
	for label in build_labels('276') {
		for suffix in ['-before.json', '-receipt.json', '.log'] {
			path := label + suffix
			assert entries[copy_prefix + path]! == archived['prelaunch/' + path]!, path
		}
	}
	assert entries[copy_prefix + 'framework/api-impl.jar']! == '1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6'
	assert entries[copy_prefix + 'native/libvinix-android-native.so']! == '5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca'
}

// Checks fresh source/artifact/launch relations; no historical archive replay.
fn validate(root string, entries map[string]string) !map[string]json2.Any {
	regular_files(entries, ['collection.json', 'prelaunch/prelaunch-sha256.json', 'run/results.json', 'run/google-maps/start-receipt.json',
		'run/google-maps/observation-before-capture.json', 'run/google-maps/serial.log', 'run/google-maps/serial.log.gz',
		'run/google-maps/application.png', 'run/google-maps/network.pcap', 'media/boot-after-run.img', 'media/efivars-after-run.fd',
		'supplemental/harness.log', 'visual-notes.txt', 'audit/omitted-sockets.json'])!
	receipt := object(root + '/collection.json')!
	run := receipt['run']!.str()
	build := receipt['build']!.str()
	ids(run, build)!
	repo := receipt['repo_root']!.str()
	prepared := base + 'maps' + run
	paired := base + 'compound' + build
	replica := 'prelaunch/prelaunch/replica/'
	prep := replica + prepared
	regular_files(entries, [prep + '/prelaunch-sha256.json', prep + '/preparation-receipt.json', 'prelaunch/prelaunch/generation.generation.json'])!
	assert entries['prelaunch/prelaunch-sha256.json']! == receipt['prelaunch_pin']!.str()
	equal_maps(subtree(entries, 'prelaunch/prelaunch'), read_map(root + '/prelaunch/prelaunch-sha256.json')!)!
	pins := read_map(root + '/' + prep + '/prelaunch-sha256.json')!
	for path, digest in pins { assert entries[replica + path.trim_left('/')]! == digest, path }
	regular_files(entries, [prep + '/build-receipt.json'])!
	suite_build := object(root + '/' + prep + '/build-receipt.json')!
	assert suite_build['exit_code']!.int() == 0 && suite_build['completed_utc']!.str() != ''
	assert suite_build['source_sha256']!.str() == entries[prep + '/suite' + run + '.v']!
	assert suite_build['binary_sha256']!.str() == entries[prep + '/suite' + run]!
	assert suite_build['nativeapk_source_sha256']!.str() == entries[prep + '/sources/nativeapk/install.v']!
	assert suite_build['compiler_sha256']!.str() == pins['/Users/alex/code/v/v_old']!
	assert suite_build['cc_sha256']!.str() == pins[suite_build['cc_path']!.str()]!
	assert entries['prelaunch/prelaunch/frozen-inputs.json']! == frozen_pin
	frozen := read_map(root + '/prelaunch/prelaunch/frozen-inputs.json')!
	for path, digest in frozen {
		if 'prelaunch/prelaunch/frozen-consumed/' + path in entries { assert entries['prelaunch/prelaunch/frozen-consumed/' + path]! == digest, path }
	}
	original := os.read_file(root + '/prelaunch/prelaunch/frozen-consumed/' + base + 'suite256-resume.v')!
	suite := os.read_file(root + '/' + prep + '/suite' + run + '.v')!
	classifier_equal(original, suite)!
	assert pins[base + 'run-android-identity256']! == 'd6479d8a49f5d65c3190dfbca6e84f306d9becb4923ca89e93a678b2fe9fa5da'
	for path in [base + 'GoogleMaps.apk', base + 'GooglePlayServices.apk', base + 'GooglePlayStore.apk'] { assert pins[path]! == frozen[path]! }
	before := read_map(root + '/' + prep + '/runtime-before.json')!
	after := read_map(root + '/' + prep + '/runtime-after.json')!
	equal_maps(before, read_map(root + '/prelaunch/prelaunch/frozen-consumed/' + base + 'maps256/runtime-after.json')!)!
	assert before.len == 109 && after.len == 109
	runtime_delta(build, before, after)!
	if build == '282' { clean_build(root, entries, after)! }
	assert after[jar]! == entries[replica + paired + '/framework/api-impl.jar']!
	assert after[native]! == entries[replica + paired + '/native/libvinix-android-native.so']!
	generation := object(root + '/prelaunch/prelaunch/generation.generation.json')!
	assert generation['generated_source_sha256']!.str() == entries[replica + receipt['generated_helper']!.str().trim_left('/')]!
	assert generation['source_manifest_sha256']!.as_map().len == 2
	for suffix, key in {'.selector.v': 'selector_source_sha256', '.selector-bin': 'selector_binary_sha256', '.template.v': 'template_sha256'} {
		assert entries['prelaunch/prelaunch/generation' + suffix]! == generation[key]!.str()
	}
	for kind, pin in generation['source_manifest_sha256']!.as_map() {
		assert kind in ['framework', 'native']
		prefix := replica + paired + '/' + kind + '/'
		assert entries[prefix + 'sources.json']! == pin.str()
		sources := read_map(root + '/' + prefix + 'sources.json')!
		assert sources.len > 0
		directory := if kind == 'framework' { 'sources/' } else { 'atlframework/' }
		for path, digest in sources { assert entries[prefix + directory + path]! == digest, path }
	}
	if build == '276' { qualified276(root, entries, paired)! }
	if build == '278' { prepared278(root, entries, paired)! }
	if build == '282' { prepared282(root, entries, paired)! }
	for label in build_labels(build) {
		regular_files(entries, [replica + paired + '/' + label + '-receipt.json', replica + paired + '/' + label + '-before.json'])!
		built := object(root + '/' + replica + paired + '/' + label + '-receipt.json')!
		assert built['exit_code']!.int() == 0 && built['completed_utc']!.str() != ''
		assert replica + paired + '/' + label + '-before.json' in entries
		if label == 'build-framework' { assert built['output_sha256']!.str() == after[jar]! }
		if label == 'build-native' { assert built['output_sha256']!.str() == after[native]! }
	}
	config := object(root + '/' + replica + base + 'attempt' + run + '.json')!
	assert config['output']!.str() == base + 'attempt' + run
	assert config['boot_image']!.str() == prepared + '/vm/boot.img' && config['efivars']!.str() == prepared + '/vm/efivars.fd'
	assert config['applications']!.as_array().len == 1 && config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 420
	state := root + '/run/google-maps'
	start := object(state + '/start-receipt.json')!
	assert start['qemu_argv']!.as_array().map(it.str()) == qemu_arguments(config, repo)
	mut start_pins := map[string]string{}
	for path, digest in start['sha256']!.as_map() { start_pins[logical(path, repo)] = digest.str() }
	expected := [prepared + '/suite' + run, base + 'attempt' + run + '.json', prepared + '/vm/boot.img', prepared + '/vm/efivars.fd',
		config['qemu']!.str(), config['firmware']!.str(), prepared + '/runtime-after.json', base + 'maps-interact-unique258']
	verify_start(start_pins, pins, expected)!
	preparation := object(root + '/' + prep + '/preparation-receipt.json')!
	assert start['recorded_before_qemu_run_utc']!.str() >= preparation['completed_before_launch_utc']!.str()
	apps := json2.decode[[]json2.Any](os.read_file(root + '/run/results.json')!)!
	assert apps.len == 1
	app := apps[0].as_map()
	assert app['id']!.str() == 'google-maps' && app['package']!.str() == 'com.google.android.apps.maps'
	observation_window(run, build, app, os.read_file(state + '/serial.log')!)!
	for key, value in object(state + '/observation-before-capture.json')! { assert json2.encode(value) == json2.encode(app[key]!), key }
	assert gzip.decompress(os.read_bytes(state + '/serial.log.gz')!)! == os.read_bytes(state + '/serial.log')!
	assert entries['run/google-maps/serial.log']! == app['serial_sha256']!.str()
	assert entries['run/google-maps/application.png']! == app['screenshot_sha256']!.str() && 'screenshot_error' !in app
	assert os.file_size(state + '/network.pcap') > 24
	harness := os.read_file(root + '/supplemental/harness.log')!
	assert harness.contains('MAPS' + run + ' observation retained before final capture')
	assert harness.contains('APK-SUITE result google-maps ' + app['outcome']!.str()) && !harness.contains('V panic')
	for name, source in {'boot-after-run.img': 'boot.img', 'efivars-after-run.fd': 'efivars.fd'} {
		assert os.file_size(root + '/media/' + name) == os.file_size(root + '/' + prep + '/vm/' + source)
	}
	assert entries['audit/collector.v']! == receipt['collector_source_sha256']!.str()
	assert entries['audit/collector']! == receipt['collector_binary_sha256']!.str()
	assert os.lstat(root + '/visual-notes.txt')!.get_filetype() == .regular && os.file_size(root + '/visual-notes.txt') > 0
	omitted := json2.decode[[]string](os.read_file(root + '/audit/omitted-sockets.json')!)!
	assert omitted.len <= 1 && omitted.all(it == 'google-maps/qmp.sock')
	mut frames := []Frame{}
	mut paths := entries.keys().filter(it.starts_with('run/') && it.ends_with('.png'))
	paths.sort()
	for path in paths { regular_files(entries, [path])!; frames << png_frame(root + '/' + path, path, entries[path]!)! }
	assert frames.len > 0
	return {'run': json2.Any(run), 'build': json2.Any(build), 'original_outcome': app['outcome']!, 'original_functional_passed': app['functional_passed']!,
		'frames': json2.decode[json2.Any](json2.encode(frames))!, 'visual_conclusions': json2.Any('Root-authored visual-notes.txt is separate from the unchanged application classifier.')}
}

fn collect(run string, build string, prelaunch string, pin string, root string, notes string) ! {
	ids(run, build)!
	external_path(root)!
	if os.lstat(notes)!.get_filetype() != .regular || os.file_size(notes) == 0 { return error('nonempty regular visual notes required') }
	if hash(prelaunch + '/prelaunch-sha256.json')! != pin { return error('wrong prelaunch pin') }
	repo := os.real_path(os.getwd())
	needle := '-qmp unix:' + repo + '/' + base + 'attempt' + run + '/google-maps/qmp.sock'
	if checked(['ps', '-A', '-o', 'command='])!.split_into_lines().any(it.contains(needle)) { return error('fresh replay QEMU is still active') }
	source := os.read_file(@FILE)!
	binary := os.read_bytes(os.executable())!
	os.mkdir_all(root + '/audit')!
	os.write_file(root + '/audit/collector.v', source)!
	os.write_file_array(root + '/audit/collector', binary)!
	clone(prelaunch, root + '/prelaunch')!
	mut raw := map[string]string{}
	mut omitted := []string{}
	walk(base + 'attempt' + run, '', root + '/run', true, mut raw, mut omitted)!
	write_json(root + '/audit/raw-sha256.json', raw)!
	write_json(root + '/audit/omitted-sockets.json', omitted)!
	supplemental := supplemental_logs(run, root + '/supplemental')!
	write_json(root + '/audit/supplemental-sha256.json', supplemental)!
	clone(base + 'maps' + run + '/vm/boot.img', root + '/media/boot-after-run.img')!
	clone(base + 'maps' + run + '/vm/efivars.fd', root + '/media/efivars-after-run.fd')!
	clone(notes, root + '/visual-notes.txt')!
	mut after_raw := map[string]string{}
	mut after_omitted := []string{}
	walk(base + 'attempt' + run, '', '', true, mut after_raw, mut after_omitted)!
	equal_maps(after_raw, raw)!
	assert omitted == after_omitted
	equal_maps(supplemental_logs(run, '')!, supplemental)!
	// The generated source is one of the launch-pinned inputs. Locate it without
	// consulting the now mutable helper source or historical checker paths.
	pins := read_map(root + '/prelaunch/prelaunch/replica/' + base + 'maps' + run + '/prelaunch-sha256.json')!
	mut helper := ''
	for path, _ in pins { if path.ends_with('.v') && os.is_file(root + '/prelaunch/prelaunch/replica/' + path.trim_left('/'))
		&& os.read_file(root + '/prelaunch/prelaunch/replica/' + path.trim_left('/'))!.contains("const target = base + 'maps" + run + "'") { helper = path } }
	if helper == '' { return error('missing generated helper pin') }
	write_json(root + '/collection.json', {'run': json2.Any(run), 'build': json2.Any(build), 'repo_root': json2.Any(repo), 'prelaunch_pin': json2.Any(pin),
		'generated_helper': json2.Any(helper), 'collected_utc': json2.Any(time.utc().str()), 'source_revision': json2.Any(checked(['git', 'rev-parse', 'HEAD'])!.trim_space()),
		'collector_source_sha256': json2.Any(sha256.sum(source.bytes()).hex()), 'collector_binary_sha256': json2.Any(sha256.sum(binary).hex()),
		'omitted_special_file': json2.Any('Actual omitted stopped QMP socket paths are recorded in audit/omitted-sockets.json.')})!
	println('MAPS REPLAY COLLECTED ' + root)
}
fn seal(root string) ! {
	if os.exists(root + '/sha256.json') { return error('fresh seal required') }
	entries := inventory(root)!
	equal_maps(subtree(entries, 'run'), read_map(root + '/audit/raw-sha256.json')!)!
	equal_maps(subtree(entries, 'supplemental'), read_map(root + '/audit/supplemental-sha256.json')!)!
	write_json(root + '/validation.json', validate(root, entries)!)!
	write_json(root + '/sha256.json', inventory(root)!)!
	println('MAPS REPLAY SEALED pin=' + hash(root + '/sha256.json')!)
}
fn check(root string, pin string) ! {
	if pin.len != 64 || hash(root + '/sha256.json')! != pin { return error('wrong complete bundle pin') }
	entries := inventory(root)!
	equal_maps(entries, read_map(root + '/sha256.json')!)!
	equal_maps(subtree(entries, 'run'), read_map(root + '/audit/raw-sha256.json')!)!
	equal_maps(subtree(entries, 'supplemental'), read_map(root + '/audit/supplemental-sha256.json')!)!
	actual := validate(root, entries)!
	recorded := object(root + '/validation.json')!
	assert actual.len == recorded.len
	for key, value in actual { assert json2.encode(value) == json2.encode(recorded[key]!), key }
	println('MAPS REPLAY COMPLETE CHECK PASS entries=' + entries.len.str())
}

fn self_test(original_path string) ! {
	root := os.temp_dir() + '/maps-replay-evidence-' + time.now().unix_micro().str()
	os.mkdir_all(root + '/empty')!
	os.write_file(root + '/item', 'original\x00bytes')!
	os.symlink('item', root + '/link')!
	os.symlink(os.getwd(), root + '/checkout-link')!
	mut rejected := false
	external_path(root + '/checkout-link/results') or { rejected = true }
	assert rejected
	os.rm(root + '/checkout-link')!
	expected := inventory(root)!
	assert expected['empty']! == 'directory' && expected['link']! == 'symlink:item'
	equal_maps(inventory(root)!, expected)!
	regular_files(expected, ['item'])!
	rejected = false
	regular_files(expected, ['link']) or { rejected = true }
	assert rejected
	rejected = false
	regular_files({'link': 'symlink:' + 'a'.repeat(56)}, ['link']) or { rejected = true }
	assert rejected
	os.write_file(root + '/item', 'changed bytes')!
	rejected = false
	equal_maps(inventory(root)!, expected) or { rejected = true }
	assert rejected
	os.rm(root + '/item')!
	rejected = false
	equal_maps(inventory(root)!, expected) or { rejected = true }
	assert rejected
	// Header parsing tests dimensions without pretending to decode image pixels.
	mut header := [u8(137), 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 4, 0, 0, 0, 3, 0]
	os.write_file_array(root + '/frame.png', header)!
	frame := png_frame(root + '/frame.png', 'frame.png', '')!
	assert frame.width == 1024 && frame.height == 768
	header[20] = 255
	os.write_file_array(root + '/frame.png', header)!
	rejected = false
	png_frame(root + '/frame.png', 'frame.png', '') or { rejected = true }
	assert rejected
	os.write_file(root + '/frame.png', 'truncated')!
	rejected = false
	png_frame(root + '/frame.png', 'frame.png', '') or { rejected = true }
	assert rejected
	original := os.read_file(original_path)!
	classifier_equal(original, original)!
	rejected = false
	classifier_equal(original, original.replace('fn observation(', 'fn changed_observation(')) or { rejected = true }
	assert rejected
	pins := {'suite': '0'.repeat(64), 'media': '1'.repeat(64)}
	verify_start(pins, pins, pins.keys())!
	rejected = false
	verify_start({'suite': pins['suite']!, 'media': '2'.repeat(64)}, pins, pins.keys()) or { rejected = true }
	assert rejected
	rejected = false
	verify_start({'suite': pins['suite']!}, pins, pins.keys()) or { rejected = true }
	assert rejected
	write_json(root + '/sha256.json', expected)!
	rejected = false
	check(root, 'f'.repeat(64)) or { rejected = true }
	assert rejected
	ids('275', '274')!
	ids('277', '276')!
	ids('279', '278')!
	ids('283', '282')!
	failed277 := {
		'startup_timeout_seconds': json2.Any(420)
		'observation_elapsed_seconds': json2.Any(262)
		'process_exited': json2.Any(true)
		'qemu_alive_before_capture': json2.Any(true)
		'backend_ready': json2.Any(true)
		'native_maps_observed': json2.Any(true)
		'outcome': json2.Any('startup_failed')
		'functional_passed': json2.Any(json2.Null{})
		'failure_markers': json2.Any([json2.Any('ANDROID-WS-FAIL main looper'), json2.Any(tooltip277), json2.Any(exit277)])
	}
	failed_serial := 'ANDROID-WS-FAIL main looper\n' + tooltip277 + '\n' + exit277 + '\n'
	observation_window('277', '276', failed277, failed_serial)!
	for run, elapsed in {'277': 262, '279': 280} {
		build := (run.int() - 1).str()
		mut failed := json2.decode[map[string]json2.Any](json2.encode(failed277))!
		failed['observation_elapsed_seconds'] = json2.Any(elapsed)
		observation_window(run, build, failed, failed_serial)!
		for key, value in {
			'startup_timeout_seconds': json2.Any(419)
			'observation_elapsed_seconds': json2.Any(elapsed + 1)
			'process_exited': json2.Any(false)
			'qemu_alive_before_capture': json2.Any(false)
			'backend_ready': json2.Any(false)
			'native_maps_observed': json2.Any(false)
			'outcome': json2.Any('passed')
			'functional_passed': json2.Any(true)
		} {
			mut changed := json2.decode[map[string]json2.Any](json2.encode(failed))!
			changed[key] = value
			rejected = false
			observation_window(run, build, changed, failed_serial) or { rejected = true }
			assert rejected, key
		}
		for marker in ['ANDROID-WS-FAIL main looper', tooltip277, exit277] {
			mut changed := json2.decode[map[string]json2.Any](json2.encode(failed))!
			changed['failure_markers'] = json2.Any(failed['failure_markers']!.as_array().filter(it.str() != marker))
			rejected = false
			observation_window(run, build, changed, failed_serial) or { rejected = true }
			assert rejected, marker
			rejected = false
			observation_window(run, build, failed, failed_serial.replace(marker, '')) or { rejected = true }
			assert rejected, marker
		}
	}
	rejected = false
	observation_window('279', '278', failed277, failed_serial) or { rejected = true }
	assert rejected
	mut live := json2.decode[map[string]json2.Any](json2.encode(failed277))!
	live['observation_elapsed_seconds'] = json2.Any(420)
	live['process_exited'] = json2.Any(false)
	observation_window('275', '274', live, '')!
	observation_window('283', '282', live, '')!
	rejected = false
	observation_window('277', '276', live, failed_serial) or { rejected = true }
	assert rejected
	rejected = false
	observation_window('279', '278', live, failed_serial) or { rejected = true }
	assert rejected
	assert build_labels('276') == ['generate-native', 'build-native']
	assert build_labels('278') == ['build-framework-compiler', 'build-framework', 'fixture-compiler', 'fixture']
	assert build_labels('282') == build_labels('278')
	assert build_labels('274').len == 6
	before_runtime := {jar: 'old-jar', native: 'old-native', clean_launcher: historical_launcher_pin}
	after_runtime := {jar: 'new-jar', native: 'new-native', clean_launcher: clean_launcher_pin}
	runtime_delta('282', before_runtime, after_runtime)!
	mut wrong_launcher := after_runtime.clone()
	wrong_launcher[clean_launcher] = 'wrong'
	rejected = false
	runtime_delta('282', before_runtime, wrong_launcher) or { rejected = true }
	assert rejected
	mut extra_runtime := after_runtime.clone()
	extra_runtime['usr/bin/run-android'] = 'wrong'
	rejected = false
	runtime_delta('282', before_runtime, extra_runtime) or { rejected = true }
	assert rejected
	mut environment := map[string]string{}
	for name in ['usr/bin/vinix-session', 'usr/bin/vinix-desktop', 'usr/bin/run-android', 'usr/bin/run-android-identity', 'usr/bin/run-android-original', clean_launcher] {
		os.mkdir_all(os.dir(root + '/environment/' + name))!
		os.write_file(root + '/environment/' + name, 'clean')!
		environment[name] = hash(root + '/environment/' + name)!
	}
	clean_environment(root + '/environment', environment)!
	os.write_file(root + '/environment/usr/bin/vinix-session', 'export VINIX_ANDROID_TRACE_VISIBILITY=android.widget.LinearLayout')!
	environment['usr/bin/vinix-session'] = hash(root + '/environment/usr/bin/vinix-session')!
	rejected = false
	clean_environment(root + '/environment', environment) or { rejected = true }
	assert rejected
	rejected = false
	clean_build(root, {'prelaunch/prelaunch/clean-launcher/sha256.json': 'f'.repeat(64),
		'prelaunch/prelaunch/clean-launcher/builder': '0'.repeat(64),
		'prelaunch/prelaunch/launcher-environment.json': '0'.repeat(64)}, after_runtime) or { rejected = true }
	assert rejected
	rejected = false
	qualified276(root, {'prelaunch/prelaunch/qualified-build-sha256.json': 'f'.repeat(64),
		'prelaunch/prelaunch/qualified-build-reference.json': '0'.repeat(64)}, base + 'compound276') or { rejected = true }
	assert rejected
	rejected = false
	prepared278(root, {'prelaunch/prelaunch/prepared-build-sha256.json': 'f'.repeat(64),
		'prelaunch/prelaunch/prepared-build-reference.json': '0'.repeat(64),
		'prelaunch/prelaunch/qualified276-sha256.json': '0'.repeat(64),
		'prelaunch/prelaunch/qualified276-reference.json': '0'.repeat(64)}, base + 'compound278') or { rejected = true }
	assert rejected
	rejected = false
	ids('275', '272') or { rejected = true }
	assert rejected
	probe := os.exec([os.executable(), '--assertion-probe'])
	assert probe.exit_code != 0 && probe.output.contains('assert false')
	println('MAPS REPLAY EVIDENCE SELF-TEST PASS changed/missing bytes, links/directories, malformed PNG, classifier mutation, missing/changed launch pins, wrong bundle pin, exact failed277/279 and negative failure markers/window, unchanged live windows, clean launcher pin/extra overlay/inherited trace rejection, invalid IDs and live assertions; fixture=' + root)
}

fn main() {
	$if prod { eprintln('replay evidence checker requires assertions; compile without -prod'); exit(2) }
	if os.args.len == 2 && os.args[1] == '--assertion-probe' { assert false; return }
	if os.args.len == 3 && os.args[1] == '--self-test' { self_test(os.args[2]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 8 && os.args[1] == 'collect' { collect(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 3 && os.args[1] == 'seal' { seal(os.args[2]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 4 && os.args[1] == 'check' { check(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
	eprintln('usage: maps-replay-evidence collect MAPS_ID BUILD_ID PRELAUNCH PIN DEST VISUAL_NOTES; seal ROOT; check ROOT PIN')
	exit(2)
}
