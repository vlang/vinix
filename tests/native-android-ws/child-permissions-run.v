// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed child drawing order/permissions probe and clean283 launcher; only Framework changes.
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

const state = '/Users/alex/.local/state/vinix/android/child-permissions326-fixture-2026-10-25'
const qualified319 = '/Users/alex/.local/state/vinix/android/tts-span319-v2-fixture-2026-10-25'
const seal319 = 'b293ffbdba4571658605e0fac2ddd3c5a91847b5d8e0f07bed3819b07197d42a'
const native315 = '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'
const framework318 = '6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d'
const framework322 = '8f814c91a597f4c4fee0adde46789d144b4256586fc7816e0a60c2f3d661d7c8'
const launcher283 = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const child_groups = ['TRACE-ENV-ABSENT-PASS', 'CALL', 'INHERITED-PASS', 'OVERRIDE-SUPER-PASS',
	'PASS']
const permission_groups = ['TRACE-ENV-ABSENT-PASS', 'POLICY-PASS', 'CALL', 'RESULTS-PASS',
	'SNAPSHOT-PASS', 'MAIN-ASYNC-PASS', 'BASE-PASS', 'VALIDATION-PASS', 'REENTRANT-PASS', 'OVERLAP-PASS',
	'PASS']

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
	assert hash(qualified319 + '/' + path)! == pins[path]!, path
	clone(qualified319 + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins {
		if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin }
	}
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(qualified319 + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(qualified319 + '/' + path, state + '/' + to)!
	actual.clear()
	inventory(state + '/' + to, '', mut actual)!
	assert actual == expected, to
}

