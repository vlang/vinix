// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK ART regression; preparation builds only a runner and one fixture APK.
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

const state = '/Users/alex/.local/state/vinix/android/timing-logger367-fixture-2026-10-26'
const baseline_pin = '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
const old_manifest = 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
const old361_manifest = '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
const old359_manifest = '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
const old_jar = 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
const old361_jar = '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a'
const old359_jar = '88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc'
const native_pin = 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
const launcher_pin = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const java_pin = '9ef6c1a939343ac850811551a8b88d4b877630ab2c94ac38c541e25ccc8cf0a5'
const cc_pin = '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'
const capture_helper = '/Users/alex/code/vinix/build/android-maps/maps-interact-unique258'
const capture_pin = 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208'
const input_pin = 'bdce9c2c0bc038b4f88a92a17655e30282b10f7f48e5dfebc3a772a190db4eca'
const source_name = 'tests/native-android-ws/timing-logger367-run.v'
const fixture_name = 'tests/native-android-ws/startupfixture/timing_logger.v'
const retained = state + '/framework367'
const old_framework = retained + '/baseline365'
const baseline = old_framework + '/baseline361/baseline359/baseline353'
const vroot = state + '/frozen/vroot'
const driver = vroot + '/timing-logger-driver'
const runner_source = vroot + '/timing-logger367-run.v'
const compiler = vroot + '/v'
const rejection = 'java.lang.ClassNotFoundException: android.util.TimingLogger'
const markers = ['TIMING-LOGGER-CONSTRUCTOR-PASS', 'TIMING-LOGGER-SPLIT-PASS',
 'TIMING-LOGGER-RESET-PASS', 'TIMING-LOGGER-DUMP-PASS', 'TIMING-LOGGER-DISABLED-PASS', 'TIMING-LOGGER-PASS']

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

fn read_map(path string) !map[string]string {
 return json2.decode[map[string]string](os.read_file(path)!)!
}

