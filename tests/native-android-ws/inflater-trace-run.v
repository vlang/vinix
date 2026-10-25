// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the qualified282 suite; trace mode adds one explicit launcher setter.
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

const state = '/Users/alex/.local/state/vinix/android/inflater-trace292-fixture-2026-10-25'
const compiler_origin = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const native_origin = '/Users/alex/.local/state/vinix/android/input286-build-2026-10-25/native/libvinix-android-native.so'
const native_pin = 'c46f56d775efef3807e34ece9c8bb5bdb949c47f6db54e59dee02e82cf60019a'
const old_jar = 'build/android-maps/framework288/framework/api-impl.jar'
const old_pin = 'ed5ca2dc9946a5d33d458c85ef808212698cc5076fefa1fb97fd6032a851ebc5'
const qualified288 = '/Users/alex/.local/state/vinix/android/frame-metrics288-build-2026-10-25'
const qualified288_pin = 'f52a1338edd143717a718e23cb1e2c7d4e3249a87f080fcfe8af8ff0bea2f27d'
const qualified283 = '/Users/alex/.local/state/vinix/android/maps283-clean-launcher-2026-10-25'
const qualified283_pin = '9e8256b31be97aa97c7bf8b4b353624514ea9cd7d9acfb7f7315d24c26670f10'
const clean_launcher_pin = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
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

fn shared_inputs() !map[string]string {
	mut pins := map[string]string{}
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'base-runtime.tar', 'native-old/api-impl.jar', 'native-old/popular-launcher', 'native-new/popular-launcher', 'trace-launcher'] {
		pins[path] = hash(state + '/' + path)!
	}
	return pins
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
	if os.is_dir(state + '/native-trace') {
		mut trace := map[string]string{}
		inventory(state + '/native-trace', '', mut trace)!
		trace.delete('api-impl.jar')
		trace.delete('popular-launcher')
		current.delete('popular-launcher')
		assert trace == current, 'trace may change only framework and launcher'
		assert hash(state + '/native-trace/api-impl.jar')! == hash(state + '/native-new/api-impl.jar')!
	}
}

fn assert_inputs(pins map[string]string) ! {
	for path, pin in pins { assert hash(path)! == pin, path }
}

fn launcher_closure(root string, phase string, mut pins map[string]string) ! {
	mut paths := os.read_lines(root + '/' + phase + '-v-files.txt')!
	for name in os.ls(root + '/cc-records')! {
		if !name.starts_with(phase + '-') || !name.ends_with('.json') { continue }
		r := json2.decode[map[string]json2.Any](os.read_file(root + '/cc-records/' + name)!)!
		assert r['exit_code']!.int() == 0, name
		paths << r['inputs']!.as_array().map(it.str())
	}
	mut actual := map[string]string{}
	for path in paths {
		resolved := os.real_path(path)
		if resolved !in pins && phase == 'discovery' && resolved.starts_with(root + '/cache/v3_thirdparty_objs/') {
			// V includes the compiler wrapper path in cached object names. A new
			// name is admitted only when its bytes equal a sealed original object.
			prefix := os.file_name(resolved).all_before_last('_')
			mut expected := ''
			for frozen_path, pin in pins {
				if frozen_path.starts_with(root + '/cache/v3_thirdparty_objs/') && os.file_name(frozen_path).all_before_last('_') == prefix { expected = pin; break }
			}
			assert expected.len == 64 && hash(resolved)! == expected, resolved
			pins[resolved] = expected
		}
		assert resolved in pins, 'unfrozen launcher build input: ' + resolved
		actual[resolved] = hash(resolved)!
		assert actual[resolved]! == pins[resolved]!, resolved
	}
	assert actual.len > 100
	write_json(root + '/' + phase + '-consumed.json', actual)!
}

