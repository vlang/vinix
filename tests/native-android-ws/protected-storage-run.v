// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare-only host stager and bounded guest controller for the storage APK.
module main

import json2
import os
import time
import modulestream

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/'
const baseline = state + 'layout-parent-dispatch336-v3-2026-10-25'
const baseline_seal = 'a583f89a37bc7d59a275fef01396a864efe04915dd070227631599058ae46762'
const suite_root = state + 'vpa-translation-z338-2026-10-25'
const suite_seal = 'c8e780dfd7439d8f85a3f8abd70a43f78a53652128d489adbfec5e5079aeaaf2'
const fixture = state + 'protected-storage-fixture-2026-10-27-r1'
const fixture_seal = '82cdff638c26fc6f662a64fce54165e487169a2a4ee2030275ab86843da9a42f'
const apk_pin = '786681da81d8b075e38f844014ab767e26f4388bfb5f8bf62e4cd380c978f0e6'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const source_path = '/Users/alex/code/vinix/tests/native-android-ws/protected-storage-run.v'
const runtime = '/opt/vinix-android-aarch64'
const guest_root = '/opt/android-test/protected-storage'
const pass_marker = 'PROTECTED-STORAGE-PASS direct-fields copy-null metadata paths preferences wrapper configuration package-context'
const ready_marker = 'ANDROID-WS-READY backend=vinix-native'
const serial_limit = 16 * 1024 * 1024
const optional_field_diagnostic = 'java.lang.NoSuchFieldError: no type "Lnge;" found and so no field "bB" could be found in class "Lorg/vinix/bootstrap/Main;" or its superclasses'
const optional_class_diagnostic = 'Caused by: java.lang.ClassNotFoundException: nge'

struct Variant {
	name string
	expected string
	framework_root string
	framework_seal string
	framework_sha256 string
	jni_root string
	jni_seal string
	jni_sha256 string
}

fn variants() []Variant {
	return [Variant{
		name: 'old', expected: 'missing-field'
		framework_root: state + 'combined-account-webview-descriptions-framework-2026-10-26-r1'
		framework_seal: 'd898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021'
		framework_sha256: '71d05c6e6288978de66a5c71279e8cb27d92c9166950813ddbf0c33ff86e1d0d'
		jni_root: state + 'current-native-build-2026-10-26-r17'
		jni_seal: '77503d184cc53fe3527f1949f7b88648b5a6bacd1e6b74bd82acb82fec222419'
		jni_sha256: '70b8db58c59d769f4f4ae4e6775fb7c3a2c4c9af42cfd3f14076092ec14818c0'
	}, Variant{
		name: 'new', expected: 'pass'
		framework_root: state + 'combined-account-webview-protected-storage-framework-2026-10-27-r2'
		framework_seal: '67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938'
		framework_sha256: 'a8ba34eb79be2473f89042c8ee940ab1994dbc902c3d45143877f8891d3b428b'
		jni_root: state + 'current-native-build-2026-10-27-protected-r1'
		jni_seal: '894c9657077cdd913a2c66c1cf78358daaccc4da8b0739ed77bb2a3dbea1b4ee'
		jni_sha256: '05ed64c8c0778cc09ea2db7d820c873c7e53c493f99c886c4992f3243f8f913a'
	}]
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn hash(path string) !string {
	$if macos {
		mut input := os.open(path)!
		defer { input.close() }
		mut bytes := []u8{len: 1024 * 1024}
		defer { unsafe { bytes.free() } }
		mut context := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(&context) != 1 { return error('SHA256 init') }
		for {
			n := input.read(mut bytes) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if C.CC_SHA256_Update(&context, bytes.data, u32(n)) != 1 { return error('SHA256 update') }
		}
		mut sum := [32]u8{}
		if C.CC_SHA256_Final(&sum[0], &context) != 1 { return error('SHA256 final') }
		return sum[..].hex()
	} $else {
		return error('host hashing requires macOS')
	}
}

fn sealed(root string, pin string) !map[string]string {
	if hash(root + '/sha256.json')! != pin { return error('seal differs: ' + root) }
	return json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
}

fn copy_pin(from string, to string, pin string) ! {
	if hash(from)! != pin { return error('input differs: ' + from) }
	os.mkdir_all(os.dir(to))!
	os.cp(from, to)!
	if hash(to)! != pin || hash(from)! != pin { return error('copy differs: ' + from) }
}

fn command(output string, label string, argv []string) ! {
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(output + '/commands/' + label + '.log', r.output)!
	write_json(output + '/commands/' + label + '.json', {
		'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code)
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str())
	})!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
}

