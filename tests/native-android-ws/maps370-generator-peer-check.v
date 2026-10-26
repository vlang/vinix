// SPDX-License-Identifier: GPL-2.0-or-later
// Independent original auditor and exact retained/live generator build closure.
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

const state = '/Users/alex/.local/state/vinix/android'
const repo = '/Users/alex/code/vinix'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const cc_pin = '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'

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

fn object(path string) !map[string]json2.Any {
 return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn inventory(path string, name string, mut pins map[string]string) ! {
 for entry in os.ls(path + '/' + name)! {
  key := if name == '' { entry } else { name + '/' + entry }
  match os.lstat(path + '/' + key)!.get_filetype() {
   .directory { inventory(path, key, mut pins)! }
   .regular { pins[key] = hash(path + '/' + key)! }
   else { return error('nonregular retained closure entry: ' + key) }
  }
 }
}

fn complete(root string, manifest string, label string) ! {
 prefix := state + '/' + label + '-peer-readback-2026-10-26'
 assert !os.exists(prefix + '.json') && !os.exists(prefix + '-command.json')
 before := hash(root + '/sha256.json')!
 assert before == manifest && hash(checker)! == checker_pin
 argv := [checker, root, manifest, prefix + '.json']
 started := time.utc().str()
 result := os.exec(argv)
 os.write_file(prefix + '.log', result.output)!
 after := hash(root + '/sha256.json')!
 os.write_file(prefix + '-command.json', json2.encode({
  'argv': json2.Any(argv)
  'started_utc': json2.Any(started)
  'completed_utc': json2.Any(time.utc().str())
  'exit_code': json2.Any(result.exit_code)
  'checker_sha256': json2.Any(checker_pin)
  'manifest_before': json2.Any(before)
  'manifest_after': json2.Any(after)
  'stdout_stderr_sha256': json2.Any(hash(prefix + '.log')!)
 }, prettify: true) + '\n')!
 assert result.exit_code == 0 && before == after && hash(checker)! == checker_pin, result.output
 receipt := object(prefix + '.json')!
 assert receipt['exit_code']!.int() == 0
 assert receipt['exact_file_set']!.bool() && receipt['every_file_hash_matches']!.bool()
 assert receipt['manifest_sha256']!.str() == manifest
 assert receipt['files_checked']!.int() == object(root + '/sha256.json')!.len
 println(label + ': complete290 actual exit 0, ' + receipt['files_checked']!.str() + ' files, receipt ' + hash(prefix + '.json')!)
}

fn audit(root string) ! {
 source := repo + '/tests/native-android-ws/maps370-generate.v'
 source_pin := 'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633'
 binary := repo + '/build/android-maps/maps370-generate-recorded'
 binary_pin := '07563db30ab619e6b3b6440ba454fb27db6e2b559331eef343d316618c42807a'
 reference := '324ff8ef4cfd10d777c5c79df32a6b1b374ef9f18cc2bc3b2d92ad11d13b209a'
 assert hash(source)! == source_pin && hash(root + '/source.v')! == source_pin
 assert hash(binary)! == binary_pin && hash(root + '/program')! == binary_pin
 assert hash(compiler)! == compiler_pin && hash(root + '/v_old276')! == compiler_pin
 assert hash('/usr/bin/cc')! == cc_pin
 assert hash(root + '/prior-generator-reference.v')! == reference
 assert hash(repo + '/tests/native-android-ws/maps368-generate.v')! == reference
 before := object(root + '/closure-before.json')!
 assert before == object(root + '/closure-after.json')! && before.len == 272
 listing := os.read_lines(root + '/closure-v-files.txt')!.filter(it.trim_space() != '')
 mut listed := map[string]bool{}
 for path in listing { assert path !in listed; listed[path] = true }
 assert listed.len == before.len
 mut retained := map[string]string{}
 inventory(root + '/closure', '', mut retained)!
 assert retained.len == before.len
 for path, pin in before {
  assert path.starts_with('/') && path in listed
  assert hash(path)! == pin.str() && retained[path.trim_left('/')]! == pin.str(), path
 }
 build := object(root + '/build-receipt.json')!
 for key, value in object(root + '/build-before.json')! { assert build[key]! == value, key }
 assert build['exit_code']!.int() == 0 && build['cwd']!.str() == repo
 assert build['VROOT']!.str() == '/Users/alex/code/v'
 assert build['source_sha256']!.str() == source_pin && build['binary_sha256']!.str() == binary_pin
 assert build['compiler_sha256']!.str() == compiler_pin && build['cc_sha256']!.str() == cc_pin
 assert build['cc_path']!.str() == '/usr/bin/cc' && build['prior_generator_sha256']!.str() == reference
 assert build['closure_before_sha256']!.str() == hash(root + '/closure-before.json')!
 assert build['closure_after_sha256']!.str() == hash(root + '/closure-after.json')!
 assert build['argv']!.as_array().map(it.str()) == ['build/android-maps/queue284-tools/v_old276', '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc', '-cflags', '-O2', '-o', 'build/android-maps/maps370-generate-recorded', source]
 closure := object(root + '/closure-receipt.json')!
 assert closure['exit_code']!.int() == 0 && closure['compiler_sha256']!.str() == compiler_pin
 assert closure['argv']!.as_array().map(it.str()) == ['build/android-maps/queue284-tools/v_old276', '-print-v-files', source]
 test := object(root + '/self-test-receipt.json')!
 assert test['exit_code']!.int() == 0 && test['binary_sha256']!.str() == binary_pin
 assert test['source_sha256']!.str() == source_pin
 assert test['argv']!.as_array().map(it.str()) == ['build/android-maps/maps370-generate-recorded', '--self-test']
 assert test['output_sha256']!.str() == hash(root + '/self-test.log')!
 assert os.read_file(root + '/self-test.log')!.trim_space() == 'MAPS370-GENERATOR-SELF-TEST-PASS'
 assert os.walk_ext(root + '/generated-c', '.c').len > 0
 // Full manifest authenticates bootstrap; its unrecorded initial exit is not inferred.
 output := state + '/maps370-generator-peer-semantics-2026-10-26.json'
 assert !os.exists(output)
 os.write_file(output, json2.encode({
  'exit_code': json2.Any(0), 'root': json2.Any(root),
  'closure_entries': json2.Any(before.len), 'same_before_after': json2.Any(true),
  'exact_live_and_retained_closure': json2.Any(true),
  'compile_exit_code': json2.Any(build['exit_code']!.int()),
  'closure_discovery_exit_code': json2.Any(closure['exit_code']!.int()),
  'selftest_exit_code': json2.Any(test['exit_code']!.int()),
  'source_sha256': json2.Any(source_pin), 'binary_sha256': json2.Any(binary_pin),
  'audit_source_sha256': json2.Any(hash(@FILE)!),
  'audit_binary_sha256': json2.Any(hash(os.executable())!),
  'scope': json2.Any('Original complete290 and exact272 live/retained host build closure. No guest or framework audit; no initial bootstrap exit inferred.')
 }, prettify: true) + '\n')!
}
fn run() ! {
 assert os.args.len == 1 && os.getwd() == repo
 root := state + '/maps370-generator-build-2026-10-26'
 reader_prefix := state + '/maps370-generator-peer-reader-2026-10-26'
 assert !os.exists(reader_prefix + '.v') && !os.exists(reader_prefix)
 reader_source := hash(@FILE)!
 reader_binary := hash(os.executable())!
 os.cp(@FILE, reader_prefix + '.v')!
 os.cp(os.executable(), reader_prefix)!
 complete(root, 'b4a46ea26a62c954470d3617a87cd3bfc593a81b8d4da82d03c4e8eaad78f3a5', 'maps370-generator')!
 audit(root)!
 assert hash(@FILE)! == reader_source && hash(reader_prefix + '.v')! == reader_source
 assert hash(os.executable())! == reader_binary && hash(reader_prefix)! == reader_binary
 println('MAPS370-GENERATOR-PEER-PASS closure=272')
}
fn main() {
 $if prod { panic('assertions required') }
 run() or { eprintln(err); exit(1) }
}
