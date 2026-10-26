// SPDX-License-Identifier: GPL-2.0-or-later
// Independently qualify the recorded Maps370 comparator and generated runner.
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
const comparator_manifest = '515cf9c83cf9c13c6957904a5bfc5458f452791de8854880fe682c214ecd396a'

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

fn audit(root string, source string, source_pin string, binary string, binary_pin string, retained_binary string, label string, comparator bool) ! {
 started := time.utc().str()
 receipt_path := state + '/' + label + '-peer-audit-2026-10-26.json'
 assert !os.exists(receipt_path)
 assert hash(compiler)! == compiler_pin && hash(root + '/v_old276')! == compiler_pin
 assert hash('/usr/bin/cc')! == cc_pin
 assert hash(source)! == source_pin && hash(root + '/' + if comparator { 'source.v' } else { 'maps370-run.v' })! == source_pin
 assert hash(binary)! == binary_pin && hash(root + '/' + retained_binary)! == binary_pin
 before := object(root + '/closure-before.json')!
 after := object(root + '/closure-after.json')!
 assert before == after
 assert before.len == 272
 listing := os.read_lines(root + '/closure-v-files.txt')!.filter(it.trim_space() != '')
 mut listed := map[string]bool{}
 for name in listing { assert name !in listed; listed[name] = true }
 assert listed.len == before.len
 mut retained := map[string]string{}
 inventory(root + '/closure', '', mut retained)!
 assert retained.len == before.len
 for path, pin in before {
  assert path in listed && path.starts_with('/')
  assert hash(path)! == pin.str(), path
  assert retained[path.trim_left('/')]! == pin.str(), path
 }
 build_before := object(root + '/build-before.json')!
 build := object(root + '/build-receipt.json')!
 closure := object(root + '/closure-receipt.json')!
 assert build['exit_code']!.int() == 0 && closure['exit_code']!.int() == 0
 for key in ['argv', 'VROOT', 'source_sha256', 'compiler_sha256', 'cc_path', 'cc_sha256', 'closure_before_sha256'] {
  assert build_before[key]! == build[key]!, key
 }
 assert build['VROOT']!.str() == '/Users/alex/code/v'
 assert build['source_sha256']!.str() == source_pin && build['binary_sha256']!.str() == binary_pin
 assert build['compiler_sha256']!.str() == compiler_pin && closure['compiler_sha256']!.str() == compiler_pin
 assert build['cc_sha256']!.str() == cc_pin && build['cc_path']!.str() == '/usr/bin/cc'
 assert build['closure_before_sha256']!.str() == hash(root + '/closure-before.json')!
 assert build['closure_after_sha256']!.str() == hash(root + '/closure-after.json')!
 if 'closure_listing_sha256' in build { assert build['closure_listing_sha256']!.str() == hash(root + '/closure-v-files.txt')! }
 argv := build['argv']!.as_array().map(it.str())
 assert os.real_path(argv[0]) == compiler
 for flag in ['-nocache', '-keepc', '-showcc', '-cflags', '-O2'] { assert flag in argv }
 assert argv.last() == source
 output_index := argv.index('-o')
 assert output_index >= 0 && os.real_path(argv[output_index + 1]) == binary
 closure_argv := closure['argv']!.as_array().map(it.str())
 assert closure_argv.len == 3 && os.real_path(closure_argv[0]) == compiler && closure_argv[1] == '-print-v-files' && closure_argv[2] == source
 mut bootstrap_exit := 0
 mut selftest_exit := -1
 if comparator {
  assert hash(root + '/bootstrap')! == 'c269ff3cc6582fd27a86d5d3821e07a573220c07cd46632a83e862fbf35b8802'
  assert build['bootstrap_sha256']!.str() == hash(root + '/bootstrap')!
  test := object(root + '/self-test-receipt.json')!
  selftest_exit = test['exit_code']!.int()
  assert selftest_exit == 0 && test['binary_sha256']!.str() == binary_pin
  assert test['argv']!.as_array().map(it.str()) == [binary, '--self-test']
  assert test['generator_commit']!.str() == 'fb3b07283836c48919e1d8d3e667e56799240a69'
  reference := 'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633'
  assert test['generator_source_sha256']!.str() == reference
  assert hash(root + '/generator-reference.v')! == reference
  assert hash(repo + '/tests/native-android-ws/maps370-generate.v')! == reference
 } else {
  bootstrap := object(root + '/generation/bootstrap-receipt.json')!
  bootstrap_exit = bootstrap['exit_code']!.int()
  assert bootstrap_exit == 0 && bootstrap['binary_sha256']!.str() == binary_pin
  assert bootstrap['source_sha256']!.str() == source_pin && bootstrap['compiler_sha256']!.str() == compiler_pin && bootstrap['cc_sha256']!.str() == cc_pin
  assert hash(root + '/generation/bootstrap')! == binary_pin
  assert hash(state + '/maps370-generation-2026-10-26/bootstrap')! == binary_pin
  assert !os.exists(root + '/sha256.json')
 }
 os.write_file(receipt_path, json2.encode({
  'root': json2.Any(root)
  'started_utc': json2.Any(started)
  'completed_utc': json2.Any(time.utc().str())
  'exit_code': json2.Any(0)
  'recorded_build_exit_code': json2.Any(build['exit_code']!.int())
  'closure_discovery_exit_code': json2.Any(closure['exit_code']!.int())
  'bootstrap_exit_code': json2.Any(if comparator { -1 } else { bootstrap_exit })
  'selftest_exit_code': json2.Any(selftest_exit)
  'retained_bootstrap_hash_matches': json2.Any(true)
  'closure_entries': json2.Any(before.len)
  'same_before_after': json2.Any(true)
  'exact_closure_listing': json2.Any(true)
  'live_and_retained_closure_hashes_match': json2.Any(true)
  'source_sha256': json2.Any(source_pin)
  'binary_sha256': json2.Any(binary_pin)
  'compiler_sha256': json2.Any(compiler_pin)
  'cc_sha256': json2.Any(cc_pin)
  'build_receipt_sha256': json2.Any(hash(root + '/build-receipt.json')!)
  'closure_receipt_sha256': json2.Any(hash(root + '/closure-receipt.json')!)
  'audit_source_sha256': json2.Any(hash(@FILE)!)
  'audit_binary_sha256': json2.Any(hash(os.executable())!)
  'scope': json2.Any('Read-only actual recorded command receipts, source/compiler/CC/binaries, exact272 live+retained closures. Generation and comparator separately complete290 qualified. Runner outer build intentionally has no manifest; no ART/runtime claim. Comparator bootstrap hash is inspected; no bootstrap exit status is inferred.')
 }, prettify: true) + '\n')!
 println(label + ': actual audit exit 0, closure ' + before.len.str() + ', receipt ' + hash(receipt_path)!)
}

