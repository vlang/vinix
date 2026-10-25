// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the failed337 preparation and record fresh generator rebuild audits.
module main

import crypto.sha256
import json2
import os
import time

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const root = state + 'maps337-failed-preservation-2026-10-25'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const failed_receipt_pin = '0a64a5e6a2cbfc04fd2af383e334ff3d0be506ed9d5558330f35fdd306f6c7e9'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	$if macos {
		mut digest := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &digest }) == 1
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) == 1
		return result[..].hex()
	} $else {
		mut digest := sha256.new()
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			digest.write(buffer[..n])!
		}
		return digest.sum([]u8{}).hex()
	}
}
fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}
fn inventory(path string, relative string, mut typed map[string]string) ! {
	for name in os.ls(path + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		file := path + '/' + key
		match os.lstat(file)!.get_filetype() {
			.regular { typed[key] = hash(file)! }
			.directory { typed[key] = 'directory'; inventory(path, key, mut typed)! }
			.symbolic_link { typed[key] = 'symlink:' + os.readlink(file)! }
			else { return error('unsupported artifact: ' + file) }
		}
		typed['@mode:' + key] = (os.lstat(file)!.mode & 0o7777).str()
	}
}
fn tree(path string) !map[string]string {
	mut result := map[string]string{}
	inventory(path, '', mut result)!
	return result
}
fn equal(actual map[string]string, expected map[string]string) ! {
	assert actual.len == expected.len, 'complete typed entry count differs'
	for key, value in expected { assert actual[key] or { '' } == value, key }
}
fn fresh(path string) ! {
	assert !os.exists(path) && !os.is_link(path), 'fresh destination required: ' + path
	os.mkdir_all(path)!
}
fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to)
	os.mkdir_all(os.dir(to))!
	result := os.exec(['/bin/cp', '-c', '-R', '-P', from, to])
	assert result.exit_code == 0, result.output
}
fn flat_seal(path string) !string {
	entries := tree(path)!
	mut regular := map[string]string{}
	for key, value in entries {
		if key.starts_with('@mode:') || value == 'directory' { continue }
		assert !value.starts_with('symlink:'), 'flat checker requires regular files: ' + key
		regular[key] = value
	}
	assert 'sha256.json' !in regular
	write_json(path + '/sha256.json', regular)!
	return hash(path + '/sha256.json')!
}
fn audit(unit string, pin string, label string) ! {
	path := state + label + '-audited-build-2026-10-25'
	fresh(path)!
	assert hash(unit)! == pin && hash(compiler)! == compiler_pin
	clone(unit, path + '/source.v')!
	clone(compiler, path + '/v_old276')!
	clone(@FILE, path + '/audit-tool.v')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.mkdir(path + '/generated-c')!
	os.setenv('VTMP', path + '/generated-c', true)
	list_argv := [compiler, '-print-v-files', unit]
	started := time.utc().str()
	listing := os.exec(list_argv)
	os.write_file(path + '/closure-v-files.txt', listing.output)!
	write_json(path + '/closure-receipt.json', {
		'argv': json2.Any(list_argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(listing.exit_code)
		'compiler_sha256': json2.Any(compiler_pin)
	})!
	assert listing.exit_code == 0, listing.output
	mut before := map[string]string{}
	for source in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[source] = hash(source)!
		clone(source, path + '/closure/' + os.abs_path(source).trim_left('/'))!
	}
	assert before.len >= 10
	write_json(path + '/closure-before.json', before)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', path + '/generator', unit]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(pin)
		'closure_before_sha256': json2.Any(hash(path + '/closure-before.json')!)
		'scope': json2.Any('Fresh rebuild after failed337 preparation; does not retroactively attest original bootstrap compilation. Generator is rebuilt but never executed.')
	}
	write_json(path + '/build-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(path + '/build.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	mut after := map[string]string{}
	for source, source_pin in before {
		after[source] = hash(source)!
		assert hash(path + '/closure/' + os.abs_path(source).trim_left('/'))! == source_pin
	}
	equal(after, before)!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin && hash(unit)! == pin
	write_json(path + '/closure-after.json', after)!
	receipt['closure_after_sha256'] = hash(path + '/closure-after.json')!
	if result.exit_code == 0 { receipt['binary_sha256'] = hash(path + '/generator')! }
	write_json(path + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	println('MAPS337-GENERATOR-AUDIT path=' + path + ' seal=' + flat_seal(path)!)
}
fn preserve() ! {
	assert hash(state + 'maps337-preparation-receipt-2026-10-25/sha256.json')! == failed_receipt_pin
	fresh(root)!
	clone(@FILE, root + '/preserve.v')!
	clone(os.executable(), root + '/preserve')!
	mut origins := map[string]string{}
	for label, from in {
		'canonical': state + 'maps337-2026-10-25'
		'prepared-runtime': repo + '/build/android-maps/maps337'
		'preparation-receipt': state + 'maps337-preparation-receipt-2026-10-25'
		'generation': state + 'maps337-generation-2026-10-25'
		'runner-build': state + 'maps337-run-build-c-2026-10-25'
		'receipt-build': state + 'maps337-receipt-build-2026-10-25'
		'generator-bootstrap-build': state + 'maps337-generator-build-2026-10-25'
		'receipt-generator-bootstrap-build': state + 'maps337-receipt-generator-build-2026-10-25'
		'generator-audited-build': state + 'maps337-generator-audited-build-2026-10-25'
		'receipt-generator-audited-build': state + 'maps337-receipt-generator-audited-build-2026-10-25'
	} {
		expected := tree(from)!
		clone(from, root + '/copies/' + label)!
		equal(tree(root + '/copies/' + label)!, expected)!
		write_json(root + '/' + label + '-typed.json', expected)!
		origins[label] = from
		println('MAPS337-PRESERVED label=' + label + ' typed-entries=' + expected.len.str())
	}
	write_json(root + '/origins.json', origins)!
	write_json(root + '/scope.json', {
		'created_utc': json2.Any(time.utc().str())
		'failed_preparation_receipt_sha256': json2.Any(failed_receipt_pin)
		'failure': json2.Any('Missing relative baseline335 config path; no guest was launched.')
		'original_paths_modified': json2.Any(false)
		'typed_copy_readback_complete': json2.Any(true)
	})!
	println('MAPS337-FAILED-PRESERVATION seal=' + flat_seal(root)!)
}
fn verify(pin string, receipt string) ! {
	assert !os.exists(receipt) && !os.is_link(receipt) && !receipt.starts_with(root + '/')
	assert hash(root + '/sha256.json')! == pin
	origins := json2.decode[map[string]string](os.read_file(root + '/origins.json')!)!
	mut checked := 0
	for label, _ in origins {
		expected := json2.decode[map[string]string](os.read_file(root + '/' + label + '-typed.json')!)!
		equal(tree(root + '/copies/' + label)!, expected)!
		checked += expected.len
	}
	assert hash(root + '/sha256.json')! == pin
	write_json(receipt, {
		'root': json2.Any(root)
		'manifest_sha256': json2.Any(pin)
		'complete_origin_typed_maps_checked': json2.Any(origins.len)
		'complete_typed_entries_checked': json2.Any(checked)
		'copied_modes_types_links_and_bytes_match': json2.Any(true)
		'checker_sha256': json2.Any(hash(os.executable())!)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(0)
	})!
	println('MAPS337-FAILED-TYPED-READBACK-PASS entries=' + checked.str())
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo && os.args.len in [2, 4]
	match os.args[1] {
		'audit' {
			audit(repo + '/tests/native-android-ws/maps337-generate.v', 'a00fa8bc380ba3e584ab1acfd253cd1eb08858e15a88926571378e2c59aa16d5', 'maps337-generator')!
			audit(repo + '/tests/native-android-ws/maps337-receipt-generate.v', '1c97c52db1985b91fbd8ab743f2828b09e76f6fd68dd14e341d813e6838bbe2f', 'maps337-receipt-generator')!
		}
		'audit339' {
			audit(repo + '/tests/native-android-ws/maps339-generate.v', '4fc001029001470d81f903e30a7f310c2056cd10a27d25b8bdd99b18b3f8d265', 'maps339-generator')!
			audit(repo + '/tests/native-android-ws/maps339-receipt-generate.v', '6e891024763f63474e8581df51056ca41c10dd468f45e9c8860f950a922e446e', 'maps339-receipt-generator')!
			audit(repo + '/tests/native-android-ws/maps339-recover.v', '4d32ca78b648748b92ee0e203ac3fdde7b023a6ae1d17e7978b2386b091fbb22', 'maps339-recovery')!
		}
		'preserve' { preserve()! }
		'verify' { assert os.args.len == 4; verify(os.args[2], os.args[3])! }
		else { panic('usage: maps337-preserve audit|audit339|preserve|verify PIN RECEIPT') }
	}
}
