// SPDX-License-Identifier: GPL-2.0-or-later
// Independent exact Intent369 source, DEX and complete-bundle readback.
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

const root = '/Users/alex/.local/state/vinix/android/intent-uri369-framework-build-2026-10-26'
const prefix = '/Users/alex/.local/state/vinix/android/intent-uri369-framework-peer-readback-2026-10-26'
const bootstrap = '/Users/alex/.local/state/vinix/android/intent-uri369-framework-builder-build-2026-10-26'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const baseline_manifest = '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
const baseline_jar = 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const changed = ['android/content/Intent.smali']

fn hash(path string) !string {
 assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular, path
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
 assert old.len == 2076 && new.len == 2076
 for name in changed { assert name in old && name in new && old[name]!.str() != new[name]!.str(), name }
 for name, pin in old { assert name in new && (name in changed || pin.str() == new[name]!.str()), name }
}
fn run(manifest string, jar string, validation_pin string, provider_commit string, provider_pin string, builder_pin string, bootstrap_pin string) ! {
 $if prod { panic('assertions required') }
 assert !os.exists(prefix + '.json') && !os.exists(prefix + '-command.json') && !os.exists(prefix + '-inspection.json')
 for pin in [manifest, jar, validation_pin, provider_pin, builder_pin, bootstrap_pin] { assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes()) }
 assert provider_commit.len == 40 && provider_commit.bytes().all(it in '0123456789abcdef'.bytes())
 checked := root + '/tools/build-bundle-check290'
 manifest_before := hash(root + '/sha256.json')!
 assert hash(checked)! == checker_pin && manifest_before == manifest
 assert hash(root + '/validation.json')! == validation_pin
 assert hash(root + '/framework/api-impl.jar')! == jar
 assert hash(root + '/framework-old.jar')! == baseline_jar
 assert hash(root + '/baseline367/sha256.json')! == baseline_manifest
 assert hash(root + '/baseline367/framework/api-impl.jar')! == baseline_jar
 assert hash(root + '/baseline367/baseline365/sha256.json')! == 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
 assert hash(root + '/baseline367/baseline365/baseline361/sha256.json')! == '9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9'
 assert hash(root + '/baseline367/baseline365/baseline361/baseline359/sha256.json')! == '7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc'
 assert hash(root + '/baseline367/baseline365/baseline361/baseline359/baseline353/sha256.json')! == '22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f'
 validation := object(root + '/validation.json')!
 assert validation['builder_sha256']!.str() == builder_pin
 assert validation['provider_sha256']!.str() == provider_pin
 assert validation['baseline_manifest_sha256']!.str() == baseline_manifest
 assert validation['new_framework_sha256']!.str() == jar
 assert validation['old_framework_sha256']!.str() == baseline_jar
 assert validation['changed_classes']!.as_array().map(it.str()) == changed
 assert validation['added_classes']!.as_array().len == 0
 assert validation['old_class_count']!.str() == '2076' && validation['new_class_count']!.str() == '2076'
 assert hash(root + '/frozen/vroot/source/intent-uri-framework-build.v')! == builder_pin
 assert hash(root + '/frozen/vroot/source/intent369-driver/androidtools/framework_intent_uri.v')! == provider_pin
 assert hash(root + '/tools/bootstrap')! == bootstrap_pin
 assert hash(bootstrap + '/intent-uri-framework-build')! == bootstrap_pin
 assert hash(bootstrap + '/frozen/vroot/v')! == compiler_pin
 bootstrap_manifest := 'f8efd6af2c765d356b33f0869990eb7531ba486162bf97433520f8e57d34e31f'
 assert hash(bootstrap + '/sha256.json')! == bootstrap_manifest
 build := object(bootstrap + '/build.json')!
 assert build['source_sha256']!.str() == builder_pin && build['binary_sha256']!.str() == bootstrap_pin
 assert object(root + '/source/bootstrap-build.json')! == build
 revisions := object(root + '/source/revisions.json')!
 assert revisions['builder_commit']!.str() == build['source_commit']!.str()
 assert revisions['bootstrap_manifest']!.str() == bootstrap_manifest && revisions['bootstrap_root']!.str() == bootstrap
 provider := object(root + '/source/provider-inputs.json')!
 assert provider['provider_commit']!.str() == provider_commit
 assert provider['provider_sha256']!.str() == provider_pin
 assert hash(root + '/commands/provider-committed-source.log')! == provider_pin
 qualified := root + '/baseline367/baseline365/baseline361/baseline359/baseline353/frozen/vroot/source/androidtools/framework.v'
 assert hash(qualified)! == provider['qualified_framework_sha256']!.str()
 marker := 'pub fn framework_replace_method('
 helper := 'module androidtools\n\n' + marker + os.read_file(qualified)!.all_after(marker).all_before('\n// Missing packages') + '\n'
 helper_path := root + '/frozen/vroot/source/intent369-driver/androidtools/framework_method.v'
 assert os.read_file(helper_path)! == helper && hash(helper_path)! == provider['qualified_helper_sha256']!.str()
 mut isolated := map[string]string{}
 inventory(root + '/frozen/vroot/source/intent369-driver/androidtools', '', mut isolated)!
 assert isolated == {'framework_intent_uri.v': provider_pin, 'framework_method.v': provider['qualified_helper_sha256']!.str()}
 smali := object(root + '/framework/smali-delta.json')!
 delta(smali['before']!.as_map(), smali['after']!.as_map())!
 inventory_map(root + '/baseline367/framework/smali', smali['before']!.as_map())!
 inventory_map(root + '/framework/smali', smali['after']!.as_map())!
 assert smali['changed']!.as_array().map(it.str()) == changed
 assert smali['added']!.as_array().len == 0 && smali['removed']!.as_array().len == 0
 assert smali['duplicate_guard_unchanged']!.bool() && smali['malformed_guard_unchanged']!.bool()
 malformed := object(root + '/framework/malformed-guard.json')!
 assert malformed['before']!.as_map() == malformed['after']!.as_map() && malformed['before']!.as_map().len == 2076
 assert malformed['guard_kind']!.str() == 'malformed-required-class-declaration'
 inventory_map(root + '/guard-malformed', malformed['after']!.as_map())!
 dex := object(root + '/framework/dex-delta.json')!
 delta(dex['old_classes']!.as_map(), dex['new_classes']!.as_map())!
 inventory_map(root + '/framework/old-dex', dex['old_classes']!.as_map())!
 inventory_map(root + '/framework/new-dex', dex['new_classes']!.as_map())!
 assert dex['changed_existing_classes']!.as_array().map(it.str()) == changed
 assert dex['added_classes']!.as_array().len == 0 && dex['removed_classes']!.as_array().len == 0
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
  argv := command['argv']!.as_array().map(it.str())
  assert argv.len > 0
  executable := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
  assert hash(executable)! == command['executable_sha256']!.str(), name
  commands++
 }
 assert commands == 33, commands.str()
 assert !os.read_file(root + '/commands/compile-driver.log')!.contains('/Users/alex/code/')
 for name in ['baseline-original', 'baseline-clone', 'baseline-after'] {
  receipt := object(root + '/qualification/' + name + '.json')!
  assert receipt['exit_code']!.int() == 0 && receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
  assert receipt['manifest_sha256']!.str() == baseline_manifest && receipt['files_checked']!.int() == 41884
 }
 for name, pin in object(root + '/host-tool-inputs.json')! { assert hash(name)! == pin.str() }
 assert !os.exists(prefix + '-reader.v') && !os.exists(prefix + '-reader')
 os.cp(@FILE, prefix + '-reader.v')!
 os.cp(os.executable(), prefix + '-reader')!
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
 os.write_file(prefix + '-inspection.json', json2.encode({'source_and_dex_exact_2076_to_2076': json2.Any(true),
  'exact_only_intent_changed': json2.Any(true), 'jar_only_classes_dex_changed': json2.Any(true),
  'source_and_dex_inventory_match_actual_files': json2.Any(true), 'duplicate_and_malformed_no_mutation': json2.Any(true),
  'all_33_commands_exit_zero': json2.Any(true), 'private_closures_unchanged_and_actual_hashes_match': json2.Any(true),
  'closure_inputs_checked': json2.Any(closure_inputs), 'complete_367_365_361_359_and_353_retained': json2.Any(true),
  'committed_exact_isolated_provider': json2.Any(true), 'all_baseline_receipts_pass': json2.Any(true),
  'qualified_helper_exact': json2.Any(true), 'provider_commit': json2.Any(provider_commit),
  'provider_sha256': json2.Any(provider_pin), 'builder_sha256': json2.Any(builder_pin),
  'bootstrap_manifest_sha256': json2.Any(bootstrap_manifest), 'bootstrap_sha256': json2.Any(bootstrap_pin),
  'validation_sha256': json2.Any(validation_pin), 'manifest_sha256': json2.Any(manifest), 'framework_jar_sha256': json2.Any(jar),
  'audit_source_sha256': json2.Any(hash(@FILE)!), 'audit_binary_sha256': json2.Any(hash(os.executable())!)}, prettify: true) + '\n')!
 println('INTENT369-PEER-QUALIFICATION-PASS commands=' + commands.str() + ' closure_inputs=' + closure_inputs.str() + ' ' + r.output.trim_space())
}
fn main() {
 if os.args.len > 2 && os.args[1] == '--hash' {
  for path in os.args[2..] { println((hash(path) or { eprintln(err); exit(1) }) + ' ' + path) }
  return
 }
 if os.args.len != 8 { eprintln('usage: peer-check MANIFEST JAR VALIDATION PROVIDER_COMMIT PROVIDER_SHA BUILDER_SHA BOOTSTRAP_SHA'); exit(1) }
 run(os.args[1], os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7]) or { eprintln(err); exit(1) }
}
