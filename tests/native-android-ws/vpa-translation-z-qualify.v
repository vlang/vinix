// SPDX-License-Identifier: GPL-2.0-or-later
// Independent qualifier for the preserved 338 same-APK ART observations.
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

const state = '/Users/alex/.local/state/vinix/android/vpa-translation-z338-2026-10-25'
const qualification = state + '/qualification'
const vroot = qualification + '/frozen/vroot'
const compiler = vroot + '/v'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'vpa-translation-z-qualify.v'
const source_path = vroot + '/source/' + source_name
const old_jar = 'c9d7d096d763730ed9f3eed1735272ef11a65e88da3d297731f832a434c6c788'
const new_jar = 'df8601f61867c276559c1799957865ef51a65b4cb8b343b848f2fca6370f16a7'
const signed_apk = '99bd02a15922d57db1d7e967e866023511cb7d629c75b2d3e913086988f44e15'

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
 assert !os.exists(path), path
 os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut files map[string]string) ! {
 for name in os.ls(root + '/' + prefix)! {
  key := if prefix == '' { name } else { prefix + '/' + name }
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { inventory(root, key, mut files)! }
   .regular { files[key] = hash(root + '/' + key)! }
   else { return error('nonregular evidence entry: ' + key) }
  }
 }
}

fn stable() !map[string]string {
 mut pins := map[string]string{}
 for dir in ['native-old', 'native-new', 'fixture-inputs', 'tools', 'source',
  'closure-inputs', 'frozen', 'generated-c', 'apk', 'framework'] {
  mut files := map[string]string{}
  inventory(state + '/' + dir, '', mut files)!
  for key, pin in files { pins[dir + '/' + key] = pin }
 }
 for key in ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json',
  'initial-media/boot.img', 'initial-media/efivars.fd'] { pins[key] = hash(state + '/' + key)! }
 return pins
}

fn record(label string, argv []string) ! {
 pin := hash(os.real_path(argv[0]))!
 started := time.utc().str()
 result := os.exec(argv)
 os.write_file(qualification + '/' + label + '.log', result.output)!
 write_json(qualification + '/' + label + '.json', {
  'argv': json2.Any(argv), 'executable_sha256': json2.Any(pin),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'exit_code': json2.Any(result.exit_code),
 })!
 assert hash(os.real_path(argv[0]))! == pin
 if result.exit_code != 0 { eprintln(result.output) }
 assert result.exit_code == 0, label
}

fn closure(label string) !map[string]string {
 record(label + '-closure', [compiler, '-path', vroot + '/vlib', '-print-v-files', source_path])!
 mut pins := map[string]string{}
 for path in os.read_lines(qualification + '/' + label + '-closure.log')!.filter(it.ends_with('.v')) {
  assert os.real_path(path).starts_with(vroot + '/'), 'nonfrozen V input: ' + path
  pins[path] = hash(path)!
 }
 assert pins.len > 0
 write_json(qualification + '/' + label + '-v-files.json', pins)!
 return pins
}

fn prepare() ! {
 assert !os.exists(state + '/sha256.json') && !os.exists(qualification)
 expected := json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
 assert stable()! == expected
 os.mkdir_all(qualification + '/frozen')!
 result := os.exec(['/bin/cp', '-c', '-R', state + '/frozen/vroot', vroot])
 assert result.exit_code == 0, result.output
 os.write_file(source_path, os.read_file('tests/native-android-ws/' + source_name)!)!
 assert hash(compiler)! == compiler_pin
 mut frozen_inputs := map[string]string{}
 inventory(vroot, '', mut frozen_inputs)!
 write_json(qualification + '/frozen-inputs-before.json', frozen_inputs)!
 write_json(qualification + '/host-inputs.json', {
  compiler: compiler_pin, os.real_path('/usr/bin/cc'): hash(os.real_path('/usr/bin/cc'))!,
  'bootstrap': hash(os.executable())!, 'source': hash(source_path)!,
 })!
 os.mkdir_all(qualification + '/generated-c')!
 os.setenv('VROOT', vroot, true)
 os.setenv('VEXE', compiler, true)
 os.setenv('VTMP', qualification + '/generated-c', true)
 before := closure('before')!
 record('compile', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc',
  '-path', vroot + '/vlib', '-o', qualification + '/qualifier', source_path])!
 cc_lines := os.read_lines(qualification + '/compile.log')!.filter(it.trim_space().starts_with('> cc '))
 assert cc_lines.len > 0
 for line in cc_lines { assert !line.contains('/Users/alex/code/'), 'nonfrozen C input' }
 assert closure('after')! == before
 mut frozen_after := map[string]string{}
 inventory(vroot, '', mut frozen_after)!
 write_json(qualification + '/frozen-inputs-after.json', frozen_after)!
 assert frozen_inputs == frozen_after
 assert stable()! == expected
 println('VPA-TRANSLATION-Z-QUALIFIER-PREPARED')
}