fn canonical(pin string) bool {
 return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn run() ! {
 $if prod { panic('requires assertions') }
 assert os.real_path(os.getwd()) == repo
 assert os.args.len >= 2 && os.args[1] in ['--comparator', '--runner'], 'usage: --comparator | --runner GENERATION_MANIFEST_SHA SOURCE_SHA BINARY_SHA'
 mode := os.args[1].trim_left('-')
 assert os.args.len == if mode == 'comparator' { 2 } else { 5 }
 if mode == 'runner' { for pin in os.args[2..] { assert canonical(pin) } }
 retained_reader := state + '/maps370-host-peer-' + mode + '-reader-2026-10-26'
 assert !os.exists(retained_reader) && !os.exists(retained_reader + '.v')
 reader_source_pin := hash(@FILE)!
 reader_binary_pin := hash(os.executable())!
 os.cp(@FILE, retained_reader + '.v')!
 os.cp(os.executable(), retained_reader)!
 if mode == 'comparator' {
  comparator := state + '/maps370-prelaunch-review-build-2026-10-26'
  complete(comparator, comparator_manifest, 'maps370-prelaunch-review-build')!
  audit(comparator, repo + '/tests/native-android-ws/maps370-prelaunch-review.v', '16665b939253625039bca65822d964af49809a3d4b12e290562e5f4979e89a93', comparator + '/program', 'd871020faca0c5b3f88c46de25895924e7958c212457c503064bc61150ca043d', 'program', 'maps370-prelaunch-recorded-build', true)!
 } else {
  generation := state + '/maps370-generation-2026-10-26'
  runner := state + '/maps370-run-build-c-2026-10-26'
  complete(generation, os.args[2], 'maps370-generation')!
  complete(runner + '/generation', os.args[2], 'maps370-retained-generation')!
  derivation := object(generation + '/derivation.json')!
  assert derivation['generated_sha256']!.str() == os.args[3]
  assert derivation['generator_sha256']!.str() == 'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633'
  assert derivation['framework_build_manifest_sha256']!.str() == '9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93'
  assert derivation['framework_sha256']!.str() == '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'
  audit(runner, generation + '/maps370-run.v', os.args[3], repo + '/build/android-maps/maps370-run-recorded', os.args[4], 'maps370-run', 'maps370-recorded-build', false)!
 }
 assert hash(@FILE)! == reader_source_pin && hash(retained_reader + '.v')! == reader_source_pin
 assert hash(os.executable())! == reader_binary_pin && hash(retained_reader)! == reader_binary_pin
 os.write_file(retained_reader + '-receipt.json', json2.encode({
  'argv': json2.Any(os.args)
  'completed_utc': json2.Any(time.utc().str())
  'exit_code': json2.Any(0)
  'reader_source_sha256': json2.Any(reader_source_pin)
  'reader_binary_sha256': json2.Any(reader_binary_pin)
  'scope': json2.Any('Original290 complete bundle readback and exact272 recorded host build closure qualification only; no guest or ART claim.')
 }, prettify: true) + '\n')!
}

fn main() {
 run() or { eprintln(err); exit(1) }
}