fn clone(output string, label string, from string, to string) ! {
	if os.exists(to) || os.is_link(to) { return error('clone target exists') }
	command(output, label, ['/bin/cp', '-c', from, to])!
}

fn qemu_argv(output string, name string) []string {
	return [os.abs_path('build/qemu-horizontal/bin/qemu-system-aarch64'),
		'-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '2048',
		'-smp', '2', '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device',
		'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		'-drive', 'if=pflash,format=raw,file=' + output + '/' + name + '/efivars.fd',
		'-drive', 'format=raw,file=' + output + '/' + name + '/boot.img',
		'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device',
		'ramfb', '-netdev', 'user,id=net0', '-device', 'virtio-net-device,netdev=net0',
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + output + '/' + name + '/serial.log']
}

fn closure(output string, label string, argv []string) !map[string]string {
	command(output, label, argv)!
	mut pins := map[string]string{}
	for path in os.read_lines(output + '/commands/' + label + '.log')! {
		if path.ends_with('.v') { pins[path] = hash(path)! }
	}
	if pins.len == 0 { return error('empty V input closure') }
	write_json(output + '/' + label + '.json', pins)!
	return pins
}

fn prepare(output string) ! {
	$if !macos { return error('prepare requires macOS APFS') }
	if !output.starts_with(state) || output.contains_any('\n\r\x00,') || os.exists(output) || os.is_link(output) {
		return error('fresh absolute external-state output required')
	}
	os.mkdir_all(output + '/commands')!
	df := os.exec(['/bin/df', '-k', output])
	if df.exit_code != 0 { return error(df.output) }
	available := df.output.trim_space().split_into_lines().last().fields()[3].u64()
	write_json(output + '/disk.json', {'available_kib': json2.Any(available), 'raw': json2.Any(df.output)})!
	if available < 1536 * 1024 { return error('at least 1536 MiB free required') }
	bp := sealed(baseline, baseline_seal)!
	sp := sealed(suite_root, suite_seal)!
	fp := sealed(fixture, fixture_seal)!
	if fp['probe.apk']! != apk_pin { return error('fixture pin differs') }
	if hash(compiler)! != compiler_pin { return error('compiler pin differs') }
	os.mkdir_all(output + '/tools')!
	os.mkdir_all(output + '/source')!
	copy_pin(source_path, output + '/source/protected-storage-run.v', hash(source_path)!)!
	copy_pin(suite_root + '/tools/suite', output + '/tools/retained-suite', sp['tools/suite']!)!
	copy_pin(fixture + '/probe.apk', output + '/probe.apk', apk_pin)!
	mut input_pins := map[string]string{}
	for path in [source_path, compiler, '/opt/homebrew/bin/aarch64-linux-musl-gcc',
		os.abs_path('build-support/android/modulestream/spawn_abi.h'),
		baseline + '/sha256.json', suite_root + '/sha256.json', fixture + '/sha256.json',
		baseline + '/base-runtime.tar', baseline + '/vm-new/boot.img', baseline + '/vm-new/efivars.fd',
		os.abs_path('build/qemu-horizontal/bin/qemu-system-aarch64'),
		'/opt/homebrew/share/qemu/edk2-aarch64-code.fd',
		os.find_abs_path_of_executable('mcopy')!, os.find_abs_path_of_executable('tar')!] {
		input_pins[path] = hash(path)!
	}
	for name in ['base-runtime.tar', 'vm-new/boot.img', 'vm-new/efivars.fd'] {
		if input_pins[baseline + '/' + name]! != bp[name]! { return error('baseline differs: ' + name) }
	}
	path_arg := output + '/source|build-support/android|@vlib|@vmodules'
	guest_flags := [compiler, '-new-compiler', '-nocache', '-os', 'linux', '-arch', 'arm64',
		'-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '-gc', 'none', '-cflags', '-static',
		'-ldflags', '-static', '-path', path_arg]
	mut closure_argv := guest_flags.clone()
	closure_argv << ['-print-v-files', output + '/source/protected-storage-run.v']
	before := closure(output, 'guest-v-files-before', closure_argv)!
	for path, pin in before {
		copy_pin(path, output + '/closure-inputs' + os.abs_path(path), pin)!
	}
	copy_pin(os.abs_path('build-support/android/modulestream/spawn_abi.h'),
		output + '/closure-inputs' + os.abs_path('build-support/android/modulestream/spawn_abi.h'),
		input_pins[os.abs_path('build-support/android/modulestream/spawn_abi.h')]!)!
	mut compile_argv := guest_flags.clone()
	compile_argv << ['-o', output + '/tools/guest', output + '/source/protected-storage-run.v']
	command(output, 'compile-guest', compile_argv)!
	after := closure(output, 'guest-v-files-after', closure_argv)!
	if before != after { return error('guest compiler inputs changed') }
	mut cases := []map[string]json2.Any{}
	for v in variants() {
		jp := sealed(v.framework_root, v.framework_seal)!
		np := sealed(v.jni_root, v.jni_seal)!
		if jp['api-impl.jar']! != v.framework_sha256 || np['native/libvinix-android-native.so']! != v.jni_sha256 {
			return error('variant seal entries differ: ' + v.name)
		}
		for p in [v.framework_root + '/sha256.json', v.jni_root + '/sha256.json'] { input_pins[p] = hash(p)! }
		root := output + '/' + v.name
		module_root := root + '/module'
		os.mkdir_all(module_root)!
		command(output, v.name + '-base-overlay', ['/usr/bin/tar', '-xf', baseline + '/base-runtime.tar', '-C', module_root])!
		for source, target in {
			'libvinix-android-native.so': runtime + '/usr/lib/art/libvinix-android-native.so'
			'libdl_bio.so.0': runtime + '/usr/lib/art/native-ws/libdl_bio.so.0'
			'vinix-android-native': runtime + '/usr/bin/vinix-android-native'
			'run-android': runtime + '/usr/bin/run-android'
			'libvinix-android-compat.so': runtime + '/usr/lib/libvinix-android-compat.so'
			'tzdata': runtime + '/usr/share/zoneinfo/tzdata'
			'cacerts': runtime + '/etc/ssl/certs/java/cacerts'
			'bionic-ws.cfg': runtime + '/usr/share/vinix-android-ws/bionic_translation/cfg.d/native.cfg'
			'libglapi.so.0': runtime + '/usr/lib/art/native-ws/libglapi.so.0'
			'libvinix-ws-GLESv1_CM.so': runtime + '/usr/lib/art/native-ws/libvinix-ws-GLESv1_CM.so'
			'libvinix-ws-GLESv2.so': runtime + '/usr/lib/art/native-ws/libvinix-ws-GLESv2.so'
		} {
			if source == 'libvinix-android-native.so' { continue }
			copy_pin(baseline + '/native-new/' + source, module_root + target, bp['native-new/' + source]!)!
		}
		for provider in ['egl-ws', 'vulkan-ws'] {
			for key, pin in bp {
				prefix := 'native-new/' + provider + '/'
				if key.starts_with(prefix) {
					copy_pin(baseline + '/' + key, module_root + runtime + '/usr/lib/art/native-ws/' + provider + '/' + key[prefix.len..], pin)!
				}
			}
		}
		copy_pin(v.framework_root + '/api-impl.jar', module_root + runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar', v.framework_sha256)!
		copy_pin(v.jni_root + '/native/libvinix-android-native.so', module_root + runtime + '/usr/lib/art/libvinix-android-native.so', v.jni_sha256)!
		copy_pin(output + '/tools/guest', module_root + '/sbin/init', hash(output + '/tools/guest')!)!
		copy_pin(output + '/probe.apk', module_root + guest_root + '/probe.apk', apk_pin)!
		os.write_file(module_root + guest_root + '/expected', v.expected + '\n')!
		os.write_file(module_root + '/etc/resolv.conf', 'nameserver 10.0.2.3\n')!
		os.chmod(module_root + '/sbin/init', 0o755)!
		os.chmod(module_root + runtime + '/usr/bin/run-android', 0o755)!
		clone(output, v.name + '-clone-boot', baseline + '/vm-new/boot.img', root + '/boot.img')!
		clone(output, v.name + '-clone-efivars', baseline + '/vm-new/efivars.fd', root + '/efivars.fd')!
		os.setenv('COPYFILE_DISABLE', '1', true)
		modulestream.copy(module_root, root + '/boot.img')!
		// Independently read the FAT member back through mcopy -> tar. Do not
		// infer deployed payload identity only from producer-side copies.
		os.mkdir(root + '/readback')!
		readback := modulestream.extract_member(root + '/boot.img', 'qemu-runtime.tar', root + '/readback')!
		if readback.producer != 0 || readback.consumer != 0 { return error('module readback failed') }
		mut deployed := map[string]string{}
		for relative, pin in {
			guest_root + '/probe.apk': apk_pin
			runtime + '/usr/lib/art/libvinix-android-native.so': v.jni_sha256
			runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar': v.framework_sha256
			'/sbin/init': hash(output + '/tools/guest')!
		} {
			observed := hash(root + '/readback' + relative)!
			if observed != pin { return error('deployed member differs: ' + relative) }
			deployed[relative] = observed
		}
		write_json(root + '/deployed-payload.json', deployed)!
		cases << {'name': json2.Any(v.name), 'expected': json2.Any(v.expected),
			'framework_sha256': json2.Any(v.framework_sha256), 'jni_sha256': json2.Any(v.jni_sha256),
			'boot_sha256_before_run': json2.Any(hash(root + '/boot.img')!),
			'efivars_sha256_before_run': json2.Any(hash(root + '/efivars.fd')!),
			'qemu_argv': json2.Any(qemu_argv(output, v.name))}
		println('PROTECTED-STORAGE-PREPARED case=' + v.name)
	}
	for path, pin in input_pins { if hash(path)! != pin { return error('input changed during preparation: ' + path) } }
	write_json(output + '/input-sha256.json', input_pins)!
	write_json(output + '/prepared.json', {'version': json2.Any(1), 'cases': json2.Any(cases),
		'source_revision': json2.Any(os.exec(['git', 'rev-parse', 'HEAD']).output.trim_space()),
		'source_sha256': json2.Any(hash(source_path)!), 'guest_sha256': json2.Any(hash(output + '/tools/guest')!),
		'apk_sha256': json2.Any(apk_pin), 'input_manifest_sha256': json2.Any(hash(output + '/input-sha256.json')!),
		'booted': json2.Any(false), 'scope': json2.Any('prepared only; no guest result or Google authentication proof')})!
	println('PROTECTED-STORAGE-PREPARE-ONLY ' + output + '/prepared.json')
}

fn semantic(log string, expected string) ! {
	if expected !in ['pass', 'missing-field'] || log.len > serial_limit { return error('invalid expected case or serial size') }
	begin := 'PROTECTED-STORAGE-GUEST-BEGIN expected=' + expected
	done := 'PROTECTED-STORAGE-GUEST-DONE expected=' + expected + ' result=pass'
	lines := log.split_into_lines().map(it.trim_right('\r'))
	if lines.filter(it == begin).len != 1 || lines.filter(it == done).len != 1 {
		return error('missing/duplicate controller lifecycle')
	}
	start := log.index(begin) or { return error('begin absent') }
	end := log.index(done) or { return error('done absent') }
	if end <= start || log.contains('PROTECTED-STORAGE-GUEST-FAIL') || log.contains('PROTECTED-STORAGE-GUEST-TIMEOUT') {
		return error('failed lifecycle')
	}
	body := log[start..end]
	body_lines := body.split_into_lines().map(it.trim_right('\r'))
	exit_line := 'PROTECTED-STORAGE-GUEST-EXIT code=' + if expected == 'pass' { '0' } else { '1' }
	if body_lines.filter(it.starts_with('PROTECTED-STORAGE-GUEST-EXIT')).len != 1
		|| body_lines.filter(it == exit_line).len != 1 { return error('missing/duplicate/conflicting child exit') }
	if expected == 'pass' {
		if lines.filter(it == pass_marker).len != 1 || body_lines.filter(it.starts_with(ready_marker)).len != 1
			|| body_lines.filter(it.starts_with('PROTECTED-STORAGE-GUEST-STDIN-CLOSED')).len != 1
			|| body_lines.filter(it == 'PROTECTED-STORAGE-GUEST-STDIN-CLOSED reason=ready-and-pass').len != 1 {
			return error('positive fixture marker/WS readiness/clean exit absent')
		}
		field_count := lines.filter(it == optional_field_diagnostic).len
		class_count := lines.filter(it == optional_class_diagnostic).len
		if field_count > 1 || field_count != class_count { return error('incomplete/duplicate optional lookup diagnostic') }
		for line in lines {
			if line.contains('NoSuchFieldError') && line != optional_field_diagnostic { return error('unexpected field lookup failure') }
			if line.contains('ClassNotFoundException') && line != optional_class_diagnostic { return error('unexpected class lookup failure') }
		}
		for bad in ['NoSuchMethodError', 'NoClassDefFoundError', 'JNI exception', 'JNI DETECTED ERROR',
			'AssertionError', 'ANDROID-WS-FAIL', 'SIGABRT', 'SIGSEGV', 'panic:'] {
			if body.contains(bad) { return error('positive failure marker: ' + bad) }
		}
		pass_at := body.index(pass_marker) or { return error('pass outside lifecycle') }
		ready_at := body.index(ready_marker) or { return error('ready outside lifecycle') }
		closed_at := body.index('PROTECTED-STORAGE-GUEST-STDIN-CLOSED') or { return error('close outside lifecycle') }
		exit_at := body.index('PROTECTED-STORAGE-GUEST-EXIT') or { return error('exit outside lifecycle') }
		if closed_at <= pass_at || closed_at <= ready_at || exit_at <= closed_at { return error('positive lifecycle order') }
	} else {
		if log.contains(pass_marker) || !body.contains('NoSuchFieldError') || !body.contains('credentialProtectedDataDir')
			|| !body.contains('org.vinix.bootstrap.Main.onCreate')
			|| !body.contains('PROTECTED-STORAGE-GUEST-EXIT code=1') {
			return error('old framework direct-field failure absent')
		}
	}
}

fn selftest() ! {
	begin := 'PROTECTED-STORAGE-GUEST-BEGIN expected=pass\n'
	end := 'PROTECTED-STORAGE-GUEST-DONE expected=pass result=pass\n'
	good := begin + pass_marker + '\n' + ready_marker + '\nPROTECTED-STORAGE-GUEST-STDIN-CLOSED reason=ready-and-pass\nPROTECTED-STORAGE-GUEST-EXIT code=0\n' + end
	semantic(good, 'pass')!
	known := good.replace(pass_marker, optional_field_diagnostic + '\n' + optional_class_diagnostic + '\n' + pass_marker)
	semantic(known, 'pass')!
	bad_cases := [good.replace(pass_marker, ''), good.replace(ready_marker, ''),
		good.replace('code=0', 'code=137'), good.replace('reason=ready-and-pass', 'reason=timeout'),
		good.replace(end, ''), good.replace(end, pass_marker + '\n' + end),
		good.replace(pass_marker, 'JNI exception\n' + pass_marker),
		good.replace(ready_marker, 'PROTECTED-STORAGE-GUEST-STDIN-CLOSED reason=ready-and-pass\n' + ready_marker),
		good + 'PROTECTED-STORAGE-GUEST-FAIL late\n',
		known.replace(optional_class_diagnostic + '\n', ''),
		known.replace('field "bB"', 'field "other"'),
		known.replace('ClassNotFoundException: nge', 'ClassNotFoundException: other'),
		known.replace(optional_field_diagnostic, optional_field_diagnostic + '\n' + optional_field_diagnostic),
		good.replace('code=0', 'code=01'),
		good.replace('PROTECTED-STORAGE-GUEST-EXIT code=0', 'PROTECTED-STORAGE-GUEST-EXIT code=0\nPROTECTED-STORAGE-GUEST-EXIT code=1'),
		good.replace(ready_marker, ready_marker + '\n' + ready_marker)]
	for text in bad_cases {
		mut rejected := false
		semantic(text, 'pass') or { rejected = true }
		if !rejected { return error('positive checker accepted mutation') }
	}
	negative := 'PROTECTED-STORAGE-GUEST-BEGIN expected=missing-field\njava.lang.NoSuchFieldError credentialProtectedDataDir\n at org.vinix.bootstrap.Main.onCreate(Main.java:1)\nPROTECTED-STORAGE-GUEST-EXIT code=1\nPROTECTED-STORAGE-GUEST-DONE expected=missing-field result=pass\n'
	semantic(negative, 'missing-field')!
	for text in [negative.replace('credentialProtectedDataDir', 'otherField'), negative.replace('Main.onCreate', 'Other.onCreate'), negative + pass_marker] {
		mut rejected := false
		semantic(text, 'missing-field') or { rejected = true }
		if !rejected { return error('negative checker accepted mutation') }
	}
	println('PROTECTED-STORAGE-CHECKER-SELFTEST-PASS cases=22')
}

fn guest() ! {
	$if linux {
		expected := os.read_file(guest_root + '/expected')!.trim_space()
		if expected !in ['pass', 'missing-field'] { return error('unknown guest expectation') }
		data := guest_root + '/data'
		home := guest_root + '/home'
		if os.exists(data) || os.exists(home) { return error('fresh application data/home required') }
		os.mkdir(data)!
		os.mkdir(home)!
		os.chmod(data, 0o700)!
		os.chmod(home, 0o700)!
		println('PROTECTED-STORAGE-GUEST-BEGIN expected=' + expected)
		mut app := os.new_process(runtime + '/usr/bin/run-android')
		app.set_environment({'PATH': '/usr/bin:/bin', 'LD_LIBRARY_PATH': '/usr/lib',
			'HOME': home, 'VINIX_ANDROID_ROOT': runtime, 'VINIX_ANDROID_HOME': home,
			'ANDROID_APP_DATA_DIR': data, 'VINIX_SURFACE_PATH': data + '/probe.surface'})
		app.set_args([guest_root + '/probe.apk', '-l', 'org.vinix.bootstrap.Main', '-w', '64', '-h', '64'])
		app.use_pgroup = true
		app.set_redirect_stdio_merged()
		app.run()
		defer { app.close() }
		mut reaped := false
		defer { if app.pid > 0 && !reaped { app.signal_pgkill(); app.wait() } }
		if app.pid <= 0 || app.stdio_fd[0] < 3 || app.stdio_fd[1] < 3 { return error('app pipes unavailable') }
		flags := C.fcntl(app.stdio_fd[1], C.F_GETFL, 0)
		if flags < 0 || C.fcntl(app.stdio_fd[1], C.F_SETFL, flags | C.O_NONBLOCK) < 0 { return error('nonblocking output pipe') }
		mut bytes := [4096]u8{}
		mut line := [8192]u8{}
		mut used := 0
		mut total := 0
		mut passed := false
		mut ready := false
		mut closed := false
		mut deadline := time.sys_mono_now() + u64(180 * time.second)
		for {
			if time.sys_mono_now() >= deadline { return error('PROTECTED-STORAGE-GUEST-TIMEOUT') }
			n := unsafe { C.read(app.stdio_fd[1], &bytes[0], bytes.len) }
			if n > 0 {
				total += int(n)
				if total > 4 * 1024 * 1024 { return error('guest output exceeds 4 MiB') }
				mut sent := 0
				for sent < n {
					written := unsafe { C.write(1, &bytes[sent], uint(n - sent)) }
					if written < 0 && C.errno == C.EINTR { continue }
					if written <= 0 { return error('serial output failed') }
					sent += int(written)
				}
				for i in 0 .. int(n) {
					if bytes[i] == `\n` {
						text := unsafe { tos(&line[0], used) }
						if text == pass_marker { passed = true }
						if text.starts_with(ready_marker) { ready = true }
						used = 0
					} else {
						if used >= line.len { return error('guest line exceeds 8192 bytes') }
						line[used] = bytes[i]
						used++
					}
				}
				if !closed && passed && ready {
					os.fd_close(app.stdio_fd[0])
					app.stdio_fd[0] = -1
					closed = true
					deadline = time.sys_mono_now() + u64(20 * time.second)
					println('PROTECTED-STORAGE-GUEST-STDIN-CLOSED reason=ready-and-pass')
				}
				continue
			}
			if n < 0 && C.errno !in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR] { return error('app output read failed') }
			if !reaped && !app.is_alive() {
				app.wait()
				reaped = true
			}
			// A child may write its final bytes between EAGAIN and waitpid.
			// Drain through EOF even after observing/reaping its exit.
			if reaped && n == 0 { break }
			time.sleep(10 * time.millisecond)
		}
		app.wait()
		reaped = true
		println('\nPROTECTED-STORAGE-GUEST-EXIT code=' + app.code.str())
		if expected == 'pass' && (!passed || !ready || !closed || app.code != 0) { return error('positive app lifecycle failed') }
		if expected == 'missing-field' && app.code != 1 { return error('negative app must exit 1') }
		println('PROTECTED-STORAGE-GUEST-DONE expected=' + expected + ' result=pass')
		for { time.sleep(time.second) }
	} $else { return error('guest requires Linux/Vinix') }
}

