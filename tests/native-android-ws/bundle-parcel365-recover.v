// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve one authenticated interrupted attempt; never fabricate a suite result.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
#include <sys/file.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
fn C.flock(int, int) int

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/bundle-parcel365-fixture-2026-10-26'
const archive = state + '/interrupted-new-01'
const alias = repo + '/build/android-maps/bundle-parcel365-new'
const source = repo + '/tests/native-android-ws/bundle-parcel365-recover.v'
const host_result = '/Users/alex/.local/state/vinix/android/bundle-parcel365-new-interrupted-host-result-2026-10-26.json'
const host_result_pin = '73896628fb8517cab69ed7be125e3893432f55598fa6d3769a4e34cb690aec36'
const host_log = '/Users/alex/.local/state/vinix/android/bundle-parcel365-new-run-2026-10-26.log'
const empty_pin = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
const shared_pin = '37797459ca3c737772306169c2b6411f93f49e1cf8faedfd431c6e81079a7b98'
const apk_pin = 'deafe7867599ccab25c5f286b21227d73a9e21d3903a30b16afc720205b10d9f'
const runner_pin = '8a9bd02103260f35568b95cecc0d9c8397e897402bdbfe46d8d35f7f74f111f6'
const runner_source_pin = 'fa2775bec1140ea0b72d33879d70a688499a1e721b91cd6300fa956fff293b35'
const moves = ['run-new', 'vm-new', 'new-environment.json', 'new-inputs-before.json', 'new.json',
 'commands/disk-new.json', 'commands/disk-new.log']
const stable_dirs = ['framework365', 'native-old', 'native-new', 'fixture-inputs', 'tools',
 'source', 'frozen', 'closure-inputs', 'generated-c', 'apk', 'initial-media']
const stable_files = ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json', 'build-pins.json']

struct Plan {
 schema string
 status string
 created_utc string
 fixture string
 destination string
 alias_path string
 alias_target string
 helper_source_sha256 string
 helper_binary_sha256 string
 host_result_sha256 string
 host_output_sha256 string
 process_snapshot string
 original_entries map[string]string
 unchanged_entries map[string]string
}