fn trace_launcher() ! {
	assert hash(qualified283 + '/sha256.json')! == qualified283_pin
	seal := json2.decode[map[string]string](os.read_file(qualified283 + '/sha256.json')!)!
	root := state + '/trace-build'
	os.mkdir_all(root + '/source')!
	os.mkdir_all(root + '/cc-records')!
	for name in ['aarch64-linux-musl-gcc', 'real-gcc.txt', 'compile-tools.json', 'input-sha256.json', 'source/launcher.v'] {
		assert hash(qualified283 + '/' + name)! == seal[name]!, name
		clone(qualified283 + '/' + name, root + '/' + name)!
	}
	clone(qualified283 + '/sha256.json', state + '/qualified283-sha256.json')!
	os.write_file(root + '/build-root.txt', root + '\n')!
	clean := os.read_file(root + '/source/launcher.v')!
	assert !clean.contains('VINIX_ANDROID_TRACE_') && clean.count('fn main() {') == 1
	trace := clean.replace('fn main() {', "fn main() {\n\tos.setenv('VINIX_ANDROID_TRACE_INFLATER', '1', true)")
	os.write_file(root + '/source/launcher.v', trace)!
	prior := json2.decode[map[string]string](os.read_file(root + '/input-sha256.json')!)!
	mut before := map[string]string{}
	for path, pin in prior {
		if path.starts_with('/Users/alex/code/vinix/build/android-maps/maps283-clean-launcher/') { continue }
		if path == '/Users/alex/code/v/v_old' { continue } // Use the pinned retained compiler below.
		if path.contains('/v3_thirdparty_objs/') {
			retained := qualified283 + '/inputs/' + path.trim_left('/')
			assert hash(retained)! == pin, retained
			target := root + '/cache/v3_thirdparty_objs/' + os.file_name(path)
			clone(retained, target)!
			before[target] = pin
			continue
		}
		assert hash(path)! == pin, path
		before[path] = pin
		clone(path, root + '/inputs/' + path.trim_left('/'))!
	}
	for path in [root + '/source/launcher.v', root + '/aarch64-linux-musl-gcc', state + '/tools/v_old276'] { before[path] = hash(path)! }
	// The isolated wrapper path makes V rebuild these helpers. Their generated
	// object bytes must still match the qualified objects in launcher_closure.
	for path in ['/Users/alex/code/v/vlib/builtin/segfault_handler_nix.c', '/Users/alex/code/v/vlib/builtin/segfault_handler_nix.h', '/Users/alex/code/v/vlib/os/execute_capture_nix.c', '/Users/alex/code/v/vlib/os/execute_capture_nix.h'] {
		before[path] = hash(path)!
		clone(path, root + '/inputs/' + path.trim_left('/'))!
	}
	// These helper dependencies were observed in the retained discovery attempt.
	// Freeze them before this build; closure checking rejects any further input.
	for relative in ['stdc-predef.h', 'stddef.h', 'bits/alltypes.h', 'errno.h', 'features.h', 'bits/errno.h', 'signal.h', 'bits/signal.h', 'stdint.h', 'bits/stdint.h', 'string.h', 'strings.h', 'unistd.h', 'bits/posix.h', 'pthread.h', 'sched.h', 'time.h', 'sys/mman.h', 'bits/mman.h', 'sys/resource.h', 'sys/time.h', 'sys/select.h', 'bits/resource.h', 'sys/ucontext.h', 'ucontext.h', 'fcntl.h', 'bits/fcntl.h', 'sys/types.h', 'endian.h'] {
		path := '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/aarch64-linux-musl/include/' + relative
		if path in before { continue }
		before[path] = hash(path)!
		clone(path, root + '/inputs/' + path.trim_left('/'))!
	}
	write_json(root + '/inputs-before.json', before)!
	old_vtmp := os.getenv_opt('VTMP')
	os.setenv('VTMP', root + '/cache', true)
	defer { if saved := old_vtmp { os.setenv('VTMP', saved, true) } else { os.unsetenv('VTMP') } }
	for phase in ['discovery', 'run-android-calculator'] {
		assert_inputs(before)!
		os.setenv('VINIX_LAUNCHER_BUILD_PHASE', phase, true)
		record('trace-' + phase, [state + '/tools/v_old276', '-nocache', '-os', 'linux', '-arch', 'arm64', '-cc', root + '/aarch64-linux-musl-gcc', '-gc', 'none', '-showcc', '-dump-files', root + '/' + phase + '-v-files.txt', '-cflags', '-O2 -D_GNU_SOURCE -static', '-ldflags', '-static', '-o', root + '/' + phase, root + '/source/launcher.v'])!
		launcher_closure(root, phase, mut before)!
		write_json(root + '/' + phase + '-inputs-after.json', before)!
		assert_inputs(before)!
	}
	os.unsetenv('VINIX_LAUNCHER_BUILD_PHASE')
	write_json(root + '/inputs-after.json', before)!
	clone(root + '/run-android-calculator', state + '/trace-launcher')!
	write_json(state + '/launcher-delta.json', {'common_launcher_sha256': clean_launcher_pin, 'trace_launcher_sha256': hash(state + '/trace-launcher')!, 'clean_source_sha256': seal['source/launcher.v']!, 'trace_source_sha256': hash(root + '/source/launcher.v')!, 'scope': 'Same child argv and polling; trace source adds exactly one explicit inflater environment setter. Common launcher replaces historical282 trace200 launcher in all variants.'})!
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
	assert hash(qualified288 + '/sha256.json')! == qualified288_pin
	pins288 := json2.decode[map[string]string](os.read_file(qualified288 + '/sha256.json')!)!
	assert pins288['framework/api-impl.jar']! == old_pin
	assert hash(qualified288 + '/framework/api-impl.jar')! == old_pin
	clone(qualified288 + '/sha256.json', state + '/qualified288-sha256.json')!
	write_json(state + '/qualified-references.json', {'compound282': qualified282, 'compound282_manifest': qualified282_pin, 'maps285': qualified285, 'maps285_manifest': qualified285_pin, 'scope': 'Selected consumed files only; no historical full-bundle audit.'})!
	for name in ['inflater-trace-fixture.v', 'inflater-trace-run.v'] { clone('tests/native-android-ws/' + name, state + '/source/' + name)! }
	clone(os.executable(), state + '/tools/inflater-trace-run')!
	assert hash(compiler_origin)! == compiler_pin
	clone(compiler_origin, state + '/tools/v_old276')!
	selected_file('prelaunch/suite', state + '/tools/suite', pins282)!
	selected_file('prelaunch/source/suite.v', state + '/source/suite.v', pins282)!
	selected_tree('prelaunch/suite-support', state + '/source/suite-support', pins282)!
	for name in ['suite-v-files.json', 'suite-compiler-before.json', 'suite-compiler-receipt.json', 'suite-compiler.log', 'fixed.json'] { selected_file('prelaunch/' + name, state + '/qualified282-' + name, pins282)! }
	assert hash(native_origin)! == native_pin
	assert hash(old_jar)! == old_pin
	trace_launcher()!
	assert hash(qualified283 + '/run-android-calculator')! == clean_launcher_pin
	selected_file('prelaunch/base-runtime.tar', state + '/base-runtime.tar', pins282)!
	for kind in ['old', 'new'] {
		selected_tree('prelaunch/native-fixed', state + '/native-' + kind, pins282)!
		os.rm(state + '/native-' + kind + '/libvinix-android-native.so')!
		clone(native_origin, state + '/native-' + kind + '/libvinix-android-native.so')!
		os.rm(state + '/native-' + kind + '/api-impl.jar')!
		if kind == 'old' { clone(qualified288 + '/framework/api-impl.jar', state + '/native-old/api-impl.jar')! }
		os.rm(state + '/native-' + kind + '/popular-launcher')!
		clone(qualified283 + '/run-android-calculator', state + '/native-' + kind + '/popular-launcher')!
		for file in ['boot.img', 'efivars.fd'] {
			assert hash(initial_media + '/' + file)! == pins285['maps285/vm/' + file]!, file
			clone(initial_media + '/' + file, state + '/vm-' + kind + '/' + file)!
		}
		mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified282-fixed.json')!)!
		config['applications'] = json2.Any([json2.Any({'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'), 'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Inflater trace fixture'), 'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/inflater-trace-fixture.v'), 'startup_seconds': json2.Any(30)})])
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
	fixture_pins := source_closure('fixture', state + '/source/inflater-trace-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/inflater-trace-fixture', state + '/source/inflater-trace-fixture.v'])!
	for path, pin in fixture_pins { assert hash(path)! == pin, path }
	write_json(state + '/fixture-v-files-after.json', fixture_pins)!
	record('generate-fixture', [state + '/tools/inflater-trace-fixture', state + '/apk'])!
	runner_pins := source_closure('runner', state + '/source/inflater-trace-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/inflater-trace-run-checked', state + '/source/inflater-trace-run.v'])!
	for path, pin in runner_pins { assert hash(path)! == pin, path }
	write_json(state + '/runner-v-files-after.json', runner_pins)!
	write_json(state + '/shared-inputs.json', shared_inputs()!)!
	println('INFLATER-TRACE-PREPARED')
}

