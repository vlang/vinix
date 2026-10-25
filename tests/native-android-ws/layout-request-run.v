// SPDX-License-Identifier: GPL-2.0-or-later
// Three ART variants: Framework329/Native315, Framework332/Native315, and332/332.
module main

import json2
import os
import startupfixture
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/layout-request332-guest-v2-2026-10-25'
const baseline = '/Users/alex/.local/state/vinix/android/system-package330-fixture-2026-10-25'
const baseline_seal = '65cc180e2298fd76ea1d1dbffebe626f2c290b9ba33b8811c9b367ffa5c73c17'
const old_framework = 'c88b7f8a7ee34776641fc235922d0d86a0d8eefc60d09e50d55836aabb624934'
const old_native = '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'
const launcher = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'layout-request-run.v'
const variants = ['old', 'native-old', 'new']
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const manual_pass = 'BOOTSTRAP-LAYOUT-REQUESTS-PASS measure size layout listener next-measure stable-cache pending-child-propagation'
const fixture_prefix = 'LAYOUT-REQUEST-FIXTURE-'
const native_groups = ['ROOT-ARMED', 'ROOT-NEXT-PASS', 'ROOT-IDLE-PASS',
	'DIALOG-ARMED', 'DIALOG-NEXT-PASS', 'DIALOG-IDLE-PASS', 'PASS']

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

fn disk_checkpoint(label string, minimum_mib u64) ! {
	r := os.exec(['/bin/df', '-k', state])
	assert r.exit_code == 0, r.output
	fields := r.output.trim_space().split_into_lines().last().fields()
	assert fields.len >= 4
	available := fields[3].u64()
	write_json(state + '/disk-' + label + '.json', {
		'utc': json2.Any(time.utc().str())
		'minimum_mib': json2.Any(minimum_mib)
		'available_kib': json2.Any(available)
		'estimated_three_variant_peak_mib': json2.Any(1050)
		'raw': json2.Any(r.output)
		'scope': json2.Any('Focused45-second ART fixture; existing1536MiB preparation and1024MiB guest gates retained; independent Maps gate unchanged')
	})!
	assert available >= minimum_mib * 1024, 'fixture requires ' + minimum_mib.str() + ' MiB free; available KiB=' + available.str()
}

fn manifest(root string, seal string) !map[string]string {
	assert seal.len == 64 && hash(root + '/sha256.json')! == seal
	return json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
}

fn selected(path string, to string, pins map[string]string) ! {
	assert hash(baseline + '/' + path)! == pins[path]!, path
	clone(baseline + '/' + path, state + '/' + to)!
	assert hash(state + '/' + to)! == pins[path]!, to
}

fn selected_tree(path string, to string, pins map[string]string) ! {
	mut expected := map[string]string{}
	for key, pin in pins {
		if key.starts_with(path + '/') { expected[key.all_after(path + '/')] = pin }
	}
	assert expected.len > 0
	mut actual := map[string]string{}
	inventory(baseline + '/' + path, '', mut actual)!
	assert actual == expected, path
	clone(baseline + '/' + path, state + '/' + to)!
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
	assert receipt['command_sha256']! == receipt['command_sha256_after']!, argv[0]
	assert r.exit_code == 0, label
}

fn paths() string { return state + '/source|@vlib|@vmodules' }

fn source_closure(label string) !map[string]string {
	record(label + '-closure', [compiler, '-path', paths(), '-print-v-files', state + '/source/' + source_name])!
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
	staged := os.exists(state + '/staged-references.json')
	refs := if staged { json2.decode[map[string]string](os.read_file(state + '/staged-references.json')!)! } else { map[string]string{} }
	mut common := map[string]string{}
	for kind in variants {
		mut files := map[string]string{}
		inventory(state + '/native-' + kind, '', mut files)!
		assert files['popular-launcher']! == launcher
		assert files['api-impl.jar']! == if kind == 'old' || !staged { old_framework } else { refs['framework_sha256']! }
		assert files['libvinix-android-native.so']! == if kind != 'new' || !staged { old_native } else { refs['native_sha256']! }
		files.delete('api-impl.jar')
		files.delete('libvinix-android-native.so')
		if common.len == 0 { common = files.clone() } else { assert files == common, 'unexpected native/runtime delta' }
	}
	if os.exists(state + '/native-common.json') {
		assert json2.decode[map[string]string](os.read_file(state + '/native-common.json')!)! == common
	} else { write_json(state + '/native-common.json', common)! }
}

