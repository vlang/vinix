// SPDX-License-Identifier: GPL-2.0-or-later
// Independent final ART readback. The original complete auditor runs once;
// the separate validator bootstrap has its own independent reviewer.
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

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/timing-logger367-fixture-2026-10-26'
const output = state + '/timing-logger367-art-peer-readback-2026-10-26'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const original_runner = 'a33a93cb8c8d21b244e92eca86a5d3dac8e23dd0142364db441b338ddcdd03a4'
const corrected_runner = '095ad9ad09f9a0a145f5cd4d24913514447ad6adde8fe24277abd26d3b00e72b'
const old_jar = 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
const new_jar = 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
const apk_pin = '301c622cf8e986632b4797c0b63f366cbabfc99b3ed5d7d42ec401d908afb534'
const rejection = 'java.lang.ClassNotFoundException: android.util.TimingLogger'
const markers = ['TIMING-LOGGER-CONSTRUCTOR-PASS', 'TIMING-LOGGER-SPLIT-PASS',
 'TIMING-LOGGER-RESET-PASS', 'TIMING-LOGGER-DUMP-PASS', 'TIMING-LOGGER-DISABLED-PASS', 'TIMING-LOGGER-PASS']

fn hash(path string) !string {
 assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular, path
 mut file := os.open(path)!
 defer { file.close() }
 mut digest := C.CC_SHA256_CTX{}
 mut buffer := []u8{len: 1024 * 1024}
 assert C.CC_SHA256_Init(unsafe { &digest }) == 1
 for {
  n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
 }
 mut result := [32]u8{}
 assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) == 1
 return result[..].hex()
}
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn pins(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn subset(all map[string]string, prefix string) map[string]string {
 mut found := map[string]string{}
 for key, pin in all { if key.starts_with(prefix) { found[key[prefix.len..]] = pin } }
 return found
}

fn inputs(manifest map[string]string) !int {
 assert hash(root + '/shared-inputs.json')! == '7116f91f15ba29f61bdbd9e5026d08b6d2a4174636e200e6f14dc4f69c049216'
 assert hash(root + '/build-pins.json')! == '22b010922ba500647cbc58bd2b16c9ebead0b5b2daf54287f5b1ff9d5cfd8e8e'
 shared := pins(root + '/shared-inputs.json')!
 mut expected := map[string]string{}
 dirs := ['framework367', 'native-old', 'native-new', 'fixture-inputs', 'tools', 'source',
  'frozen', 'closure-inputs', 'generated-c', 'apk', 'initial-media']
 singles := ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json', 'build-pins.json']
 for key, pin in manifest {
  if key in singles || dirs.any(key.starts_with(it + '/')) { expected[key] = pin }
 }
 assert shared == expected, 'complete prepared input inventory must match canonical manifest'
 for kind in ['old', 'new'] {
  for phase in ['before', 'after'] { assert pins(root + '/' + kind + '-inputs-' + phase + '.json')! == shared }
 }
 mut old := subset(shared, 'native-old/')
 mut new := subset(shared, 'native-new/')
 assert old['api-impl.jar']! == old_jar && new['api-impl.jar']! == new_jar
 old.delete('api-impl.jar')
 new.delete('api-impl.jar')
 assert old.len > 0 && old == new, 'framework JAR must be sole native closure delta'
 assert old['libvinix-android-native.so']! == 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
 assert old['popular-launcher']! == '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
 assert subset(shared, 'apk/smali/').keys().sorted() == ['org/vinix/bootstrap/Main.smali',
  'org/vinix/bootstrap/TimingLoggerProbe.smali', 'org/vinix/bootstrap/TimingLoggerSubclass.smali']
 assert shared['apk/probe.apk']! == apk_pin && hash(root + '/apk/probe.apk')! == apk_pin
 assert shared['tools/checked-runner']! == original_runner
 for key, pin in {
  'framework367/sha256.json': '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
  'framework367/baseline365/sha256.json': 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
  'framework367/baseline365/baseline361/sha256.json': '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
  'framework367/baseline365/baseline361/baseline359/sha256.json': '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
  'framework367/baseline365/baseline361/baseline359/baseline353/sha256.json': '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
 } { assert shared[key]! == pin && hash(root + '/' + key)! == pin }
 mut closure_count := 0
 for kind in ['fixture-driver', 'runner'] {
  before := pins(root + '/' + kind + '-before-v-files.json')!
  assert before == pins(root + '/' + kind + '-after-v-files.json')! && before.len > 0
  for path, pin in before {
   assert os.real_path(path) == path && path.starts_with(root + '/frozen/vroot/')
   assert !path.contains('/androidtools/'), 'framework generator in ART fixture build'
   assert shared[path[root.len + 1..]]! == pin
   assert shared['closure-inputs/' + path.trim_left('/')]! == pin
  }
  closure_count += before.len
 }
 mut a := object(root + '/old.json')!
 mut b := object(root + '/new.json')!
 for key in ['output', 'native_dir', 'boot_image', 'efivars'] {
  assert a[key]!.str() != b[key]!.str()
  a.delete(key)
  b.delete(key)
 }
 assert a == b, 'same runtime configuration and application except per-run paths'
 apps := a['applications']!.as_array()
 assert apps.len == 1 && apps[0].as_map()['apk']!.str() == root + '/apk/probe.apk'
 assert apps[0].as_map()['startup_seconds']!.int() == 35
 return closure_count
}

fn runtime(kind string) ! {
 values := json2.decode[[]map[string]json2.Any](os.read_file(root + '/run-' + kind + '/results.json')!)!
 assert values.len == 1
 raw := values[0]
 log := os.read_file(root + '/run-' + kind + '/bootstrap-fixture/serial.log')!
 lines := log.split_into_lines().map(it.trim_space())
 assert raw['id']!.str() == 'bootstrap-fixture' && raw['package']!.str() == 'org.vinix.bootstrap'
 assert raw['container_sha256']!.str() == apk_pin && raw['metadata']!.as_map()['apk_sha256']!.str() == apk_pin
 assert raw['staged_apk']!.str() == root + '/apk/probe.apk'
 assert raw['launcher_entered']!.bool() && raw['native_maps_observed']!.bool()
 assert raw['functional_passed']! is json2.Null && raw['startup_seconds']!.int() == 35
 assert lines.filter(it == 'TIMING-LOGGER-BEGIN').len == 1
 if kind == 'old' {
  expected := ['TIMING-LOGGER-BEGIN', 'ANDROID-WS-FAIL start activity', rejection,
   'at java.lang.Class.classForName(Native Method)', 'at java.lang.Class.forName(Class.java:453)',
   'at java.lang.Class.forName(Class.java:378)', 'at org.vinix.bootstrap.TimingLoggerProbe.check(Unknown Source:2)',
   'at org.vinix.bootstrap.Main.onCreate(Unknown Source:10)', 'at android.app.Activity.vinixPerformCreate(Unknown Source:5)',
   'Caused by: ' + rejection, '... 6 more',
   'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true']
  start := lines.index(expected[0])
  assert start >= 0 && start + expected.len <= lines.len && lines[start..start + expected.len] == expected
  assert lines.filter(it.starts_with('at ')) == expected[3..9]
  assert log.count('ClassNotFoundException') == 2 && log.count('ANDROID-WS-FAIL') == 1
  assert lines.filter(it.starts_with('Caused by:')) == ['Caused by: ' + rejection] && !log.contains('Suppressed:')
  for marker in markers { assert !log.contains(marker) }
  assert raw['outcome']!.str() == 'startup_failed' && raw['process_exited']!.bool()
  assert raw['failure_markers']!.as_array().map(it.str()) == [expected[1], rejection, expected[9], expected[11]]
 } else {
  mut expected := ['TIMING-LOGGER-BEGIN', 'TIMING-LOGGER367-INITIAL', 'initial: begin',
   'TIMING-LOGGER367-INITIAL', 'initial: end, 0 ms', markers[0], markers[1], markers[2]]
  for _ in 0 .. 2 {
   for message in ['deterministic: begin', 'deterministic:      7 ms, a',
    'deterministic:      9 ms, b', 'deterministic: end, 16 ms'] { expected << 'TIMING-LOGGER367'; expected << message }
  }
  expected << markers[3..]
  assert lines.filter(it.starts_with('TIMING-LOGGER') || it.starts_with('initial:') || it.starts_with('deterministic:')) == expected
  for marker in markers { assert lines.filter(it == marker).len == 1 }
  assert raw['outcome']!.str() == 'window_observed' && !raw['process_exited']!.bool()
  assert raw['observation_elapsed_seconds']!.int() >= 35 && raw['qemu_alive_before_capture']!.bool()
  assert raw['failure_markers']!.as_array().len == 0
  for bad in ['ClassNotFoundException', 'ANDROID-WS-FAIL', 'APK-SUITE-EXIT id=bootstrap-fixture ',
   'APK-SUITE-DEPENDENCY-FAIL', 'ANDROID-WS-DEPENDENCY-FAIL', 'ANDROID-WS-PROCESS-FAIL'] { assert !log.contains(bad) }
 }
 for bad in ['AssertionError', 'NullPointerException', 'VerifyError', 'NoClassDefFoundError',
  'NoSuchMethodError', 'NoSuchFieldError', 'UnsatisfiedLinkError', 'JNI DETECTED ERROR',
  'ExceptionInInitializerError', 'AbstractMethodError'] { assert !log.contains(bad) }
 for phase in ['', '-seal'] {
  receipt := pins(root + '/qualification/observed-' + kind + phase + '-semantic-check.json')!
  assert receipt['checker_binary_sha256']! == corrected_runner && receipt['status']! == 'expected-result-pass'
  assert receipt['signed_apk_sha256']! == apk_pin && receipt['variant']! == kind
  assert receipt['old_framework_sha256']! == old_jar && receipt['new_framework_sha256']! == new_jar
  assert receipt['serial_sha256']! == hash(root + '/run-' + kind + '/bootstrap-fixture/serial.log')!
  assert receipt['raw_results_sha256']! == hash(root + '/run-' + kind + '/results.json')!
  assert receipt['raw_outcome']! == raw['outcome']!.str()
 }
 assert pins(root + '/qualification/observed-' + kind + '-semantic-check.json')! == pins(root + '/qualification/observed-' + kind + '-seal-semantic-check.json')!
}

fn invocations() ! {
 assert !os.exists(root + '/old-semantic-check.json'), 'preserve original validator failure'
 observed := pins(root + '/qualification/observed-invocations.json')!
 assert observed.len == 9
 for path, pin in observed {
  retained := root + '/qualification/original-invocations/' + os.base(path)
  assert hash(retained)! == pin && hash(path)! == pin
 }
 for kind in ['old', 'new'] {
  prefix := root + '/qualification/original-invocations/timing-logger367-fixture-' + kind + '-2026-10-26'
  actual := object(prefix + '-command.json')!
  before := object(prefix + '-before.json')!
  for key, value in before { assert value == actual[key]! }
  assert actual['argv']!.as_array().map(it.str()) == [root + '/tools/checked-runner', kind]
  assert actual['executable_sha256_before']!.str() == original_runner && actual['executable_sha256_after']!.str() == original_runner
  assert actual['recorder_source_sha256']!.str() == '36cd71cdec17ccf3cd4fb964786deb177e161cb49c76cd8d437a80b4dd2d187d'
  assert actual['recorder_binary_sha256']!.str() == 'dc823bd2632ede0ff06e7cfa1987fe1dff9dd4417e3314b9a0b145c2db6f71bb'
  assert actual['cwd']!.str() == repo && actual['started_utc']!.str() < actual['completed_utc']!.str()
  assert actual['exit_code']!.int() == if kind == 'old' { 1 } else { 0 }
  assert actual['output_sha256']!.str() == hash(prefix + '.log')!
  assert hash(prefix + '-command.json')! == if kind == 'old' {
   'f46e40bc67b3ce9c8f232426496914ac2ff8541da30a90f59ca40494431c5b68'
  } else { '8f7547aae1fd70f13ac924d0311007c35dc52d40167cd33d1ec43d64a0375891' }
  original_log := os.read_file(prefix + '.log')!
  assert if kind == 'old' { original_log.contains('V panic: exact TimingLogger CNFE') }
   else { original_log.trim_space() == 'TIMING-LOGGER-NEW-EXPECTED-RESULT-PASS' }
  suite := object(root + '/commands/suite-' + kind + '.json')!
  assert suite['exit_code']!.int() == 0 && suite['executable_sha256']!.str() == hash(root + '/tools/suite')!
  assert suite['argv']!.as_array().map(it.str()) == [root + '/tools/suite', root + '/' + kind + '.json']
 }
 assert pins(root + '/new-semantic-check.json')!['checker_binary_sha256']! == original_runner
 assert hash(root + '/qualification/validator-build/sha256.json')! == 'e8c12e1253ef246f1e7df1567ca8ae489963e0eca6f7fbd21438e1f5b9180116'
 assert hash(root + '/qualification/validator-build/frozen/vroot/source/timing-logger367-validator.v')! == '2fb71f7be68319affe0d0fe2a9fbd07e62d8883a9d66dd125205d5e38bbfcf79'
}

fn observed_actions(manifest string, count int) ! {
 for action in ['qualify', 'seal'] {
  prefix := state + '/timing-logger367-fixture-observed-' + action + '-2026-10-26'
  actual := object(prefix + '-command.json')!
  before := object(prefix + '-before.json')!
  for key, value in before { assert value == actual[key]! }
  executable := state + '/timing-logger367-validator-build-2026-10-26/timing-logger367-validator'
  assert actual['argv']!.as_array().map(it.str()) == [executable, 'observed-' + action]
  assert actual['exit_code']!.int() == 0 && actual['cwd']!.str() == repo
  assert actual['started_utc']!.str() < actual['completed_utc']!.str()
  assert actual['executable_sha256_before']!.str() == corrected_runner
  assert actual['executable_sha256_after']!.str() == corrected_runner && hash(executable)! == corrected_runner
  assert actual['recorder_source_sha256']!.str() == '2afa2383b475974b996ca968d74a37cc8249087744aa6b03e275f46ee9961c6b'
  assert actual['recorder_binary_sha256']!.str() == 'b19b1cecaba579b1b3a20f8b762a1bce0b6988ea56be3fc74d6b34507dd00b62'
  assert actual['output_sha256']!.str() == hash(prefix + '.log')!
  ending := if action == 'qualify' { 'TIMING-LOGGER-OBSERVED-QUALIFICATION-PASS' }
   else { 'INFLATER-TRACE-BUNDLE-SEALED root=' + root + ' files=' + count.str() + ' manifest=' + manifest }
  assert os.read_file(prefix + '.log')!.trim_space().split_into_lines() == [
   'TIMING-LOGGER-OLD-EXPECTED-RESULT-PASS', 'TIMING-LOGGER-NEW-EXPECTED-RESULT-PASS', ending]
  for suffix in ['-before.json', '-command.json', '.log'] {
   os.cp(prefix + suffix, output + '/' + os.base(prefix) + suffix)!
  }
 }
}

fn main() {
 $if prod { panic('assertions required') }
 assert os.args.len == 2 && os.getwd() == repo && os.real_path(root) == root
 manifest_pin := os.args[1]
 assert manifest_pin.len == 64 && manifest_pin.bytes().all(it in '0123456789abcdef'.bytes())
 assert !os.exists(output) && !os.is_link(output), 'fresh adjacent reader output required'
 assert hash(root + '/sha256.json')! == manifest_pin && hash(checker)! == checker_pin
 manifest := pins(root + '/sha256.json')!
 closure_count := inputs(manifest)!
 invocations()!
 runtime('old')!
 runtime('new')!
 os.mkdir(output)!
 os.cp(@FILE, output + '/reader.v')!
 os.cp(os.executable(), output + '/reader')!
 observed_actions(manifest_pin, manifest.len)!
 argv := [checker, root, manifest_pin, output + '/complete-receipt.json']
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(output + '/stdout.log', r.output)!
 os.write_file(output + '/command.json', json2.encode({
  'argv': json2.Any(argv), 'working_directory': json2.Any(repo),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'exit_code': json2.Any(r.exit_code), 'checker_sha256': json2.Any(checker_pin),
  'manifest_sha256_before': json2.Any(manifest_pin), 'manifest_sha256_after': json2.Any(hash(root + '/sha256.json')!),
  'reader_source_sha256': json2.Any(hash(@FILE)!), 'reader_binary_sha256': json2.Any(hash(os.executable())!),
  'stdout_sha256': json2.Any(hash(output + '/stdout.log')!), 'frozen_closure_inputs': json2.Any(closure_count)
 }, prettify: true) + '\n')!
 assert r.exit_code == 0, r.output
 assert hash(root + '/sha256.json')! == manifest_pin && hash(checker)! == checker_pin
 receipt := object(output + '/complete-receipt.json')!
 assert receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
 assert receipt['manifest_sha256']!.str() == manifest_pin && receipt['files_checked']!.int() == manifest.len
 println('TIMING367-ART-PEER-PASS closure_inputs=' + closure_count.str() + ' ' + r.output.trim_space())
}
