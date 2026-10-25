// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the qualified282 guest suite, changing only the framework between runs.
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

const state = '/Users/alex/.local/state/vinix/android/frame-metrics287-fixture-2026-10-25'
const compiler_origin = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const native_origin = '/Users/alex/.local/state/vinix/android/input286-build-2026-10-25/native/libvinix-android-native.so'
const native_pin = 'c46f56d775efef3807e34ece9c8bb5bdb949c47f6db54e59dee02e82cf60019a'
const old_jar = 'build/android-maps/compound282/framework/api-impl.jar'
const old_pin = '92b069b1dbb31b08960d00d4f33f84b068a3adf53af9339f2ef3c1a6478f0618'
const initial_media = '/Users/alex/.local/state/vinix/android/maps285-2026-10-25-prelaunch/prelaunch/maps285/vm'
const qualified282 = '/Users/alex/.local/state/vinix/android/compound282-2026-10-25'
const qualified282_pin = 'd966016994e234c6f4d8b2bf4a39fc041be60023fc7f61a1cf653fedeaf857d4'
const qualified285 = '/Users/alex/.local/state/vinix/android/maps285-2026-10-25-prelaunch'
const qualified285_pin = 'e69637746f704240c9c9e19ecd85aa421df786c55931cf1ca361c51dbb07e895'

fn hash(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut sum := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &sum }) == 1
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &sum }, buffer.data, u32(n)) == 1
	}
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &sum }) == 1
	return result[..].hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone(from string, to string) ! {
	assert !os.exists(to), to
	os.mkdir_all(os.dir(to))!
	r := os.exec(['cp', '-c', '-R', os.real_path(from), to])
	assert r.exit_code == 0, r.output
}

fn record(label string, argv []string) ! {
	assert !os.exists(state + '/' + label + '-receipt.json'), label
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'VROOT': json2.Any(os.getenv('VROOT')), 'command_sha256': json2.Any(hash(os.real_path(argv[0]))!)}
	write_json(state + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(state + '/' + label + '.log', r.output)!
	if !label.ends_with('-closure') { print(r.output) }
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	write_json(state + '/' + label + '-receipt.json', receipt)!
	assert r.exit_code == 0, label
}

fn inventory(dir string, relative string, mut files map[string]string) ! {
	for name in os.ls(dir + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := dir + '/' + key
		if os.is_dir(path) { inventory(dir, key, mut files)! }
		else if os.is_file(path) { files[key] = hash(path)! }
	}
}

fn stable_inputs(kind string) !map[string]string {
	mut files := map[string]string{}
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'base-runtime.tar', 'native-' + kind + '/api-impl.jar', 'native-' + kind + '/libvinix-android-native.so'] {
		files[path] = hash(state + '/' + path)!
	}
	assert files['tools/v_old276']! == compiler_pin
	assert files['native-' + kind + '/libvinix-android-native.so']! == native_pin
	mut native_files := map[string]string{}
	inventory(state + '/native-' + kind, '', mut native_files)!
	for path, pin in native_files { files['native-' + kind + '/' + path] = pin }
	return files
}

fn selected_file(relative string, target string, pins map[string]string) ! {
	assert hash(qualified282 + '/' + relative)! == pins[relative]!, relative
	clone(qualified282 + '/' + relative, target)!
	assert hash(target)! == pins[relative]!, target
}

fn selected_tree(relative string, target string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for path, pin in pins { if path.starts_with(relative + '/') && pin.len == 64 { expected[path.all_after(relative + '/')] = pin } }
	mut actual := map[string]string{}
	inventory(qualified282 + '/' + relative, '', mut actual)!
	assert actual == expected, relative
	clone(qualified282 + '/' + relative, target)!
	actual.clear()
	inventory(target, '', mut actual)!
	assert actual == expected, target
}

fn source_closure(label string, source string) !map[string]string {
	record(label + '-closure', [state + '/tools/v_old276', '-print-v-files', source])!
	mut pins := map[string]string{}
	for path in os.read_lines(state + '/' + label + '-closure.log')!.filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := state + '/closure-inputs/' + path.trim_left('/')
		if os.exists(target) { assert hash(target)! == pins[path]!, path }
		else { clone(path, target)! }
	}
	assert pins.len > 0
	write_json(state + '/' + label + '-v-files.json', pins)!
	return pins
}

