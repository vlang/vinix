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
const root = state + '/intent-uri371-fixture-2026-10-26'
const origin = state + '/intent-uri369-fixture-2026-10-26'
const snapshot = state + '/intent-uri369-failure-readback-b-2026-10-26'
const original_inventory = '6e2288faa9a4eb14f3a5495a751b1298d1e179e181eba247627880748181da4b'
const original_receipt = '0f91fd7499563acb0cb863b04e078d2390210986d53e8888f9c1f7558a706e96'
const source_pin = 'e6de49d024b706ffc34f6169b3a1a31f725708d3bbfd7425657513d9c6d2e707'
const shared_pin = '81c6c4915ce15be52471fed4ba3972f04d913ad88c7a77a59ccd79bb6e0b0dad'
const build_pin = '73e13c76dfb0e74245a3010723badc66549a2da68bcf3c1f665364b1f4b0847b'
const framework_pin = '71e311764ece295185656854294a514a9c641419c567d5f96ac66f52f4b89750'
const bootstrap_pin = '4c192b967eb30a27caa5fa08d5d5c0ff15e4136e89134390d91c7704ef4488b6'
const action_source_pin = 'cb0dafd546e714bbeb3157a49f420b758e5d98221e9de1b3891396e722c46819'
const action_binary_pin = 'b2d0fdd9791b7f25b509b3ac7145759ce2f69076387c7b1f5b2f9d1945a64997'
const output = state + '/intent-uri371-art-peer-readback-2026-10-26'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const runner_pin = '00c60580fbd151f9760dbf9b83604d469ebcf29093822aa38a73b518932c966b'
const original_runner = '3229369e8b908233b6d6dcd0a8b7aa2d45697c734de3e11ebe38c84082e10d33'
const old_jar = 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
const new_jar = '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
const failed_jar = '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'
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


fn canonical(key string) bool {
 return key != '' && !key.starts_with('/') && !key.ends_with('/')
  && key.split('/').all(it != '' && it != '.' && it != '..')
}

fn regular_names(path string, prefix string, mut found map[string]bool) ! {
 for name in os.ls(path + '/' + prefix)! {
  key := if prefix == '' { name } else { prefix + '/' + name }
  assert canonical(key)
  match os.lstat(path + '/' + key)!.get_filetype() {
   .directory { regular_names(path, key, mut found)! }
   .regular { found[key] = true }
   else { return error('nonregular historical evidence: ' + key) }
  }
 }
}

fn control_selected(key string) bool {
 return key.starts_with('run-old/') || key.starts_with('native-old/')
  || key.starts_with('apk/') || key.starts_with('commands/')
  || key in ['old.json', 'config.json', 'build-pins.json', 'old-inputs-before.json',
   'old-inputs-after.json', 'shared-inputs.json', 'old-semantic-check.json',
   'source/intent-uri369-run.v', 'tools/checked-runner', 'tools/suite']
}

