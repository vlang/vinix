// SPDX-License-Identifier: GPL-2.0-or-later
// Independent retained ART results and original290 complete bundle readback.
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
const root = state + '/intent-uri369-fixture-2026-10-26'
const output = state + '/intent-uri369-art-peer-readback-2026-10-26'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const runner_pin = '3229369e8b908233b6d6dcd0a8b7aa2d45697c734de3e11ebe38c84082e10d33'
const old_jar = 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
const new_jar = '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'
const apk_pin = '710eeaa6cc2b5f0d5ddd0fde5b3b62e71e844220c20584846f121dbbe13eec85'
const rejection = "java.lang.NoSuchMethodError: No static method parseUri(Ljava/lang/String;I)Landroid/content/Intent; in class Landroid/content/Intent; or its super classes (declaration of 'android.content.Intent' appears in /opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar)"
const markers = ['INTENT-URI-ORDINARY-PASS', 'INTENT-URI-MODERN-PASS', 'INTENT-URI-EXTRAS-PASS',
 'INTENT-URI-FLAGS-PASS', 'INTENT-URI-ANDROID-APP-PASS', 'INTENT-URI-SELECTOR-PASS',
 'INTENT-URI-LEGACY-PASS', 'INTENT-URI-ERRORS-PASS', 'INTENT-URI-PASS']

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
 assert hash(root + '/shared-inputs.json')! == 'b29b3fdf6510d67c0fb105beaaf37a4e6ea3dc77319504f35b8138fc57cbd17d'
 assert hash(root + '/build-pins.json')! == '7ee94db94a84a92d7582e52f70f936b556d7e7c9ccc6f10114baefa859dae5ae'
 shared := pins(root + '/shared-inputs.json')!
 mut expected := map[string]string{}
 dirs := ['framework369', 'native-old', 'native-new', 'fixture-inputs', 'tools', 'source',
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
 mut baseline := subset(shared, 'framework369/baseline367/baseline365/baseline361/baseline359/baseline353/native-new/')
 assert baseline['api-impl.jar']! == '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
 baseline.delete('api-impl.jar')
 assert old == baseline, 'complete qualified353 native closure must remain unchanged'
 assert old['libvinix-android-native.so']! == 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
 assert old['popular-launcher']! == '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
 assert subset(shared, 'apk/smali/').keys().sorted() == ['org/vinix/bootstrap/IntentUriProbe.smali', 'org/vinix/bootstrap/Main.smali']
 assert shared['apk/probe.apk']! == apk_pin && hash(root + '/apk/probe.apk')! == apk_pin
 assert shared['tools/checked-runner']! == runner_pin
 assert shared['source/intent-uri369-run.v']! == '09b717df537cb6d320224b53e74405c5ba62b994114443bdfe64d93d4218fd1b'
 assert shared['frozen/vroot/intent-uri-driver/startupfixture/intent_uri.v']! == 'c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c'
 for key, pin in {
  'framework369/sha256.json': '9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93'
  'framework369/baseline367/sha256.json': '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
  'framework369/baseline367/baseline365/sha256.json': 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
  'framework369/baseline367/baseline365/baseline361/sha256.json': '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
  'framework369/baseline367/baseline365/baseline361/baseline359/sha256.json': '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
  'framework369/baseline367/baseline365/baseline361/baseline359/baseline353/sha256.json': '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
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
 for kind, config in {'old': a, 'new': b} {
  assert config['output']!.str() == repo + '/build/android-maps/intent-uri369-' + kind
  assert config['native_dir']!.str() == root + '/native-' + kind
  assert config['boot_image']!.str() == root + '/vm-' + kind + '/boot.img'
  assert config['efivars']!.str() == root + '/vm-' + kind + '/efivars.fd'
 }
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

fn require(condition bool, message string) ! {
 if !condition { return error(message) }
}

fn expected_intent_output() []string {
 mut lines := ['INTENT-URI-BEGIN']
 lines << markers
 return lines
}

fn semantic_at(kind string, raw map[string]json2.Any, log string, apk string, staged_apk string) ! {
 require(kind in ["old", "new"], "variant")!
 lines := log.split_into_lines().map(it.trim_space())
 require(raw["id"]!.str() == "bootstrap-fixture" && raw["package"]!.str() == "org.vinix.bootstrap", "fixture identity")!
 require(raw["container_sha256"]!.str() == apk && raw["metadata"]!.as_map()["apk_sha256"]!.str() == apk, "APK identity")!
 require(raw["staged_apk"]!.str() == staged_apk, "staged APK")!
 require(raw["launcher_entered"]!.bool() && raw["native_maps_observed"]!.bool(), "native ART launch")!
 require(raw["functional_passed"]! is json2.Null && raw["startup_seconds"]!.int() == 35, "original classifier and window")!
 require(lines.filter(it == "INTENT-URI-BEGIN").len == 1, "single probe start")!
 if kind == "old" {
  for marker in markers { require(!log.contains(marker), "old emitted " + marker)! }
  require(lines.filter(it.starts_with('INTENT-URI')) == ['INTENT-URI-BEGIN'], 'only old probe start')!
  require(lines.filter(it == rejection).len == 1 && log.count('NoSuchMethodError') == 1,
   'exact direct parseUri missing static method')!
  begin := lines.index('INTENT-URI-BEGIN')
  failure := lines.index(rejection)
  require(begin >= 0 && failure > begin, 'old probe entered before linkage failure')!
  require(!log.contains('Caused by:') && !log.contains('Suppressed:')
   && !log.contains('Class.forName('), 'direct invocation without wrapped cause')!
  frames := lines.filter(it.starts_with('at org.vinix.bootstrap.'))
  prefixes := ['at org.vinix.bootstrap.IntentUriProbe.ordinary(',
   'at org.vinix.bootstrap.IntentUriProbe.check(', 'at org.vinix.bootstrap.Main.onCreate(']
  require(frames.len == prefixes.len, 'isolated old application frames')!
  for i, prefix in prefixes { require(frames[i].starts_with(prefix), 'ordered old application frame')! }
  require(lines.index(frames[0]) > failure, 'old frames follow direct failure')!
  require(lines.index(frames.last()) < lines.index('APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true'),
   'old application frames precede guest exit1')!
  require(lines.filter(it == "ANDROID-WS-FAIL start activity").len == 1 && log.count("ANDROID-WS-FAIL") == 1, "start activity failure")!
  require(lines.filter(it == "APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true").len == 1, "guest exit1")!
  require(raw["outcome"]!.str() == "startup_failed" && raw["process_exited"]!.bool(), "old raw failure")!
  require(raw["failure_markers"]!.as_array().map(it.str()) == ["ANDROID-WS-FAIL start activity", rejection,
   "APK-SUITE-EXIT id=bootstrap-fixture code=1 native_observed=true gtk_x11_absent=true"], "old raw markers")!
 } else {
  mut position := log.index("INTENT-URI-BEGIN") or { return error("missing start") }
  for marker in markers {
   require(lines.filter(it == marker).len == 1, "single " + marker)!
   next := log.index(marker) or { return error("missing " + marker) }
   require(next > position, "ordered " + marker)!
   position = next
  }
  require(lines.filter(it.starts_with('INTENT-URI')) == expected_intent_output(), 'complete ordered parseUri phases')!
  require(!log.contains("NoSuchMethodError") && !log.contains("ANDROID-WS-FAIL"), "new failure marker")!
  for bad in ["APK-SUITE-EXIT id=bootstrap-fixture ", "APK-SUITE-DEPENDENCY-FAIL",
   "ANDROID-WS-DEPENDENCY-FAIL", "ANDROID-WS-PROCESS-FAIL"] { require(!log.contains(bad), "final serial failure: " + bad)! }
  require(raw["outcome"]!.str() == "window_observed" && !raw["process_exited"]!.bool(), "new raw survival")!
  require(raw["observation_elapsed_seconds"]!.int() >= 35 && raw["qemu_alive_before_capture"]!.bool(), "full35second window")!
  require(raw["failure_markers"]!.as_array().len == 0, "raw failure markers")!
 }
 for bad in ["AssertionError", "NullPointerException", "VerifyError", "NoClassDefFoundError",
  "ClassNotFoundException", "NoSuchFieldError", "UnsatisfiedLinkError", "JNI DETECTED ERROR",
  "ExceptionInInitializerError", "AbstractMethodError"] { require(!log.contains(bad), bad)! }
}

fn semantic_source() ! {
 source := os.read_file(@FILE)!
 reference := os.read_file(root + '/source/intent-uri369-run.v')!
 assert hash(root + '/source/intent-uri369-run.v')! == '09b717df537cb6d320224b53e74405c5ba62b994114443bdfe64d93d4218fd1b'
 assert source.all_after('\nconst rejection = ').all_before('\nfn ').trim_space()
  == reference.all_after('\nconst rejection = ').all_before('\nfn ').trim_space()
 // Keep the retained harness oracle verbatim, including its helper functions.
 for name in ['require', 'expected_intent_output', 'semantic_at'] {
  start := '\nfn ' + name + '('
  assert source.count(start) == 1 && reference.count(start) == 1
  assert source.all_after(start).all_before('\nfn ').trim_space() == reference.all_after(start).all_before('\nfn ').trim_space(), name
 }
}

fn runtime(kind string) ! {
 values := json2.decode[[]map[string]json2.Any](os.read_file(root + '/run-' + kind + '/results.json')!)!
 assert values.len == 1
 log := os.read_file(root + '/run-' + kind + '/bootstrap-fixture/serial.log')!
 semantic_at(kind, values[0], log, apk_pin, root + '/apk/probe.apk')!
 receipt := pins(root + '/' + kind + '-semantic-check.json')!
 assert receipt == pins(root + '/qualification/' + kind + '-seal-semantic-check.json')!
 assert receipt['checker_binary_sha256']! == runner_pin && receipt['status']! == 'expected-result-pass'
 assert receipt['signed_apk_sha256']! == apk_pin && receipt['variant']! == kind
 assert receipt['old_framework_sha256']! == old_jar && receipt['new_framework_sha256']! == new_jar
 assert receipt['native_sha256']! == 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
 assert receipt['serial_sha256']! == hash(root + '/run-' + kind + '/bootstrap-fixture/serial.log')!
 assert receipt['raw_results_sha256']! == hash(root + '/run-' + kind + '/results.json')!
 assert receipt['raw_outcome']! == values[0]['outcome']!.str()
 suite := object(root + '/commands/suite-' + kind + '.json')!
 assert suite['exit_code']!.int() == 0 && suite['executable_sha256']!.str() == hash(root + '/tools/suite')!
 assert suite['argv']!.as_array().map(it.str()) == [root + '/tools/suite', root + '/' + kind + '.json']
}

fn actions(manifest string, count int) ! {
 for action in ['prepare', 'old', 'new', 'seal'] {
  prefix := state + '/intent-uri369-fixture-' + action + '-2026-10-26'
  actual := object(prefix + '-command.json')!
  before := object(prefix + '-before.json')!
  for key, value in before { assert value == actual[key]! }
  argv := actual['argv']!.as_array().map(it.str())
  if action == 'prepare' {
   assert argv == [state + '/intent-uri369-run-bootstrap-build-b-2026-10-26/intent-uri369-run', 'prepare',
    state + '/intent-uri369-framework-build-2026-10-26',
    '9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93', new_jar,
    'cac9f6367c79fc7de92deb45809502798ddcb123', 'c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c']
  } else { assert argv == [root + '/tools/checked-runner', action] }
  pin := if action == 'prepare' { '6244cdb6e9a61cf0ddc438b90b833e3a991049d2031793f3ac2424362b1f9f5e' } else { runner_pin }
  assert actual['executable_sha256_before']!.str() == pin && actual['executable_sha256_after']!.str() == pin
  assert actual['exit_code']!.int() == 0 && actual['cwd']!.str() == repo
  assert actual['started_utc']!.str() < actual['completed_utc']!.str()
  assert actual['recorder_source_sha256']!.str() == 'dadc55f3adbb702a8f770a4aae55968474e8d97989b5a1461d579227b6c9fe53'
  assert actual['recorder_binary_sha256']!.str() == '74816f7773b207caf2aa463d4dbaf9a9f7de22cc5f709ae008feab0dead48f24'
  assert actual['output_sha256']!.str() == hash(prefix + '.log')!
  lines := os.read_file(prefix + '.log')!.trim_space().split_into_lines()
  if action in ['old', 'new'] { assert lines == ['INTENT-URI-' + action.to_upper() + '-EXPECTED-RESULT-PASS'] }
  if action == 'seal' {
   assert lines == ['INTENT-URI-OLD-EXPECTED-RESULT-PASS', 'INTENT-URI-NEW-EXPECTED-RESULT-PASS',
    'INFLATER-TRACE-BUNDLE-SEALED root=' + root + ' files=' + count.str() + ' manifest=' + manifest]
  }
  for suffix in ['-before.json', '-command.json', '.log'] {
   os.cp(prefix + suffix, output + '/' + os.base(prefix) + suffix)!
  }
 }
}

fn main() {
 $if prod { panic('assertions required') }
 assert os.args.len == 2 && os.getwd() == repo && os.real_path(root) == root
 if os.args[1] == '--source-check' {
  semantic_source()!
  println('INTENT369-ART-ORACLE-SOURCE-PASS')
  return
 }
 manifest_pin := os.args[1]
 assert manifest_pin.len == 64 && manifest_pin.bytes().all(it in '0123456789abcdef'.bytes())
 assert !os.exists(output) && !os.is_link(output), 'fresh adjacent reader output required'
 assert hash(root + '/sha256.json')! == manifest_pin && hash(checker)! == checker_pin
 manifest := pins(root + '/sha256.json')!
 semantic_source()!
 closure_count := inputs(manifest)!
 runtime('old')!
 runtime('new')!
 reader_source := hash(@FILE)!
 reader_binary := hash(os.executable())!
 os.mkdir(output)!
 os.cp(@FILE, output + '/reader.v')!
 os.cp(os.executable(), output + '/reader')!
 actions(manifest_pin, manifest.len)!
 argv := [checker, root, manifest_pin, output + '/complete-receipt.json']
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(output + '/stdout.log', r.output)!
 os.write_file(output + '/command.json', json2.encode({
  'argv': json2.Any(argv), 'working_directory': json2.Any(repo),
  'reader_argv': json2.Any(os.args),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'exit_code': json2.Any(r.exit_code), 'checker_sha256': json2.Any(checker_pin),
  'manifest_sha256_before': json2.Any(manifest_pin), 'manifest_sha256_after': json2.Any(hash(root + '/sha256.json')!),
  'reader_source_sha256': json2.Any(reader_source), 'reader_binary_sha256': json2.Any(reader_binary),
  'stdout_sha256': json2.Any(hash(output + '/stdout.log')!), 'frozen_closure_inputs': json2.Any(closure_count)
 }, prettify: true) + '\n')!
 assert r.exit_code == 0, r.output
 assert hash(root + '/sha256.json')! == manifest_pin && hash(checker)! == checker_pin
 assert hash(@FILE)! == reader_source && hash(output + '/reader.v')! == reader_source
 assert hash(os.executable())! == reader_binary && hash(output + '/reader')! == reader_binary
 receipt := object(output + '/complete-receipt.json')!
 assert receipt['exit_code']!.int() == 0 && receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
 assert receipt['manifest_sha256']!.str() == manifest_pin && receipt['files_checked']!.int() == manifest.len
 println('INTENT369-ART-PEER-PASS closure_inputs=' + closure_count.str() + ' ' + r.output.trim_space())
}