fn check(kind string) ! {
 assert kind in ['old', 'new']
 expected := json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
 assert stable()! == expected
 for phase in ['before', 'after'] {
  assert json2.decode[map[string]string](os.read_file(state + '/' + kind + '-inputs-' + phase + '.json')!)! == expected
 }
 output := state + '/run-' + kind
 log := os.read_file(output + '/bootstrap-fixture/serial.log')!
 lines := log.split_into_lines().map(it.trim_space())
 raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
 assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
 assert hash(state + '/apk/probe.apk')! == signed_apk
 assert raw[0]['container_sha256']!.str() == signed_apk
 metadata := raw[0]['metadata']!.as_map()
 assert metadata['apk_sha256']!.str() == signed_apk
 assert raw[0]['staged_apk']!.str() == state + '/apk/probe.apk'
 assert raw[0]['launcher_entered']!.bool() && raw[0]['native_maps_observed']!.bool()
 assert raw[0]['functional_passed']! is json2.Null
 assert raw[0]['startup_seconds']!.int() == 45
 if kind == 'old' {
  assert !log.contains('VPA-STAGE-PASS') && !log.contains('VPA-TRANSLATION-Z-PASS')
  assert log.count('java.lang.NoSuchMethodError:') == 1
  assert log.contains('translationZ(F)Landroid/view/ViewPropertyAnimator;') ||
   (log.contains('translationZ(float)') && log.contains('android.view.ViewPropertyAnimator'))
  assert lines.filter(it == 'ANDROID-WS-FAIL start activity').len == 1
  assert log.count('ANDROID-WS-FAIL') == 1
  assert raw[0]['outcome']!.str() == 'startup_failed' && raw[0]['process_exited']!.bool()
 } else {
  for marker in ['VPA-STAGE-PASS two-vpas intermediate-z main-looper nonnull-end counter',
   'VPA-STAGE-PASS three-vpas intermediate-z main-looper nonnull-end counter',
   'VPA-STAGE-PASS three-vpas unchanged-properties counter',
   'VPA-STAGE-PASS automatic-start translation-z', 'VPA-TRANSLATION-Z-PASS'] {
   assert lines.filter(it == marker).len == 1, marker
  }
  assert !log.contains('NoSuchMethodError') && !log.contains('ANDROID-WS-FAIL')
  assert raw[0]['outcome']!.str() == 'window_observed' && !raw[0]['process_exited']!.bool()
  assert raw[0]['observation_elapsed_seconds']!.int() >= 45
  assert raw[0]['qemu_alive_before_capture']!.bool()
  assert raw[0]['failure_markers']!.as_array().len == 0
 }
 for bad in ['AssertionError', 'NoSuchFieldError', 'NoClassDefFoundError', 'ClassNotFoundException',
  'UnsatisfiedLinkError', 'VerifyError', 'JNI DETECTED ERROR', 'ExceptionInInitializerError', 'AbstractMethodError'] {
  assert !log.contains(bad), bad
 }
 receipt := {
  'variant': kind, 'status': 'expected-result-pass',
  'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!,
  'raw_results_sha256': hash(output + '/results.json')!, 'raw_outcome': raw[0]['outcome']!.str(),
  'checker_binary_sha256': hash(os.executable())!, 'checker_source_sha256': hash(source_path)!,
  'signed_apk_sha256': signed_apk,
  'scope': 'Preserved same signed APK on actual ART: expected old missing translationZ method; fixed stored Z properties and finite main-Looper 2/3-VPA transitions, unchanged-property completion and automatic start. No Maps replay qualification or native depth-order claim.',
 }
 write_json(qualification + '/' + kind + '-semantic-check.json', receipt)!
 if kind == 'old' {
  assert !os.exists(state + '/old-semantic-check.json')
  write_json(state + '/old-semantic-check.json', receipt)!
 }
 println('VPA-TRANSLATION-Z-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn qualify() ! {
 assert !os.exists(state + '/sha256.json')
 assert os.real_path(os.executable()) == qualification + '/qualifier'
 assert hash(compiler)! == compiler_pin
 mut old := map[string]string{}
 mut new := map[string]string{}
 inventory(state + '/native-old', '', mut old)!
 inventory(state + '/native-new', '', mut new)!
 assert old['api-impl.jar']! == old_jar && new['api-impl.jar']! == new_jar
 old.delete('api-impl.jar')
 new.delete('api-impl.jar')
 assert old == new
 before := json2.decode[map[string]string](os.read_file(qualification + '/before-v-files.json')!)!
 assert before == json2.decode[map[string]string](os.read_file(qualification + '/after-v-files.json')!)!
 for path, pin in before { assert hash(path)! == pin, path }
 for kind in ['old', 'new'] { check(kind)! }
}

fn main() {
 $if prod { panic('assertions required') }
 assert os.args.len == 2
 match os.args[1] {
  'prepare' { prepare()! }
  'qualify' { qualify()! }
  else { panic('prepare | qualify') }
 }
}