fn object(path string) !map[string]json2.Any {
 return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn write_json[T](path string, value T) ! {
 os.mkdir_all(os.dir(path))!
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

fn qualify_build(root string, manifest_pin string, payload string, payload_pin string) !int {
 assert canonical_pin(manifest_pin) && canonical_pin(payload_pin)
 assert hash(root + '/sha256.json')! == manifest_pin
 expected := read_map(root + '/sha256.json')!
 assert expected.len > 0 && 'sha256.json' !in expected && expected[payload] == payload_pin
 mut actual := map[string]string{}
 inventory(root, '', mut actual)!
 actual.delete('sha256.json')
 assert actual == expected, 'complete build readback differs: ' + root
 assert hash(root + '/sha256.json')! == manifest_pin
 return actual.len
}

// BEGIN SHARED FRAMEWORK359 CONTRACT
fn qualify_framework359(root string, manifest_pin string, jar_pin string) !int {
 count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
 qualify_build(root + '/baseline353', baseline_pin, 'framework/api-impl.jar', '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83')!
 delta := object(root + '/framework/dex-delta.json')!
 old := delta['old_classes']!.as_map()
 new := delta['new_classes']!.as_map()
 changed := 'android/content/pm/PackageManager.smali'
 if old.len != 2073 || new.len != 2073
  || delta['changed_existing_classes']!.as_array().map(it.str()) != [changed]
  || delta['added_classes']!.as_array().len != 0 || delta['removed_classes']!.as_array().len != 0
  || delta['old_jar_sha256']!.str() != '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
  || delta['new_jar_sha256']!.str() != jar_pin || delta['jar_only_changed_member']!.str() != 'classes.dex'
  || delta['jar_member_count']!.int() < 1 || changed !in old || changed !in new {
  return error('exact permission359 framework delta required')
 }
 for name, pin in old {
  if name !in new || (name == changed && pin.str() == new[name]!.str())
   || (name != changed && pin.str() != new[name]!.str()) {
   return error('permission359 DEX class delta differs: ' + name)
  }
 }
 smali := object(root + '/framework/smali-delta.json')!
 before := smali['before']!.as_map()
 after := smali['after']!.as_map()
 if before.len != 2073 || after.len != 2073 || changed !in before || changed !in after
  || smali['changed']!.as_array().map(it.str()) != [changed] || !smali['duplicate_guard_unchanged']!.bool() {
  return error('exact permission359 source and duplicate guard required')
 }
 for name, pin in before {
  if name !in after || (name == changed && pin.str() == after[name]!.str())
   || (name != changed && pin.str() != after[name]!.str()) {
   return error('permission359 source class delta differs: ' + name)
  }
 }
 validation := read_map(root + '/validation.json')!
 if validation['baseline_manifest_sha256']! != baseline_pin
  || validation['old_framework_sha256']! != '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
  || validation['new_framework_sha256']! != jar_pin || validation['changed_class']! != changed
  || validation['class_count']! != '2073' {
  return error('permission359 validation differs')
 }
 return count
}
// END SHARED FRAMEWORK359 CONTRACT

// BEGIN SHARED FRAMEWORK361 CONTRACT
fn qualify_framework361(root string, manifest_pin string, jar_pin string) !int {
 count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
 qualify_framework359(root + '/baseline359', old359_manifest, old359_jar)!
 changed := 'android/atl/ATLLoadedApp.smali'
 added := 'android/atl/VinixServiceStop.smali'
 delta := object(root + '/framework/dex-delta.json')!
 old := delta['old_classes']!.as_map()
 new := delta['new_classes']!.as_map()
 require(old.len == 2073 && new.len == 2074 && changed in old && changed in new
  && added !in old && added in new, 'service361 DEX class set')!
 require(delta['changed_existing_classes']!.as_array().map(it.str()) == [changed]
  && delta['added_classes']!.as_array().map(it.str()) == [added]
  && delta['removed_classes']!.as_array().len == 0
  && delta['old_jar_sha256']!.str() == old359_jar && delta['new_jar_sha256']!.str() == jar_pin
  && delta['jar_only_changed_member']!.str() == 'classes.dex'
  && delta['jar_member_count']!.int() > 0, 'exact service361 framework delta')!
 for name, pin in old {
  require(name in new && (name == changed || pin.str() == new[name]!.str()), 'service361 DEX class: ' + name)!
 }
 require(old[changed]!.str() != new[changed]!.str(), 'service361 changed DEX class')!
 smali := object(root + '/framework/smali-delta.json')!
 before := smali['before']!.as_map()
 after := smali['after']!.as_map()
 require(before.len == 2073 && after.len == 2074 && changed in before && changed in after
  && added !in before && added in after, 'service361 source class set')!
 require(smali['changed']!.as_array().map(it.str()) == [changed]
  && smali['added']!.as_array().map(it.str()) == [added]
  && smali['removed']!.as_array().len == 0 && smali['duplicate_guard_unchanged']!.bool()
  && smali['malformed_guard_unchanged']!.bool(), 'service361 source and rejection guards')!
 for name, pin in before {
  require(name in after && (name == changed || pin.str() == after[name]!.str()), 'service361 source class: ' + name)!
 }
 require(before[changed]!.str() != after[changed]!.str(), 'service361 changed source class')!
 malformed := object(root + '/framework/malformed-guard.json')!
 require(malformed['before']!.as_map() == malformed['after']!.as_map()
  && malformed['before']!.as_map().len == 2073, 'service361 malformed input unchanged')!
 validation := read_map(root + '/validation.json')!
 require(validation['baseline_manifest_sha256']! == old359_manifest
  && validation['old_framework_sha256']! == old359_jar && validation['new_framework_sha256']! == jar_pin
  && validation['changed_class']! == changed && validation['added_class']! == added
  && validation['old_class_count']! == '2073' && validation['new_class_count']! == '2074',
  'service361 validation')!
 return count
}

// END SHARED FRAMEWORK361 CONTRACT

fn qualify_framework365(root string, manifest_pin string, jar_pin string) !int {
 count := qualify_build(root, manifest_pin, 'framework/api-impl.jar', jar_pin)!
 qualify_framework361(root + '/baseline361', old361_manifest, old361_jar)!
 changed := ['android/os/BaseBundle.smali', 'android/os/Bundle.smali', 'android/os/Parcel.smali',
  'android/os/Parcelable' + '$' + 'ClassLoaderCreator.smali']
 added := ['android/os/VinixBundleCreator.smali']
 for key in ['dex', 'smali'] {
  delta := object(root + '/framework/' + key + '-delta.json')!
  before := delta[if key == 'dex' { 'old_classes' } else { 'before' }]!.as_map()
  after := delta[if key == 'dex' { 'new_classes' } else { 'after' }]!.as_map()
  require(before.len == 2074 && after.len == 2075, 'bundle365 class counts')!
  for name in changed { require(name in before && name in after && before[name]!.str() != after[name]!.str(), 'bundle365 required change: ' + name)! }
  for name in added { require(name !in before && name in after, 'bundle365 required addition: ' + name)! }
  for name, pin in before { require(name in after && (name in changed || pin.str() == after[name]!.str()), 'bundle365 class: ' + name)! }
  require(delta[if key == 'dex' { 'changed_existing_classes' } else { 'changed' }]!.as_array().map(it.str()) == changed
   && delta[if key == 'dex' { 'added_classes' } else { 'added' }]!.as_array().map(it.str()) == added
   && delta[if key == 'dex' { 'removed_classes' } else { 'removed' }]!.as_array().len == 0, 'bundle365 exact class delta')!
  if key == 'dex' {
   require(delta['old_jar_sha256']!.str() == old361_jar && delta['new_jar_sha256']!.str() == jar_pin
    && delta['jar_only_changed_member']!.str() == 'classes.dex' && delta['jar_member_count']!.int() > 0, 'bundle365 JAR delta')!
  } else {
   require(delta['duplicate_guard_unchanged']!.bool() && delta['malformed_guard_unchanged']!.bool(), 'bundle365 rejection guards')!
  }
 }
 malformed := object(root + '/framework/malformed-guard.json')!
 require(malformed['before']!.as_map() == malformed['after']!.as_map()
  && malformed['before']!.as_map().len == 2074, 'bundle365 malformed input unchanged')!
 validation := object(root + '/validation.json')!
 require(validation['baseline_manifest_sha256']!.str() == old361_manifest
  && validation['old_framework_sha256']!.str() == old361_jar && validation['new_framework_sha256']!.str() == jar_pin
  && validation['changed_classes']!.as_array().map(it.str()) == changed
  && validation['added_classes']!.as_array().map(it.str()) == added
  && validation['old_class_count']!.str() == '2074' && validation['new_class_count']!.str() == '2075', 'bundle365 validation')!
 return count
}

fn qualify_framework367(root string, manifest_pin string, jar_pin string) !int {
 count := qualify_build(root, manifest_pin, "framework/api-impl.jar", jar_pin)!
 qualify_framework365(root + "/baseline365", old_manifest, old_jar)!
 added := "android/util/TimingLogger.smali"
 for key in ["dex", "smali"] {
  delta := object(root + "/framework/" + key + "-delta.json")!
  before := delta[if key == "dex" { "old_classes" } else { "before" }]!.as_map()
  after := delta[if key == "dex" { "new_classes" } else { "after" }]!.as_map()
  require(before.len == 2075 && after.len == 2076 && added !in before && added in after, "timing367 class counts and addition")!
  for name, pin in before { require(name in after && pin.str() == after[name]!.str(), "timing367 existing class unchanged: " + name)! }
  require(delta[if key == "dex" { "changed_existing_classes" } else { "changed" }]!.as_array().len == 0
   && delta[if key == "dex" { "added_classes" } else { "added" }]!.as_array().map(it.str()) == [added]
   && delta[if key == "dex" { "removed_classes" } else { "removed" }]!.as_array().len == 0, "timing367 exact class delta")!
  if key == "dex" {
   require(delta["old_jar_sha256"]!.str() == old_jar && delta["new_jar_sha256"]!.str() == jar_pin
    && delta["jar_only_changed_member"]!.str() == "classes.dex" && delta["jar_member_count"]!.int() > 0, "timing367 JAR delta")!
  } else {
   require(delta["duplicate_guard_unchanged"]!.bool() && delta["malformed_guard_unchanged"]!.bool(), "timing367 rejection guards")!
  }
 }
 malformed := object(root + "/framework/malformed-guard.json")!
 require(malformed["before"]!.as_map() == malformed["after"]!.as_map()
  && malformed["before"]!.as_map().len == 2076
  && malformed["guard_kind"]!.str() == "existing-malformed-destination", "timing367 malformed destination unchanged")!
 validation := object(root + "/validation.json")!
 require(validation["baseline_manifest_sha256"]!.str() == old_manifest
  && validation["old_framework_sha256"]!.str() == old_jar && validation["new_framework_sha256"]!.str() == jar_pin
  && validation["changed_classes"]!.as_array().len == 0
  && validation["added_classes"]!.as_array().map(it.str()) == [added]
  && validation["old_class_count"]!.str() == "2075" && validation["new_class_count"]!.str() == "2076", "timing367 validation")!
 return count
}

fn canonical_pin(pin string) bool {
 return pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
}

fn record(label string, argv []string) !string {
 assert !os.exists(state + '/commands/' + label + '.json'), label
 exe := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
 pin := hash(exe)!
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(state + '/commands/' + label + '.log', r.output)!
 write_json(state + '/commands/' + label + '.json', {
  'argv': json2.Any(argv), 'working_directory': json2.Any(os.getwd()),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'exit_code': json2.Any(r.exit_code), 'executable_sha256': json2.Any(pin)
 })!
 assert hash(exe)! == pin, exe
 assert r.exit_code == 0, label + ': ' + r.output
 return r.output
}

fn clone(from string, to string) ! {
 assert !os.exists(to) && !os.is_link(to), to
 os.mkdir_all(os.dir(to))!
 r := os.exec(['/bin/cp', '-c', '-R', os.real_path(from), to])
 assert r.exit_code == 0, r.output
}

fn disk(label string, minimum_mib u64) ! {
 raw := record('disk-' + label, ['/bin/df', '-k', state])!
 assert raw.trim_space().split_into_lines().last().fields()[3].u64() >= minimum_mib * 1024
}

fn closure(label string, paths string, source string) !map[string]string {
 listing := record(label + '-closure', [compiler, '-path', paths, '-print-v-files', source])!
 mut pins := map[string]string{}
 for path in listing.split_into_lines().filter(it.ends_with('.v')) {
  assert os.real_path(path).starts_with(state + '/'), 'nonfrozen V input: ' + path
  assert !path.contains('/androidtools/'), 'framework generator in fixture closure'
  pins[path] = hash(path)!
  target := state + '/closure-inputs/' + path.trim_left('/')
  if os.exists(target) { assert hash(target)! == pins[path]!, path }
  else { clone(path, target)! }
 }
 assert pins.len > 0
 write_json(state + '/' + label + '-v-files.json', pins)!
 return pins
}

fn compile(label string, paths string, source string, output string) ! {
 before := closure(label + '-before', paths, source)!
 log := record('compile-' + label, [compiler, '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc',
  '-path', paths, '-o', output, source])!
 assert !log.contains('/Users/alex/code/'), 'mutable checkout in C compiler command'
 assert before == closure(label + '-after', paths, source)!
 assert hash(compiler)! == compiler_pin && hash('/usr/bin/cc')! == cc_pin
}

fn host_inputs(config map[string]json2.Any) !map[string]string {
 mut pins := map[string]string{}
 for key in ['aapt2', 'apksigner', 'firmware', 'input_tool', 'java', 'qemu'] {
  path := os.real_path(config[key]!.str())
  pins[path] = hash(path)!
 }
 pins[compiler] = hash(compiler)!
 pins['/usr/bin/cc'] = hash('/usr/bin/cc')!
 pins[capture_helper] = hash(capture_helper)!
 assert pins[capture_helper]! == capture_pin
 assert pins[os.real_path(config['input_tool']!.str())]! == input_pin
 assert pins[compiler]! == compiler_pin && pins['/usr/bin/cc']! == cc_pin
 assert pins[os.real_path(java)]! == java_pin
 return pins
}

fn stable() !map[string]string {
 mut pins := map[string]string{}
 for dir in ['framework367', 'native-old', 'native-new', 'fixture-inputs', 'tools',
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

fn qualify() ! {
 pins := read_map(state + '/build-pins.json')!
 assert pins['baseline353_manifest']! == baseline_pin
 assert pins['baseline361_manifest']! == old361_manifest && pins['baseline365_manifest']! == old_manifest && pins['baseline359_manifest']! == old359_manifest && pins['old_framework_jar']! == old_jar
 assert hash(runner_source)! == hash(state + '/source/timing-logger367-run.v')!
 qualify_framework367(retained, pins['framework_manifest']!, pins['framework_jar']!)!
 mut old := map[string]string{}
 mut new := map[string]string{}
 mut original := map[string]string{}
 inventory(state + '/native-old', '', mut old)!
 inventory(state + '/native-new', '', mut new)!
 inventory(baseline + '/native-new', '', mut original)!
 assert old['api-impl.jar']! == old_jar
 assert original['api-impl.jar']! == '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
 assert old['libvinix-android-native.so']! == native_pin && old['popular-launcher']! == launcher_pin
 assert new['api-impl.jar']! == pins['framework_jar']! && new['api-impl.jar']! != old_jar
 old.delete('api-impl.jar')
 new.delete('api-impl.jar')
 original.delete('api-impl.jar')
 assert old == original, 'qualified353 native closure must remain unchanged'
 assert old == new, 'new framework JAR must be the sole runtime delta'
 assert hash(state + '/tools/checked-runner')! == pins['runner']!
 assert hash(state + '/apk/probe.apk')! == pins['apk']!
}

fn prepare(root string, manifest_pin string, jar_pin string, revision string, fixture_pin string) ! {
 assert !os.exists(state) && !os.is_link(state), 'fresh external output required'
 assert os.dir(root) == os.dir(state) && os.base(root).starts_with('timing-logger367-framework-build-')
 assert os.real_path(root) == root && !os.is_link(root) && jar_pin != old_jar
 assert canonical_pin(manifest_pin) && canonical_pin(jar_pin) && canonical_pin(fixture_pin)
 assert revision.len == 40 && revision.bytes().all(it in '0123456789abcdef'.bytes())
 os.mkdir_all(state + '/commands')!
 disk('prepare', 1024)!
 qualify_framework367(root, manifest_pin, jar_pin)!
 clone(root, retained)!
 qualify_framework367(retained, manifest_pin, jar_pin)!
 clone(os.executable(), state + '/tools/bootstrap')!
 clone(source_name, state + '/source/timing-logger367-run.v')!
 // The pinned compiler selects builtin sources from the input's enclosing
 // vroot. Keep new inputs beneath a separate clone; never modify baseline353.
 clone(baseline + '/frozen/vroot', vroot)!
 clone(source_name, runner_source)!
 committed := record('fixture-committed-source', ['git', 'show', revision + ':' + fixture_name])!
 assert committed == os.read_file(fixture_name)! && hash(fixture_name)! == fixture_pin
 clone(fixture_name, driver + '/startupfixture/timing_logger.v')!
 os.write_file(driver + '/main.v', fixture_driver())!
 for key in ['native-new', 'fixture-inputs'] {
  if key == 'native-new' {
   for kind in ['old', 'new'] { clone(baseline + '/' + key, state + '/native-' + kind)! }
  } else { clone(baseline + '/' + key, state + '/' + key)! }
 }
 for key in ['tools/suite', 'tools/inflater-trace-seal', 'source/suite.v', 'source/inflater-trace-seal.v',
  'base-runtime.tar', 'initial-media.json', 'initial-media/boot.img', 'initial-media/efivars.fd'] {
  clone(baseline + '/' + key, state + '/' + key)!
 }
 clone(baseline + '/source/suite-support', state + '/source/suite-support')!
 clone(baseline + '/apk/fixture.p12', state + '/apk/fixture.p12')!
 mut config := object(baseline + '/config.json')!
 config['java'] = java
 config['aapt2'] = state + '/fixture-inputs/aapt2'
 config['apksigner'] = state + '/fixture-inputs/apksigner.jar'
 config['base_module'] = state + '/base-runtime.tar'
 config['applications'] = json2.Any([json2.Any({
  'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'),
  'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Timing logger fixture'),
  'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/timing-logger367-run.v'),
  'startup_seconds': json2.Any(35),
 })])
 write_json(state + '/config.json', config)!
 write_json(state + '/host-inputs.json', host_inputs(config)!)!
 os.mkdir_all(state + '/generated-c')!
 os.mkdir_all(state + '/vmodules')!
 os.setenv('VTMP', state + '/generated-c', true)
 os.setenv('VMODULES', state + '/vmodules', true)
 os.setenv('VROOT', vroot, true)
 os.setenv('VEXE', compiler, true)
 compile('runner', vroot + '/vlib', runner_source, state + '/tools/checked-runner')!
 compile('fixture-driver', driver + '|' + vroot + '/vlib', driver, state + '/tools/fixture-driver')!
 record('fixture-smali', [state + '/tools/fixture-driver', state + '/apk'])!
 mut fixture_classes := map[string]string{}
 inventory(state + '/apk/smali', '', mut fixture_classes)!
 assert fixture_classes.keys().sorted() == ['org/vinix/bootstrap/Main.smali',
  'org/vinix/bootstrap/TimingLoggerProbe.smali', 'org/vinix/bootstrap/TimingLoggerSubclass.smali'],
  'minimal timing-logger-only APK required'
 build_apk()!
 os.rm(state + '/native-old/api-impl.jar')!
 clone(old_framework + '/framework/api-impl.jar', state + '/native-old/api-impl.jar')!
 os.rm(state + '/native-new/api-impl.jar')!
 clone(retained + '/framework/api-impl.jar', state + '/native-new/api-impl.jar')!
 write_json(state + '/build-pins.json', {'framework_manifest': manifest_pin, 'framework_jar': jar_pin,
  'fixture_commit': revision, 'fixture_source': fixture_pin, 'runner': hash(state + '/tools/checked-runner')!,
  'apk': hash(state + '/apk/probe.apk')!, 'baseline353_manifest': baseline_pin,
  'baseline359_manifest': old359_manifest, 'baseline361_manifest': old361_manifest, 'baseline365_manifest': old_manifest, 'old_framework_jar': old_jar})!
 qualify()!
 write_json(state + '/shared-inputs.json', stable()!)!
 assert host_inputs(config)! == read_map(state + '/host-inputs.json')!
 println('TIMING-LOGGER-PREPARED apk=' + hash(state + '/apk/probe.apk')! + ' runner=' + hash(state + '/tools/checked-runner')!)
}

fn fixture_driver() string {
 return r'module main
import startupfixture
import os
fn method(signature string, body string) string {
 return ".method " + signature + "\n.locals 2\n" + body + "\n.end method\n"
}
fn main() {
 assert os.args.len == 2
 dir := os.args[1]
 root := dir + "/smali/org/vinix/bootstrap"
 os.mkdir_all(root)!
 startupfixture.install_timing_logger_probe(root)!
 os.write_file(root + "/Main.smali", ".class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n" +
  method("public constructor <init>()V", "invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void") +
  method("public onCreate(Landroid/os/Bundle;)V", "invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, \"TIMING-LOGGER-BEGIN\"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\ninvoke-static {}, Lorg/vinix/bootstrap/TimingLoggerProbe;->check()V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, \"Timing logger regression\"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nreturn-void"))!
}
'
}

fn build_apk() ! {
 dir := state + '/apk'
 tools := state + '/fixture-inputs'
 os.mkdir_all(dir + '/res/values')!
 os.write_file(dir + '/res/values/values.xml', '<resources><string name="app_name">Timing logger fixture</string></resources>')!
 os.write_file(dir + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/><application android:label="Timing logger fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
 record('apk-resources', [tools + '/aapt2', 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])!
 record('apk-link', [tools + '/aapt2', 'link', '-I', tools + '/framework-res.apk', '--manifest', dir + '/AndroidManifest.xml', '-o', dir + '/unsigned.apk', dir + '/resources.zip'])!
 record('apk-smali', [java, '-cp', tools + '/smali/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])!
 assert os.is_file(dir + '/classes.dex') && os.file_size(dir + '/classes.dex') > 0, 'fresh fixture DEX required'
 record('apk-zip', ['/usr/bin/zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])!
 record('apk-sign', [java, '-jar', tools + '/apksigner.jar', 'sign', '--ks', dir + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', dir + '/probe.apk', dir + '/unsigned.apk'])!
 record('apk-verify', [java, '-jar', tools + '/apksigner.jar', 'verify', '-v', '--print-certs', dir + '/probe.apk'])!
 record('apk-badging', [tools + '/aapt2', 'dump', 'badging', dir + '/probe.apk'])!
}

fn run(kind string) ! {
 assert kind in ['old', 'new'] && !os.exists(state + '/sha256.json')
 assert hash(os.executable())! == hash(state + '/tools/checked-runner')!
 qualify()!
 before := stable()!
 assert before == read_map(state + '/shared-inputs.json')!
 disk(kind, 768)!
 mut removed := []string{}
 for key, _ in os.environ() {
  if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' { removed << key; os.unsetenv(key) }
 }
 write_json(state + '/' + kind + '-environment.json', {'removed_host_variables': removed})!
 output := state + '/run-' + kind
 alias := os.abs_path('build/android-maps/timing-logger367-' + kind)
 assert !os.exists(alias) && !os.is_link(alias) && !os.exists(output)
 os.mkdir_all(output)!
 os.symlink(output, alias)!
 media := read_map(state + '/initial-media.json')!
 for file in ['boot.img', 'efivars.fd'] {
  assert hash(state + '/initial-media/' + file)! == media[file]!
  clone(state + '/initial-media/' + file, state + '/vm-' + kind + '/' + file)!
 }
 mut config := object(state + '/config.json')!
 assert host_inputs(config)! == read_map(state + '/host-inputs.json')!
 config['output'] = alias
 config['native_dir'] = state + '/native-' + kind
 config['boot_image'] = state + '/vm-' + kind + '/boot.img'
 config['efivars'] = state + '/vm-' + kind + '/efivars.fd'
 write_json(state + '/' + kind + '.json', config)!
 write_json(state + '/' + kind + '-inputs-before.json', before)!
 record('suite-' + kind, [state + '/tools/suite', state + '/' + kind + '.json'])!
 assert stable()! == before && host_inputs(config)! == read_map(state + '/host-inputs.json')!
 write_json(state + '/' + kind + '-inputs-after.json', stable()!)!
 check(kind, state + '/' + kind + '-semantic-check.json')!
}

fn require(condition bool, message string) ! {
 if !condition { return error(message) }
}

fn semantic(kind string, raw map[string]json2.Any, log string, apk string) ! {
 semantic_at(kind, raw, log, apk, state + '/apk/probe.apk')!
}

fn expected_timing_output() []string {
 mut lines := ['TIMING-LOGGER-BEGIN',
  'TIMING-LOGGER367-INITIAL', 'initial: begin',
  'TIMING-LOGGER367-INITIAL', 'initial: end, 0 ms',
  markers[0], markers[1], markers[2]]
 for _ in 0 .. 2 {
  for message in ['deterministic: begin', 'deterministic:      7 ms, a',
   'deterministic:      9 ms, b', 'deterministic: end, 16 ms'] {
   lines << 'TIMING-LOGGER367'
   lines << message
  }
 }
 lines << markers[3..]
 return lines
}

fn expected_old_output() []string {
 return ['TIMING-LOGGER-BEGIN', 'ANDROID-WS-FAIL start activity', rejection,
  'at java.lang.Class.classForName(Native Method)',
  'at java.lang.Class.forName(Class.java:453)',
  'at java.lang.Class.forName(Class.java:378)',
  'at org.vinix.bootstrap.TimingLoggerProbe.check(Unknown Source:2)',
  'at org.vinix.bootstrap.Main.onCreate(Unknown Source:10)',
  'at android.app.Activity.vinixPerformCreate(Unknown Source:5)',
  'Caused by: ' + rejection, '... 6 more',
  'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true']
}

fn semantic_at(kind string, raw map[string]json2.Any, log string, apk string, staged_apk string) ! {
 require(kind in ["old", "new"], "variant")!
 lines := log.split_into_lines().map(it.trim_space())
 require(raw["id"]!.str() == "bootstrap-fixture" && raw["package"]!.str() == "org.vinix.bootstrap", "fixture identity")!
 require(raw["container_sha256"]!.str() == apk && raw["metadata"]!.as_map()["apk_sha256"]!.str() == apk, "APK identity")!
 require(raw["staged_apk"]!.str() == staged_apk, "staged APK")!
 require(raw["launcher_entered"]!.bool() && raw["native_maps_observed"]!.bool(), "native ART launch")!
 require(raw["functional_passed"]! is json2.Null && raw["startup_seconds"]!.int() == 35, "original classifier and window")!
 require(lines.filter(it == "TIMING-LOGGER-BEGIN").len == 1, "single probe start")!
 if kind == "old" {
  for marker in markers { require(!log.contains(marker), "old emitted " + marker)! }
  expected := expected_old_output()
  begin := lines.index('TIMING-LOGGER-BEGIN')
  require(begin >= 0 && begin + expected.len <= lines.len, 'complete old exception block')!
  require(lines[begin..begin + expected.len] == expected, 'exact observed nested CNFE block')!
  require(lines.filter(it == rejection).len == 1 && log.count('ClassNotFoundException') == 2,
   'exact outer and nested TimingLogger CNFE')!
  require(lines.filter(it.starts_with('Caused by:')) == ['Caused by: ' + rejection]
   && !log.contains('Suppressed:'), 'single exact old cause')!
  require(lines.filter(it.starts_with('at ')) == expected[3..9], 'exact ordered six old frames')!
  require(lines.filter(it == "ANDROID-WS-FAIL start activity").len == 1 && log.count("ANDROID-WS-FAIL") == 1, "start activity failure")!
  require(lines.filter(it == "APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true").len == 1, "guest exit1")!
  require(raw["outcome"]!.str() == "startup_failed" && raw["process_exited"]!.bool(), "old raw failure")!
  require(raw["failure_markers"]!.as_array().map(it.str()) == ["ANDROID-WS-FAIL start activity", rejection,
   'Caused by: ' + rejection,
   "APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true"], "old raw markers")!
 } else {
  mut position := log.index("TIMING-LOGGER-BEGIN") or { return error("missing start") }
  for marker in markers {
   require(lines.filter(it == marker).len == 1, "single " + marker)!
   next := log.index(marker) or { return error("missing " + marker) }
   require(next > position, "ordered " + marker)!
   position = next
  }
  // The pinned native Log writer emits each tag and message on separate lines.
  // Include phase markers so an extra disabled dump or misplaced dump fails.
  timing_lines := lines.filter(it.starts_with('TIMING-LOGGER') || it.starts_with('initial:')
   || it.starts_with('deterministic:'))
  require(timing_lines == expected_timing_output(), 'complete tagged dump sequence and phases')!
  for i, line in lines {
   if line in ['TIMING-LOGGER367-INITIAL', 'TIMING-LOGGER367'] {
    prefix := if line == 'TIMING-LOGGER367-INITIAL' { 'initial:' } else { 'deterministic:' }
    require(i + 1 < lines.len && lines[i + 1].starts_with(prefix), 'adjacent native tag and message')!
   }
  }
  require(!log.contains("ClassNotFoundException") && !log.contains("ANDROID-WS-FAIL"), "new failure marker")!
  for bad in ["APK-SUITE-EXIT id=bootstrap-fixture ", "APK-SUITE-DEPENDENCY-FAIL",
   "ANDROID-WS-DEPENDENCY-FAIL", "ANDROID-WS-PROCESS-FAIL"] { require(!log.contains(bad), "final serial failure: " + bad)! }
  require(raw["outcome"]!.str() == "window_observed" && !raw["process_exited"]!.bool(), "new raw survival")!
  require(raw["observation_elapsed_seconds"]!.int() >= 35 && raw["qemu_alive_before_capture"]!.bool(), "full35second window")!
  require(raw["failure_markers"]!.as_array().len == 0, "raw failure markers")!
 }
 for bad in ["AssertionError", "NullPointerException", "VerifyError", "NoClassDefFoundError",
  "NoSuchMethodError", "NoSuchFieldError", "UnsatisfiedLinkError", "JNI DETECTED ERROR",
  "ExceptionInInitializerError", "AbstractMethodError"] { require(!log.contains(bad), bad)! }
}

fn check(kind string, receipt string) ! {
 assert !os.exists(state + '/sha256.json') && !os.exists(receipt)
 qualify()!
 expected := read_map(state + '/shared-inputs.json')!
 assert stable()! == expected
 for phase in ['before', 'after'] { assert read_map(state + '/' + kind + '-inputs-' + phase + '.json')! == expected }
 output := state + '/run-' + kind
 log := os.read_file(output + '/bootstrap-fixture/serial.log')!
 raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
 assert raw.len == 1
 apk := hash(state + '/apk/probe.apk')!
 semantic(kind, raw[0], log, apk)!
 write_json(receipt, {'variant': kind, 'status': 'expected-result-pass',
  'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!, 'raw_results_sha256': hash(output + '/results.json')!,
  'raw_outcome': raw[0]['outcome']!.str(), 'checker_binary_sha256': hash(os.executable())!,
  'signed_apk_sha256': apk, 'native_sha256': native_pin, 'old_framework_sha256': old_jar,
  'new_framework_sha256': read_map(state + '/build-pins.json')!['framework_jar']!,
  'scope': 'Same signed timing-logger-only APK on actual ART. Qualified365 must fail Class.forName for android.util.TimingLogger with the exact class CNFE and isolated fixture frames. New must validate subclass-visible state, constructor/reset timing, split order and elapsed values, dump format and disabled behavior, then survive35seconds. Only framework JAR differs. Separate Maps replay required.'})!
 println('TIMING-LOGGER-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

// Preserve the original failed old validator invocation and successful new
// invocation. Requalification changes only the old exception-shape validator;
// the prepared runner, APK, runtime closure and actual guest output stay pinned.
fn observed_invocations() !map[string]string {
 original_runner := 'a33a93cb8c8d21b244e92eca86a5d3dac8e23dd0142364db441b338ddcdd03a4'
 recorder_source := '36cd71cdec17ccf3cd4fb964786deb177e161cb49c76cd8d437a80b4dd2d187d'
 recorder_binary := 'dc823bd2632ede0ff06e7cfa1987fe1dff9dd4417e3314b9a0b145c2db6f71bb'
 assert hash(state + '/tools/checked-runner')! == original_runner
 assert !os.exists(state + '/old-semantic-check.json')
 mut pins := map[string]string{}
 for kind in ['old', 'new'] {
  prefix := os.dir(state) + '/timing-logger367-fixture-' + kind + '-2026-10-26'
  before := object(prefix + '-before.json')!
  actual := object(prefix + '-command.json')!
  assert before.keys().sorted() == ['argv', 'cwd', 'executable_sha256_before',
   'recorder_binary_sha256', 'recorder_source_sha256', 'started_utc']
  assert actual.keys().sorted() == ['argv', 'completed_utc', 'cwd', 'executable_sha256_after',
   'executable_sha256_before', 'exit_code', 'output_sha256', 'recorder_binary_sha256',
   'recorder_source_sha256', 'started_utc']
  for key, value in before { assert json2.encode(value) == json2.encode(actual[key]!) }
  assert actual['argv']!.as_array().map(it.str()) == [state + '/tools/checked-runner', kind]
  assert actual['cwd']!.str() == '/Users/alex/code/vinix'
  assert actual['started_utc']!.str() < actual['completed_utc']!.str()
  assert actual['executable_sha256_before']!.str() == original_runner
   && actual['executable_sha256_after']!.str() == original_runner
  assert actual['recorder_source_sha256']!.str() == recorder_source
   && actual['recorder_binary_sha256']!.str() == recorder_binary
  assert actual['exit_code']!.int() == if kind == 'old' { 1 } else { 0 }
  output_pin := if kind == 'old' { '6e3f6f2a3f4f1d09eeb4295a029adb624cd4806237bdb2beb25ed4e637d96f46' }
   else { '9cbbf87c03c32e04a06c5b1db095a0b9a0f57b621aa83916f3f331164513d045' }
  assert actual['output_sha256']!.str() == output_pin && hash(prefix + '.log')! == output_pin
  if kind == 'old' { assert os.read_file(prefix + '.log')!.contains('V panic: exact TimingLogger CNFE') }
  else { assert os.read_file(prefix + '.log')!.trim_space() == 'TIMING-LOGGER-NEW-EXPECTED-RESULT-PASS' }
  suite := object(state + '/commands/suite-' + kind + '.json')!
  assert suite['exit_code']!.int() == 0
  for suffix in ['-before.json', '-command.json', '.log'] { pins[prefix + suffix] = hash(prefix + suffix)! }
 }
 for item in ['timing-logger367-action-recorder.v', 'timing-logger367-action-recorder'] {
  path := os.dir(state) + '/' + item
  assert hash(path)! == if item.ends_with('.v') { recorder_source } else { recorder_binary }
  pins[path] = hash(path)!
 }
 original_new := read_map(state + '/new-semantic-check.json')!
 assert original_new['checker_binary_sha256']! == original_runner
 assert original_new['status']! == 'expected-result-pass' && original_new['variant']! == 'new'
 assert original_new['serial_sha256']! == hash(state + '/run-new/bootstrap-fixture/serial.log')!
 assert original_new['raw_results_sha256']! == hash(state + '/run-new/results.json')!
 pins[state + '/new-semantic-check.json'] = hash(state + '/new-semantic-check.json')!
 return pins
}

fn observed_qualify() ! {
 assert !os.exists(state + '/qualification/observed-invocations.json')
 pins := observed_invocations()!
 for path, pin in pins {
  target := state + '/qualification/original-invocations/' + os.base(path)
  assert !os.exists(target)
  clone(path, target)!
  assert hash(target)! == pin
 }
 write_json(state + '/qualification/observed-invocations.json', pins)!
 for kind in ['old', 'new'] { check(kind, state + '/qualification/observed-' + kind + '-semantic-check.json')! }
 assert observed_invocations()! == pins
 println('TIMING-LOGGER-OBSERVED-QUALIFICATION-PASS')
}

fn observed_seal() ! {
 assert !os.exists(state + '/sha256.json')
 pins := read_map(state + '/qualification/observed-invocations.json')!
 assert observed_invocations()! == pins
 for path, pin in pins { assert hash(state + '/qualification/original-invocations/' + os.base(path))! == pin }
 for kind in ['old', 'new'] {
  prior := read_map(state + '/qualification/observed-' + kind + '-semantic-check.json')!
  receipt := state + '/qualification/observed-' + kind + '-seal-semantic-check.json'
  check(kind, receipt)!
  assert read_map(receipt)! == prior, 'observed semantic result changed before sealing'
 }
 assert stable()! == read_map(state + '/shared-inputs.json')!
 assert observed_invocations()! == pins
 r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
 os.write_file(state + '-seal.log', r.output)!
 assert r.exit_code == 0, r.output
 print(r.output)
}

fn synthetic_raw(kind string, apk string) map[string]json2.Any {
 return {'id': json2.Any('bootstrap-fixture'), 'package': json2.Any('org.vinix.bootstrap'),
  'container_sha256': json2.Any(apk), 'metadata': json2.Any({'apk_sha256': json2.Any(apk)}),
  'staged_apk': json2.Any(state + '/apk/probe.apk'), 'launcher_entered': json2.Any(true),
  'native_maps_observed': json2.Any(true), 'functional_passed': json2.Any(json2.Null{}),
  'startup_seconds': json2.Any(35), 'observation_elapsed_seconds': json2.Any(35),
  'qemu_alive_before_capture': json2.Any(true), 'process_exited': json2.Any(kind == 'old'),
  'outcome': json2.Any(if kind == 'old' { 'startup_failed' } else { 'window_observed' }),
  'failure_markers': json2.Any(if kind == 'old' { ['ANDROID-WS-FAIL start activity', rejection,
   'Caused by: ' + rejection,
   'APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true'] } else { []string{} })}
}

fn rejected(kind string, raw map[string]json2.Any, log string, apk string) ! {
 semantic(kind, raw, log, apk) or { return }
 return error('semantic checker accepted a negative self-test')
}

fn self_test() ! {
 apk := "0".repeat(64)
 old_raw := synthetic_raw("old", apk)
 new_raw := synthetic_raw("new", apk)
 old_log := expected_old_output().join('\n') + '\n'
 new_log := expected_timing_output().join('\n') + '\n'
 semantic("old", old_raw, old_log, apk)!
 semantic("new", new_raw, new_log, apk)!
 for marker in markers {
  rejected("old", old_raw, old_log + marker + "\n", apk)!
  rejected("new", new_raw, new_log.replace(marker + "\n", ""), apk)!
  rejected("new", new_raw, new_log + marker + "\n", apk)!
 }
 for frame in ["Class.forName(", "TimingLoggerProbe.check(", "Main.onCreate("] {
  rejected("old", old_raw, old_log.replace(frame, "Other.method("), apk)!
 }
 rejected("old", old_raw, old_log.replace(rejection, "java.lang.ClassNotFoundException: unrelated"), apk)!
 rejected("old", old_raw, old_log.replace(rejection, "java.lang.ClassNotFoundException: android.util.Other"), apk)!
 rejected("old", old_raw, old_log + " at org.vinix.bootstrap.TimingLoggerProbe.check(Unknown Source:0)\n", apk)!
 for line in expected_old_output()[2..] {
  rejected('old', old_raw, old_log.replace(line + '\n', ''), apk)!
 }
 for changed in ['Caused by: java.lang.ClassNotFoundException: android.util.Other',
  'Caused by: java.lang.NoClassDefFoundError: android.util.TimingLogger'] {
  rejected('old', old_raw, old_log.replace('Caused by: ' + rejection, changed), apk)!
 }
 rejected('old', old_raw, old_log.replace('... 6 more', '... 5 more'), apk)!
 rejected('old', old_raw, old_log.replace('... 6 more', 'at unrelated.Frame.call(Unknown Source:0)\n... 6 more'), apk)!
 rejected('old', old_raw, old_log.replace('... 6 more', 'unrelated\n... 6 more'), apk)!
 rejected('old', old_raw, old_log.replace('Class.java:453', 'Class.java:454'), apk)!
 rejected('old', old_raw, old_log.replace('Unknown Source:2', 'Unknown Source:0'), apk)!
 rejected('old', old_raw, old_log.replace('Activity.vinixPerformCreate', 'Activity.onCreate'), apk)!
 rejected('old', old_raw, old_log + 'Caused by: ' + rejection + '\n', apk)!
 rejected('old', old_raw, old_log + 'Suppressed: unrelated\n', apk)!
 rejected('old', old_raw, old_log + old_log, apk)!
 for i in 3 .. 8 {
  frames := expected_old_output()
  pair := frames[i] + '\n' + frames[i + 1]
  rejected('old', old_raw, old_log.replace(pair, frames[i + 1] + '\n' + frames[i]), apk)!
 }
 mut missing_cnfe := synthetic_raw("old", apk)
 missing_cnfe["failure_markers"] = ["ANDROID-WS-FAIL start activity",
  "APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true"]
 rejected("old", missing_cnfe, old_log, apk)!
 rejected("old", old_raw, old_log.replace("ANDROID-WS-FAIL start activity", "ANDROID-WS-FAIL main looper"), apk)!
 rejected("old", old_raw, old_log + rejection + "\n", apk)!
 rejected("new", new_raw, "TIMING-LOGGER-BEGIN\n" + markers.reverse().join("\n") + "\n", apk)!
 for bad_log in [
  new_log.replace('initial: end, 0 ms', 'initial: end, 1 ms'),
  new_log.replace('TIMING-LOGGER367-INITIAL', 'TIMING-LOGGER367'),
  new_log.replace('deterministic:      7 ms, a', 'deterministic:      8 ms, a'),
  new_log.replace('deterministic:      9 ms, b', 'deterministic:      9 ms, a'),
  new_log.replace('deterministic: end, 16 ms', 'deterministic: end, 15 ms'),
  new_log.replace('deterministic:      7 ms, a\n', ''),
  new_log.replace('deterministic: begin\n', 'deterministic: begin\ndeterministic: unexpected\n'),
  new_log.replace(markers[4], 'TIMING-LOGGER367\ndeterministic: begin\n' + markers[4]),
  new_log.replace('TIMING-LOGGER367\ndeterministic:', 'TIMING-LOGGER367\nunrelated\ndeterministic:'),
  new_log.replace(markers[2], '').replace('initial: begin', markers[2] + '\ninitial: begin'),
 ] { rejected('new', new_raw, bad_log, apk)! }
 for kind in ["old", "new"] {
  log := if kind == "old" { old_log } else { new_log }
  raw := if kind == "old" { old_raw } else { new_raw }
  rejected(kind, raw, log + "TIMING-LOGGER-BEGIN\n", apk)!
  rejected(kind, raw, log.replace("TIMING-LOGGER-BEGIN\n", ""), apk)!
  rejected(kind, raw, log + "java.lang.VerifyError\n", apk)!
  rejected(kind, raw, log, "1".repeat(64))!
  mut changed := synthetic_raw(kind, apk)
  changed["functional_passed"] = true
  rejected(kind, changed, log, apk)!
  mut changed_exit := synthetic_raw(kind, apk)
  changed_exit["process_exited"] = kind != "old"
  rejected(kind, changed_exit, log, apk)!
  for field in ["id", "package", "staged_apk", "launcher_entered", "native_maps_observed", "startup_seconds"] {
   mut bad_identity := synthetic_raw(kind, apk)
   bad_identity[field] = match field {
    "launcher_entered", "native_maps_observed" { json2.Any(false) }
    "startup_seconds" { json2.Any(34) }
    else { json2.Any("unrelated") }
   }
   rejected(kind, bad_identity, log, apk)!
  }
 }
 for field in ["observation_elapsed_seconds", "qemu_alive_before_capture", "failure_markers", "outcome"] {
  mut changed := synthetic_raw("new", apk)
  changed[field] = match field {
   "observation_elapsed_seconds" { json2.Any(34) }
   "qemu_alive_before_capture" { json2.Any(false) }
   "failure_markers" { json2.Any(["ANDROID-WS-FAIL start activity"]) }
   else { json2.Any("startup_failed") }
  }
  rejected("new", changed, new_log, apk)!
 }
 for bad in ["ANDROID-WS-FAIL start activity", "java.lang.AssertionError", "APK-SUITE-DEPENDENCY-FAIL",
  "ANDROID-WS-DEPENDENCY-FAIL", "ANDROID-WS-PROCESS-FAIL", "APK-SUITE-EXIT id=bootstrap-fixture code=0"] {
  rejected("new", new_raw, new_log + bad + "\n", apk)!
 }
 println("TIMING-LOGGER-SEMANTIC-SELF-TEST-PASS")
}

fn main() {
 $if prod { panic('assertions required') }
 if os.args.len == 7 && os.args[1] == 'prepare' {
  prepare(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6])!
  return
 }
 assert os.args.len == 2, 'prepare FRAMEWORK_ROOT MANIFEST_SHA JAR_SHA FIXTURE_COMMIT FIXTURE_SHA | old | new | qualify | seal | observed-qualify | observed-seal | self-test'
 match os.args[1] {
  'self-test' { self_test()! }
  'old', 'new' { run(os.args[1])! }
  'observed-qualify' { observed_qualify()! }
  'observed-seal' { observed_seal()! }
  'qualify' { for kind in ['old', 'new'] { check(kind, state + '/qualification/' + kind + '-semantic-check.json')! } }
  'seal' {
   assert !os.exists(state + '/sha256.json')
   qualify()!
   for kind in ['old', 'new'] {
    prior := read_map(state + '/' + kind + '-semantic-check.json')!
    receipt := state + '/qualification/' + kind + '-seal-semantic-check.json'
    check(kind, receipt)!
    assert read_map(receipt)! == prior, 'semantic result changed before sealing'
   }
   assert stable()! == read_map(state + '/shared-inputs.json')!
   // The sealer inventories the complete root. Do not append command receipts
   // inside that root after it has written the final manifest.
   r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
   os.write_file(state + '-seal.log', r.output)!
   assert r.exit_code == 0, r.output
   print(r.output)
  }
  else { panic('unknown action') }
 }
}