fn inputs(manifest map[string]string) !int {
 assert hash(root + '/shared-inputs.json')! == shared_pin
 assert hash(root + '/build-pins.json')! == build_pin
 shared := pins(root + '/shared-inputs.json')!
 mut expected := map[string]string{}
 dirs := ['framework371', 'native-old', 'native-new', 'fixture-inputs', 'tools', 'source',
  'frozen', 'closure-inputs', 'generated-c', 'apk', 'initial-media', 'control369']
 singles := ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json',
  'build-pins.json', 'control-origin.json', 'control-sha256.json',
  'control-origin-inventory.json', 'control-failure-receipt.json']
 for key, pin in manifest {
  if key in singles || dirs.any(key.starts_with(it + '/')) { expected[key] = pin }
 }
 assert shared == expected, 'complete prepared input inventory must match canonical manifest'
 for phase in ['before', 'after'] { assert pins(root + '/new-inputs-' + phase + '.json')! == shared }
 mut old := subset(shared, 'native-old/')
 mut new := subset(shared, 'native-new/')
 assert old['api-impl.jar']! == old_jar && new['api-impl.jar']! == new_jar
 assert old == subset(shared, 'control369/files/native-old/')
 old.delete('api-impl.jar')
 new.delete('api-impl.jar')
 assert old.len > 0 && old == new, 'framework JAR must be sole native closure delta'
 mut baseline := subset(shared, 'framework371/baseline367/baseline365/baseline361/baseline359/baseline353/native-new/')
 assert baseline['api-impl.jar']! == '1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83'
 baseline.delete('api-impl.jar')
 assert old == baseline, 'complete qualified353 native closure must remain unchanged'
 assert old['libvinix-android-native.so']! == 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
 assert old['popular-launcher']! == '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
 assert subset(shared, 'apk/') == subset(shared, 'control369/files/apk/'), 'entire signed APK build retained byte-identically'
 assert subset(shared, 'apk/smali/').keys().sorted() == ['org/vinix/bootstrap/IntentUriProbe.smali', 'org/vinix/bootstrap/Main.smali']
 assert shared['apk/probe.apk']! == apk_pin && hash(root + '/apk/probe.apk')! == apk_pin
 assert shared['tools/checked-runner']! == runner_pin
 assert shared['source/intent-uri371-run.v']! == source_pin
 assert shared['frozen/vroot/intent-uri-driver/startupfixture/intent_uri.v']! == 'c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c'
 for key, pin in {
  'framework371/sha256.json': framework_pin
  'framework371/baseline367/sha256.json': '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
  'framework371/baseline367/baseline365/sha256.json': 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
  'framework371/baseline367/baseline365/baseline361/sha256.json': '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
  'framework371/baseline367/baseline365/baseline361/baseline359/sha256.json': '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
  'framework371/baseline367/baseline365/baseline361/baseline359/baseline353/sha256.json': '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
 } { assert shared[key]! == pin && hash(root + '/' + key)! == pin }
 before := pins(root + '/runner-before-v-files.json')!
 assert before == pins(root + '/runner-after-v-files.json')! && before.len == 270
 for path, pin in before {
  assert os.real_path(path) == path && path.starts_with(root + '/frozen/vroot/')
  assert !path.contains('/androidtools/')
  assert shared[path[root.len + 1..]]! == pin
  assert shared['closure-inputs/' + path.trim_left('/')]! == pin
 }
 assert !os.exists(root + '/commands/fixture-smali.json') && !os.exists(root + '/commands/apk-sign.json'), 'signed APK must be reused'
 mut a := object(root + '/control369/files/old.json')!
 mut b := object(root + '/new.json')!
 for entry in [{ 'kind': 'old', 'base': origin, 'alias': '369' }, { 'kind': 'new', 'base': root, 'alias': '371' }] {
  config := if entry['kind']! == 'old' { a } else { b }
  base := entry['base']!
  kind := entry['kind']!
  assert config['output']!.str() == repo + '/build/android-maps/intent-uri' + entry['alias']! + '-' + kind
  assert config['native_dir']!.str() == base + '/native-' + kind
  assert config['boot_image']!.str() == base + '/vm-' + kind + '/boot.img'
  assert config['efivars']!.str() == base + '/vm-' + kind + '/efivars.fd'
  apps := config['applications']!.as_array()
  assert apps.len == 1 && apps[0].as_map()['apk']!.str() == base + '/apk/probe.apk'
  assert apps[0].as_map()['startup_seconds']!.int() == 35
 }
 for key in ['output', 'native_dir', 'boot_image', 'efivars'] { a.delete(key); b.delete(key) }
 normalized := json2.decode[map[string]json2.Any](json2.encode(a).replace(origin, root).replace('source/intent-uri369-run.v', 'source/intent-uri371-run.v'))!
 assert normalized == b, 'same complete runtime configuration except explicit per-run paths'
 return before.len + control(manifest)!
}