fn native_equality() ! {
	mut old := map[string]string{}
	mut current := map[string]string{}
	inventory(state + '/native-old', '', mut old)!
	inventory(state + '/native-new', '', mut current)!
	old.delete('api-impl.jar')
	current.delete('api-impl.jar')
	assert old == current, 'only the framework may differ between native directories'
	write_json(state + '/native-common.json', old)!
}

fn prepare() ! {
	assert !os.exists(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	assert hash(qualified282 + '/sha256.json')! == qualified282_pin
	pins282 := json2.decode[map[string]string](os.read_file(qualified282 + '/sha256.json')!)!
	clone(qualified282 + '/sha256.json', state + '/qualified282-sha256.json')!
	assert hash(qualified285 + '/prelaunch-sha256.json')! == qualified285_pin
	pins285 := json2.decode[map[string]string](os.read_file(qualified285 + '/prelaunch-sha256.json')!)!
	clone(qualified285 + '/prelaunch-sha256.json', state + '/qualified285-sha256.json')!
	write_json(state + '/qualified-references.json', {'compound282': qualified282, 'compound282_manifest': qualified282_pin, 'maps285': qualified285, 'maps285_manifest': qualified285_pin, 'scope': 'Selected consumed files only; no historical full-bundle audit.'})!
	for name in ['frame-metrics-fixture.v', 'frame-metrics-run.v'] { clone('tests/native-android-ws/' + name, state + '/source/' + name)! }
	clone(os.executable(), state + '/tools/frame-metrics-run')!
	assert hash(compiler_origin)! == compiler_pin
	clone(compiler_origin, state + '/tools/v_old276')!
	selected_file('prelaunch/suite', state + '/tools/suite', pins282)!
	selected_file('prelaunch/source/suite.v', state + '/source/suite.v', pins282)!
	selected_tree('prelaunch/suite-support', state + '/source/suite-support', pins282)!
	for name in ['suite-v-files.json', 'suite-compiler-before.json', 'suite-compiler-receipt.json', 'suite-compiler.log', 'fixed.json'] { selected_file('prelaunch/' + name, state + '/qualified282-' + name, pins282)! }
	assert hash(native_origin)! == native_pin
	assert hash(old_jar)! == old_pin
	selected_file('prelaunch/base-runtime.tar', state + '/base-runtime.tar', pins282)!
	for kind in ['old', 'new'] {
		selected_tree('prelaunch/native-fixed', state + '/native-' + kind, pins282)!
		os.rm(state + '/native-' + kind + '/libvinix-android-native.so')!
		clone(native_origin, state + '/native-' + kind + '/libvinix-android-native.so')!
		os.rm(state + '/native-' + kind + '/api-impl.jar')!
		if kind == 'old' { selected_file('prelaunch/native-fixed/api-impl.jar', state + '/native-old/api-impl.jar', pins282)! }
		for file in ['boot.img', 'efivars.fd'] {
			assert hash(initial_media + '/' + file)! == pins285['maps285/vm/' + file]!, file
			clone(initial_media + '/' + file, state + '/vm-' + kind + '/' + file)!
		}
		mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified282-fixed.json')!)!
		config['applications'] = json2.Any([json2.Any({'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'), 'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Frame metrics fixture'), 'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/frame-metrics-fixture.v'), 'startup_seconds': json2.Any(30)})])
		for key, value in {'base_module': state + '/base-runtime.tar', 'boot_image': state + '/vm-' + kind + '/boot.img', 'efivars': state + '/vm-' + kind + '/efivars.fd', 'native_dir': state + '/native-' + kind, 'output': state + '/run-' + kind} { config[key] = value }
		write_json(state + '/' + kind + '.json', config)!
	}
	native_equality()!
	mut media := map[string]string{}
	for file in ['boot.img', 'efivars.fd'] {
		media[file] = hash(initial_media + '/' + file)!
		for kind in ['old', 'new'] { assert hash(state + '/vm-' + kind + '/' + file)! == media[file]!, file }
	}
	write_json(state + '/initial-media.json', media)!
	fixture_pins := source_closure('fixture', state + '/source/frame-metrics-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/frame-metrics-fixture', state + '/source/frame-metrics-fixture.v'])!
	for path, pin in fixture_pins { assert hash(path)! == pin, path }
	write_json(state + '/fixture-v-files-after.json', fixture_pins)!
	record('generate-fixture', [state + '/tools/frame-metrics-fixture', state + '/apk'])!
	runner_pins := source_closure('runner', state + '/source/frame-metrics-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/frame-metrics-run-checked', state + '/source/frame-metrics-run.v'])!
	for path, pin in runner_pins { assert hash(path)! == pin, path }
	write_json(state + '/runner-v-files-after.json', runner_pins)!
	println('FRAME-METRICS-PREPARED')
}

