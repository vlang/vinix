// SPDX-License-Identifier: GPL-2.0-or-later
// Same signed Nine-patch tint probe and clean283 launcher; only Framework/Native change.
module main

import compress.zlib
import encoding.binary
import hash.crc32
import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/nine-patch-tint316-fixture-2026-10-25'
const qualified313 = '/Users/alex/.local/state/vinix/android/paint-text-widths313-fixture-2026-10-25'
const seal313 = 'ea40e7026cfb606156aca1c0af2ce23b1b9e7af6a92170858921d76ef67bda2a'
const native312 = '51280a48fcefd27a49ba7a9b7d9b6d226c0a164af2517d3c851ea1bf3c7cf9de'
const framework312 = '33d231c02740bbb79bdc663f1ac79e142452aadb85348bee5a5165b0a03d674f'
const launcher283 = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

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
	assert hash(qualified313 + '/' + path)! == pins[path]!, path
	clone(qualified313 + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins {
		if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin }
	}
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(qualified313 + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(qualified313 + '/' + path, state + '/' + to)!
	actual.clear()
	inventory(state + '/' + to, '', mut actual)!
	assert actual == expected, to
}

fn record(label string, argv []string) ! {
	assert !os.exists(state + '/' + label + '-receipt.json'), label
	mut receipt := {
		'argv':           json2.Any(argv)
		'started_utc':    json2.Any(time.utc().str())
		'VROOT':          json2.Any(os.getenv('VROOT'))
		'command_sha256': json2.Any(hash(os.real_path(argv[0]))!)
	}
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
	assert old['api-impl.jar']! == framework312
	assert old['libvinix-android-native.so']! == native312
	assert old['popular-launcher']! == launcher283 && new['popular-launcher']! == launcher283
	if os.exists(state + '/qualified315-reference.json') {
		pins := json2.decode[map[string]string](os.read_file(state + '/qualified315-reference.json')!)!
		assert new['api-impl.jar']! == pins['framework_sha256']!
		assert new['libvinix-android-native.so']! == pins['native_sha256']!
	} else {
		assert new['api-impl.jar']! == framework312
		assert new['libvinix-android-native.so']! == native312
	}
	old.delete('api-impl.jar')
	new.delete('api-impl.jar')
	old.delete('libvinix-android-native.so')
	new.delete('libvinix-android-native.so')
	assert old == new, 'Only Framework and Native may differ between variants'
	if os.exists(state + '/native-common.json') {
		assert json2.decode[map[string]string](os.read_file(state + '/native-common.json')!)! == old
	} else {
		write_json(state + '/native-common.json', old)!
	}
}