fn stable_inputs() !map[string]string {
	mut pins := map[string]string{}
	for dir in ['native-old', 'native-native-old', 'native-new', 'fixture-inputs', 'tools',
		'source', 'closure-inputs', 'generated-c', 'apk'] {
		mut files := map[string]string{}
		inventory(state + '/' + dir, '', mut files)!
		for key, pin in files { pins[dir + '/' + key] = pin }
	}
	for name in ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json',
		'initial-media/boot.img', 'initial-media/efivars.fd'] { pins[name] = hash(state + '/' + name)! }
	return pins
}

fn host_inputs(config map[string]json2.Any) !map[string]string {
	mut pins := map[string]string{}
	for key in ['aapt2', 'apksigner', 'firmware', 'input_tool', 'java', 'qemu'] {
		path := os.real_path(config[key]!.str())
		pins[path] = hash(path)!
	}
	pins[compiler] = hash(compiler)!
	assert pins[compiler]! == compiler_pin
	pins[os.real_path('/usr/bin/cc')] = hash(os.real_path('/usr/bin/cc'))!
	return pins
}

fn prepare() ! {
	assert !os.exists(state) && !os.is_link(state), 'fresh evidence root required'
	os.mkdir_all(state + '/source')!
	disk_checkpoint('prepare', 1536)!
	pins := manifest(baseline, baseline_seal)!
	clone(baseline + '/sha256.json', state + '/qualified330-sha256.json')!
	clone('tests/native-android-ws/' + source_name, state + '/source/' + source_name)!
	clone('tests/native-android-ws/startupfixture', state + '/source/startupfixture')!
	clone(os.executable(), state + '/tools/layout-request-bootstrap')!
	for name in ['tools/suite', 'tools/inflater-trace-seal', 'source/inflater-trace-seal.v',
		'source/suite.v', 'base-runtime.tar', 'initial-media.json', 'initial-media/boot.img',
		'initial-media/efivars.fd'] { selected(name, name, pins)! }
	for name in ['source/suite-support', 'fixture-inputs'] { selected_tree(name, name, pins)! }
	for kind in variants { selected_tree('native-new', 'native-' + kind, pins)! }
	native_equality()!
	selected('config.json', 'qualified330-config.json', pins)!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified330-config.json')!)!
	config['java'] = java
	config['applications'] = json2.Any([json2.Any({
		'apk': json2.Any(state + '/apk/probe.apk')
		'distribution': json2.Any('Vinix regression fixture')
		'id': json2.Any('bootstrap-fixture')
		'name': json2.Any('Callback layout requests and native traversal fixture')
		'package': json2.Any('org.vinix.bootstrap')
		'source': json2.Any(state + '/source/' + source_name)
		'startup_seconds': json2.Any(45)
	})])
	config['base_module'] = state + '/base-runtime.tar'
	write_json(state + '/config.json', config)!
	write_json(state + '/host-inputs.json', host_inputs(config)!)!
	os.mkdir_all(state + '/generated-c')!
	os.setenv('VTMP', state + '/generated-c', true)
	before := source_closure('runner-before')!
	record('compile-runner', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-enable-globals',
		'-path', paths(), '-o', state + '/tools/layout-request-run-checked', state + '/source/' + source_name])!
	after := source_closure('runner-after')!
	assert before == after, 'consumed V inputs changed during compilation'
	for path, pin in before { assert hash(state + '/closure-inputs/' + path.trim_left('/'))! == pin }
	record('generate-fixture', [state + '/tools/layout-request-run-checked', 'emit', state + '/apk'])!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	write_json(state + '/prepared-inputs.json', stable_inputs()!)!
	println('LAYOUT-REQUEST-PREPARED')
}