fn run(kind string) ! {
	native_equality()!
	// QEMU's UNIX socket path is limited to 103 bytes on this host. Keep the
	// results in the retained bundle while exposing a shorter ignored alias.
	tag := kind + '-guest'
	output := state + '/run-' + tag
	alias := os.abs_path('build/android-maps/fm287-' + kind)
	assert (alias + '/bootstrap-fixture/qmp.sock').len < 104
	assert !os.exists(alias) && !os.is_link(alias), alias
	os.mkdir_all(output)!
	os.symlink(output, alias)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/' + kind + '.json')!)!
	media := json2.decode[map[string]string](os.read_file(state + '/initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] {
		assert hash(initial_media + '/' + file)! == media[file]!, file
		clone(initial_media + '/' + file, state + '/vm-' + tag + '/' + file)!
	}
	config['output'] = alias
	config['boot_image'] = state + '/vm-' + tag + '/boot.img'
	config['efivars'] = state + '/vm-' + tag + '/efivars.fd'
	write_json(state + '/' + tag + '.json', config)!
	before := stable_inputs(kind)!
	if kind == 'old' { assert before['native-old/api-impl.jar']! == old_pin }
	write_json(state + '/' + tag + '-inputs-before.json', before)!
	record('suite-' + tag, [state + '/tools/suite', state + '/' + tag + '.json'])!
	assert stable_inputs(kind)! == before, 'run changed immutable inputs'
	write_json(state + '/' + tag + '-inputs-after.json', stable_inputs(kind)!)!
	log := os.read_file(output + '/bootstrap-fixture/serial.log')!
	if kind == 'old' {
		assert log.contains('java.lang.NoSuchMethodError') && log.contains('addOnFrameMetricsAvailableListener'), log
		assert !log.contains('BOOTSTRAP-READY')
	} else {
		for name in ['DETACHED', 'VALUES', 'SIGNATURE', 'ATTACHED'] { assert log.count('BOOTSTRAP-FRAME-METRICS-' + name + '-PASS') == 1, name }
		assert log.count('BOOTSTRAP-READY') == 1
		for bad in ['AssertionError', 'NoSuchMethodError', 'NoClassDefFoundError', 'VerifyError', 'ANDROID-WS-FAIL'] { assert !log.contains(bad), bad }
	}
	write_json(state + '/' + tag + '-semantic-check.json', {'kind': kind, 'status': 'expected-result-pass', 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!, 'checker_binary': hash(os.executable())!})!
	println('FRAME-METRICS-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	assert os.args.len >= 2
	match os.args[1] {
		'prepare' { prepare()! }
		'old' { run('old')! }
		'new' {
			assert os.args.len == 4, 'new JAR SHA256'
			assert os.args[3].len == 64 && hash(os.args[2])! == os.args[3]
			clone(os.args[2], state + '/native-new/api-impl.jar')!
			run('new')!
		}
		'seal' {
			assert !os.exists(state + '/sha256.json')
			mut files := map[string]string{}
			inventory(state, '', mut files)!
			write_json(state + '/sha256.json', files)!
			for path, pin in files { assert hash(state + '/' + path)! == pin, path }
			println('FRAME-METRICS-SEALED files=${files.len} manifest=' + hash(state + '/sha256.json')!)
		}
		else { panic('prepare | old | new JAR SHA256 | seal') }
	}
}
