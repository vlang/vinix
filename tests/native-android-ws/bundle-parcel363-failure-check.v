// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve a failed ART experiment; this checker never reports a fixture pass.
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

const state = '/Users/alex/.local/state/vinix/android/bundle-parcel363-fixture-2026-10-26'
const framework_manifest = '584a5fb8315925d6f715dda02289ac1fc0c966cb06496cfe6afe36e32b43cf03'
const new_jar = '14a019f166550f5cf5cff48b4c29d0d7aa61db35d3514cef00b4a67ad151de63'
const old_jar = '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a'
const native_pin = 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
const launcher_pin = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const apk_pin = 'c34f9b9b231fb2b1c7ce747c76c9fe695ba2ecc3980ee3775c547d86fbf1ff11'
const runner_pin = '4f05831c5ac84237e04f54fdf30b8d39d03c49a81e67295f9f5e20edb43ac626'
const source_pin = '80b0b752ba231687a3e45ae92854c797ce7b5395cd8ebf3007c3a27340f748b4'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const fixture_pin = 'ea61bf298f17589252fda8612b616c463c7cdf01bdc7d3816402dc4462f1bfb5'
const shared_pin = '9fd9d7d847c5ebaba5d668b89ff195e0a76df750ded451963635e7325bd40d49'
const original_cnfe = 'java.lang.ClassNotFoundException: Didn\'t find class "org.vinix.bootstrap.BundleParcelValue" on path: DexPathList[[zip file "/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar", zip file "/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk"],nativeLibraryDirectories=[/opt/vinix-android-aarch64/usr/lib/art, /opt/vinix-android-aarch64/usr/lib/art]]'
const exit_marker = 'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true'
const serial_pins = {'old': '3685de7f8ed7f929a0397194e1a22a18f61bbe77102aff1b035017bac210536d',
 'new': '95927bd8fc4e5b65dbf28c3b33738cab17649ab36a616243485d3ad02c236858'}
const raw_pins = {'old': '3d77da281431e6885a16a8b57ec1d3c3bd217652f0e8eef6e734e5510c9c0a74',
 'new': 'b5a1e21b8e03bb17f3a50e854045bd9663414cef0d74871be0a21c0f5f2b307f'}

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

fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn write_json[T](path string, value T) ! {
 assert !os.exists(path), path
 os.mkdir_all(os.dir(path))!
 os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut files map[string]string) ! {
 for name in os.ls(root + '/' + prefix)! {
  key := if prefix == '' { name } else { prefix + '/' + name }
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { inventory(root, key, mut files)! }
   .regular { files[key] = hash(root + '/' + key)! }
   else { return error('nonregular evidence: ' + key) }
  }
 }
}

fn complete(root string, manifest string, payload string, pin string) !int {
 assert hash(root + '/sha256.json')! == manifest
 expected := read_map(root + '/sha256.json')!
 assert expected.len > 0 && 'sha256.json' !in expected && expected[payload]! == pin
 mut actual := map[string]string{}
 inventory(root, '', mut actual)!
 actual.delete('sha256.json')
 assert actual == expected && hash(root + '/sha256.json')! == manifest, root
 return actual.len
}

fn stable() !map[string]string {
 mut pins := map[string]string{}
 for dir in ['framework363', 'native-old', 'native-new', 'fixture-inputs', 'tools',
  'source', 'frozen', 'closure-inputs', 'generated-c', 'apk', 'initial-media'] {
  mut files := map[string]string{}
  inventory(state + '/' + dir, '', mut files)!
  for key, pin in files { pins[dir + '/' + key] = pin }
 }
 for key in ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json', 'build-pins.json'] {
  pins[key] = hash(state + '/' + key)!
 }
 return pins
}

fn ordered(lines []string, expected []string) ! {
 assert lines.len == expected.len
 for i, prefix in expected { assert lines[i].starts_with(prefix), prefix }
}

