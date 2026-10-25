// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed system-resource/dialog probe and clean283 launcher; only Framework changes.
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

const state = '/Users/alex/.local/state/vinix/android/system-package330-fixture-2026-10-25'
const qualified319 = '/Users/alex/.local/state/vinix/android/tts-span319-v2-fixture-2026-10-25'
const seal319 = 'b293ffbdba4571658605e0fac2ddd3c5a91847b5d8e0f07bed3819b07197d42a'
const seal325 = '17df965baca0c030e1111a9b974410e9594b6e9ccfb814d371df6a53b0ead682'
const native315 = '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'
const framework318 = '6b826b2b7c37eb6b101d2627854064d1d06988f7c8bbdf1b94c1dea012e86b5d'
const framework325 = '181743124944671e934bc6003f6915511f3b43aabd060842e793309b8d988cfa'
const launcher283 = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const groups = ['TRACE-ENV-ABSENT-PASS', 'CALL', 'CACHE-PASS', 'RESOURCES-PASS',
	'UNSIGNED-METADATA-PASS', 'DIALOG-CREATE-PASS', 'PASS']

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

// Focused 45-second fixture only. Historical326 retained about170MiB of module
// and results per variant; APFS cloned VM writes add an uncertain increment.
// Estimate700MiB for the pair, with1536MiB before preparation and1024MiB before
// each guest. This does not change the independent Maps5120MiB replay gate.
fn disk_checkpoint(label string, minimum_mib u64) ! {
	r := os.exec(['/bin/df', '-k', state])
	assert r.exit_code == 0, r.output
	fields := r.output.trim_space().split_into_lines().last().fields()
	assert fields.len >= 4
	available := fields[3].u64()
	assert available >= minimum_mib * 1024, 'fixture requires ' + minimum_mib.str() + ' MiB free; available KiB=' + available.str()
	write_json(state + '/disk-' + label + '.json', {
		'utc': json2.Any(time.utc().str())
		'minimum_mib': json2.Any(minimum_mib)
		'available_kib': json2.Any(available)
		'estimated_pair_peak_mib': json2.Any(700)
		'raw': json2.Any(r.output)
		'scope': json2.Any('Focused paired45-second fixture estimate; Maps5120MiB gate unchanged')
	})!
}

fn qualified_manifest(root string, seal string) !map[string]string {
	assert seal.len == 64 && hash(root + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	assert pins.len > 0, root
	// Authenticate every consumed file/tree below; retain the complete new bundle.
	// No historical bundle is modified or replaced by a selected-input check.
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
		'argv': json2.Any(argv)
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VTMP': json2.Any(os.getenv('VTMP'))
		'SYSTEM_PACKAGE_FIXTURE_TOOLS_ROOT': json2.Any(os.getenv('SYSTEM_PACKAGE_FIXTURE_TOOLS_ROOT'))
		'SYSTEM_PACKAGE_FIXTURE_JAVA': json2.Any(os.getenv('SYSTEM_PACKAGE_FIXTURE_JAVA'))
		'command_sha256': json2.Any(hash(os.real_path(argv[0]))!)
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
		assert hash(state + '/closure-inputs/' + path.trim_left('/'))! == pin, path
	}
	write_json(state + '/' + label + '-v-files-after.json', pins)!
}