fn stable_inputs() !map[string]string {
	mut pins := map[string]string{}
	for dir in ['native-old', 'native-new', 'fixture-inputs'] {
		mut files := map[string]string{}
		inventory(state + '/' + dir, '', mut files)!
		for key, pin in files { pins[dir + '/' + key] = pin }
	}
	for path in ['apk/probe.apk', 'tools/suite', 'tools/v_old276', 'tools/nine-patch-tint-run-checked',
		'base-runtime.tar', 'source/nine-patch-tint-fixture.v', 'source/nine-patch-tint-run.v',
		'config.json', 'host-inputs.json', 'initial-media.json', 'initial-media/boot.img',
		'initial-media/efivars.fd'] {
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

// Decode the retained framebuffer independently of the rendering path. The
// frozen screenshot encoder writes noninterlaced 8-bit RGB/RGBA PNGs.
fn screenshot_pixels(path string) !map[string]string {
	b := os.read_bytes(path)!
	assert b.len > 33 && b[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10]
	mut offset := 8
	mut width := 0
	mut height := 0
	mut channels := 0
	mut compressed := []u8{}
	mut ended := false
	for offset + 12 <= b.len {
		size := int(binary.big_endian_u32(b[offset..offset + 4]))
		assert size >= 0 && size <= b.len - offset - 12
		end := offset + 8 + size
		assert crc32.sum(b[offset + 4..end]) == binary.big_endian_u32(b[end..end + 4])
		kind := b[offset + 4..offset + 8].bytestr()
		match kind {
			'IHDR' {
				assert offset == 8 && size == 13
				width = int(binary.big_endian_u32(b[offset + 8..offset + 12]))
				height = int(binary.big_endian_u32(b[offset + 12..offset + 16]))
				assert width == 1024 && height == 768
				assert b[offset + 16] == 8 && b[offset + 17] in [u8(2), 6]
				assert b[offset + 18..end] == [u8(0), 0, 0]
				channels = if b[offset + 17] == 2 { 3 } else { 4 }
			}
			'IDAT' {
				assert channels > 0 && !ended
				compressed << b[offset + 8..end]
			}
			'IEND' {
				assert size == 0
				ended = true
			}
			else {
				assert kind[0] & 0x20 != 0, 'unexpected critical PNG chunk: ' + kind
			}
		}
		offset = end + 4
		if ended { break }
	}
	assert ended && offset == b.len && compressed.len > 0
	rows := zlib.decompress(compressed)!
	stride := width * channels
	assert rows.len == height * (stride + 1)
	mut pixels := []u8{len: height * stride}
	for y in 0 .. height {
		filter := rows[y * (stride + 1)]
		assert filter <= 4
		for x in 0 .. stride {
			i := y * stride + x
			left := if x >= channels { int(pixels[i - channels]) } else { 0 }
			up := if y > 0 { int(pixels[i - stride]) } else { 0 }
			corner := if y > 0 && x >= channels { int(pixels[i - stride - channels]) } else { 0 }
			predict := match filter {
				0 { 0 }
				1 { left }
				2 { up }
				3 { (left + up) / 2 }
				else {
					p := left + up - corner
					a := if p >= left { p - left } else { left - p }
					b_up := if p >= up { p - up } else { up - p }
					c := if p >= corner { p - corner } else { corner - p }
					if a <= b_up && a <= c {
						left
					} else if b_up <= c {
						up
					} else {
						corner
					}
				}
			}
			pixels[i] = u8(int(rows[y * (stride + 1) + x + 1]) + predict)
		}
	}
	mut counts := [0, 0]!
	mut bounds := [[1024, 768, -1, -1]!, [1024, 768, -1, -1]!]!
	for y in 90 .. 700 {
		for x in 128 .. 592 {
			i := (y * width + x) * channels
			if channels == 4 && pixels[i + 3] != 255 { continue }
			rgb := u32(pixels[i]) << 16 | u32(pixels[i + 1]) << 8 | u32(pixels[i + 2])
			color := if rgb == 0x2471c4 {
				0
			} else if rgb == 0xe53935 {
				1
			} else {
				continue
			}
			counts[color]++
			if x < bounds[color][0] { bounds[color][0] = x }
			if y < bounds[color][1] { bounds[color][1] = y }
			if x > bounds[color][2] { bounds[color][2] = x }
			if y > bounds[color][3] { bounds[color][3] = y }
		}
	}
	return {
		'screenshot':            path
		'screenshot_sha256':     hash(path)!
		'width':                 width.str()
		'height':                height.str()
		'roi':                   'x128..592,y90..700 exclusive; inside unchanged normal application window'
		'blue_rgb':              '2471c4'
		'blue_pixels':           counts[0].str()
		'blue_bounds_inclusive': bounds[0].str()
		'red_rgb':               'e53935'
		'red_pixels':            counts[1].str()
		'red_bounds_inclusive':  bounds[1].str()
		'expected_pixels_each':  '5040'
		'scope':                 'Actual retained normal-root framebuffer, independent PNG decode with CRC and filter checks; custom root View draws expected opaque SRC_IN blue and red nine-patch regions, each84x60, through normal Canvas drawing.'
	}
}

fn prepare() ! {
	assert !os.exists(state) && !os.is_link(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	pins := qualified_manifest(qualified313, seal313)!
	clone(qualified313 + '/sha256.json', state + '/qualified313-sha256.json')!
	assert pins['native-new/libvinix-android-native.so']! == native312
	assert pins['native-new/api-impl.jar']! == framework312
	write_json(state + '/qualified-references.json', {
		'fixture313':                qualified313
		'fixture313_manifest':       seal313
		'recorded_baseline_entries': pins.len.str()
		'scope':                     'Pinned historical manifest authenticated; every selected consumed file and complete selected tree rechecked before and after cloning. Full historical bundle was qualified previously and is not rescanned here. Historical root unchanged. Common clean283 launcher, baseline Framework312 and Native312 retained without rebuild.'
	})!
	for name in ['nine-patch-tint-fixture.v', 'nine-patch-tint-run.v'] {
		clone('tests/native-android-ws/' + name, state + '/source/' + name)!
	}
	clone(os.executable(), state + '/tools/nine-patch-tint-run-bootstrap')!
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
	selected('new.json', 'qualified313-new.json', pins)!
	selected_tree('native-new', 'native-old', pins)!
	selected_tree('native-new', 'native-new', pins)!
	native_equality()!
	for file in ['boot.img', 'efivars.fd'] {
		selected('initial-media/' + file, 'initial-media/' + file, pins)!
	}
	selected('initial-media.json', 'qualified313-initial-media.json', pins)!
	media := json2.decode[map[string]string](os.read_file(state + '/qualified313-initial-media.json')!)!
	for file in ['boot.img', 'efivars.fd'] {
		assert hash(state + '/initial-media/' + file)! == media[file]!, file
	}
	write_json(state + '/initial-media.json', media)!
	selected_tree('fixture-inputs', 'fixture-inputs', pins)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified313-new.json')!)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	config['applications'] = json2.Any([json2.Any({
		'apk':             json2.Any(state + '/apk/probe.apk')
		'distribution':    json2.Any('Vinix regression fixture')
		'id':              json2.Any('bootstrap-fixture')
		'name':            json2.Any('Nine-patch tint fixture')
		'package':         json2.Any('org.vinix.bootstrap')
		'source':          json2.Any(state + '/source/nine-patch-tint-fixture.v')
		'startup_seconds': json2.Any(45)
	})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	fixture_pins := source_closure('fixture', state + '/source/nine-patch-tint-fixture.v')!
	record('compile-fixture', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'-o', state + '/tools/nine-patch-tint-fixture', state + '/source/nine-patch-tint-fixture.v'])!
	closure_unchanged('fixture', fixture_pins)!
	os.setenv('NINE_PATCH_TINT_FIXTURE_TOOLS_ROOT', state + '/fixture-inputs', true)
	record('generate-fixture', [state + '/tools/nine-patch-tint-fixture', state + '/apk'])!
	os.unsetenv('NINE_PATCH_TINT_FIXTURE_TOOLS_ROOT')
	runner_pins := source_closure('runner', state + '/source/nine-patch-tint-run.v')!
	record('compile-runner', [state + '/tools/v_old276', '-nocache', '-cc', 'cc', '-cflags', '-O2',
		'-o', state + '/tools/nine-patch-tint-run-checked', state + '/source/nine-patch-tint-run.v'])!
	closure_unchanged('runner', runner_pins)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	println('NINE-PATCH-TINT-PREPARED')
}