fn inspect() !map[string]string {
 pins := read_map(state + '/build-pins.json')!
 assert pins['framework_manifest']! == framework_manifest && pins['framework_jar']! == new_jar
 assert pins['old_framework_jar']! == old_jar && pins['apk']! == apk_pin && pins['runner']! == runner_pin
 assert pins['fixture_commit']! == '2082297e21b003d63df2cf17a584c781aa903627' && pins['fixture_source']! == fixture_pin
 assert hash(state + '/apk/probe.apk')! == apk_pin && hash(state + '/tools/checked-runner')! == runner_pin
 assert hash(state + '/source/bundle-parcel-run.v')! == source_pin && hash(state + '/frozen/vroot/bundle-parcel-run.v')! == source_pin
 assert hash(state + '/frozen/vroot/bundle-parcel-driver/startupfixture/bundle_parcel.v')! == fixture_pin
 assert hash(state + '/shared-inputs.json')! == shared_pin
 expected := read_map(state + '/shared-inputs.json')!
 assert stable()! == expected
 complete(state + '/framework363', framework_manifest, 'framework/api-impl.jar', new_jar)!
 mut original := map[string]string{}
 inventory(state + '/framework363/baseline361/baseline359/baseline353/native-new', '', mut original)!
 original.delete('api-impl.jar')
 for kind in ['old', 'new'] {
  assert read_map(state + '/' + kind + '-inputs-before.json')! == expected
  if kind == 'old' {
   assert read_map(state + '/old-inputs-after.json')! == expected
  } else {
   // The original runner stopped before emitting this receipt; preserve its absence.
   assert !os.exists(state + '/new-inputs-after.json')
  }
  mut native := map[string]string{}
  inventory(state + '/native-' + kind, '', mut native)!
  assert native['api-impl.jar']! == if kind == 'old' { old_jar } else { new_jar }
  assert native['libvinix-android-native.so']! == native_pin && native['popular-launcher']! == launcher_pin
  native.delete('api-impl.jar')
  assert native == original, 'only framework JAR differs'
  command := object(state + '/commands/suite-' + kind + '.json')!
  assert command['exit_code']!.int() == 0 && command['executable_sha256']!.str() == hash(state + '/tools/suite')!
  assert command['argv']!.as_array().map(it.str()) == [state + '/tools/suite', state + '/' + kind + '.json']
  output := state + '/run-' + kind
  assert hash(output + '/bootstrap-fixture/serial.log')! == serial_pins[kind]!
  assert hash(output + '/results.json')! == raw_pins[kind]!
  raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
  assert raw.len == 1
  row := raw[0]
  assert row['id']!.str() == 'bootstrap-fixture' && row['package']!.str() == 'org.vinix.bootstrap'
  assert row['staged_apk']!.str() == state + '/apk/probe.apk' && row['container_sha256']!.str() == apk_pin
  assert row['metadata']!.as_map()['apk_sha256']!.str() == apk_pin
  assert row['source']!.str() == state + '/source/bundle-parcel-run.v'
  assert row['outcome']!.str() == 'startup_failed' && row['process_exited']!.bool()
  assert row['functional_passed']! is json2.Null && row['startup_seconds']!.int() == 35
  assert row['launcher_entered']!.bool() && row['native_maps_observed']!.bool() && row['qemu_alive_before_capture']!.bool()
  assert row['serial_sha256']!.str() == serial_pins[kind]!
  assert hash(output + '/bootstrap-fixture/application.png')! == row['screenshot_sha256']!.str()
  log := os.read_file(output + '/bootstrap-fixture/serial.log')!
  lines := log.split_into_lines().map(it.trim_space())
  for exact in ['BUNDLE-PARCEL-BEGIN', 'ANDROID-WS-FAIL start activity', exit_marker] { assert lines.filter(it == exact).len == 1 }
  assert log.count('ANDROID-WS-FAIL') == 1
  frames := lines.filter(it.starts_with('at android.os.Parcel.') || it.starts_with('at org.vinix.bootstrap.'))
  if kind == 'old' {
   assert lines.filter(it == original_cnfe).len == 1 && log.count('ClassNotFoundException') == 1
   assert !log.contains('AssertionError') && !log.contains('BUNDLE-PARCEL-DEFERRED-PASS') && !log.contains('BUNDLE-PARCEL-COPY-PASS')
   ordered(frames, ['at android.os.Parcel.readParcelable(', 'at android.os.Parcel.readValue(',
    'at android.os.Parcel.readBundle(', 'at android.os.Parcel.readValue(', 'at android.os.Parcel.readBundle(',
    'at android.os.Parcel.readBundle(', 'at org.vinix.bootstrap.BundleParcelProbe.snapshot(',
    'at org.vinix.bootstrap.BundleParcelProbe.check(', 'at org.vinix.bootstrap.Main.onCreate('])!
   assert row['failure_markers']!.as_array().map(it.str()) == ['ANDROID-WS-FAIL start activity', original_cnfe, exit_marker]
  } else {
   assertion := 'java.lang.AssertionError: Bundle deferred parcel state, loader or value'
   assert lines.filter(it == assertion).len == 1 && log.count('AssertionError') == 1 && !log.contains('ClassNotFoundException')
   ordered(lines.filter(it.starts_with('BUNDLE-PARCEL-')), ['BUNDLE-PARCEL-BEGIN', 'BUNDLE-PARCEL-DEFERRED-PASS', 'BUNDLE-PARCEL-COPY-PASS'])!
   ordered(frames, ['at org.vinix.bootstrap.BundleParcelProbe.decoded(Unknown Source:99)',
    'at org.vinix.bootstrap.BundleParcelProbe.check(Unknown Source:113)', 'at org.vinix.bootstrap.Main.onCreate(Unknown Source:3)'])!
   assert row['observation_elapsed_seconds']!.int() < 35
   assert row['failure_markers']!.as_array().map(it.str()) == ['ANDROID-WS-FAIL start activity', exit_marker]
  }
  for missing in ['BUNDLE-PARCEL-ROUNDTRIP-PASS', 'BUNDLE-PARCEL-EMPTY-PASS', 'BUNDLE-PARCEL-PASS',
   'VerifyError', 'NullPointerException', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'JNI DETECTED ERROR'] { assert !log.contains(missing), missing }
 }
 parcel := os.read_file(state + '/framework363/framework/smali/android/os/Parcel.smali')!.split_into_lines().map(it.trim_space()).filter(it != '').join('\n')
 assert parcel.contains(':pswitch_a2\nnew-instance v0, Landroid/os/Binder;\ninvoke-direct {v0}, Landroid/os/Binder;-><init>()V\ngoto/16 :goto_21')
 assert parcel.contains(':cond_163\ninstance-of v0, p1, Landroid/os/Binder;\nif-eqz v0, :cond_16e\nconst/16 v0, 0x15\ninvoke-virtual {p0, v0}, Landroid/os/Parcel;->writeInt(I)V\ngoto/16 :goto_6')
 assert stable()! == expected
 assert hash(state + '/shared-inputs.json')! == shared_pin
 return {'status': 'FAILED-ART-EVIDENCE', 'fixture_passed': 'false', 'old_result': 'expected eager app Parcelable CNFE reproduced',
  'new_result': 'startup_failed after DEFERRED-PASS and COPY-PASS; shared decoded assertion in post-copy putAll decode',
  'separate_provider_finding': 'preserved generic Parcel Binder branches write only tag21 and construct a new Binder on read, losing identity; follow-up ART is required to establish the causal fix',
  'original_checker_defect': 'synthetic old CNFE text and array-first frames differed from retained actual ART; original source and runner preserved',
  'original_new_after_receipt': 'absent; original runner stopped before writing it; preservation audit verifies current shared inputs unchanged before and after inspection',
  'signed_apk_sha256': apk_pin, 'preparation_runner_sha256': runner_pin, 'preparation_source_sha256': source_pin,
  'original_shared_inputs_sha256': shared_pin,
  'framework_manifest_sha256': framework_manifest, 'old_framework_sha256': old_jar, 'new_framework_sha256': new_jar,
  'old_serial_sha256': serial_pins['old']!, 'old_results_sha256': raw_pins['old']!,
  'new_serial_sha256': serial_pins['new']!, 'new_results_sha256': raw_pins['new']!,
  'scope': 'Preservation and exact failure verification only. Both raw ART outcomes are startup_failed; no full35second new survival, no successful regression qualification, no Maps result.'}
}