fn native_equality() ! {
	mut old := map[string]string{}
	mut new := map[string]string{}
	inventory(state + '/native-old', '', mut old)!
	inventory(state + '/native-new', '', mut new)!
	assert old['api-impl.jar']! == if os.exists(state + '/qualified325-reference.json') { framework325 } else { framework318 }
	if os.exists(state + '/qualified329-reference.json') {
		pins := json2.decode[map[string]string](os.read_file(state + '/qualified329-reference.json')!)!
		assert new['api-impl.jar']! == pins['framework_sha256']!
	} else {
		assert new['api-impl.jar']! == old['api-impl.jar']!
	}
	for files in [old, new] {
		assert files['libvinix-android-native.so']! == native315
		assert files['popular-launcher']! == launcher283
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
	for dir in ['native-old', 'native-new', 'fixture-inputs', 'tools', 'source', 'closure-inputs',
		'generated-c', 'apk/disassembled-probe'] {
		mut files := map[string]string{}
		inventory(state + '/' + dir, '', mut files)!
		for key, pin in files { pins[dir + '/' + key] = pin }
	}
	for path in ['apk/probe.apk', 'apk/classes.dex', 'base-runtime.tar', 'config.json',
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

fn ordered_markers(log string, prefix string, names []string) int {
	mut previous := -1
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
	disk_checkpoint('prepare', 1536)!
	pins := qualified_manifest(qualified319, seal319)!
	clone(qualified319 + '/sha256.json', state + '/qualified319-sha256.json')!
	assert pins['native-new/libvinix-android-native.so']! == native315
	assert pins['native-new/api-impl.jar']! == framework318
	write_json(state + '/qualified-references.json', {
		'fixture319': qualified319
		'fixture319_manifest': seal319
		'recorded_baseline_entries': pins.len.str()
		'scope': 'Pinned historical manifest; every consumed file and complete selected tree authenticated. Common Native315 and clean283 launcher retained unchanged. Framework318 staging placeholders are replaced by325/329 before either guest starts. Full historical bundles remain untouched.'
	})!
	for name in ['system-package-fixture.v', 'system-package-run.v'] {
		clone('tests/native-android-ws/' + name, state + '/source/' + name)!
	}
	clone(os.executable(), state + '/tools/system-package-run-bootstrap')!
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
	config['java'] = java
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({
		'apk': json2.Any(state + '/apk/probe.apk')
		'distribution': json2.Any('Vinix regression fixture')
		'id': json2.Any('bootstrap-fixture')
		'name': json2.Any('Resource-only system package and dialog fixture')
		'package': json2.Any('org.vinix.bootstrap')
		'source': json2.Any(state + '/source/system-package-fixture.v')
		'startup_seconds': json2.Any(45)
	})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	os.mkdir_all(state + '/generated-c')!
	os.setenv('VTMP', state + '/generated-c', true)
	fixture_pins := source_closure('fixture', state + '/source/system-package-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-keepc', '-showcc', '-cc',
		'cc', '-cflags', '-O2', '-o', state + '/tools/system-package-fixture',
		state + '/source/system-package-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	mut tools_before := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut tools_before)!
	write_json(state + '/generate-fixture-tools-before.json', tools_before)!
	os.setenv('SYSTEM_PACKAGE_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	os.setenv('SYSTEM_PACKAGE_FIXTURE_JAVA', java, true)
	record('generate-fixture', [state + '/tools/system-package-fixture', state + '/apk'])!
	os.unsetenv('SYSTEM_PACKAGE_FIXTURE_TOOLS_ROOT')
	os.unsetenv('SYSTEM_PACKAGE_FIXTURE_JAVA')
	mut tools_after := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut tools_after)!
	write_json(state + '/generate-fixture-tools-after.json', tools_after)!
	assert tools_after == tools_before, 'fixture generation tools changed'
	// Inspect the classes inside the signed container that both guests execute.
	// Source smali and the intermediate classes.dex are retained independently.
	probe_pin := hash(state + '/apk/probe.apk')!
	record('disassemble-fixture', [java, '-cp', state + '/fixture-inputs/smali/*',
		'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', state + '/apk/probe.apk',
		'-o', state + '/apk/disassembled-probe'])!
	assert hash(state + '/apk/probe.apk')! == probe_pin
	mut disassembly_tools := map[string]string{}
	inventory(state + '/fixture-inputs', '', mut disassembly_tools)!
	assert disassembly_tools == tools_before, 'fixture disassembly tools changed'
	mut dex_classes := map[string]string{}
	inventory(state + '/apk/disassembled-probe', '', mut dex_classes)!
	mut class_names := dex_classes.keys()
	class_names.sort()
	assert class_names == ['org/vinix/bootstrap/Main.smali',
		'org/vinix/bootstrap/SystemPackageProbe.smali'], class_names.str()
	write_json(state + '/executed-fixture-dex.json', {
		'signed_apk_sha256': json2.Any(probe_pin)
		'intermediate_dex_sha256': json2.Any(hash(state + '/apk/classes.dex')!)
		'classes': json2.decode[json2.Any](json2.encode(dex_classes))!
		'scope': json2.Any('Baksmali disassembly of the actual signed probe.apk supplied to both guests; no guest started during preparation')
	})!
	runner_pins := source_closure('runner', state + '/source/system-package-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-keepc', '-showcc', '-cc',
		'cc', '-cflags', '-O2', '-o', state + '/tools/system-package-run-checked',
		state + '/source/system-package-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('SYSTEM-PACKAGE-PREPARED')
}

fn unsealed() {
	assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged'
}

fn stage(old_root string, old_seal string, old_framework string, new_root string, new_seal string, new_framework string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	old_pins := qualified_manifest(old_root, old_seal)!
	assert old_seal == seal325 && old_framework == framework325
	assert old_pins['framework/api-impl.jar']! == old_framework
	assert hash(old_root + '/framework/api-impl.jar')! == old_framework
	clone(old_root + '/sha256.json', state + '/qualified325-framework-sha256.json')!
	for kind in ['old', 'new'] {
		os.rm(state + '/native-' + kind + '/api-impl.jar')!
		clone(old_root + '/framework/api-impl.jar', state + '/native-' + kind + '/api-impl.jar')!
		assert hash(state + '/native-' + kind + '/api-impl.jar')! == old_framework
	}
	write_json(state + '/qualified325-reference.json', {
		'framework_root': old_root
		'framework_manifest_sha256': old_seal
		'framework_sha256': old_framework
		'framework_recorded_entries': old_pins.len.str()
		'scope': 'Pinned build manifest and selected framework payload authenticated before and after staging; full build bundle independently checked separately. Historical root unchanged.'
	})!
	mut old_before := map[string]string{}
	mut new_before := map[string]string{}
	inventory(state + '/native-old', '', mut old_before)!
	inventory(state + '/native-new', '', mut new_before)!
	assert old_before == new_before
	write_json(state + '/staged325-native-inputs.json', old_before)!
	new_pins := qualified_manifest(new_root, new_seal)!
	assert new_framework.len == 64 && new_framework !in [framework318, framework325]
	assert new_pins['framework/api-impl.jar']! == new_framework
	assert hash(new_root + '/framework/api-impl.jar')! == new_framework
	clone(new_root + '/sha256.json', state + '/qualified329-framework-sha256.json')!
	os.rm(state + '/native-new/api-impl.jar')!
	clone(new_root + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
	assert hash(state + '/native-new/api-impl.jar')! == new_framework
	write_json(state + '/qualified329-reference.json', {
		'framework_root': new_root
		'framework_manifest_sha256': new_seal
		'framework_sha256': new_framework
		'framework_recorded_entries': new_pins.len.str()
		'scope': 'Pinned build manifest and selected framework payload authenticated before and after staging; full build bundle independently checked separately. Historical root unchanged.'
		'delta': 'Only api-impl.jar differs between325/329; same Native315, signed APK, other runtime files and clean283 launcher.'
	})!
	assert hash(old_root + '/sha256.json')! == old_seal
	assert hash(new_root + '/sha256.json')! == new_seal
	assert hash(old_root + '/framework/api-impl.jar')! == old_framework
	assert hash(new_root + '/framework/api-impl.jar')! == new_framework
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('SYSTEM-PACKAGE-STAGED')
}

fn run(kind string) ! {
	unsealed()
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['system-package-fixture.v', 'system-package-run.v'] {
		assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)!, name
	}
	assert hash(os.executable())! == hash(state + '/tools/system-package-run-checked')!, 'use checked frozen runner'
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	disk_checkpoint(kind, 1024)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' {
			removed << key
			os.unsetenv(key)
		}
	}
	write_json(state + '/' + kind + '-environment.json', {
		'removed_host_trace_variables': json2.Any(removed)
		'guest_requirement': json2.Any('APK requires every VINIX_ANDROID_TRACE_* variable and ATL_UGLY_ENABLE_LOCATION absent; clean283 launcher unchanged')
		'launcher_sha256': json2.Any(launcher283)
	})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/sp330-' + kind)
	assert (alias + '/bootstrap-fixture/qmp.sock').len < 104
	assert !os.exists(alias) && !os.is_link(alias), alias
	assert !os.exists(output) && !os.is_link(output), output
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
	previous := ordered_markers(log, 'SYSTEM-PACKAGE-FIXTURE-', groups)
	assert log.count('BOOTSTRAP-READY') == 1
	assert marker_position(log, 'BOOTSTRAP-READY') > previous
	raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
	assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
	assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
	assert raw[0]['launcher_entered']!.bool()
	assert raw[0]['native_maps_observed']!.bool()
	assert raw[0]['qemu_alive_before_capture']!.bool()
	assert raw[0]['backend_ready']!.bool()
	assert !raw[0]['process_exited']!.bool()
	assert raw[0]['failure_markers']!.as_array().len == 0
	assert raw[0]['functional_passed']! is json2.Null
	outcome := raw[0]['outcome']!.str()
	assert outcome == 'window_observed', outcome
	// The old error is caught; both guests must finish the same runtime probe.
	// Search the full serial because system initialization can precede CALL.
	if kind == 'old' {
		assert log.count('APK signature verification failed') == 1
		failure := marker_position(log, 'APK signature verification failed')
		cache_pass := marker_position(log, 'SYSTEM-PACKAGE-FIXTURE-CACHE-PASS')
		assert failure < cache_pass
		block := log[failure..cache_pass]
		mut at := -1
		for stack in ['java.lang.NullPointerException: string arg == null',
			'at java.lang.String.concat(', 'at android.atl.VinixApkSignatures.verify(',
			'at android.content.pm.PackageParser.collectCertificates(',
			'at android.atl.ATLLoadedApp.getSystemApplication('] {
			position := marker_position(block, stack)
			assert position > at, stack
			at = position
		}
	} else {
		for bad in ['APK signature verification failed', 'java.lang.NullPointerException:',
			'at java.lang.String.concat(', 'at android.atl.VinixApkSignatures.verify('] {
			assert !log.contains(bad), bad
		}
	}
	for bad in ['AssertionError', 'ANDROID-WS-FAIL', 'APK-SUITE-EXIT', 'NoSuchMethodError',
		'NoSuchFieldError', 'NoClassDefFoundError', 'ClassNotFoundException', 'UnsatisfiedLinkError',
		'VerifyError', 'JNI DETECTED ERROR', 'ExceptionInInitializerError'] {
		assert !log.contains(bad), bad
	}
	write_json(state + '/' + kind + '-semantic-check.json', {
		'variant': kind
		'status': 'expected-result-pass'
		'expectation': if kind == 'old' {
			'System cache, resource identity, null signing metadata and dialog construction pass; exactly one caught null-archive verifier stack is retained before CACHE-PASS'
		} else {
			'Identical system cache, resource identity, null signing metadata and dialog construction pass without null-archive verification error'
		}
		'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!
		'checker_binary_sha256': hash(os.executable())!
		'raw_results_path': output + '/results.json'
		'raw_results_sha256': hash(output + '/results.json')!
		'raw_outcome': outcome
		'raw_classifier_scope': 'Unchanged historical suite startup observation; functional_passed remains null. Separate semantic fixture verdict. No new APK crypto qualification or Maps route qualification.'
	})!
	println('SYSTEM-PACKAGE-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
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
			for kind in ['old', 'new'] { assert os.exists(state + '/' + kind + '-semantic-check.json') }
			assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
			native_equality()!
			r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
			print(r.output)
			assert r.exit_code == 0
		}
		else { panic('prepare | stage OLD_ROOT OLD_MANIFEST OLD_JAR NEW_ROOT NEW_MANIFEST NEW_JAR | old | new | seal') }
	}
}