fn unsealed() { assert !os.exists(state + '/sha256.json'), 'sealed evidence must remain unchanged' }

fn stage(native_root string, native_seal string, native_key string, framework_root string, framework_seal string, framework_key string) ! {
	unsealed()
	assert !os.exists(state + '/shared-inputs.json'), 'stage exactly once'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/prepared-inputs.json')!)!
	np := manifest(native_root, native_seal)!
	fp := manifest(framework_root, framework_seal)!
	native_pin := np[native_key]!
	framework_pin := fp[framework_key]!
	assert native_pin != old_native && framework_pin != old_framework
	assert hash(native_root + '/' + native_key)! == native_pin
	assert hash(framework_root + '/' + framework_key)! == framework_pin
	clone(native_root + '/sha256.json', state + '/qualified332-native-sha256.json')!
	clone(framework_root + '/sha256.json', state + '/qualified332-framework-sha256.json')!
	for kind in ['native-old', 'new'] {
		os.rm(state + '/native-' + kind + '/api-impl.jar')!
		clone(framework_root + '/' + framework_key, state + '/native-' + kind + '/api-impl.jar')!
	}
	os.rm(state + '/native-new/libvinix-android-native.so')!
	clone(native_root + '/' + native_key, state + '/native-new/libvinix-android-native.so')!
	write_json(state + '/staged-references.json', {
		'baseline_root': baseline
		'baseline_manifest_sha256': baseline_seal
		'native_root': native_root
		'native_manifest_sha256': native_seal
		'native_key': native_key
		'native_sha256': native_pin
		'framework_root': framework_root
		'framework_manifest_sha256': framework_seal
		'framework_key': framework_key
		'framework_sha256': framework_pin
		'scope': 'Selected payloads authenticated against sealed manifests; complete source build readbacks are separate. Framework329/Native315 old, Framework332/Native315 native-old, Framework332/Native332 new. All other runtime files, signed APK and clean283 launcher identical.'
	})!
	native_equality()!
	assert hash(native_root + '/sha256.json')! == native_seal
	assert hash(framework_root + '/sha256.json')! == framework_seal
	assert hash(native_root + '/' + native_key)! == native_pin
	assert hash(framework_root + '/' + framework_key)! == framework_pin
	write_json(state + '/shared-inputs.json', stable_inputs()!)!
	println('LAYOUT-REQUEST-STAGED')
}

fn position(log string, marker string) int { return log.index(marker) or { panic('missing marker: ' + marker) } }

fn ordered(log string, markers []string) int {
	mut previous := -1
	for marker in markers {
		assert log.count(marker) == 1, marker
		next := position(log, marker)
		assert next > previous, marker
		previous = next
	}
	return previous
}