fn unsealed() {
	assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged'
}

fn stage(root string, seal string, native string, framework_root string, framework_seal string, framework string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	pins := qualified_manifest(root, seal)!
	assert native.len == 64 && native != native312 && pins['native/libvinix-android-native.so']! == native
	assert hash(root + '/native/libvinix-android-native.so')! == native
	framework_pins := qualified_manifest(framework_root, framework_seal)!
	assert framework.len == 64 && framework != framework312 && framework_pins['framework/api-impl.jar']! == framework
	assert hash(framework_root + '/framework/api-impl.jar')! == framework
	clone(root + '/sha256.json', state + '/qualified315-native-sha256.json')!
	clone(framework_root + '/sha256.json', state + '/qualified315-framework-sha256.json')!
	os.rm(state + '/native-new/libvinix-android-native.so')!
	clone(root + '/native/libvinix-android-native.so', state + '/native-new/libvinix-android-native.so')!
	assert hash(state + '/native-new/libvinix-android-native.so')! == native
	os.rm(state + '/native-new/api-impl.jar')!
	clone(framework_root + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
	assert hash(state + '/native-new/api-impl.jar')! == framework
	write_json(state + '/qualified315-reference.json', {
		'native_root':                root
		'native_manifest_sha256':     seal
		'native_sha256':              native
		'native_recorded_entries':    pins.len.str()
		'framework_root':             framework_root
		'framework_manifest_sha256':  framework_seal
		'framework_sha256':           framework
		'framework_recorded_entries': framework_pins.len.str()
		'scope':                      'Pinned build manifests and selected Native/Framework payload hashes authenticated before and after staging; complete build bundles are independently checked separately. Historical roots unchanged.'
		'delta':                      'Only api-impl.jar and libvinix-android-native.so change; same signed APK, other runtime files and clean283 launcher.'
	})!
	native_equality()!
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('NINE-PATCH-TINT-STAGED')
}

fn run(kind string) ! {
	unsealed()
	assert kind in ['old', 'new']
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!, 'shared inputs changed between variants'
	for name in ['nine-patch-tint-fixture.v', 'nine-patch-tint-run.v'] {
		assert hash('tests/native-android-ws/' + name)! == hash(state + '/source/' + name)!
	}
	assert hash(os.executable())! == hash(state + '/tools/nine-patch-tint-run-checked')!, 'use the checked frozen runner'
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
	alias := os.abs_path('build/android-maps/nt316-' + kind)
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
	assert log.count('BOOTSTRAP-NINE-PATCH-TINT-TRACE-ENV-ABSENT-PASS') == 1
	assert log.count('BOOTSTRAP-NINE-PATCH-TINT-CALL') == 1
	raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
	assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
	assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
	outcome := raw[0]['outcome']!.str()
	if kind == 'old' {
		assert log.count('java.lang.AssertionError:') == 1
		assert log.count('java.lang.AssertionError: NinePatch tint: stateful tint reports stateful actual=0 expected=1') == 1
		assert log.count('ANDROID-WS-FAIL start activity') == 1
		assert log.count('ANDROID-WS-FAIL') == 1
		assert !log.contains('BOOTSTRAP-READY')
		for name in ['STATEFUL', 'COLORS', 'FILTER', 'ALPHA', 'ISOLATION', 'CANVAS', 'DRAW'] {
			assert !log.contains('BOOTSTRAP-NINE-PATCH-TINT-' + name + '-PASS'), name
		}
		assert !log.contains('BOOTSTRAP-NINE-PATCH-TINT-PASS')
		assert outcome == 'startup_failed', outcome
	} else {
		for name in ['STATEFUL', 'COLORS', 'FILTER', 'ALPHA', 'ISOLATION', 'CANVAS', 'DRAW'] {
			assert log.count('BOOTSTRAP-NINE-PATCH-TINT-' + name + '-PASS') == 1, name
		}
		assert log.count('BOOTSTRAP-NINE-PATCH-TINT-PASS') == 1
		assert log.count('BOOTSTRAP-READY') == 1
		for bad in ['AssertionError', 'NoSuchMethodError', 'ANDROID-WS-FAIL'] {
			assert !log.contains(bad), bad
		}
		assert outcome == 'window_observed', outcome
		screenshot := output + '/bootstrap-fixture/application.png'
		assert hash(screenshot)! == raw[0]['screenshot_sha256']!.str()
		pixels := screenshot_pixels(screenshot)!
		write_json(state + '/new-screenshot-pixels.json', pixels)!
		assert pixels['blue_pixels']!.int() == 5040, 'exact opaque blue tinted block required'
		assert pixels['red_pixels']!.int() == 5040, 'exact opaque red tinted block required'
		assert pixels['blue_bounds_inclusive']! == '[144, 190, 227, 249]'
		assert pixels['red_bounds_inclusive']! == '[228, 190, 311, 249]'
	}
	for bad in ['NoSuchMethodError', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'VerifyError',
		'JNI DETECTED ERROR'] {
		assert !log.contains(bad), bad
	}
	write_json(state + '/' + kind + '-semantic-check.json', {
		'variant':               kind
		'status':                'expected-result-pass'
		'expectation':           if kind == 'old' {
			'Stateful NinePatch tint reports false and triggers the exact first assertion; startup_failed is the expected baseline result'
		} else {
			'Stateful tint, checked/default colors, explicit filter precedence, alpha, shared-bitmap isolation, Canvas target selection and real View drawing pass'
		}
		'serial_sha256':         hash(output + '/bootstrap-fixture/serial.log')!
		'checker_binary_sha256': hash(os.executable())!
		'raw_results_path':      output + '/results.json'
		'raw_results_sha256':    hash(output + '/results.json')!
		'raw_outcome':           outcome
		'raw_classifier_scope':  'Unchanged historical suite startup observation, separate from semantic fixture verdict.'
	})!
	println('NINE-PATCH-TINT-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
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
			assert os.args.len == 8, 'stage NATIVE_ROOT NATIVE_MANIFEST_SHA NATIVE_SHA FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA'
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
			panic('prepare | stage NATIVE_ROOT NATIVE_MANIFEST_SHA NATIVE_SHA FRAMEWORK_ROOT FRAMEWORK_MANIFEST_SHA FRAMEWORK_SHA | old | new | seal')
		}
	}
}
