// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed text hint probe and clean283 launcher; only Framework/Native change.
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

const state = '/Users/alex/.local/state/vinix/android/text-hint305-fixture-2026-10-25'
const failed302 = '/Users/alex/.local/state/vinix/android/text-hint302-fixture-2026-10-25'
const failed302_seal = '6ebca2f735a835a2c86403fa39be40e8f8c9acf213f83b01bdb9690dc882563e'
const failed302_receipt = '/Users/alex/.local/state/vinix/android/text-hint302-failure-2026-10-25.json'
const failed302_receipt_pin = '657b46ec8e04d1cbf701f46a499e01024d685db4625ef81910061cf8daf00b51'
const qualified297 = '/Users/alex/.local/state/vinix/android/path-ops297c-fixture-2026-10-25'
const seal297 = '7511a2dcf20e811fd616f7a006f7d389b8930eff838c3f68ab08958b049876af'
const native296 = 'ddea604e0759bf57587231ed0634f5586771c6266ed88d6bfcecb74ee73e0d0a'
const framework296b = '1a8e5c929c23f842561fbe2ea30f403327a317d3b27984c0280b9dd509b74200'
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
	assert hash(qualified297 + '/' + path)! == pins[path]!, path
	clone(qualified297 + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins { if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin } }
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(qualified297 + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(qualified297 + '/' + path, state + '/' + to)!
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
	assert old['api-impl.jar']! == framework296b
	assert old['popular-launcher']! == launcher283 && new['popular-launcher']! == launcher283
	assert old['libvinix-android-native.so']! == native296
	if os.exists(state + '/qualified302-reference.json') {
		pins := json2.decode[map[string]string](os.read_file(state + '/qualified302-reference.json')!)!
		assert new['api-impl.jar']! == pins['framework_sha256']!
		assert new['libvinix-android-native.so']! == pins['native_sha256']!
	} else {
		assert new['api-impl.jar']! == framework296b
		assert new['libvinix-android-native.so']! == native296
	}
	old.delete('api-impl.jar')
	new.delete('api-impl.jar')
	old.delete('libvinix-android-native.so')
	new.delete('libvinix-android-native.so')
	assert old == new, 'Only Framework and Native may differ between variants'
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
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'tools/text-hint-run-checked', 'base-runtime.tar', 'source/text-hint-fixture.v', 'source/text-hint-run.v', 'config.json', 'host-inputs.json', 'initial-media.json', 'initial-media/boot.img', 'initial-media/efivars.fd', 'previous-failure/receipt.json', 'previous-failure/sha256.json', 'retry-reference.json'] { pins[path] = hash(state + '/' + path)! }
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
	assert hash(failed302 + '/sha256.json')! == failed302_seal
	assert hash(failed302_receipt)! == failed302_receipt_pin
	failed_pins := json2.decode[map[string]string](os.read_file(failed302 + '/sha256.json')!)!
	failure := json2.decode[map[string]string](os.read_file(failed302_receipt)!)!
	assert failure['status']! == 'failed' && failure['manifest_sha256']! == failed302_seal
	assert failure['new_serial_sha256']! == failed_pins['run-new/bootstrap-fixture/serial.log']!
	assert hash(failed302 + '/run-new/bootstrap-fixture/serial.log')! == failure['new_serial_sha256']!
	clone(failed302 + '/sha256.json', state + '/previous-failure/sha256.json')!
	clone(failed302_receipt, state + '/previous-failure/receipt.json')!
	write_json(state + '/retry-reference.json', {'root': failed302, 'manifest_sha256': failed302_seal, 'failure_receipt_sha256': failed302_receipt_pin, 'reason': 'Failed all-ink assertion included the normal EditText underline. This fresh attempt compares full transparent-hint and null-hint ARGB bitmaps, preserving background and cursor pixels while detecting any hint leakage; opaque positive controls remain.'})!
	assert hash(qualified297 + '/sha256.json')! == seal297
	pins := json2.decode[map[string]string](os.read_file(qualified297 + '/sha256.json')!)!
	clone(qualified297 + '/sha256.json', state + '/qualified297-sha256.json')!
	assert pins['native-new/libvinix-android-native.so']! == native296
	assert pins['native-new/api-impl.jar']! == framework296b
	write_json(state + '/qualified-references.json', {'fixture297': qualified297, 'fixture297_manifest': seal297, 'scope': 'Selected consumed files checked against qualified manifest; historical root unchanged. Common clean283 launcher, baseline Framework296b and Native296 retained without rebuild.'})!
	for name in ['text-hint-fixture.v', 'text-hint-run.v'] { clone('tests/native-android-ws/' + name, state + '/source/' + name)! }
	clone(os.executable(), state + '/tools/text-hint-run-bootstrap')!
	for name in ['tools/v_old276', 'tools/suite', 'tools/inflater-trace-seal', 'source/inflater-trace-seal.v', 'source/suite.v', 'base-runtime.tar'] { selected(name, name, pins)! }
	assert hash('tests/native-android-ws/inflater-trace-seal.v')! == hash(state + '/source/inflater-trace-seal.v')!
	selected_tree('source/suite-support', 'source/suite-support', pins)!
	for name in ['qualified282-suite-v-files.json', 'qualified282-suite-compiler-before.json', 'qualified282-suite-compiler-receipt.json', 'qualified282-suite-compiler.log'] { selected(name, name, pins)! }
	selected('new.json', 'qualified297-new.json', pins)!
	selected_tree('native-new', 'native-old', pins)!
	selected_tree('native-new', 'native-new', pins)!
	native_equality()!
	for file in ['boot.img', 'efivars.fd'] { selected('initial-media/' + file, 'initial-media/' + file, pins)! }
	selected('initial-media.json', 'qualified297-initial-media.json', pins)!
	media := json2.decode[map[string]string](os.read_file(state + '/qualified297-initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] { assert hash(state + '/initial-media/' + file)! == media[file]!, file }
	write_json(state + '/initial-media.json', media)!
	selected_tree('fixture-inputs', 'fixture-inputs', pins)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified297-new.json')!)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'), 'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Text hint fixture'), 'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/text-hint-fixture.v'), 'startup_seconds': json2.Any(45)})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	fixture_pins := source_closure('fixture', state + '/source/text-hint-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/text-hint-fixture', state + '/source/text-hint-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	os.setenv('TEXT_HINT_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	record('generate-fixture', [state + '/tools/text-hint-fixture', state + '/apk'])!
	os.unsetenv('TEXT_HINT_FIXTURE_TOOLS_ROOT')
	runner_pins := source_closure('runner', state + '/source/text-hint-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/text-hint-run-checked', state + '/source/text-hint-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('TEXT-HINT-PREPARED')
}

fn unsealed() {
	assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged'
}

fn stage(root string, seal string, native string, framework_root string, framework_seal string, framework string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	pins := qualified_manifest(root, seal)!
	assert native.len == 64 && native != native296 && pins['native/libvinix-android-native.so']! == native
	assert hash(root + '/native/libvinix-android-native.so')! == native
	framework_pins := qualified_manifest(framework_root, framework_seal)!
	assert framework.len == 64 && framework != framework296b && framework_pins['framework/api-impl.jar']! == framework
	assert hash(framework_root + '/framework/api-impl.jar')! == framework
	clone(root + '/sha256.json', state + '/qualified302-native-sha256.json')!
	clone(framework_root + '/sha256.json', state + '/qualified302-framework-sha256.json')!
	os.rm(state + '/native-new/libvinix-android-native.so')!
	clone(root + '/native/libvinix-android-native.so', state + '/native-new/libvinix-android-native.so')!
	assert hash(state + '/native-new/libvinix-android-native.so')! == native
	os.rm(state + '/native-new/api-impl.jar')!
	clone(framework_root + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
	assert hash(state + '/native-new/api-impl.jar')! == framework
	write_json(state + '/qualified302-reference.json', {'native_root': root, 'native_manifest_sha256': seal, 'native_sha256': native, 'framework_root': framework_root, 'framework_manifest_sha256': framework_seal, 'framework_sha256': framework, 'scope': 'Complete sealed build bundles verified at staging; selected native and framework payloads consumed without modifying the historical roots.', 'delta': 'Only api-impl.jar and libvinix-android-native.so change; same signed APK, other runtime files and clean283 launcher.'})!
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('TEXT-HINT-STAGED')
}

fn run(kind string) ! {
	unsealed()
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['text-hint-fixture.v', 'text-hint-run.v'] { assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)! }
	assert hash(os.executable())! == hash(state + '/tools/text-hint-run-checked')!, 'use the checked frozen runner'
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') { removed << key; os.unsetenv(key) }
	}
	write_json(state + '/' + kind + '-environment.json', {'removed_host_trace_variables': json2.Any(removed), 'guest_requirement': json2.Any('APK independently requires every VINIX_ANDROID_TRACE_* variable absent; common clean283 launcher unchanged'), 'launcher_sha256': json2.Any(launcher283)})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/th305-' + kind)
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
	for name in ['TRACE-ENV-ABSENT'] { assert log.count('BOOTSTRAP-TEXT-HINT-' + name + '-PASS') == 1, name }
	if kind == 'old' {
		assert log.count('BOOTSTRAP-TEXT-HINT-EXPECTED-STUB-PASS') == 1
		assert !log.contains('BOOTSTRAP-TEXT-HINT-PASS')
		for name in ['APIS', 'PIXELS', 'COLORS', 'MEASURE', 'CURSOR'] { assert !log.contains('BOOTSTRAP-TEXT-HINT-' + name + '-PASS'), name }
		assert !log.contains('BOOTSTRAP-RIPPLE-RADIUS-PASS')
	} else {
		for name in ['APIS', 'PIXELS', 'COLORS', 'MEASURE', 'CURSOR'] { assert log.count('BOOTSTRAP-TEXT-HINT-' + name + '-PASS') == 1, name }
		assert log.count('BOOTSTRAP-TEXT-HINT-PASS') == 1
		assert log.count('BOOTSTRAP-RIPPLE-RADIUS-PASS') == 1
		assert !log.contains('BOOTSTRAP-TEXT-HINT-EXPECTED-STUB-PASS')
	}
	assert log.count('BOOTSTRAP-READY') == 1
	for bad in ['AssertionError', 'NoSuchMethodError', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'VerifyError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR'] { assert !log.contains(bad), bad }
	write_json(state + '/' + kind + '-semantic-check.json', {'variant': kind, 'status': 'expected-result-pass', 'expectation': if kind == 'old' { 'EditText retains hint text but renders no hint pixels, and base TextView hint API remains a stub; baseline behavior independently recognized by APK' } else { 'TextView and EditText hints preserve API state and render independently raster-checked pixels with hint colors, layout measurement and cursor behavior; inherited RippleDrawable radius accessors preserve instance state and invalidate their callback' }, 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!, 'checker_binary_sha256': hash(os.executable())!, 'raw_results_path': output + '/results.json', 'raw_results_sha256': hash(output + '/results.json')!, 'raw_classifier_scope': 'Unchanged historical suite startup observation, separate from semantic fixture verdict.'})!
	println('TEXT-HINT-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	assert os.args.len >= 2
	match os.args[1] {
		'prepare' { assert os.args.len == 2; prepare()! }
		'stage' { assert os.args.len == 8, 'stage NATIVE_ROOT NATIVE_MANIFEST_SHA NATIVE_SHA FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA'; stage(os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5]), os.args[6], os.args[7])! }
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
		else { panic('prepare | stage NATIVE_ROOT NATIVE_MANIFEST_SHA NATIVE_SHA FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA | old | new | seal') }
	}
}