fn bootstrap(root string, manifest string) !string {
 assert os.dir(root) == os.dir(state) && os.base(root).starts_with('bundle-parcel363-failure-check-build-')
 binary := hash(os.executable())!
 complete(root, manifest, 'bundle-parcel363-failure-check', binary)!
 build := object(root + '/build.json')!
 source := root + '/frozen/vroot/source/bundle-parcel363-failure-check.v'
 assert build['binary_sha256']!.str() == binary && build['source_sha256']!.str() == hash(source)!
 assert build['compiler_sha256']!.str() == compiler_pin && hash(root + '/frozen/vroot/v')! == compiler_pin
 before := read_map(root + '/closure-before.json')!
 assert before == read_map(root + '/closure-after.json')! && before.len == build['v_input_count']!.int()
 for path, pin in before { assert os.real_path(path).starts_with(root + '/') && hash(path)! == pin }
 environment := read_map(root + '/compile-environment.json')!
 vroot := root + '/frozen/vroot'
 assert environment == {'VROOT': vroot, 'VEXE': vroot + '/v', 'VTMP': root + '/generated-c', 'VMODULES': root + '/vmodules'}
 compile := object(root + '/commands/compile.json')!
 assert compile['exit_code']!.int() == 0 && compile['executable_sha256']!.str() == compiler_pin
 assert compile['argv']!.as_array().map(it.str()) == [vroot + '/v', '-path', vroot + '/vlib', '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-o', root + '/bundle-parcel363-failure-check', source]
 test := object(root + '/commands/self-test.json')!
 assert test['exit_code']!.int() == 0 && test['executable_sha256']!.str() == binary
 assert test['argv']!.as_array().map(it.str()) == [root + '/bundle-parcel363-failure-check', 'self-test']
 assert os.read_file(root + '/commands/self-test.log')!.trim_space() == 'BUNDLE-PARCEL363-FAILED-ART-EVIDENCE-INSPECTED'
 for path, pin in build['host_tools']!.as_map() { assert hash(path)! == pin.str() }
 return hash(source)!
}

