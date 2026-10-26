module main
import os
import json2
import time
#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const root = '/Users/alex/.local/state/vinix/android/timing-logger367-framework-build-2026-10-26'
const prefix = '/Users/alex/.local/state/vinix/android/timing-logger367-framework-peer-readback-2026-10-26'
const baseline_manifest = 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
const baseline_jar = 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const provider_pin = '9ad633613ab9108a3df262ffbeb4a372588f68a12bb21cfcf5a061ff34d175ef'
const builder_pin = '779059bdd4c1fb73e9c5300ad738bc7541e02e70adea33c78e6c750bc1d201ea'
const added = ['android/util/TimingLogger.smali']

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
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn inventory(path string, name string, mut pins map[string]string) ! {
 for entry in os.ls(path + '/' + name)! {
  key := if name == '' { entry } else { name + '/' + entry }
  match os.lstat(path + '/' + key)!.get_filetype() {
   .directory { inventory(path, key, mut pins)! }
   .regular { pins[key] = hash(path + '/' + key)! }
   else { return error('nonregular: ' + key) }
  }
 }
}
fn inventory_map(path string, claimed map[string]json2.Any) ! {
 mut actual := map[string]string{}
 inventory(path, '', mut actual)!
 assert actual.len == claimed.len, path
 for name, pin in actual { assert claimed[name]!.str() == pin, path + '/' + name }
}
fn delta(old map[string]json2.Any, new map[string]json2.Any) ! {
 assert old.len == 2075 && new.len == 2076
 for name in added { assert name !in old && name in new, name }
 for name, pin in old { assert name in new && pin.str() == new[name]!.str(), name }
}
fn run(manifest string, jar string, validation_pin string) ! {
 assert !os.exists(prefix + '.json') && !os.exists(prefix + '-command.json') && !os.exists(prefix + '-inspection.json')
 for pin in [manifest, jar, validation_pin] { assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes()) }
 checked := root + '/tools/build-bundle-check290'
 manifest_before := hash(root + '/sha256.json')!
 assert hash(checked)! == checker_pin && manifest_before == manifest
 assert hash(root + '/validation.json')! == validation_pin
 assert hash(root + '/framework/api-impl.jar')! == jar
 assert hash(root + '/framework-old.jar')! == baseline_jar
 assert hash(root + '/baseline365/sha256.json')! == baseline_manifest
 assert hash(root + '/baseline365/framework/api-impl.jar')! == baseline_jar
 assert hash(root + '/baseline365/baseline361/sha256.json')! == '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
 assert hash(root + '/baseline365/baseline361/baseline359/sha256.json')! == '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
 assert hash(root + '/baseline365/baseline361/baseline359/baseline353/sha256.json')! == '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
 validation := object(root + '/validation.json')!
 assert validation['builder_sha256']!.str() == builder_pin
 assert validation['provider_sha256']!.str() == provider_pin
 assert validation['baseline_manifest_sha256']!.str() == baseline_manifest
 assert validation['new_framework_sha256']!.str() == jar
 assert validation['old_framework_sha256']!.str() == baseline_jar
 assert validation['changed_classes']!.as_array().len == 0
 assert validation['added_classes']!.as_array().map(it.str()) == added
 assert validation['old_class_count']!.str() == '2075' && validation['new_class_count']!.str() == '2076'
 assert hash(root + '/frozen/vroot/source/timing-logger-framework-build.v')! == builder_pin
 assert hash(root + '/frozen/vroot/source/timing367-driver/androidtools/framework_timing_logger.v')! == provider_pin
 assert hash(root + '/tools/bootstrap')! == 'f8072f7b3ede3cc6b5dfc41cfe1c10af7d39a68a8760128217e7615cda3e88d7'
 provider := object(root + '/source/provider-inputs.json')!
 assert provider['provider_commit']!.str() == 'dc2aa95c43f544e12ddfd403d746d3c852b1cf2a'
 assert provider['provider_sha256']!.str() == provider_pin
 assert hash(root + '/commands/provider-committed-source.log')! == provider_pin
 mut isolated := map[string]string{}
 inventory(root + '/frozen/vroot/source/timing367-driver/androidtools', '', mut isolated)!
 assert isolated == {'framework_timing_logger.v': provider_pin}
 smali := object(root + '/framework/smali-delta.json')!
 delta(smali['before']!.as_map(), smali['after']!.as_map())!
 inventory_map(root + '/baseline365/framework/smali', smali['before']!.as_map())!
 inventory_map(root + '/framework/smali', smali['after']!.as_map())!
 assert smali['changed']!.as_array().len == 0
 assert smali['added']!.as_array().map(it.str()) == added && smali['removed']!.as_array().len == 0
 assert smali['duplicate_guard_unchanged']!.bool() && smali['malformed_guard_unchanged']!.bool()
 malformed := object(root + '/framework/malformed-guard.json')!
 assert malformed['before']!.as_map() == malformed['after']!.as_map() && malformed['before']!.as_map().len == 2076
 assert malformed['guard_kind']!.str() == 'existing-malformed-destination'
 inventory_map(root + '/guard-malformed', malformed['after']!.as_map())!
 dex := object(root + '/framework/dex-delta.json')!
 delta(dex['old_classes']!.as_map(), dex['new_classes']!.as_map())!
 inventory_map(root + '/framework/old-dex', dex['old_classes']!.as_map())!
 inventory_map(root + '/framework/new-dex', dex['new_classes']!.as_map())!
 assert dex['changed_existing_classes']!.as_array().len == 0
 assert dex['added_classes']!.as_array().map(it.str()) == added && dex['removed_classes']!.as_array().len == 0
 assert dex['new_jar_sha256']!.str() == jar && dex['old_jar_sha256']!.str() == baseline_jar
 assert dex['jar_only_changed_member']!.str() == 'classes.dex'
 mut old_members := map[string]string{}
 mut new_members := map[string]string{}
 inventory(root + '/framework/old-jar', '', mut old_members)!
 inventory(root + '/framework/new-jar', '', mut new_members)!
 assert old_members.len == new_members.len && old_members.len == dex['jar_member_count']!.int()
 for name, pin in old_members {
  assert name in new_members
  assert if name == 'classes.dex' { pin != new_members[name]! } else { pin == new_members[name]! }
 }
 assert new_members['classes.dex']! == hash(root + '/framework/classes.dex')!
 mut closure_inputs := 0
 for kind in ['driver', 'builder'] {
  before := object(root + '/' + kind + '-before-v-files.json')!
  assert before == object(root + '/' + kind + '-after-v-files.json')!
  for path, pin in before { assert os.real_path(path).starts_with(root + '/') && hash(path)! == pin.str(), path }
  closure_inputs += before.len
 }
 mut commands := 0
 for name in os.ls(root + '/commands')!.filter(it.ends_with('.json')) {
  command := object(root + '/commands/' + name)!
  assert command['exit_code']!.int() == 0, name
  assert command['executable_sha256']!.str().len == 64, name
  commands++
 }
 assert commands == 32, commands.str()
 assert !os.read_file(root + '/commands/compile-driver.log')!.contains('/Users/alex/code/')
 for name in ['baseline-original', 'baseline-clone', 'baseline-after'] {
  receipt := object(root + '/qualification/' + name + '.json')!
  assert receipt['exit_code']!.int() == 0 && receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
  assert receipt['manifest_sha256']!.str() == baseline_manifest && receipt['files_checked']!.int() == 32872
 }
 for name, pin in object(root + '/host-tool-inputs.json')! { assert hash(name)! == pin.str() }
 argv := [checked, root, manifest, prefix + '.json']
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(prefix + '.log', r.output)!
 manifest_after := hash(root + '/sha256.json')!
 os.write_file(prefix + '-command.json', json2.encode({'argv': json2.Any(argv),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'exit_code': json2.Any(r.exit_code), 'executable_sha256': json2.Any(checker_pin),
  'manifest_before': json2.Any(manifest_before), 'manifest_after': json2.Any(manifest_after),
  'stdout_stderr_sha256': json2.Any(hash(prefix + '.log')!)}, prettify: true) + '\n')!
 assert r.exit_code == 0 && hash(checked)! == checker_pin && manifest_before == manifest_after, r.output
 receipt := object(prefix + '.json')!
 assert receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
 assert receipt['files_checked']!.int() == object(root + '/sha256.json')!.len
 os.write_file(prefix + '-inspection.json', json2.encode({'source_and_dex_exact_2075_to_2076': json2.Any(true),
  'exact_only_added_timing_logger': json2.Any(true), 'jar_only_classes_dex_changed': json2.Any(true),
  'source_and_dex_inventory_match_actual_files': json2.Any(true), 'duplicate_and_malformed_no_mutation': json2.Any(true),
  'all_32_commands_exit_zero': json2.Any(true), 'private_closures_unchanged_and_actual_hashes_match': json2.Any(true),
  'closure_inputs_checked': json2.Any(closure_inputs), 'complete_365_361_359_and_353_retained': json2.Any(true),
  'committed_exact_isolated_provider': json2.Any(true), 'all_baseline_receipts_pass': json2.Any(true),
  'validation_sha256': json2.Any(validation_pin), 'manifest_sha256': json2.Any(manifest), 'framework_jar_sha256': json2.Any(jar),
  'audit_source_sha256': json2.Any(hash(@FILE)!), 'audit_binary_sha256': json2.Any(hash(os.executable())!)}, prettify: true) + '\n')!
 println('TIMING367-PEER-QUALIFICATION-PASS commands=' + commands.str() + ' closure_inputs=' + closure_inputs.str() + ' ' + r.output.trim_space())
}
fn main() {
 if os.args.len > 2 && os.args[1] == '--hash' {
  for path in os.args[2..] { println((hash(path) or { eprintln(err); exit(1) }) + ' ' + path) }
  return
 }
 if os.args.len != 4 { eprintln('usage: peer-check MANIFEST_SHA JAR_SHA VALIDATION_SHA'); exit(1) }
 run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
