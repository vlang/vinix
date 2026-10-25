// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed PNG probe, Framework290 and clean283 launcher; only Native changes.
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

const state = '/Users/alex/.local/state/vinix/android/bitmap-png294-fixture-2026-10-25'
const qualified292 = '/Users/alex/.local/state/vinix/android/inflater-trace292-fixture-2026-10-25'
const seal292 = '6aad28bbd334fbaff5d07bd89f2b4cfb11f89c861e9a5abac86cb51ee967ef45'
const qualified286 = '/Users/alex/.local/state/vinix/android/input286-build-2026-10-25'
const seal286 = 'd7ce481cec4c1c687d6647ddded15f3dc61393ce91678767c2681b04cf9019f8'
const native286 = 'c46f56d775efef3807e34ece9c8bb5bdb949c47f6db54e59dee02e82cf60019a'
const framework290 = '50fe71a5719b74fb4fe0cfd0531213b216cad87ee87fc78e5cb348f38237b232'
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

fn selected(path string, to string, pins map[string]string) ! {
	assert hash(qualified292 + '/' + path)! == pins[path]!, path
	clone(qualified292 + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins { if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin } }
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(qualified292 + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(qualified292 + '/' + path, state + '/' + to)!
	actual.clear()
	inventory(state + '/' + to, '', mut actual)!
	assert actual == expected, to
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
	assert old['api-impl.jar']! == framework290 && new['api-impl.jar']! == framework290
	assert old['popular-launcher']! == launcher283 && new['popular-launcher']! == launcher283
	assert old['libvinix-android-native.so']! == native286
	old.delete('libvinix-android-native.so')
	new.delete('libvinix-android-native.so')
	assert old == new, 'Native library must be the only variant input delta'
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
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'tools/bitmap-png-run-checked', 'base-runtime.tar', 'source/bitmap-png-fixture.v', 'source/bitmap-png-run.v', 'config.json', 'host-inputs.json', 'initial-media.json', 'initial-media/boot.img', 'initial-media/efivars.fd'] { pins[path] = hash(state + '/' + path)! }
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
	assert !os.exists(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	assert hash(qualified292 + '/sha256.json')! == seal292
	pins := json2.decode[map[string]string](os.read_file(qualified292 + '/sha256.json')!)!
	clone(qualified292 + '/sha256.json', state + '/qualified292-sha256.json')!
	assert hash(qualified286 + '/sha256.json')! == seal286
	old := json2.decode[map[string]string](os.read_file(qualified286 + '/sha256.json')!)!
	assert old['native/libvinix-android-native.so']! == native286
	assert hash(qualified286 + '/native/libvinix-android-native.so')! == native286
	clone(qualified286 + '/sha256.json', state + '/qualified286-sha256.json')!
	write_json(state + '/qualified-references.json', {'fixture292': qualified292, 'fixture292_manifest': seal292, 'native286': qualified286, 'native286_manifest': seal286, 'scope': 'Selected consumed files checked against qualified manifests; historical roots unchanged. Common clean283 launcher and Framework290 retained without rebuild.'})!
	for name in ['bitmap-png-fixture.v', 'bitmap-png-run.v'] { clone('tests/native-android-ws/' + name, state + '/source/' + name)! }
	clone(os.executable(), state + '/tools/bitmap-png-run-bootstrap')!
	for name in ['tools/v_old276', 'tools/suite', 'tools/inflater-trace-seal', 'source/inflater-trace-seal.v', 'source/suite.v', 'base-runtime.tar'] { selected(name, name, pins)! }
	assert hash('tests/native-android-ws/inflater-trace-seal.v')! == hash(state + '/source/inflater-trace-seal.v')!
	selected_tree('source/suite-support', 'source/suite-support', pins)!
	for name in ['qualified282-suite-v-files.json', 'qualified282-suite-compiler-before.json', 'qualified282-suite-compiler-receipt.json', 'qualified282-suite-compiler.log'] { selected(name, name, pins)! }
	selected('new.json', 'qualified292-new.json', pins)!
	selected_tree('native-new', 'native-old', pins)!
	selected_tree('native-new', 'native-new', pins)!
	native_equality()!
	for file in ['boot.img', 'efivars.fd'] { selected('vm-old/' + file, 'initial-media/' + file, pins)! }
	selected('initial-media.json', 'qualified292-initial-media.json', pins)!
	media := json2.decode[map[string]string](os.read_file(state + '/qualified292-initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] { assert hash(state + '/initial-media/' + file)! == media[file]!, file }
	write_json(state + '/initial-media.json', media)!
	clone('build/android-native-ws/aapt2', state + '/fixture-inputs/aapt2')!
	clone('build/android-native-ws/android-15/lib/apksigner.jar', state + '/fixture-inputs/apksigner.jar')!
	clone('/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk', state + '/fixture-inputs/framework-res.apk')!
	for name in os.ls('build/android-framework/tools')!.filter(it.ends_with('.jar')) { clone('build/android-framework/tools/' + name, state + '/fixture-inputs/smali/' + name)! }
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified292-new.json')!)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'), 'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Bitmap PNG fixture'), 'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/bitmap-png-fixture.v'), 'startup_seconds': json2.Any(45)})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	fixture_pins := source_closure('fixture', state + '/source/bitmap-png-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/bitmap-png-fixture', state + '/source/bitmap-png-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	os.setenv('BITMAP_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	record('generate-fixture', [state + '/tools/bitmap-png-fixture', state + '/apk'])!
	os.unsetenv('BITMAP_FIXTURE_TOOLS_ROOT')
	runner_pins := source_closure('runner', state + '/source/bitmap-png-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/tools/bitmap-png-run-checked', state + '/source/bitmap-png-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('BITMAP-PNG-PREPARED')
}

fn stage(root string, seal string, native string) ! {
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	assert seal.len == 64 && hash(root + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	assert native.len == 64 && native != native286 && pins['native/libvinix-android-native.so']! == native
	assert hash(root + '/native/libvinix-android-native.so')! == native
	clone(root + '/sha256.json', state + '/qualified293-sha256.json')!
	os.rm(state + '/native-new/libvinix-android-native.so')!
	clone(root + '/native/libvinix-android-native.so', state + '/native-new/libvinix-android-native.so')!
	assert hash(state + '/native-new/libvinix-android-native.so')! == native
	write_json(state + '/qualified293-reference.json', {'root': root, 'manifest_sha256': seal, 'native_sha256': native, 'delta': 'Only libvinix-android-native.so changes; same signed APK, Framework290 and clean283 launcher.'})!
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('BITMAP-PNG-STAGED')
}

fn run(kind string) ! {
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['bitmap-png-fixture.v', 'bitmap-png-run.v'] { assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)! }
	assert hash(os.executable())! == hash(state + '/tools/bitmap-png-run-checked')!, 'use the checked frozen runner'
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') { removed << key; os.unsetenv(key) }
	}
	write_json(state + '/' + kind + '-environment.json', {'removed_host_trace_variables': json2.Any(removed), 'guest_requirement': json2.Any('APK independently requires every VINIX_ANDROID_TRACE_* variable absent; common clean283 launcher unchanged'), 'launcher_sha256': json2.Any(launcher283)})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/bp294-' + kind)
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
	for name in ['TRACE-ENV-ABSENT'] { assert log.count('BOOTSTRAP-BITMAP-PNG-' + name + '-PASS') == 1, name }
	if kind == 'old' {
		assert log.count('BOOTSTRAP-BITMAP-PNG-EXPECTED-MISSING-NATIVE-PASS') == 1
		assert !log.contains('BOOTSTRAP-BITMAP-PNG-POSITIVE-PASS')
	} else {
		for name in ['RGBA', 'QUALITY', 'ONE-PIXEL', 'ALPHA8-PADDED', 'CONTRACTS', 'POSITIVE'] { assert log.count('BOOTSTRAP-BITMAP-PNG-' + name + '-PASS') == 1, name }
		assert !log.contains('BOOTSTRAP-BITMAP-PNG-EXPECTED-MISSING-NATIVE-PASS')
		assert !log.contains('UnsatisfiedLinkError')
	}
	assert log.count('BOOTSTRAP-READY') == 1
	for bad in ['AssertionError', 'NoSuchMethodError', 'NoClassDefFoundError', 'VerifyError', 'ANDROID-WS-FAIL', 'JNI DETECTED ERROR'] { assert !log.contains(bad), bad }
	write_json(state + '/' + kind + '-semantic-check.json', {'variant': kind, 'status': 'expected-result-pass', 'expectation': if kind == 'old' { 'exact missing native_save_to_png UnsatisfiedLinkError caught by APK' } else { 'actual PNG independently decoded and contract checks passed' }, 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!, 'checker_binary_sha256': hash(os.executable())!, 'raw_results_path': output + '/results.json', 'raw_results_sha256': hash(output + '/results.json')!, 'raw_classifier_scope': 'Unchanged historical suite startup observation, separate from semantic fixture verdict.'})!
	println('BITMAP-PNG-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	assert os.args.len >= 2
	match os.args[1] {
		'prepare' { assert os.args.len == 2; prepare()! }
		'stage' { assert os.args.len == 5, 'stage QUALIFIED293 MANIFEST_SHA NATIVE_SHA'; stage(os.abs_path(os.args[2]), os.args[3], os.args[4])! }
		'old', 'new' { assert os.args.len == 2; run(os.args[1])! }
		else { panic('prepare | stage QUALIFIED293 MANIFEST_SHA NATIVE_SHA | old | new') }
	}
}
