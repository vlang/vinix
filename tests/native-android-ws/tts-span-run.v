// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed TtsSpan probe and clean283 launcher; only Framework changes.
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

const state = '/Users/alex/.local/state/vinix/android/tts-span319-v2-fixture-2026-10-25'
const qualified316 = '/Users/alex/.local/state/vinix/android/nine-patch-tint316-fixture-2026-10-25'
const seal316 = 'e75336f72da4e4613b13876de58098425deadafbfb967874609d57e807197e20'
const native315 = '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'
const framework315 = '1e9ebbe318ae030ed22f06bc99553872fa43d820e0981d143586304560161cc6'
const launcher283 = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const groups = ['MAPS', 'CORE', 'BUILDERS', 'PARCEL-WRITE', 'PARCEL-READ', 'PARCEL-NULL', 'PARCEL-EMPTY',
	'SPANS']

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
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
	assert pins.len > 0, root
	// This fresh runner consumes selected inputs from already qualified bundles.
	// Authenticate each consumed file/tree below, and enumerate the complete new
	// evidence bundle at sealing. Historical evidence remains untouched.
	return pins
}

fn selected(path string, to string, pins map[string]string) ! {
	assert hash(qualified316 + '/' + path)! == pins[path]!, path
	clone(qualified316 + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins {
		if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin }
	}
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(qualified316 + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(qualified316 + '/' + path, state + '/' + to)!
	actual.clear()
	inventory(state + '/' + to, '', mut actual)!
	assert actual == expected, to
}

fn record(label string, argv []string) ! {
	assert !os.exists(state + '/' + label + '-receipt.json'), label
	mut receipt := {
		'argv':                        json2.Any(argv)
		'started_utc':                 json2.Any(time.utc().str())
		'VROOT':                       json2.Any(os.getenv('VROOT'))
		'TTS_SPAN_FIXTURE_TOOLS_ROOT': json2.Any(os.getenv('TTS_SPAN_FIXTURE_TOOLS_ROOT'))
		'command_sha256':              json2.Any(hash(os.real_path(argv[0]))!)
	}
	write_json(state + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	if !label.ends_with('-closure') { print(r.output) }
	os.write_file(state + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['command_sha256_after'] = json2.Any(hash(os.real_path(argv[0]))!)
	write_json(state + '/' + label + '-receipt.json', receipt)!
	assert receipt['command_sha256']! == receipt['command_sha256_after']!, 'compiled command changed: ' + argv[0]
	assert r.exit_code == 0, label
}

fn source_closure(label string, source string) !map[string]string {
	record(label + '-closure', [state + '/tools/v_old276', '-print-v-files', source])!
	mut pins := map[string]string{}
	for path in os.read_lines(state + '/' + label + '-closure.log')!.filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := state + '/closure-inputs/' + path.trim_left('/')
		if os.exists(target) {
			assert hash(target)! == pins[path]!, path
		} else {
			clone(path, target)!
		}
	}
	assert pins.len > 0
	write_json(state + '/' + label + '-v-files.json', pins)!
	return pins
}

fn closure_unchanged(label string, pins map[string]string) ! {
	for path, pin in pins {
		assert hash(path)! == pin, path
	}
	write_json(state + '/' + label + '-v-files-after.json', pins)!
}

fn native_equality() ! {
	mut old := map[string]string{}
	mut new := map[string]string{}
	inventory(state + '/native-old', '', mut old)!
	inventory(state + '/native-new', '', mut new)!
	assert old['api-impl.jar']! == framework315
	assert old['libvinix-android-native.so']! == native315 && new['libvinix-android-native.so']! == native315
	assert old['popular-launcher']! == launcher283 && new['popular-launcher']! == launcher283
	if os.exists(state + '/qualified318-reference.json') {
		pins := json2.decode[map[string]string](os.read_file(state + '/qualified318-reference.json')!)!
		assert new['api-impl.jar']! == pins['framework_sha256']!
	} else {
		assert new['api-impl.jar']! == framework315
	}
	old.delete('api-impl.jar')
	new.delete('api-impl.jar')
	assert old == new, 'Only Framework may differ between variants'
	if os.exists(state + '/native-common.json') {
		assert json2.decode[map[string]string](os.read_file(state + '/native-common.json')!)! == old
	} else {
		write_json(state + '/native-common.json', old)!
	}
}

fn stable_inputs() !map[string]string {
	mut pins := map[string]string{}
	for dir in ['native-old', 'native-new', 'fixture-inputs', 'tools'] {
		mut files := map[string]string{}
		inventory(state + '/' + dir, '', mut files)!
		for key, pin in files { pins[dir + '/' + key] = pin }
	}
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'tools/tts-span-run-checked',
		'base-runtime.tar', 'source/tts-span-fixture.v', 'source/tts-span-run.v', 'config.json',
		'host-inputs.json', 'initial-media.json', 'initial-media/boot.img', 'initial-media/efivars.fd'] {
		pins[path] = hash(state + '/' + path)!
	}
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

fn marker_position(log string, marker string) int {
	return log.index(marker) or { panic('missing marker: ' + marker) }
}

fn prepare() ! {
	assert !os.exists(state) && !os.is_link(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	pins := qualified_manifest(qualified316, seal316)!
	clone(qualified316 + '/sha256.json', state + '/qualified316-sha256.json')!
	assert pins['native-new/libvinix-android-native.so']! == native315
	assert pins['native-new/api-impl.jar']! == framework315
	write_json(state + '/qualified-references.json', {
		'fixture316':                qualified316
		'fixture316_manifest':       seal316
		'recorded_baseline_entries': pins.len.str()
		'scope':                     'Pinned historical manifest authenticated; every selected consumed file and complete selected tree rechecked before and after cloning. Full historical bundle was qualified previously and is not rescanned here. Historical root unchanged. Common clean283 launcher, baseline Framework315-v2 and Native315 retained without rebuild.'
	})!
	for name in ['tts-span-fixture.v', 'tts-span-run.v'] {
		clone('tests/native-android-ws/' + name, state + '/source/' + name)!
	}
	clone(os.executable(), state + '/tools/tts-span-run-bootstrap')!
	for name in ['tools/v_old276', 'tools/suite', 'tools/inflater-trace-seal',
		'source/inflater-trace-seal.v', 'source/suite.v', 'base-runtime.tar'] {
		selected(name, name, pins)!
	}
	assert hash('tests/native-android-ws/inflater-trace-seal.v')! == hash(state + '/source/inflater-trace-seal.v')!
	selected_tree('source/suite-support', 'source/suite-support', pins)!
	for name in ['qualified282-suite-v-files.json', 'qualified282-suite-compiler-before.json',
		'qualified282-suite-compiler-receipt.json', 'qualified282-suite-compiler.log'] {
		selected(name, name, pins)!
	}
	selected('new.json', 'qualified316-new.json', pins)!
	selected_tree('native-new', 'native-old', pins)!
	selected_tree('native-new', 'native-new', pins)!
	native_equality()!
	for file in ['boot.img', 'efivars.fd'] {
		selected('initial-media/' + file, 'initial-media/' + file, pins)!
	}
	selected('initial-media.json', 'qualified316-initial-media.json', pins)!
	media := json2.decode[map[string]string](os.read_file(state + '/qualified316-initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] {
		assert hash(state + '/initial-media/' + file)! == media[file]!, file
	}
	write_json(state + '/initial-media.json', media)!
	selected_tree('fixture-inputs', 'fixture-inputs', pins)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified316-new.json')!)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({
		'apk':             json2.Any(state + '/apk/probe.apk')
		'distribution':    json2.Any('Vinix regression fixture')
		'id':              json2.Any('bootstrap-fixture')
		'name':            json2.Any('TtsSpan fixture')
		'package':         json2.Any('org.vinix.bootstrap')
		'source':          json2.Any(state + '/source/tts-span-fixture.v')
		'startup_seconds': json2.Any(45)
	})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	fixture_pins := source_closure('fixture', state + '/source/tts-span-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'-o', state + '/tools/tts-span-fixture', state + '/source/tts-span-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	mut fixture_tools_before := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut fixture_tools_before)!
	write_json(state + '/generate-fixture-tools-before.json', fixture_tools_before)!
	os.setenv('TTS_SPAN_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	record('generate-fixture', [state + '/tools/tts-span-fixture', state + '/apk'])!
	os.unsetenv('TTS_SPAN_FIXTURE_TOOLS_ROOT')
	mut fixture_tools_after := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut fixture_tools_after)!
	write_json(state + '/generate-fixture-tools-after.json', fixture_tools_after)!
	assert fixture_tools_after == fixture_tools_before, 'fixture generation tools changed'
	runner_pins := source_closure('runner', state + '/source/tts-span-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'-o', state + '/tools/tts-span-run-checked', state + '/source/tts-span-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('TTS-SPAN-PREPARED')
}

fn unsealed() {
	assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged'
}

fn stage(root string, seal string, framework string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	pins := qualified_manifest(root, seal)!
	assert framework.len == 64 && framework != framework315 && pins['framework/api-impl.jar']! == framework
	assert hash(root + '/framework/api-impl.jar')! == framework
	clone(root + '/sha256.json', state + '/qualified318-framework-sha256.json')!
	os.rm(state + '/native-new/api-impl.jar')!
	clone(root + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
	assert hash(state + '/native-new/api-impl.jar')! == framework
	write_json(state + '/qualified318-reference.json', {
		'framework_root':             root
		'framework_manifest_sha256':  seal
		'framework_sha256':           framework
		'framework_recorded_entries': pins.len.str()
		'scope':                      'Pinned build manifest and selected Framework payload hash authenticated before and after staging; complete build bundle is independently checked separately. Historical root unchanged.'
		'delta':                      'Only api-impl.jar changes; same Native315, signed APK, other runtime files and clean283 launcher.'
	})!
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('TTS-SPAN-STAGED')
}

fn run(kind string) ! {
	unsealed()
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['tts-span-fixture.v', 'tts-span-run.v'] {
		assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)!
	}
	assert hash(os.executable())! == hash(state + '/tools/tts-span-run-checked')!, 'use the checked frozen runner'
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') {
			removed << key
			os.unsetenv(key)
		}
	}
	write_json(state + '/' + kind + '-environment.json', {
		'removed_host_trace_variables': json2.Any(removed)
		'guest_requirement':            json2.Any('APK independently requires every VINIX_ANDROID_TRACE_* variable absent; common clean283 launcher unchanged')
		'launcher_sha256':              json2.Any(launcher283)
	})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/ts319v2-' + kind)
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
	assert log.count('BOOTSTRAP-TTS-SPAN-TRACE-ENV-ABSENT-PASS') == 1
	assert log.count('BOOTSTRAP-TTS-SPAN-CALL') == 1
	assert marker_position(log, 'BOOTSTRAP-TTS-SPAN-TRACE-ENV-ABSENT-PASS') < marker_position(log, 'BOOTSTRAP-TTS-SPAN-CALL')
	raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
	assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
	assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
	outcome := raw[0]['outcome']!.str()
	if kind == 'old' {
		assert log.count('java.lang.NoClassDefFoundError:') == 1
		assert log.count('java.lang.NoClassDefFoundError: Failed resolution of: Landroid/text/style/TtsSpan;') == 1
		assert log.count('java.lang.ClassNotFoundException:') == 1
		assert log.count('java.lang.ClassNotFoundException: android.text.style.TtsSpan') == 1
		assert log.count('ANDROID-WS-FAIL start activity') == 1
		assert log.count('ANDROID-WS-FAIL') == 1
		assert !log.contains('BOOTSTRAP-READY')
		assert !log.contains('BOOTSTRAP-TTS-SPAN-PASS')
		assert !log.contains('AssertionError')
		for name in groups {
			assert !log.contains('BOOTSTRAP-TTS-SPAN-' + name + '-PASS'), name
		}
		assert outcome == 'startup_failed', outcome
	} else {
		mut previous := marker_position(log, 'BOOTSTRAP-TTS-SPAN-CALL')
		for name in groups {
			marker := 'BOOTSTRAP-TTS-SPAN-' + name + '-PASS'
			assert log.count(marker) == 1, name
			position := marker_position(log, marker)
			assert position > previous, 'ordered fixture marker: ' + name
			previous = position
		}
		assert log.count('BOOTSTRAP-TTS-SPAN-PASS') == 1
		assert log.count('BOOTSTRAP-READY') == 1
		assert marker_position(log, 'BOOTSTRAP-TTS-SPAN-PASS') > previous
		assert marker_position(log, 'BOOTSTRAP-READY') > marker_position(log, 'BOOTSTRAP-TTS-SPAN-PASS')
		assert outcome == 'window_observed', outcome
		for bad in ['AssertionError', 'NoSuchMethodError', 'NoClassDefFoundError',
			'ClassNotFoundException', 'ANDROID-WS-FAIL'] {
			assert !log.contains(bad), bad
		}
	}
	for bad in ['NoSuchMethodError', 'UnsatisfiedLinkError', 'VerifyError', 'JNI DETECTED ERROR'] {
		assert !log.contains(bad), bad
	}
	write_json(state + '/' + kind + '-semantic-check.json', {
		'variant':               kind
		'status':                'expected-result-pass'
		'expectation':           if kind == 'old' {
			'TtsSpan is absent and triggers the exact first missing-class failure; startup_failed is the expected baseline result'
		} else {
			'Maps constructor, core values, typed builder arguments, Parcelable write/read/null/empty behavior and span retention pass in exact marker order'
		}
		'serial_sha256':         hash(output + '/bootstrap-fixture/serial.log')!
		'checker_binary_sha256': hash(os.executable())!
		'raw_results_path':      output + '/results.json'
		'raw_results_sha256':    hash(output + '/results.json')!
		'raw_outcome':           outcome
		'raw_classifier_scope':  'Unchanged historical suite startup observation, separate from semantic fixture verdict.'
	})!
	println('TTS-SPAN-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	os.setenv('VROOT', '/Users/alex/code/v', true)
	assert os.args.len >= 2
	match os.args[1] {
		'prepare' {
			assert os.args.len == 2
			prepare()!
		}
		'stage' {
			assert os.args.len == 5, 'stage FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA'
			stage(os.abs_path(os.args[2]), os.args[3], os.args[4])!
		}
		'old', 'new' {
			assert os.args.len == 2
			run(os.args[1])!
		}
		'seal' {
			assert os.args.len == 2
			unsealed()
			for kind in ['old', 'new'] {
				assert os.exists(state + '/' + kind + '-semantic-check.json')
			}
			assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
			native_equality()!
			r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
			print(r.output)
			assert r.exit_code == 0
		}
		else {
			panic('prepare | stage FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA | old | new | seal')
		}
	}
}