fn control(manifest map[string]string) !int {
 assert !os.is_link(origin) && os.real_path(origin) == origin
 assert !os.exists(origin + '/sha256.json') && !os.exists(origin + '/new-semantic-check.json'), 'failed369 remains unsealed'
 assert hash(snapshot + '/files.json')! == original_inventory
 assert hash(snapshot + '/receipt.json')! == original_receipt
 assert hash(root + '/control-origin-inventory.json')! == original_inventory
 assert hash(root + '/control-failure-receipt.json')! == original_receipt
 complete := pins(root + '/control-origin-inventory.json')!
 proof := object(root + '/control-failure-receipt.json')!
 assert complete.len == 52112 && proof['original_file_count']!.int() == complete.len
 assert proof['status']!.str() == 'preserved-real-new-art-failure' && proof['original_root']!.str() == origin
 assert proof['original_files_sha256']!.str() == original_inventory
 assert proof['cwd']!.str() == repo && proof['started_utc']!.str() < proof['completed_utc']!.str()
 assert proof['reader_source_sha256']!.str() == hash(snapshot + '/reader.v')!
 assert proof['reader_binary_sha256']!.str() == hash(snapshot + '/reader')!
 adjacent := pins(snapshot + '/adjacent.json')!
 assert hash(snapshot + '/adjacent.json')! == proof['adjacent_inventory_sha256']!.str()
 mut present := map[string]bool{}
 regular_names(origin, '', mut present)!
 assert present.keys().sorted() == complete.keys().sorted(), 'entire original historical root remains required'
 selected := pins(root + '/control-sha256.json')!
 paths := pins(root + '/control-origin.json')!
 mut expected := map[string]string{}
 for key, pin in complete {
  assert canonical(key) && pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
  if control_selected(key) { expected['files/' + key] = pin }
 }
 for label in ['prepare', 'old', 'new'] {
  for suffix in ['-before.json', '-command.json', '.log'] {
   expected['actions/' + label + suffix] = adjacent[state + '/intent-uri369-fixture-' + label + '-2026-10-26' + suffix]!
  }
 }
 assert selected == expected && paths.keys().sorted() == selected.keys().sorted()
 assert subset(manifest, 'control369/') == selected, 'canonical exact retained control set'
 for key, pin in selected {
  path := if key.starts_with('files/') { origin + '/' + key.all_after('files/') }
   else {
    part := key.all_after('actions/')
    label := if part.starts_with('prepare') { 'prepare' } else if part.starts_with('old') { 'old' } else { 'new' }
    state + '/intent-uri369-fixture-' + label + '-2026-10-26' + part.all_after(label)
   }
  assert canonical(key) && paths[key]! == path && hash(path)! == pin
 }
 for key, pin in {
  'old.json': '72cc1af880e989e562fec52a481841716d6fbb70cbda59b80e1ab700f1213eaf'
  'old-semantic-check.json': '5f59ce1d8d19a3e84e9c48975d69bf0581aa66e5b3409051c000a733f92e4ea3'
  'run-old/results.json': 'c431188b61ac61e9969959504e59e6a3ae53f0f05b547f890a50e30d804457bf'
  'run-old/bootstrap-fixture/serial.log': 'a53bff853dfa70c61b0a5775fdbbf8be013890208c811c3aa2e05861fb9d33c9'
  'commands/suite-old.json': '0217b826dcf1547cc24e8127e1097a23546422b5a35ac9130746e0b79a7e283d'
 } { assert selected['files/' + key]! == pin }
 c := root + '/control369/files'
 original_shared := pins(c + '/shared-inputs.json')!
 assert hash(c + '/shared-inputs.json')! == 'b29b3fdf6510d67c0fb105beaaf37a4e6ea3dc77319504f35b8138fc57cbd17d'
 assert pins(c + '/old-inputs-before.json')! == original_shared && pins(c + '/old-inputs-after.json')! == original_shared
 for key, pin in original_shared { assert complete[key]! == pin }
 mut closure_count := 0
 for kind in ['fixture-driver', 'runner'] {
  a := kind + '-before-v-files.json'
  b := kind + '-after-v-files.json'
  assert hash(origin + '/' + a)! == complete[a]! && hash(origin + '/' + b)! == complete[b]!
  before := pins(origin + '/' + a)!
  assert before == pins(origin + '/' + b)! && before.len > 0
  for path, pin in before {
   assert os.real_path(path) == path && path.starts_with(origin + '/frozen/vroot/') && !path.contains('/androidtools/')
   assert original_shared[path[origin.len + 1..]]! == pin
   assert original_shared['closure-inputs/' + path.trim_left('/')]! == pin
  }
  closure_count += before.len
 }
 historical_actions()!
 return closure_count
}