fn run(kind string) ! {
	assert shared_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared input changed between fixture variants'
	native_equality()!
	// QEMU's UNIX socket path is limited to 103 bytes on this host. Keep the
	// results in the retained bundle while exposing a shorter ignored alias.
	tag := kind + '-guest'
	output := state + '/run-' + tag
	alias := os.abs_path('build/android-maps/if292-' + kind)
	assert (alias + '/bootstrap-fixture/qmp.sock').len < 104
	assert !os.exists(alias) && !os.is_link(alias), alias
	os.mkdir_all(output)!
	os.symlink(output, alias)!
	config_kind := if kind == 'trace' { 'new' } else { kind }
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/' + config_kind + '.json')!)!
	media := json2.decode[map[string]string](os.read_file(state + '/initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] {
		assert hash(initial_media + '/' + file)! == media[file]!, file
		clone(initial_media + '/' + file, state + '/vm-' + tag + '/' + file)!
	}
	config['output'] = alias
	config['native_dir'] = state + '/native-' + kind
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
	for name in ['CALLBACKS', 'THROWABLE', 'WARNING', 'ERROR'] { assert log.count('BOOTSTRAP-INFLATER-TRACE-' + name + '-PASS') == 1, name }
	work := if kind == 'new' { 'SKIPPED' } else { 'PRESENT' }
	other_work := if kind == 'new' { 'PRESENT' } else { 'SKIPPED' }
	assert log.count('BOOTSTRAP-INFLATER-TRACE-WORK-' + work + '-PASS') == 1
	assert !log.contains('BOOTSTRAP-INFLATER-TRACE-WORK-' + other_work + '-PASS')
	env := if kind == 'trace' { 'ONE' } else { 'ABSENT' }
	assert log.count('BOOTSTRAP-INFLATER-TRACE-TRACE-ENV-' + env + '-PASS') == 1
	assert log.count('BOOTSTRAP-READY') == 1
	for bad in ['AssertionError', 'NoSuchMethodError', 'NoClassDefFoundError', 'VerifyError', 'ANDROID-WS-FAIL'] { assert !log.contains(bad), bad }
	write_json(state + '/' + tag + '-semantic-check.json', {'kind': kind, 'status': 'expected-result-pass', 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!, 'checker_binary': hash(os.executable())!})!
	println('INFLATER-TRACE-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
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
		'trace' {
			clone(state + '/native-new', state + '/native-trace')!
			os.rm(state + '/native-trace/popular-launcher')!
			clone(state + '/trace-launcher', state + '/native-trace/popular-launcher')!
			run('trace')!
		}
		'seal' {
			assert !os.exists(state + '/sha256.json')
			mut files := map[string]string{}
			inventory(state, '', mut files)!
			write_json(state + '/sha256.json', files)!
			for path, pin in files { assert hash(state + '/' + path)! == pin, path }
			println('INFLATER-TRACE-SEALED files=${files.len} manifest=' + hash(state + '/sha256.json')!)
		}
		else { panic('prepare | old | new JAR SHA256 | trace | seal') }
	}
}