fn audit(root string, manifest string) !map[string]string {
 source := bootstrap(root, manifest)!
 mut result := inspect()!
 result['checker_bootstrap_root'] = root
 result['checker_bootstrap_manifest_sha256'] = manifest
 result['checker_binary_sha256'] = hash(os.executable())!
 result['checker_source_sha256'] = source
 return result
}

fn main() {
 $if prod { panic('assertions required') }
 if os.args.len == 2 && os.args[1] == 'self-test' {
  result := inspect()!
  assert result['status']! == 'FAILED-ART-EVIDENCE' && result['fixture_passed']! == 'false'
  println('BUNDLE-PARCEL363-FAILED-ART-EVIDENCE-INSPECTED')
  return
 }
 if os.args.len == 4 && os.args[1] == 'audit' {
  assert !os.exists(state + '/sha256.json') && !os.exists(state + '/failure-audit')
  result := audit(os.args[2], os.args[3])!
  os.mkdir_all(state + '/failure-audit')!
  for pair in [[os.args[2] + '/bundle-parcel363-failure-check', 'checker'],
   [os.args[2] + '/frozen/vroot/source/bundle-parcel363-failure-check.v', 'source.v']] {
   r := os.exec(['/bin/cp', '-c', pair[0], state + '/failure-audit/' + pair[1]])
   assert r.exit_code == 0, r.output
  }
  write_json(state + '/failed-art-check.json', result)!
  assert stable()! == read_map(state + '/shared-inputs.json')!
  println('BUNDLE-PARCEL363-FAILED-ART-EVIDENCE-RECORDED')
  return
 }
 assert os.args.len == 2 && os.args[1] == 'seal', 'self-test | audit BOOTSTRAP_ROOT MANIFEST_SHA | seal'
 assert !os.exists(state + '/sha256.json')
 prior := read_map(state + '/failed-art-check.json')!
 result := audit(prior['checker_bootstrap_root']!, prior['checker_bootstrap_manifest_sha256']!)!
 assert result == prior && hash(state + '/failure-audit/checker')! == prior['checker_binary_sha256']!
 assert hash(state + '/failure-audit/source.v')! == prior['checker_source_sha256']!
 write_json(state + '/qualification/failed-art-seal-check.json', result)!
 // Complete sealing is separate from fixture qualification. Retain all failures.
 argv := [state + '/tools/inflater-trace-seal', 'seal', state]
 assert hash('tests/native-android-ws/inflater-trace-seal.v')! == hash(state + '/source/inflater-trace-seal.v')!
 pin := hash(argv[0])!
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(state + '-failed-art-seal.log', r.output)!
 write_json(state + '-failed-art-seal-command.json', {'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code),
  'executable_sha256': json2.Any(pin), 'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str())})!
 assert r.exit_code == 0 && hash(argv[0])! == pin, r.output
 print(r.output)
}