fn check_guest(kind string, output string) ! {
	log := os.read_file(output + '/bootstrap-fixture/serial.log')!
	ordered(log, [fixture_prefix + 'TRACE-ENV-ABSENT-PASS', fixture_prefix + 'CALL'])
	raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
	assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
	assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
	assert raw[0]['launcher_entered']!.bool()
	assert raw[0]['native_maps_observed']!.bool()
	assert raw[0]['qemu_alive_before_capture']!.bool()
	assert raw[0]['functional_passed']! is json2.Null
	outcome := raw[0]['outcome']!.str()
	if kind == 'new' {
		mut markers := [fixture_prefix + 'CALL', manual_pass]
		for name in native_groups { markers << fixture_prefix + name }
		markers << 'BOOTSTRAP-READY'
		ordered(log, markers)
		assert outcome == 'window_observed', outcome
		assert raw[0]['backend_ready']!.bool()
		assert !raw[0]['process_exited']!.bool()
		assert raw[0]['failure_markers']!.as_array().len == 0
		for bad in ['AssertionError', 'ANDROID-WS-FAIL', 'APK-SUITE-EXIT'] { assert !log.contains(bad), bad }
	} else {
		expected := if kind == 'old' {
			'java.lang.AssertionError: callback request lost, extra traversal or cached measurement not consumed'
		} else { 'java.lang.AssertionError: root callback request did not schedule the next measurement' }
		assert log.count('java.lang.AssertionError:') == 1
		assert log.count(expected) == 1
		assert log.count('APK-SUITE-EXIT id=bootstrap-fixture code=1 ') == 1
		assert position(log, 'APK-SUITE-EXIT id=bootstrap-fixture code=1 ') > position(log, expected)
		assert !log.contains('BOOTSTRAP-READY') && !log.contains(fixture_prefix + 'PASS')
		assert !log.contains(fixture_prefix + 'ROOT-NEXT-PASS')
		if kind == 'old' { assert !log.contains(manual_pass) && !log.contains(fixture_prefix + 'ROOT-ARMED') }
		else { ordered(log, [manual_pass, fixture_prefix + 'ROOT-ARMED', expected]) }
		assert outcome == 'startup_failed', outcome
		assert raw[0]['process_exited']!.bool()
		stage := if kind == 'old' { 'ANDROID-WS-FAIL start activity' } else { 'ANDROID-WS-FAIL main looper' }
		assert log.count('ANDROID-WS-FAIL') == 1
		ordered(log, [stage, expected, 'APK-SUITE-EXIT id=bootstrap-fixture code=1 '])
		failures := raw[0]['failure_markers']!.as_array()
		assert failures.len == 2
		assert failures[0].str() == stage
		assert failures[1].str().starts_with('APK-SUITE-EXIT id=bootstrap-fixture code=1 ')
	}
	for bad in ['NoSuchMethodError', 'NoSuchFieldError', 'NoClassDefFoundError', 'ClassNotFoundException',
		'UnsatisfiedLinkError', 'VerifyError', 'JNI DETECTED ERROR', 'ExceptionInInitializerError'] { assert !log.contains(bad), bad }
	write_json(state + '/' + kind + '-semantic-check.json', {
		'variant': kind
		'status': 'expected-result-pass'
		'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!
		'raw_results_path': output + '/results.json'
		'raw_results_sha256': hash(output + '/results.json')!
		'raw_outcome': outcome
		'checker_binary_sha256': hash(os.executable())!
		'scope': 'Manual startup probe qualifies framework callback flags in ART. Attached root/dialog checks qualify sampled native follow-up traversal and draw stability after settling; host suite separately covers all native callback positions. Raw historical classifier is distinct from semantic verdict; no Maps route qualification.'
	})!
	println('LAYOUT-REQUEST-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn run(kind string) ! {
	unsealed()
	assert kind in variants
	assert hash(os.executable())! == hash(state + '/tools/layout-request-run-checked')!, 'use frozen checked runner'
	assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
	native_equality()!
	mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
	assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
	disk_checkpoint(kind, 1024)!
	mut removed := []string{}
	for key, _ in os.environ() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' { removed << key; os.unsetenv(key) }
	}
	write_json(state + '/' + kind + '-environment.json', {'removed_host_variables': removed})!
	output := state + '/run-' + kind
	alias := os.abs_path('build/android-maps/lr332v2-' + kind)
	assert (alias + '/bootstrap-fixture/qmp.sock').len < 104
	assert !os.exists(alias) && !os.is_link(alias) && !os.exists(output) && !os.is_link(output)
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
	check_guest(kind, output)!
}

// Smali generation and signing are below; the public startup fixture generator
// remains the source of the manual regression classes.