fn record(label string, argv []string) ! {
	assert !os.exists(state + '/' + label + '-receipt.json'), label
	mut receipt := {
		'argv':                                      json2.Any(argv)
		'started_utc':                               json2.Any(time.utc().str())
		'VROOT':                                     json2.Any(os.getenv('VROOT'))
		'CHILD_DRAWING_ORDER_FIXTURE_TOOLS_ROOT':    json2.Any(os.getenv('CHILD_DRAWING_ORDER_FIXTURE_TOOLS_ROOT'))
		'CHILD_DRAWING_ORDER_PERMISSION_SMALI_ROOT': json2.Any(os.getenv('CHILD_DRAWING_ORDER_PERMISSION_SMALI_ROOT'))
		'command_sha256':                            json2.Any(hash(os.real_path(argv[0]))!)
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
	if os.exists(state + '/qualified322-reference.json') {
		assert old['api-impl.jar']! == framework322
	} else {
		assert old['api-impl.jar']! == framework318
	}
	assert old['libvinix-android-native.so']! == native315 && new['libvinix-android-native.so']! == native315
	assert old['popular-launcher']! == launcher283 && new['popular-launcher']! == launcher283
	if os.exists(state + '/qualified325-reference.json') {
		pins := json2.decode[map[string]string](os.read_file(state + '/qualified325-reference.json')!)!
		assert new['api-impl.jar']! == pins['framework_sha256']!
	} else {
		assert new['api-impl.jar']! == framework318
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
	for dir in ['native-old', 'native-new', 'fixture-inputs', 'permission-smali', 'tools'] {
		mut files := map[string]string{}
		inventory(state + '/' + dir, '', mut files)!
		for key, pin in files { pins[dir + '/' + key] = pin }
	}
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'tools/child-permissions-run-checked',
		'base-runtime.tar', 'source/child-drawing-order-fixture.v',
		'source/activity-permissions-fixture.v', 'source/child-permissions-run.v', 'config.json',
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

fn ordered_markers(log string, prefix string, names []string, after int) int {
	mut previous := after
	for name in names {
		marker := prefix + name
		assert log.count(marker) == 1, marker
		position := marker_position(log, marker)
		assert position > previous, 'ordered fixture marker: ' + marker
		previous = position
	}
	return previous
}

fn prepare() ! {
	assert !os.exists(state) && !os.is_link(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	pins := qualified_manifest(qualified319, seal319)!
	clone(qualified319 + '/sha256.json', state + '/qualified319-sha256.json')!
	assert pins['native-new/libvinix-android-native.so']! == native315
	assert pins['native-new/api-impl.jar']! == framework318
	write_json(state + '/qualified-references.json', {
		'fixture319':                qualified319
		'fixture319_manifest':       seal319
		'recorded_baseline_entries': pins.len.str()
		'scope':                     'Pinned historical manifest authenticated; every selected consumed file and complete selected tree rechecked before and after cloning. Full historical bundle was qualified previously and is not rescanned here. Historical root unchanged. Common clean283 launcher and Native315 retained without rebuild; starting Framework318-v2 payloads are replaced by qualified322 for both variants, then qualified325 for new only before either guest starts.'
	})!
	for name in ['child-drawing-order-fixture.v', 'activity-permissions-fixture.v',
		'child-permissions-run.v'] {
		clone('tests/native-android-ws/' + name, state + '/source/' + name)!
	}
	clone(os.executable(), state + '/tools/child-permissions-run-bootstrap')!
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
	selected('new.json', 'qualified319-new.json', pins)!
	selected_tree('native-new', 'native-old', pins)!
	selected_tree('native-new', 'native-new', pins)!
	native_equality()!
	for file in ['boot.img', 'efivars.fd'] {
		selected('initial-media/' + file, 'initial-media/' + file, pins)!
	}
	selected('initial-media.json', 'qualified319-initial-media.json', pins)!
	media := json2.decode[map[string]string](os.read_file(state + '/qualified319-initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] {
		assert hash(state + '/initial-media/' + file)! == media[file]!, file
	}
	write_json(state + '/initial-media.json', media)!
	selected_tree('fixture-inputs', 'fixture-inputs', pins)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified319-new.json')!)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({
		'apk':             json2.Any(state + '/apk/probe.apk')
		'distribution':    json2.Any('Vinix regression fixture')
		'id':              json2.Any('bootstrap-fixture')
		'name':            json2.Any('Child drawing order and permissions fixture')
		'package':         json2.Any('org.vinix.bootstrap')
		'source':          json2.Any(state + '/source/child-drawing-order-fixture.v')
		'startup_seconds': json2.Any(45)
	})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	permission_pins := source_closure('permission-fixture', state + '/source/activity-permissions-fixture.v')!
	record('compile-permission-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags',
		'-O2', '-o', state + '/tools/activity-permissions-fixture',
		state + '/source/activity-permissions-fixture.v'])!
	closure_unchanged('permission-fixture', permission_pins)!
	record('generate-permission-smali', [
		state + '/tools/activity-permissions-fixture',
		state + '/permission-smali',
	])!
	mut permission_smali_before := map[string]string{}
	inventory(state + '/permission-smali', '', mut permission_smali_before)!
	permission_manifest := json2.decode[map[string]string](os.read_file(state + '/permission-smali/sources.json')!)!
	assert permission_manifest.len == 3 && permission_smali_before.len == 4
	for name in ['PermissionProbe', 'PermissionBaseActivity', 'PermissionCompletion'] {
		key := 'org/vinix/bootstrap/' + name + '.smali'
		assert permission_manifest[key]! == permission_smali_before[key]!, key
	}
	write_json(state + '/generate-permission-smali-before.json', permission_smali_before)!
	fixture_pins := source_closure('fixture', state + '/source/child-drawing-order-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'-o', state + '/tools/child-drawing-order-fixture',
		state + '/source/child-drawing-order-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	mut fixture_tools_before := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut fixture_tools_before)!
	write_json(state + '/generate-fixture-tools-before.json', fixture_tools_before)!
	os.setenv('CHILD_DRAWING_ORDER_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	os.setenv('CHILD_DRAWING_ORDER_PERMISSION_SMALI_ROOT', state + '/permission-smali', true)
	record('generate-fixture', [state + '/tools/child-drawing-order-fixture', state + '/apk'])!
	os.unsetenv('CHILD_DRAWING_ORDER_FIXTURE_TOOLS_ROOT')
	os.unsetenv('CHILD_DRAWING_ORDER_PERMISSION_SMALI_ROOT')
	mut permission_smali_after := map[string]string{}
	inventory(state + '/permission-smali', '', mut permission_smali_after)!
	write_json(state + '/generate-permission-smali-after.json', permission_smali_after)!
	assert permission_smali_after == permission_smali_before, 'permission smali changed during combined fixture build'
	mut fixture_tools_after := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut fixture_tools_after)!
	write_json(state + '/generate-fixture-tools-after.json', fixture_tools_after)!
	assert fixture_tools_after == fixture_tools_before, 'fixture generation tools changed'
	runner_pins := source_closure('runner', state + '/source/child-permissions-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'-o', state + '/tools/child-permissions-run-checked',
		state + '/source/child-permissions-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('CHILD-PERMISSIONS-PREPARED')
}

fn unsealed() {
	assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged'
}

fn stage(old_root string, old_seal string, old_framework string, new_root string, new_seal string, new_framework string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	old_pins := qualified_manifest(old_root, old_seal)!
	assert old_framework == framework322 && old_pins['framework/api-impl.jar']! == old_framework
	assert hash(old_root + '/framework/api-impl.jar')! == old_framework
	clone(old_root + '/sha256.json', state + '/qualified322-framework-sha256.json')!
	for kind in ['old', 'new'] {
		os.rm(state + '/native-' + kind + '/api-impl.jar')!
		clone(old_root + '/framework/api-impl.jar', state + '/native-' + kind + '/api-impl.jar')!
		assert hash(state + '/native-' + kind + '/api-impl.jar')! == old_framework
	}
	write_json(state + '/qualified322-reference.json', {
		'framework_root':             old_root
		'framework_manifest_sha256':  old_seal
		'framework_sha256':           old_framework
		'framework_recorded_entries': old_pins.len.str()
		'scope':                      'Pinned build manifest and selected Framework payload hash authenticated before and after staging; complete build bundle is independently checked separately. Historical root unchanged.'
		'delta':                      'Qualified322 staged into both variants before qualified325 overlays new only; same Native315, signed APK, other runtime files and clean283 launcher.'
	})!
	mut old_before := map[string]string{}
	mut new_before := map[string]string{}
	inventory(state + '/native-old', '', mut old_before)!
	inventory(state + '/native-new', '', mut new_before)!
	assert old_before == new_before
	write_json(state + '/staged322-native-inputs.json', old_before)!
	new_pins := qualified_manifest(new_root, new_seal)!
	assert new_framework.len == 64 && new_framework !in [framework318, framework322]
	assert new_pins['framework/api-impl.jar']! == new_framework
	assert hash(new_root + '/framework/api-impl.jar')! == new_framework
	clone(new_root + '/sha256.json', state + '/qualified325-framework-sha256.json')!
	os.rm(state + '/native-new/api-impl.jar')!
	clone(new_root + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
	assert hash(state + '/native-new/api-impl.jar')! == new_framework
	write_json(state + '/qualified325-reference.json', {
		'framework_root':             new_root
		'framework_manifest_sha256':  new_seal
		'framework_sha256':           new_framework
		'framework_recorded_entries': new_pins.len.str()
		'scope':                      'Pinned build manifest and selected Framework payload hash authenticated before and after staging; complete build bundle is independently checked separately. Historical root unchanged.'
		'delta':                      'Only api-impl.jar differs between old322 and new325; same Native315, signed APK, other runtime files and clean283 launcher.'
	})!
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('CHILD-PERMISSIONS-STAGED')
}

fn run(kind string) ! {
	unsealed()
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['child-drawing-order-fixture.v', 'activity-permissions-fixture.v',
		'child-permissions-run.v'] {
		assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)!
	}
	assert hash(os.executable())! == hash(state + '/tools/child-permissions-run-checked')!, 'use the checked frozen runner'
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' {
			removed << key
			os.unsetenv(key)
		}
	}
	write_json(state + '/' + kind + '-environment.json', {
		'removed_host_trace_variables': json2.Any(removed)
		'guest_requirement':            json2.Any('APK independently requires every VINIX_ANDROID_TRACE_* variable and ATL_UGLY_ENABLE_LOCATION absent; common clean283 launcher unchanged')
		'launcher_sha256':              json2.Any(launcher283)
	})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/cp326-' + kind)
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
	assert log.count('BOOTSTRAP-CHILD-DRAWING-ORDER-ATTEMPT') == 1
	attempt := marker_position(log, 'BOOTSTRAP-CHILD-DRAWING-ORDER-ATTEMPT')
	raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
	assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
	assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
	assert raw[0]['launcher_entered']!.bool()
	assert raw[0]['native_maps_observed']!.bool()
	assert raw[0]['qemu_alive_before_capture']!.bool()
	outcome := raw[0]['outcome']!.str()
	if kind == 'old' {
		child_call := ordered_markers(log, 'BOOTSTRAP-CHILD-DRAWING-ORDER-', child_groups[..2], attempt)
		assert log.count('BOOTSTRAP-CHILD-DRAWING-ORDER-MISSING') == 1
		missing := marker_position(log, 'BOOTSTRAP-CHILD-DRAWING-ORDER-MISSING')
		assert missing > child_call
		for name in child_groups[2..] {
			assert !log.contains('BOOTSTRAP-CHILD-DRAWING-ORDER-' + name), name
		}
		permission_call := ordered_markers(log, 'BOOTSTRAP-PERMISSIONS-', permission_groups[..3], missing)
		assert log.count('BOOTSTRAP-PERMISSIONS-NO-CALLBACK') == 1
		assert marker_position(log, 'BOOTSTRAP-PERMISSIONS-NO-CALLBACK') > permission_call
		for name in permission_groups[3..] {
			assert !log.contains('BOOTSTRAP-PERMISSIONS-' + name), name
		}
		assert log.count('java.lang.AssertionError:') == 1
		assert log.count('java.lang.AssertionError: requestPermissions did not deliver callback') == 1
		assert marker_position(log, 'java.lang.AssertionError: requestPermissions did not deliver callback') > marker_position(log, 'BOOTSTRAP-PERMISSIONS-NO-CALLBACK')
		assert log.count('APK-SUITE-EXIT id=bootstrap-fixture code=1 ') == 1
		assert marker_position(log, 'APK-SUITE-EXIT id=bootstrap-fixture code=1 ') > marker_position(log, 'java.lang.AssertionError: requestPermissions did not deliver callback')
		assert !log.contains('ANDROID-WS-FAIL')
		assert !log.contains('BOOTSTRAP-READY')
		assert !log.contains('BOOTSTRAP-CHILD-PERMISSIONS-PASS')
		assert outcome == 'startup_failed', outcome
		assert raw[0]['process_exited']!.bool()
		assert raw[0]['failure_markers']!.as_array().len == 1
		assert raw[0]['failure_markers']!.as_array()[0].str().starts_with('APK-SUITE-EXIT id=bootstrap-fixture code=1 ')
	} else {
		assert !log.contains('BOOTSTRAP-CHILD-DRAWING-ORDER-MISSING')
		assert !log.contains('BOOTSTRAP-PERMISSIONS-NO-CALLBACK')
		child_pass := ordered_markers(log, 'BOOTSTRAP-CHILD-DRAWING-ORDER-', child_groups, attempt)
		previous := ordered_markers(log, 'BOOTSTRAP-PERMISSIONS-', permission_groups, child_pass)
		assert log.count('BOOTSTRAP-CHILD-PERMISSIONS-PASS') == 1
		assert log.count('BOOTSTRAP-READY') == 1
		assert marker_position(log, 'BOOTSTRAP-CHILD-PERMISSIONS-PASS') > previous
		assert marker_position(log, 'BOOTSTRAP-READY') > marker_position(log, 'BOOTSTRAP-CHILD-PERMISSIONS-PASS')
		assert outcome == 'window_observed', outcome
		assert !raw[0]['process_exited']!.bool()
		assert raw[0]['backend_ready']!.bool()
		assert raw[0]['failure_markers']!.as_array().len == 0
		for bad in ['AssertionError', 'ANDROID-WS-FAIL'] {
			assert !log.contains(bad), bad
		}
	}
	for bad in ['NoSuchMethodError', 'NoClassDefFoundError', 'ClassNotFoundException',
		'UnsatisfiedLinkError', 'VerifyError', 'JNI DETECTED ERROR'] {
		assert !log.contains(bad), bad
	}
	write_json(state + '/' + kind + '-semantic-check.json', {
		'variant':               kind
		'status':                'expected-result-pass'
		'expectation':           if kind == 'old' {
			'Baseline exactly catches missing getChildDrawingOrder(II)I, then permission deadline reports no callback with the exact asynchronous assertion and controlled exit code 1; startup_failed is the expected baseline result'
		} else {
			'Child inherited/default/override/super dispatch and asynchronous permission policy, snapshots, main-thread delivery, base callback, validation, reentrancy and overlap groups pass in exact order before combined PASS and READY'
		}
		'serial_sha256':         hash(output + '/bootstrap-fixture/serial.log')!
		'checker_binary_sha256': hash(os.executable())!
		'raw_results_path':      output + '/results.json'
		'raw_results_sha256':    hash(output + '/results.json')!
		'raw_outcome':           outcome
		'raw_classifier_scope':  'Unchanged historical suite startup observation, separate from semantic fixture verdict.'
	})!
	println('CHILD-PERMISSIONS-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
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
			assert os.args.len == 8, 'stage OLD_FRAMEWORK_ROOT OLD_MANIFEST_SHA OLD_FRAMEWORK_SHA NEW_FRAMEWORK_ROOT NEW_MANIFEST_SHA NEW_FRAMEWORK_SHA'
			stage(os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5]), os.args[6], os.args[7])!
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
			panic('prepare | stage OLD_FRAMEWORK_ROOT OLD_MANIFEST_SHA OLD_FRAMEWORK_SHA NEW_FRAMEWORK_ROOT NEW_MANIFEST_SHA NEW_FRAMEWORK_SHA | old | new | seal')
		}
	}
}