fn require(ok bool, message string) ! {
 if !ok { return error(message) }
}

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
fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }
fn map_json(values map[string]string) json2.Any {
 mut out := map[string]json2.Any{}
 for key, value in values { out[key] = value }
 return out
}
fn write_json[T](path string, value T) ! {
 require(!os.exists(path) && !os.is_link(path), 'fresh output required: ' + path)!
 os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn external(path string) ! {
 require(os.is_abs_path(path) && os.real_path(os.dir(path)) == os.dir(path)
  && !path.starts_with(state + '/') && !os.exists(path) && !os.is_link(path), 'fresh external output required')!
}
fn ordinary(path string) ! {
 require(os.is_abs_path(path) && os.real_path(path) == path
  && os.lstat(path)!.get_filetype() == .regular, 'canonical regular file required: ' + path)!
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
 for name in os.ls(root + '/' + relative)! {
  key := if relative == '' { name } else { relative + '/' + name }
  path := root + '/' + key
  info := os.lstat(path)!
  match info.get_filetype() {
   .regular { entries[key] = hash(path)! }
   .directory { entries[key] = 'directory'; inventory(root, key, mut entries)! }
   else { return error('regular evidence required: ' + path) }
  }
  entries['@mode:' + key] = (info.mode & 0o7777).str()
 }
}
fn tree(root string) !map[string]string {
 require(os.is_dir(root) && !os.is_link(root) && os.real_path(root) == root, 'ordinary canonical directory required: ' + root)!
 mut entries := map[string]string{}
 inventory(root, '', mut entries)!
 return entries
}
fn mutable_path(key string) bool {
 path := key.trim_string_left('@mode:')
 return moves.any(path == it || path.starts_with(it + '/'))
}
fn partition(all map[string]string, mutable bool) map[string]string {
 mut out := map[string]string{}
 for key, value in all { if mutable_path(key) == mutable { out[key] = value } }
 return out
}

fn shape(all map[string]string) ! {
 for path in moves {
  require(path in all && '@mode:' + path in all, 'missing interrupted evidence: ' + path)!
  require((all[path] == 'directory') == (path in ['run-new', 'vm-new']), 'wrong evidence type: ' + path)!
 }
 for path in ['sha256.json', 'run-new/results.json', 'new-inputs-after.json', 'new-semantic-check.json',
  'commands/suite-new.json', 'commands/suite-new.log', 'interrupted-new-01'] {
  require(path !in all, 'completed or previously preserved attempt refused: ' + path)!
 }
 for path in all.keys() {
  require(!path.starts_with('qualification/new') && !path.starts_with('@mode:qualification/new'), 'new qualification already exists')!
 }
 for path in ['run-new/companion-packages.json', 'run-new/module', 'run-new/bootstrap-fixture/serial.log',
  'run-new/bootstrap-fixture/network.pcap', 'run-new/bootstrap-fixture/qemu.pid',
  'vm-new/boot.img', 'vm-new/efivars.fd', 'vm-new/boot.img.suite.lock'] {
  require(path in all, 'missing interrupted payload: ' + path)!
 }
}

fn processes() !string {
 r := os.exec(['/bin/ps', '-axo', 'pid=,command='])
 require(r.exit_code == 0, 'cannot inspect live processes')!
 pid_text := os.read_file(state + '/run-new/bootstrap-fixture/qemu.pid')!.trim_space()
 require(pid_text.len > 0 && pid_text.bytes().all(it >= `0` && it <= `9`) && pid_text.int() > 1, 'invalid recorded QEMU PID')!
 for line in r.output.split_into_lines() {
  fields := line.fields()
  if fields.len < 2 { continue }
  pid := fields[0].int()
  if pid == os.getpid() { continue }
  require(pid != pid_text.int(), 'recorded QEMU PID remains live or was reused')!
  require(!line.contains(state) && !line.contains(alias), 'fixture process remains live: ' + line)!
 }
 return r.output
}

fn inspect() !Plan {
 require(os.getwd() == repo, 'repository working directory required')!
 require(os.is_link(alias) && os.readlink(alias)! == state + '/run-new'
  && os.real_path(alias) == state + '/run-new', 'only the exact original new alias is permitted')!
 ordinary(host_result)!
 ordinary(host_log)!
 require(hash(host_result)! == host_result_pin && hash(host_log)! == empty_pin, 'actual host interruption evidence differs')!
 host := object(host_result)!
 require(host['session_id']!.int() == 62200 && host['workdir']!.str() == repo
  && host['shell_command']!.str() == state + '/tools/checked-runner new > ' + host_log + ' 2>&1', 'actual host invocation differs')!
 completion := host['completion']!.as_map()
 require(completion['exit_code']!.int() == 1 && completion['chunk_id']!.str() == '32ad02'
  && completion['output']!.str() == '', 'actual host completion differs')!
 process_snapshot := processes()!
 all := tree(state)!
 shape(all)!
 for path, pin in {
  'shared-inputs.json': shared_pin
  'apk/probe.apk': apk_pin
  'tools/checked-runner': runner_pin
  'source/bundle-parcel365-run.v': runner_source_pin
  'frozen/vroot/bundle-parcel365-run.v': runner_source_pin
  'old-semantic-check.json': 'ed743de38ac77fb56bff8a87e81d9f97706892ef8ebd089288e5755049fcb25b'
  'run-old/results.json': '6817becd0f480cb5f1e847f446b645f946e2bc8e462ffbfc82d9fe4b6361d39f'
  'run-old/bootstrap-fixture/serial.log': 'f245f4f91e4b144d2ce72ded0fa28b758c98921e8acf44c66f69278ca079a483'
  'framework365/sha256.json': 'b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99'
  'native-new/api-impl.jar': 'b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa'
  'native-old/api-impl.jar': '077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a'
 } { require(all[path] == pin, 'pinned fixture input differs: ' + path)! }
 expected := read_map(state + '/shared-inputs.json')!
 mut actual := map[string]string{}
 for key, value in all {
  if !key.starts_with('@mode:') && value != 'directory'
   && (key in stable_files || stable_dirs.any(key.starts_with(it + '/'))) { actual[key] = value }
 }
 require(actual == expected, 'complete immutable shared inventory differs')!
 for path, pin in read_map(state + '/host-inputs.json')! { require(hash(path)! == pin, 'host tool differs: ' + path)! }
 for path in ['old-inputs-before.json', 'old-inputs-after.json', 'new-inputs-before.json'] {
  require(read_map(state + '/' + path)! == expected, 'before/after immutable map differs: ' + path)!
 }
 mut config := object(state + '/config.json')!
 config['output'] = alias
 config['native_dir'] = state + '/native-new'
 config['boot_image'] = state + '/vm-new/boot.img'
 config['efivars'] = state + '/vm-new/efivars.fd'
 require(config == object(state + '/new.json')!, 'interrupted new config differs')!
 log := os.read_file(state + '/run-new/bootstrap-fixture/serial.log')!
 markers := ['BUNDLE-PARCEL-BEGIN', 'BUNDLE-PARCEL-DEFERRED-PASS', 'BUNDLE-PARCEL-COPY-PASS',
  'BUNDLE-PARCEL-ROUNDTRIP-PASS', 'BUNDLE-PARCEL-EMPTY-PASS', 'BUNDLE-PARCEL-PASS']
 lines := log.split_into_lines().map(it.trim_space())
 require(lines.filter(it.starts_with('BUNDLE-PARCEL-')) == markers, 'exact interrupted marker sequence required')!
 require(log.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
  && log.count('ANDROID-WS-MAPS pid=') == 3, 'interrupted native observation differs')!
 for bad in ['ANDROID-WS-FAIL', 'APK-SUITE-EXIT', 'AssertionError', 'ClassNotFoundException', 'VerifyError'] {
  require(!log.contains(bad), 'interrupted guest failure differs: ' + bad)!
 }
 processes()!
 return Plan{'bundle-parcel365-interrupted-recovery-v1', 'INCOMPLETE-ONLY-PRESERVATION-PLAN',
  time.utc().str(), state, archive, alias, state + '/run-new', hash(source)!, hash(os.executable())!,
  host_result_pin, empty_pin, process_snapshot, partition(all, true), partition(all, false)}
}

fn preserve(plan_path string, pin string, receipt string) ! {
 external(receipt)!
 ordinary(plan_path)!
 require(os.is_abs_path(plan_path) && !plan_path.starts_with(state + '/') && hash(plan_path)! == pin, 'authenticated external plan required')!
 plan := json2.decode[Plan](os.read_file(plan_path)!)!
 require(plan.schema == 'bundle-parcel365-interrupted-recovery-v1' && plan.status == 'INCOMPLETE-ONLY-PRESERVATION-PLAN'
  && plan.fixture == state && plan.destination == archive && plan.alias_path == alias && plan.alias_target == state + '/run-new'
  && plan.helper_source_sha256 == hash(source)! && plan.helper_binary_sha256 == hash(os.executable())!
  && plan.host_result_sha256 == host_result_pin && plan.host_output_sha256 == empty_pin, 'recovery plan identity differs')!
 // The original suite uses the same existing lock. Hold it across all renames.
 ordinary(state + '/vm-new/boot.img.suite.lock')!
 mut suite_lock := os.open_file(state + '/vm-new/boot.img.suite.lock', 'r+')!
 defer { suite_lock.close() }
 require(C.flock(suite_lock.fd, 6) == 0, 'suite lock remains held')!
 defer { C.flock(suite_lock.fd, 8) }
 fresh := inspect()!
 require(fresh.original_entries == plan.original_entries && fresh.unchanged_entries == plan.unchanged_entries,
  'fixture changed after preservation plan')!
 require(hash(plan_path)! == pin, 'plan changed during validation')!
 processes()!
 os.mkdir(archive)!
 os.cp(plan_path, archive + '/recovery-plan.json')!
 os.cp(host_result, archive + '/host-invocation-result.json')!
 os.cp(host_log, archive + '/host-invocation-output.log')!
 require(hash(archive + '/recovery-plan.json')! == pin
  && hash(archive + '/host-invocation-result.json')! == host_result_pin
  && hash(archive + '/host-invocation-output.log')! == empty_pin, 'preserved provenance differs')!
 write_json(archive + '/original-paths.json', {'fixture': json2.Any(state),
  'original_alias': json2.Any(alias), 'original_alias_target': json2.Any(state + '/run-new'),
  'moved_paths': json2.Any(moves), 'original_entries': map_json(plan.original_entries),
  'scope': json2.Any('Interrupted host exit1 preserved; absent suite result remains absent. No fixture pass claimed.')})!
 require(os.is_link(alias) && os.readlink(alias)! == state + '/run-new', 'alias changed before removal')!
 os.rm(alias)!
 for path in moves {
  os.mkdir_all(os.dir(archive + '/' + path))!
  require(!os.exists(archive + '/' + path) && !os.is_link(archive + '/' + path), 'fresh preservation target required')!
  os.mv(state + '/' + path, archive + '/' + path)!
 }
 preserved := tree(archive)!
 mut payload := preserved.clone()
 for key in payload.keys() {
  path := key.trim_string_left('@mode:')
  if path in ['recovery-plan.json', 'host-invocation-result.json', 'host-invocation-output.log', 'original-paths.json', 'commands'] {
   payload.delete(key)
  }
 }
 require(payload == plan.original_entries, 'preserved typed payload differs')!
 mut after := tree(state)!
 for key in after.keys() {
  path := key.trim_string_left('@mode:')
  if path == 'interrupted-new-01' || path.starts_with('interrupted-new-01/') { after.delete(key) }
 }
 require(after == plan.unchanged_entries, 'immutable or old evidence changed during preservation')!
 require(!os.exists(alias) && !os.is_link(alias) && hash(state + '/shared-inputs.json')! == shared_pin, 'fresh retry precondition differs')!
 write_json(receipt, {'status': json2.Any('INTERRUPTED-ATTEMPT-PRESERVED'), 'fixture_passed': json2.Any(false),
  'completed_utc': json2.Any(time.utc().str()), 'fixture': json2.Any(state), 'archive': json2.Any(archive),
  'plan': json2.Any(plan_path), 'plan_sha256': json2.Any(pin), 'helper_source_sha256': json2.Any(hash(source)!),
  'helper_binary_sha256': json2.Any(hash(os.executable())!), 'actual_interrupted_host_exit_code': json2.Any(1),
  'host_result_sha256': json2.Any(host_result_pin), 'preserved_entries': map_json(preserved),
  'unchanged_entry_count': json2.Any(after.len), 'retry_command': json2.Any([state + '/tools/checked-runner', 'new']),
  'scope': json2.Any('Only seven authenticated new-attempt paths renamed and the exact new alias removed. Immutable inputs and all old evidence unchanged. Original checked-runner must independently perform and qualify the fresh run.')})!
 println('BUNDLE-PARCEL365-INTERRUPTED-ATTEMPT-PRESERVED')
}

fn self_test() ! {
 mut entries := map[string]string{}
 for path in moves { entries[path] = if path in ['run-new', 'vm-new'] { 'directory' } else { 'hash' }; entries['@mode:' + path] = '420' }
 for path in ['run-new/companion-packages.json', 'run-new/module', 'run-new/bootstrap-fixture/serial.log',
  'run-new/bootstrap-fixture/network.pcap', 'run-new/bootstrap-fixture/qemu.pid',
  'vm-new/boot.img', 'vm-new/efivars.fd', 'vm-new/boot.img.suite.lock'] { entries[path] = 'hash' }
 shape(entries)!
 for completed in ['sha256.json', 'run-new/results.json', 'new-inputs-after.json', 'new-semantic-check.json',
  'commands/suite-new.json', 'commands/suite-new.log', 'qualification/new-semantic-check.json', 'interrupted-new-01'] {
  mut wrong := entries.clone(); wrong[completed] = 'hash'
  mut rejected := false
  shape(wrong) or { rejected = true }
  require(rejected, 'completed attempt accepted: ' + completed)!
 }
 for missing in moves {
  mut wrong := entries.clone(); wrong.delete(missing)
  mut rejected := false
  shape(wrong) or { rejected = true }
  require(rejected, 'missing evidence accepted: ' + missing)!
 }
 require(partition(entries, true).len == entries.len && partition(entries, false).len == 0, 'partition')!
 println('BUNDLE-PARCEL365-RECOVERY-GUARDS-PASS')
}

fn main() {
 $if prod { panic('assertions required') }
 if os.args.len == 2 && os.args[1] == 'self-test' { self_test()!; return }
 if os.args.len == 3 && os.args[1] == 'inspect' {
  external(os.args[2])!
  write_json(os.args[2], inspect()!)!
  println('BUNDLE-PARCEL365-INCOMPLETE-PRESERVATION-PLAN')
  return
 }
 require(os.args.len == 5 && os.args[1] == 'recover', 'usage: self-test | inspect FRESH_EXTERNAL_PLAN | recover PLAN PLAN_SHA FRESH_EXTERNAL_RECEIPT')!
 preserve(os.args[2], os.args[3], os.args[4])!
}