const main_class = 'Lorg/vinix/bootstrap/Main;'
const request_view = 'Lorg/vinix/bootstrap/LayoutRequestView;'
const draw_view = 'Lorg/vinix/bootstrap/WsLayoutRequestView;'

fn smali_method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn smali_marker(name string) string {
	return 'const-string v0, "' + fixture_prefix + name + '"\ninvoke-static {v0}, ${main_class}->mark(Ljava/lang/String;)V\n'
}

fn draw_class() string {
	return '.class public ${draw_view}\n.super ${request_view}\n.field public draws:I\n' +
		smali_method('public constructor <init>(Landroid/content/Context;)V', '
invoke-direct {p0, p1}, ${request_view}-><init>(Landroid/content/Context;)V
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/View;->setWillNotDraw(Z)V
const/16 v0, 160
invoke-virtual {p0, v0}, Landroid/view/View;->setMinimumWidth(I)V
const/16 v0, 120
invoke-virtual {p0, v0}, Landroid/view/View;->setMinimumHeight(I)V
return-void', 1) +
		smali_method('protected onDraw(Landroid/graphics/Canvas;)V', '
iget v0, p0, ${draw_view}->draws:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${draw_view}->draws:I
return-void', 1)
}

// Polling never invalidates a view. Two equal samples with a real draw first
// isolate the armed request from startup/window resize work. Counts include
// onDraw: Java measure/layout caches alone cannot establish native quiescence.
fn attached_activity() string {
	mut source := '.class public ${main_class}\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' +
		'.field private view:${draw_view}\n.field private dialog:Landroid/app/Dialog;\n' +
		'.field private handler:Landroid/os/Handler;\n.field private stage:I\n.field private polls:I\n' +
		'.field private stable:I\n.field private savedMeasures:I\n.field private savedLayouts:I\n.field private savedDraws:I\n'
	source += smali_method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	source += smali_method('private static mark(Ljava/lang/String;)V', '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v0, p0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void', 1)
	source += smali_method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :location
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
goto :bad
:location
const-string v0, "ATL_UGLY_ENABLE_LOCATION"
invoke-static {v0}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
' + smali_marker('TRACE-ENV-ABSENT-PASS') + '
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "trace variables and location override must be absent"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 3)
	source += smali_method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, ${main_class}->traceAbsent()V
' + smali_marker('CALL') + '
invoke-static {p0}, Lorg/vinix/bootstrap/LayoutRequestProbe;->check(Landroid/content/Context;)V
new-instance v0, Landroid/os/Handler;
invoke-direct {v0}, Landroid/os/Handler;-><init>()V
iput-object v0, p0, ${main_class}->handler:Landroid/os/Handler;
new-instance v0, ${draw_view}
invoke-direct {v0, p0}, ${draw_view}-><init>(Landroid/content/Context;)V
iput-object v0, p0, ${main_class}->view:${draw_view}
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
invoke-direct {p0}, ${main_class}->post()V
return-void', 1)
	source += smali_method('private post()V', '
iget-object v0, p0, ${main_class}->handler:Landroid/os/Handler;
const-wide/16 v1, 200
invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
move-result v0
if-nez v0, :done
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "main Handler rejected layout fixture poll"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void', 3)
	source += smali_method('private retry(Ljava/lang/String;)V', '
iget v0, p0, ${main_class}->polls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_class}->polls:I
const/16 v1, 40
if-lt v0, v1, :again
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:again
invoke-direct {p0}, ${main_class}->post()V
return-void', 2)
	source += attached_counts()
	source += attached_callbacks()
	source += attached_dispatch()
	return source
}

fn attached_counts() string {
	mut source := smali_method('private saveCounts()V', '
iget-object v0, p0, ${main_class}->view:${draw_view}
iget v1, v0, ${request_view}->measures:I
iput v1, p0, ${main_class}->savedMeasures:I
iget v1, v0, ${request_view}->layouts:I
iput v1, p0, ${main_class}->savedLayouts:I
iget v1, v0, ${draw_view}->draws:I
iput v1, p0, ${main_class}->savedDraws:I
return-void', 2)
	source += smali_method('private sameCounts()Z', '
iget-object v0, p0, ${main_class}->view:${draw_view}
iget v1, v0, ${request_view}->measures:I
iget v2, p0, ${main_class}->savedMeasures:I
if-ne v1, v2, :different
iget v1, v0, ${request_view}->layouts:I
iget v2, p0, ${main_class}->savedLayouts:I
if-ne v1, v2, :different
iget v1, v0, ${draw_view}->draws:I
iget v2, p0, ${main_class}->savedDraws:I
if-ne v1, v2, :different
const/4 v0, 1
return v0
:different
const/4 v0, 0
return v0', 3)
	source += smali_method('private settle(Z)V', '
iget-object v0, p0, ${main_class}->view:${draw_view}
iget v1, v0, ${request_view}->measures:I
if-lez v1, :changed
iget v1, v0, ${request_view}->layouts:I
if-lez v1, :changed
iget v1, v0, ${draw_view}->draws:I
if-lez v1, :changed
invoke-virtual {v0}, Landroid/view/View;->isLayoutRequested()Z
move-result v1
if-nez v1, :changed
invoke-direct {p0}, ${main_class}->sameCounts()Z
move-result v0
if-eqz v0, :changed
iget v0, p0, ${main_class}->stable:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_class}->stable:I
const/4 v1, 2
if-lt v0, v1, :wait
invoke-direct {p0, p1}, ${main_class}->arm(Z)V
return-void
:changed
const/4 v0, 0
iput v0, p0, ${main_class}->stable:I
:wait
invoke-direct {p0}, ${main_class}->saveCounts()V
const-string v0, "root or dialog did not settle before arming callback request"
invoke-direct {p0, v0}, ${main_class}->retry(Ljava/lang/String;)V
return-void', 2)
	return source
}

fn attached_callbacks() string {
	mut source := smali_method('private arm(Z)V', '
iget-object v0, p0, ${main_class}->view:${draw_view}
const/4 v1, 0
iput v1, v0, ${request_view}->measures:I
iput v1, v0, ${request_view}->layouts:I
iput v1, v0, ${draw_view}->draws:I
iput-boolean v1, v0, ${request_view}->fired:Z
iput v1, p0, ${main_class}->polls:I
iput v1, p0, ${main_class}->stable:I
const/4 v1, 1
if-eqz p1, :mode
const/4 v1, 3
:mode
iput v1, v0, ${request_view}->mode:I
invoke-virtual {v0}, Landroid/view/View;->requestLayout()V
iget v0, p0, ${main_class}->stage:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_class}->stage:I
if-nez p1, :dialog
' + smali_marker('ROOT-ARMED') + '
goto :done
:dialog
' + smali_marker('DIALOG-ARMED') + '
:done
invoke-direct {p0}, ${main_class}->post()V
return-void', 2)
	source += smali_method('private awaitNext(Z)V', '
iget-object v0, p0, ${main_class}->view:${draw_view}
iget-boolean v1, v0, ${request_view}->fired:Z
if-eqz v1, :wait
const/4 v2, 2
iget v1, v0, ${request_view}->measures:I
if-lt v1, v2, :wait
iget v1, v0, ${request_view}->layouts:I
if-lt v1, v2, :wait
iget v1, v0, ${draw_view}->draws:I
if-lt v1, v2, :wait
invoke-virtual {v0}, Landroid/view/View;->isLayoutRequested()Z
move-result v1
if-nez v1, :wait
invoke-direct {p0}, ${main_class}->saveCounts()V
iget v0, p0, ${main_class}->stage:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${main_class}->stage:I
if-nez p1, :dialog
' + smali_marker('ROOT-NEXT-PASS') + '
goto :done
:dialog
' + smali_marker('DIALOG-NEXT-PASS') + '
:done
invoke-direct {p0}, ${main_class}->post()V
return-void
:wait
const-string v0, "root callback request did not schedule the next measurement"
if-eqz p1, :retry
const-string v0, "dialog callback request did not schedule the next measurement"
:retry
invoke-direct {p0, v0}, ${main_class}->retry(Ljava/lang/String;)V
return-void', 3)
	source += smali_method('private idle(Z)V', '
invoke-direct {p0}, ${main_class}->sameCounts()Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, ${main_class}->view:${draw_view}
invoke-virtual {v0}, Landroid/view/View;->isLayoutRequested()Z
move-result v0
if-nez v0, :bad
if-nez p1, :dialogDone
' + smali_marker('ROOT-IDLE-PASS') + '
new-instance v0, Landroid/app/Dialog;
invoke-direct {v0, p0}, Landroid/app/Dialog;-><init>(Landroid/content/Context;)V
iput-object v0, p0, ${main_class}->dialog:Landroid/app/Dialog;
new-instance v1, ${draw_view}
invoke-direct {v1, p0}, ${draw_view}-><init>(Landroid/content/Context;)V
iput-object v1, p0, ${main_class}->view:${draw_view}
invoke-virtual {v0, v1}, Landroid/app/Dialog;->setContentView(Landroid/view/View;)V
invoke-virtual {v0}, Landroid/app/Dialog;->show()V
const/4 v0, 0
iput v0, p0, ${main_class}->polls:I
iput v0, p0, ${main_class}->stable:I
iput v0, p0, ${main_class}->savedMeasures:I
iput v0, p0, ${main_class}->savedLayouts:I
iput v0, p0, ${main_class}->savedDraws:I
const/4 v0, 3
iput v0, p0, ${main_class}->stage:I
invoke-direct {p0}, ${main_class}->post()V
return-void
:dialogDone
' + smali_marker('DIALOG-IDLE-PASS') + '
iget-object v0, p0, ${main_class}->dialog:Landroid/app/Dialog;
invoke-virtual {v0}, Landroid/app/Dialog;->dismiss()V
const/4 v0, 6
iput v0, p0, ${main_class}->stage:I
' + smali_marker('PASS') + '
const-string v0, "BOOTSTRAP-READY"
invoke-static {v0}, ${main_class}->mark(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "callback traversal did not become idle: measurement layout draw counts or pending request changed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 2)
	return source
}

fn attached_dispatch() string {
	return smali_method('public run()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eq v0, v1, :dispatch
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "layout fixture callback must run on main Looper"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:dispatch
iget v0, p0, ${main_class}->stage:I
packed-switch v0, :cases
return-void
:rootSettle
const/4 v0, 0
invoke-direct {p0, v0}, ${main_class}->settle(Z)V
return-void
:rootNext
const/4 v0, 0
invoke-direct {p0, v0}, ${main_class}->awaitNext(Z)V
return-void
:rootIdle
const/4 v0, 0
invoke-direct {p0, v0}, ${main_class}->idle(Z)V
return-void
:dialogSettle
const/4 v0, 1
invoke-direct {p0, v0}, ${main_class}->settle(Z)V
return-void
:dialogNext
const/4 v0, 1
invoke-direct {p0, v0}, ${main_class}->awaitNext(Z)V
return-void
:dialogIdle
const/4 v0, 1
invoke-direct {p0, v0}, ${main_class}->idle(Z)V
return-void
:cases
.packed-switch 0
:rootSettle
:rootNext
:rootIdle
:dialogSettle
:dialogNext
:dialogIdle
.end packed-switch', 2)
}

fn emit_smali(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh smali output required'
	root := out + '/org/vinix/bootstrap'
	os.mkdir_all(root)!
	startupfixture.install_layout_request_probe(root)!
	os.write_file(root + '/Main.smali', attached_activity())!
	os.write_file(root + '/WsLayoutRequestView.smali', draw_class())!
}

fn apk_command(out string, label string, argv []string, pins map[string]string) ! {
	for path, pin in pins { assert hash(path)! == pin, path }
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(out + '/' + label + '.log', r.output)!
	write_json(out + '/' + label + '-receipt.json', {
		'argv': json2.Any(argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'input_sha256': json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(hash(os.executable())!)
	})!
	for path, pin in pins { assert hash(path)! == pin, path }
	assert r.exit_code == 0, label + ': ' + r.output
}

fn emit_apk(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh APK output required'
	emit_smali(out + '/smali')!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">Layout request fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Layout request fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	tools := state + '/fixture-inputs'
	aapt := tools + '/aapt2'
	signer := tools + '/apksigner.jar'
	framework := tools + '/framework-res.apk'
	smali := tools + '/smali'
	keytool := os.dir(java) + '/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = hash(path)! }
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = hash(smali + '/' + name)! }
	}
	assert pins.len > 6
	write_json(out + '/tool-inputs-before.json', pins)!
	apk_command(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	apk_command(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	apk_command(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex')
	apk_command(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	apk_command(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix layout request fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	apk_command(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'], pins)!
	apk_command(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	apk_command(out, 'signed-dex-disassemble', [java, '-cp', smali + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', out + '/probe.apk', '-o', out + '/signed-dex'], pins)!
	mut classes := map[string]string{}
	inventory(out + '/signed-dex', '', mut classes)!
	mut names := classes.keys()
	names.sort()
	assert names == ['org/vinix/bootstrap/LayoutRequestParent.smali', 'org/vinix/bootstrap/LayoutRequestProbe.smali', 'org/vinix/bootstrap/LayoutRequestView.smali', 'org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/WsLayoutRequestView.smali']
	write_json(out + '/executed-fixture-dex.json', {
		'actual_signed_apk_sha256': json2.Any(hash(out + '/probe.apk')!)
		'assembled_classes_dex_sha256': json2.Any(hash(out + '/classes.dex')!)
		'actual_signed_apk_disassembled_classes': json2.decode[json2.Any](json2.encode(classes))!
		'scope': json2.Any('Exact five classes disassembled from the actual signed APK, including public startupfixture manual check and attached root/dialog polling plus draw counter. No ART execution claimed by assembly.')
	})!
	write_json(out + '/tool-inputs-after.json', pins)!
	println('LAYOUT-REQUEST-FIXTURE-APK ' + hash(out + '/probe.apk')!)
}

fn main() {
	$if prod { panic('assertions required') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	assert os.args.len >= 2
	match os.args[1] {
		'prepare' { assert os.args.len == 2; prepare()! }
		'stage' {
			assert os.args.len == 8, 'stage NATIVE_ROOT NATIVE_MANIFEST NATIVE_KEY FRAMEWORK_ROOT FRAMEWORK_MANIFEST FRAMEWORK_KEY'
			stage(os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5]), os.args[6], os.args[7])!
		}
		'old', 'native-old', 'new' { assert os.args.len == 2; run(os.args[1])! }
		'emit' { assert os.args.len == 3; emit_apk(os.abs_path(os.args[2]))! }
		'emit-smali' { assert os.args.len == 3; emit_smali(os.abs_path(os.args[2]))! }
		'seal' {
			assert os.args.len == 2
			unsealed()
			for kind in variants { assert os.exists(state + '/' + kind + '-semantic-check.json') }
			assert stable_inputs()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
			native_equality()!
			r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
			print(r.output)
			assert r.exit_code == 0
		}
		else { panic('prepare | stage NATIVE_ROOT NATIVE_MANIFEST NATIVE_KEY FRAMEWORK_ROOT FRAMEWORK_MANIFEST FRAMEWORK_KEY | old | native-old | new | seal') }
	}
}
