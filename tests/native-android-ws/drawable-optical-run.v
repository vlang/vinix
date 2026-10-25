// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed optical-insets probe, Native302 and clean283 launcher; only Framework changes.
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

const state = '/Users/alex/.local/state/vinix/android/drawable-optical307-fixture-2026-10-25'
const qualified305 = '/Users/alex/.local/state/vinix/android/text-hint305-fixture-2026-10-25'
const seal305 = 'c8d333681b80386d16c48faf540c84ff4e464e45c098a4e1ee96d9de92c79b7a'
const native302 = 'f31fb4916ef7983aabcfb03ad0f21ffb7d84cf7cd433cd6c3568ce75def82f7e'
const framework302 = '570b88718c3520aacf7f462f01230e0fd880770ac888a8743e949d2ef970fd44'
const launcher283 = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	mut sum := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &digest }) == 1
	return sum[..].hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	r := os.exec(['/bin/cp', '-c', '-R', os.real_path(from), to])
	assert r.exit_code == 0, r.output
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut files)! }
			.regular { files[key] = hash(path)! }
			else { return error('nonregular input: ' + path) }
		}
	}
}

fn qualified_manifest(root string, seal string) !map[string]string {
	assert seal.len == 64 && hash(root + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == pins, 'complete qualified build bundle changed: ' + root
	return pins
}

fn selected(path string, to string, pins map[string]string) ! {
	assert hash(qualified305 + '/' + path)! == pins[path]!, path
	clone(qualified305 + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins { if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin } }
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(qualified305 + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(qualified305 + '/' + path, state + '/' + to)!
	actual.clear()
	inventory(state + '/' + to, '', mut actual)!
	assert actual == expected, to
}

fn record(label string, argv []string) ! {
	assert !os.exists(state + '/' + label + '-receipt.json'), label
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'VROOT': json2.Any(os.getenv('VROOT')), 'command_sha256': json2.Any(hash(os.real_path(argv[0]))!)}
	write_json(state + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	if !label.ends_with('-closure') { print(r.output) }
	os.write_file(state + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	write_json(state + '/' + label + '-receipt.json', receipt)!
	assert r.exit_code == 0, label
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

fn closure_unchanged(label string, pins map[string]string) ! {
	for path, pin in pins { assert hash(path)! == pin, path }
	write_json(state + '/' + label + '-v-files-after.json', pins)!
}

fn native_equality() ! {
	mut old := map[string]string{}
	mut new := map[string]string{}
	inventory(state + '/native-old', '', mut old)!
	inventory(state + '/native-new', '', mut new)!
	assert old['api-impl.jar']! == framework302
	assert old['popular-launcher']! == launcher283 && new['popular-launcher']! == launcher283
	assert old['libvinix-android-native.so']! == native302 && new['libvinix-android-native.so']! == native302
	if os.exists(state + '/qualified306-reference.json') {
		pins := json2.decode[map[string]string](os.read_file(state + '/qualified306-reference.json')!)!
		assert new['api-impl.jar']! == pins['framework_sha256']!
	} else { assert new['api-impl.jar']! == framework302 }
	old.delete('api-impl.jar')
	new.delete('api-impl.jar')
	assert old == new, 'Only Framework may differ between variants; Native302 is identical'
	if os.exists(state + '/native-common.json') { assert json2.decode[map[string]string](os.read_file(state + '/native-common.json')!)! == old }
	else { write_json(state + '/native-common.json', old)! }
}

fn stable_inputs() !map[string]string {
	mut pins := map[string]string{}
	for dir in ['native-old', 'native-new', 'fixture-inputs'] {
		mut files := map[string]string{}
		inventory(state + '/' + dir, '', mut files)!
		for key, pin in files { pins[dir + '/' + key] = pin }
	}
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'tools/drawable-optical-run-checked', 'base-runtime.tar', 'source/drawable-optical-insets-fixture.v', 'source/drawable-optical-run.v', 'config.json', 'host-inputs.json', 'initial-media.json', 'initial-media/boot.img', 'initial-media/efivars.fd'] { pins[path] = hash(state + '/' + path)! }
	assert pins['tools/v_old276']! == compiler_pin
	return pins
}

fn host_inputs(config map[string]json2.Any) !map[string]string {
	mut pins := map[string]string{}
	for key in ['aapt2', 'apksigner', 'firmware', 'input_tool', 'java', 'qemu'] {
		path := os.real_path(config[key]!.str())
		pins[path] = hash(path)!
	}
	return pins
}

fn prepare() ! {
	assert !os.exists(state) && !os.is_link(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	pins := qualified_manifest(qualified305, seal305)!
	clone(qualified305 + '/sha256.json', state + '/qualified305-sha256.json')!
	assert pins['native-new/libvinix-android-native.so']! == native302
	assert pins['native-new/api-impl.jar']! == framework302
	write_json(state + '/qualified-references.json', {'fixture305': qualified305, 'fixture305_manifest': seal305, 'regular_files_verified': pins.len.str(), 'scope': 'Complete sealed baseline verified; selected consumed files rechecked before and after cloning. Historical root unchanged. Common clean283 launcher, baseline Framework302 and Native302 retained without rebuild.'})!
	for name in ['drawable-optical-insets-fixture.v', 'drawable-optical-run.v'] { clone('tests/native-android-ws/' + name, state + '/source/' + name)! }
	clone(os.executable(), state + '/tools/drawable-optical-run-bootstrap')!
	for name in ['tools/v_old276', 'tools/suite', 'tools/inflater-trace-seal', 'source/inflater-trace-seal.v', 'source/suite.v', 'base-runtime.tar'] { selected(name, name, pins)! }
	assert hash('tests/native-android-ws/inflater-trace-seal.v')! == hash(state + '/source/inflater-trace-seal.v')!
	selected_tree('source/suite-support', 'source/suite-support', pins)!
	for name in ['qualified282-suite-v-files.json', 'qualified282-suite-compiler-before.json', 'qualified282-suite-compiler-receipt.json', 'qualified282-suite-compiler.log'] { selected(name, name, pins)! }
	selected('new.json', 'qualified305-new.json', pins)!
	selected_tree('native-new', 'native-old', pins)!
	selected_tree('native-new', 'native-new', pins)!
	native_equality()!
	for file in ['boot.img', 'efivars.fd'] { selected('initial-media/' + file, 'initial-media/' + file, pins)! }
	selected('initial-media.json', 'qualified305-initial-media.json', pins)!
	media := json2.decode[map[string]string](os.read_file(state + '/qualified305-initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] { assert hash(state + '/initial-media/' + file)! == media[file]!, file }
	write_json(state + '/initial-media.json', media)!
	selected_tree('fixture-inputs', 'fixture-inputs', pins)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified305-new.json')!)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'), 'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Drawable optical insets fixture'), 'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/drawable-optical-insets-fixture.v'), 'startup_seconds': json2.Any(45)})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	fixture_pins := source_closure('fixture', state + '/source/drawable-optical-insets-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/drawable-optical-insets-fixture', state + '/source/drawable-optical-insets-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	os.setenv('DRAWABLE_OPTICAL_INSETS_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	record('generate-fixture', [state + '/tools/drawable-optical-insets-fixture', state + '/apk'])!
	os.unsetenv('DRAWABLE_OPTICAL_INSETS_FIXTURE_TOOLS_ROOT')
	runner_pins := source_closure('runner', state + '/source/drawable-optical-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/drawable-optical-run-checked', state + '/source/drawable-optical-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('DRAWABLE-OPTICAL-PREPARED')
}

fn unsealed() {
	assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged'
}

fn stage(framework_root string, framework_seal string, framework string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	framework_pins := qualified_manifest(framework_root, framework_seal)!
	assert framework.len == 64 && framework != framework302 && framework_pins['framework/api-impl.jar']! == framework
	assert hash(framework_root + '/framework/api-impl.jar')! == framework
	clone(framework_root + '/sha256.json', state + '/qualified306-framework-sha256.json')!
	os.rm(state + '/native-new/api-impl.jar')!
	clone(framework_root + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
	assert hash(state + '/native-new/api-impl.jar')! == framework
	write_json(state + '/qualified306-reference.json', {'framework_root': framework_root, 'framework_manifest_sha256': framework_seal, 'framework_sha256': framework, 'framework_regular_files_verified': framework_pins.len.str(), 'native_sha256': native302, 'scope': 'Complete sealed framework build bundle verified at staging; framework payload consumed without modifying the historical root.', 'delta': 'Only api-impl.jar changes; same signed APK, Native302, other runtime files and clean283 launcher.'})!
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('DRAWABLE-OPTICAL-STAGED')
}

fn run(kind string) ! {
	unsealed()
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['drawable-optical-insets-fixture.v', 'drawable-optical-run.v'] { assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)! }
	assert hash(os.executable())! == hash(state + '/tools/drawable-optical-run-checked')!, 'use the checked frozen runner'
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') { removed << key; os.unsetenv(key) }
	}
	write_json(state + '/' + kind + '-environment.json', {'removed_host_trace_variables': json2.Any(removed), 'guest_requirement': json2.Any('APK independently requires every VINIX_ANDROID_TRACE_* variable absent; common clean283 launcher unchanged'), 'launcher_sha256': json2.Any(launcher283)})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/do307-' + kind)
	assert (alias + '/bootstrap-fixture/qmp.sock').len < 104
	assert !os.exists(alias) && !os.is_link(alias), alias
	os.mkdir_all(output)!
	os.symlink(output, alias)!
	media := json2.decode[map[string]string](os.read_file(state + '/initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] {
		assert hash(state + '/initial-media/' + file)! == media[file]!, file
		clone(state + '/initial-media/' + file, state + '/vm-' + kind + '/' + file)!
		assert hash(state + '/vm-' + kind + '/' + file)! == media[file]!, file
	}
	config['output'] = alias
	config['native_dir'] = state + '/native-' + kind
	config['boot_image'] = state + '/vm-' + kind + '/boot.img'
	config['efivars'] = state + '/vm-' + kind + '/efivars.fd'
	write_json(state + '/' + kind + '.json', config)!
	before := stable_inputs()!
	write_json(state + '/' + kind + '-inputs-before.json', before)!
	record('suite-' + kind, [state + '/tools/suite', state + '/' + kind + '.json'])!
	assert stable_inputs()! == before
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	write_json(state + '/' + kind + '-inputs-after.json', stable_inputs()!)!
	log := os.read_file(output + '/bootstrap-fixture/serial.log')!
	assert log.count('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-TRACE-ENV-ABSENT-PASS') == 1
	assert log.count('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-CALL') == 1
	raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
	assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
	assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
	outcome := raw[0]['outcome']!.str()
	if kind == 'old' {
		assert log.count('java.lang.NoSuchMethodError:') == 1
		assert log.count('java.lang.NoSuchMethodError: No virtual method getOpticalInsets()Landroid/graphics/Insets; in class Landroid/graphics/drawable/Drawable;') == 1
		assert log.count('ANDROID-WS-FAIL start activity') == 1
		assert log.count('ANDROID-WS-FAIL') == 1
		assert !log.contains('BOOTSTRAP-READY')
		for name in ['DEFAULT', 'DISPATCH'] { assert !log.contains('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-' + name + '-PASS'), name }
		assert !log.contains('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-PASS')
		assert outcome == 'startup_failed', outcome
	} else {
		for name in ['DEFAULT', 'DISPATCH'] { assert log.count('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-' + name + '-PASS') == 1, name }
		assert log.count('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-PASS') == 1
		assert log.count('BOOTSTRAP-READY') == 1
		for bad in ['NoSuchMethodError', 'ANDROID-WS-FAIL'] { assert !log.contains(bad), bad }
		assert outcome == 'window_observed', outcome
	}
	for bad in ['AssertionError', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'VerifyError', 'JNI DETECTED ERROR'] { assert !log.contains(bad), bad }
	write_json(state + '/' + kind + '-semantic-check.json', {'variant': kind, 'status': 'expected-result-pass', 'expectation': if kind == 'old' { 'The first direct Drawable.getOpticalInsets()Insets call throws the exact uncaught NoSuchMethodError; startup_failed is the expected baseline result' } else { 'Drawable defaults return shared Insets.NONE with zero edges, and inherited/overridden getter dispatch and public reflection contracts pass' }, 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!, 'checker_binary_sha256': hash(os.executable())!, 'raw_results_path': output + '/results.json', 'raw_results_sha256': hash(output + '/results.json')!, 'raw_outcome': outcome, 'raw_classifier_scope': 'Unchanged historical suite startup observation, separate from semantic fixture verdict.'})!
	println('DRAWABLE-OPTICAL-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	assert os.args.len >= 2
	match os.args[1] {
		'prepare' { assert os.args.len == 2; prepare()! }
		'stage' { assert os.args.len == 5, 'stage FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA'; stage(os.abs_path(os.args[2]), os.args[3], os.args[4])! }
		'old', 'new' { assert os.args.len == 2; run(os.args[1])! }
		'seal' {
			assert os.args.len == 2
			unsealed()
			for kind in ['old', 'new'] { assert os.exists(state + '/' + kind + '-semantic-check.json') }
			assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
			native_equality()!
			r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
			print(r.output)
			assert r.exit_code == 0
		}
		else { panic('prepare | stage FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA | old | new | seal') }
	}
}