fn historical_actions() ! {
 for action in ['prepare', 'old', 'new'] {
  prefix := root + '/control369/actions/' + action
  actual := object(prefix + '-command.json')!
  before := object(prefix + '-before.json')!
  for key, value in before { assert value == actual[key]! }
  argv := actual['argv']!.as_array().map(it.str())
  if action == 'prepare' {
   assert argv == [state + '/intent-uri369-run-bootstrap-build-b-2026-10-26/intent-uri369-run', 'prepare',
    state + '/intent-uri369-framework-build-2026-10-26', '9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93', failed_jar,
    'cac9f6367c79fc7de92deb45809502798ddcb123', 'c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c']
  } else { assert argv == [origin + '/tools/checked-runner', action] }
  pin := if action == 'prepare' { '6244cdb6e9a61cf0ddc438b90b833e3a991049d2031793f3ac2424362b1f9f5e' } else { original_runner }
  assert actual['executable_sha256_before']!.str() == pin && actual['executable_sha256_after']!.str() == pin
  assert actual['exit_code']!.int() == if action == 'new' { 1 } else { 0 }
  assert actual['cwd']!.str() == repo && actual['started_utc']!.str() < actual['completed_utc']!.str()
  assert actual['recorder_source_sha256']!.str() == 'dadc55f3adbb702a8f770a4aae55968474e8d97989b5a1461d579227b6c9fe53'
  assert actual['recorder_binary_sha256']!.str() == '74816f7773b207caf2aa463d4dbaf9a9f7de22cc5f709ae008feab0dead48f24'
  assert actual['output_sha256']!.str() == hash(prefix + '.log')!
  if action == 'old' { assert os.read_file(prefix + '.log')!.trim_space() == 'INTENT-URI-OLD-EXPECTED-RESULT-PASS' }
  if action == 'new' { assert os.read_file(prefix + '.log')!.contains('single INTENT-URI-ANDROID-APP-PASS') }
 }
}

fn runtime(kind string) ! {
 c := if kind == 'old' { root + '/control369/files' } else { root }
 values := json2.decode[[]map[string]json2.Any](os.read_file(c + '/run-' + kind + '/results.json')!)!
 assert values.len == 1
 log := os.read_file(c + '/run-' + kind + '/bootstrap-fixture/serial.log')!
 semantic_at(kind, values[0], log, apk_pin, (if kind == 'old' { origin } else { root }) + '/apk/probe.apk')!
 receipt := pins(root + '/' + kind + '-semantic-check.json')!
 assert receipt == pins(root + '/qualification/' + kind + '-seal-semantic-check.json')!
 assert receipt['signed_apk_sha256']! == apk_pin && receipt['variant']! == kind
 assert receipt['old_framework_sha256']! == old_jar && receipt['new_framework_sha256']! == new_jar
 assert receipt['native_sha256']! == 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
 assert receipt['serial_sha256']! == hash(c + '/run-' + kind + '/bootstrap-fixture/serial.log')!
 assert receipt['raw_results_sha256']! == hash(c + '/run-' + kind + '/results.json')!
 if kind == 'old' {
  assert receipt['status']! == 'retained-old-control-pass' && receipt['checker_source_sha256']! == source_pin
  assert receipt['original_root']! == origin && receipt['original_inventory_sha256']! == original_inventory
  assert receipt['retained_map_sha256']! == hash(root + '/control-sha256.json')!
  assert receipt['original_semantic_receipt_sha256']! == hash(c + '/old-semantic-check.json')!
  assert receipt['original_old_action_sha256']! == hash(root + '/control369/actions/old-command.json')!
  prior := pins(c + '/old-semantic-check.json')!
  assert prior['variant']! == 'old' && prior['status']! == 'expected-result-pass'
  assert prior['checker_binary_sha256']! == original_runner && hash(c + '/tools/checked-runner')! == original_runner
  for key in ['serial_sha256', 'raw_results_sha256', 'signed_apk_sha256', 'native_sha256', 'old_framework_sha256'] { assert prior[key]! == receipt[key]! }
  assert prior['new_framework_sha256']! == failed_jar && prior['raw_outcome']! == 'startup_failed'
 } else {
  assert receipt['status']! == 'expected-result-pass' && receipt['checker_binary_sha256']! == runner_pin
  assert receipt['raw_outcome']! == values[0]['outcome']!.str()
 }
 suite := object(c + '/commands/suite-' + kind + '.json')!
 assert suite['exit_code']!.int() == 0 && suite['executable_sha256']!.str() == hash(root + '/tools/suite')!
 assert suite['argv']!.as_array().map(it.str()) == [(if kind == 'old' { origin } else { root }) + '/tools/suite', (if kind == 'old' { origin } else { root }) + '/' + kind + '.json']
}