fn run() ! {
	$if linux { guest()!; return }
	if os.args.len == 2 && os.args[1] == 'selftest' { selftest()!; return }
	if os.args.len == 3 && os.args[1] == 'prepare' { prepare(os.args[2])!; return }
	if os.args.len == 5 && os.args[1] == 'check' {
		if os.exists(os.args[4]) || os.is_link(os.args[4]) { return error('fresh result output required') }
		if os.file_size(os.args[3]) > serial_limit { return error('serial exceeds 16 MiB') }
		text := os.read_file(os.args[3])!
		semantic(text, os.args[2])!
		write_json(os.args[4], {'expected': json2.Any(os.args[2]), 'functional_passed': json2.Any(true),
			'serial_sha256': json2.Any(hash(os.args[3])!), 'checker_source_sha256': json2.Any(hash(source_path)!),
			'scope': json2.Any('protected storage APK only; no account authentication claim')})!
		println('PROTECTED-STORAGE-CHECK-PASS expected=' + os.args[2])
		return
	}
	return error('usage: protected-storage-run selftest | prepare NEW_EXTERNAL_OUTPUT | check pass|missing-field SERIAL NEW_RESULT_JSON')
}

fn main() {
	run() or { eprintln('PROTECTED-STORAGE-GUEST-FAIL ' + err.msg()); exit(1) }
}