fn actions(manifest string, count int) ! {
 for action in ['prepare', 'new', 'seal'] {
  prefix := state + '/intent-uri371-fixture-' + action + '-2026-10-26'
  actual := object(prefix + '-command.json')!
  before := object(prefix + '-before.json')!
  for key, value in before { assert value == actual[key]! }
  argv := actual['argv']!.as_array().map(it.str())
  if action == 'prepare' {
   assert argv == [state + '/intent-uri371-run-bootstrap-build-2026-10-26/intent-uri371-run', 'prepare',
    state + '/intent-uri371-framework-build-2026-10-26', framework_pin, new_jar,
    'cac9f6367c79fc7de92deb45809502798ddcb123', 'c992874027c12aa7d7125246754a646749de01d7ea4034db0d7a3a150e27f36c']
  } else { assert argv == [root + '/tools/checked-runner', action] }
  pin := if action == 'prepare' { bootstrap_pin } else { runner_pin }
  assert actual['executable_sha256_before']!.str() == pin && actual['executable_sha256_after']!.str() == pin
  assert actual['exit_code']!.int() == 0 && actual['cwd']!.str() == repo
  assert actual['started_utc']!.str() < actual['completed_utc']!.str()
  assert actual['recorder_source_sha256']!.str() == action_source_pin
  assert actual['recorder_binary_sha256']!.str() == action_binary_pin
  assert actual['output_sha256']!.str() == hash(prefix + '.log')!
  lines := os.read_file(prefix + '.log')!.trim_space().split_into_lines()
  if action == 'new' { assert lines == ['INTENT-URI-NEW-EXPECTED-RESULT-PASS'] }
  if action == 'seal' {
   assert lines == ['INTENT-URI-RETAINED-OLD-CONTROL-PASS', 'INTENT-URI-NEW-EXPECTED-RESULT-PASS',
    'INFLATER-TRACE-BUNDLE-SEALED root=' + root + ' files=' + count.str() + ' manifest=' + manifest]
  }
  for suffix in ['-before.json', '-command.json', '.log'] { os.cp(prefix + suffix, output + '/' + os.base(prefix) + suffix)! }
 }
 // Keep the historic compiler maps used by this reader without modifying369.
 for kind in ['fixture-driver', 'runner'] {
  for phase in ['before', 'after'] {
   name := kind + '-' + phase + '-v-files.json'
   os.cp(origin + '/' + name, output + '/original369-' + name)!
  }
 }
 os.cp(snapshot + '/adjacent.json', output + '/original369-adjacent.json')!
 os.cp(snapshot + '/reader.v', output + '/original369-failure-reader.v')!
 os.cp(snapshot + '/reader', output + '/original369-failure-reader')!
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
 reference := os.read_file(root + '/source/intent-uri371-run.v')!
 assert hash(root + '/source/intent-uri371-run.v')! == source_pin
 assert source.all_after('\nconst rejection = ').all_before('\nfn ').trim_space()
  == reference.all_after('\nconst rejection = ').all_before('\nfn ').trim_space()
 // Keep the retained harness oracle verbatim, including its helper functions.
 for name in ['require', 'expected_intent_output', 'semantic_at'] {
  start := '\nfn ' + name + '('
  assert source.count(start) == 1 && reference.count(start) == 1
  assert source.all_after(start).all_before('\nfn ').trim_space() == reference.all_after(start).all_before('\nfn ').trim_space(), name
 }
}

fn main() {
 $if prod { panic('assertions required') }
 assert os.args.len == 2 && os.getwd() == repo && os.real_path(root) == root
 if os.args[1] == '--source-check' {
  semantic_source()!
  println('INTENT371-ART-ORACLE-SOURCE-PASS')
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
  'stdout_sha256': json2.Any(hash(output + '/stdout.log')!), 'frozen_closure_inputs': json2.Any(closure_count),
  'fresh_runner_frozen_closure_inputs': json2.Any(270),
  'historical_control_scope': json2.Any('Pinned complete 52112-file historical snapshot; full original file presence required; every selected retained control byte rehashed at origin and in the canonical371 bundle.'),
  'original_historical_inventory_sha256': json2.Any(original_inventory)
 }, prettify: true) + '\n')!
 assert r.exit_code == 0, r.output
 assert hash(root + '/sha256.json')! == manifest_pin && hash(checker)! == checker_pin
 assert hash(@FILE)! == reader_source && hash(output + '/reader.v')! == reader_source
 assert hash(os.executable())! == reader_binary && hash(output + '/reader')! == reader_binary
 receipt := object(output + '/complete-receipt.json')!
 assert receipt['exit_code']!.int() == 0 && receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
 assert receipt['manifest_sha256']!.str() == manifest_pin && receipt['files_checked']!.int() == manifest.len
 assert receipt['root']!.str() == root && receipt['checker_sha256']!.str() == checker_pin
 assert receipt['argv']!.as_array().map(it.str()) == argv
 assert receipt['started_utc']!.str() >= started && receipt['started_utc']!.str() <= receipt['completed_utc']!.str()
 println('INTENT371-ART-PEER-PASS closure_inputs=' + closure_count.str() + ' ' + r.output.trim_space())
}
