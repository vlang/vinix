// SPDX-License-Identifier: GPL-2.0-or-later
// Remove only the exact redundant failed Compound258 working copy.
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
const canonical = '/Users/alex/.local/state/vinix/android/compound258-2026-10-24'
const working = repo + '/build/android-maps/compound258'
const manifest_pin = 'a279c5a2ea4dcd8aa83dc133e494647a2ec2fcb48d4c84d4bc3b22ce6de2f7a9'
const auditor_pin = '8c14b80b16da88d0e111b828942748a4b069e0cc9ae35fe8f777e5c5679728c0'
const auditor_source_pin = 'a0ccbe21fdd1deea43286d1c13794430a49c93351edf002aa2718fc2897113d1'
const sidecar = '/Users/alex/.local/state/vinix/android/compound258-working-cleanup-2026-10-26'
const source = repo + '/tests/native-android-ws/compound258-working-cleanup.v'

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) == 1
	return result[..].hex()
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		info := os.lstat(path)!
		match info.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { entries[key] = 'directory'; inventory(root, key, mut entries)! }
			else { return error('unexpected artifact: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn tree(root string) !map[string]string {
	assert root == os.real_path(root) && os.is_dir(root) && !os.is_link(root)
	mut entries := map[string]string{}
	entries['.'] = 'directory'
	entries['@mode:.'] = (os.lstat(root)!.mode & 0o7777).str()
	inventory(root, '', mut entries)!
	return entries
}

fn equal(actual map[string]string, expected map[string]string) ! {
	mut differences := []string{}
	for key, value in actual {
		if key !in expected || expected[key] != value { differences << key }
	}
	for key in expected.keys() { if key !in actual { differences << 'missing:' + key } }
	if differences.len != 0 { return error('typed tree differs: ' + differences.str()) }
}

fn verified_canonical() !map[string]string {
	assert hash(canonical + '/sha256.json')! == manifest_pin
	expected := json2.decode[map[string]string](os.read_file(canonical + '/sha256.json')!)!
	assert expected.len == 6996, 'complete historical inventory required'
	all := tree(canonical)!
	mut plain := map[string]string{}
	for key, value in all {
		if key != '.' && key != 'sha256.json' && !key.starts_with('@mode:') { plain[key] = value }
	}
	equal(plain, expected)!
	assert hash(canonical + '/audit/compound-styled-evidence')! == auditor_pin
	assert hash(canonical + '/audit/compound-styled-evidence.v')! == auditor_source_pin
	assert hash(canonical + '/sha256.json')! == manifest_pin
	return all
}

fn completed(all map[string]string) map[string]string {
	mut entries := {'.': all['completed']!, '@mode:.': all['@mode:completed']!}
	for key, value in all {
		if key.starts_with('completed/') { entries[key.all_after('completed/')] = value }
		else if key.starts_with('@mode:completed/') { entries['@mode:' + key.all_after('@mode:completed/')] = value }
	}
	assert entries.len > 1000
	return entries
}

fn disk() !string {
	r := os.exec(['/bin/df', '-k', canonical])
	assert r.exit_code == 0
	return r.output
}

fn write_json(path string, value map[string]json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn guard_test() ! {
	wanted := {'file': 'abc', '@mode:file': '420'}
	equal(wanted, wanted)!
	for changed in [
		{'file': 'different', '@mode:file': '420'},
		{'file': 'abc', '@mode:file': '493'},
		{'file': 'directory', '@mode:file': '420'},
		{'@mode:file': '420'},
		{'file': 'abc', '@mode:file': '420', 'extra': 'abc'},
	] {
		mut rejected := false
		equal(changed, wanted) or { rejected = true }
		assert rejected, 'changed hash, type, mode or file set must be rejected'
	}
	println('COMPOUND258-CLEANUP-GUARD-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2
	if os.args[1] == '--self-test' { guard_test()!; return }
	assert os.args[1] in ['check', 'remove-authenticated-working-copy']
	assert os.getwd() == repo && os.real_path(canonical) == canonical
	started := time.utc().str()
	before := disk()!
	all := verified_canonical()!
	wanted := completed(all)
	equal(tree(working)!, wanted)!
	if os.args[1] == 'check' {
		println('COMPOUND258-CLEANUP-CHECK-PASS canonical_entries=6996 working_typed_entries=' + wanted.len.str())
		return
	}
	assert !os.exists(sidecar) && !os.is_link(sidecar), 'fresh cleanup evidence required'
	source_pin := hash(source)!
	binary_pin := hash(os.executable())!
	os.mkdir_all(sidecar + '/consumed-tooling')!
	for input, pin in {source: source_pin, os.executable(): binary_pin} {
		output := sidecar + '/consumed-tooling/' + os.base(input)
		os.cp(input, output)!
		assert hash(output)! == pin && hash(input)! == pin
	}
	// The unchanged historical checker must still reject this failed regression.
	argv := [canonical + '/audit/compound-styled-evidence', 'check', canonical, manifest_pin]
	audit := os.exec(argv)
	os.write_file(sidecar + '/historical-check.log', audit.output)!
	assert audit.exit_code != 0 && audit.output.contains('DEFAULTS-PASS')
	assert audit.output.contains('serial.contains') && !audit.output.contains('COMPOUND-STYLED-EVIDENCE PASS')
	write_json(sidecar + '/historical-check.json', {
		'argv': json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': audit.exit_code
		'log_sha256': hash(sidecar + '/historical-check.log')!
		'auditor_sha256': auditor_pin
		'auditor_source_sha256': auditor_source_pin
		'expected_result': json2.Any('strict semantic rejection of retained failed default assertion')
	})!
	equal(tree(working)!, wanted)!
	assert hash(canonical + '/sha256.json')! == manifest_pin
	os.write_file(sidecar + '/working-typed-sha256.json', json2.encode(wanted, prettify: true) + '\n')!
	mut receipt := {
		'started_utc': json2.Any(started)
		'canonical_root': json2.Any(canonical)
		'canonical_manifest_sha256': json2.Any(manifest_pin)
		'canonical_manifest_entries': json2.Any(6996)
		'working_root': json2.Any(working)
		'working_typed_entries': json2.Any(wanted.len)
		'working_typed_manifest_sha256': json2.Any(hash(sidecar + '/working-typed-sha256.json')!)
		'source_sha256': json2.Any(source_pin)
		'binary_sha256': json2.Any(binary_pin)
		'df_before': json2.Any(before)
	}
	write_json(sidecar + '/qualified-before-removal.json', receipt)!
	equal(tree(working)!, wanted)!
	assert hash(source)! == source_pin && hash(os.executable())! == binary_pin
	assert os.real_path(working) == working && os.is_dir(working) && !os.is_link(working)
	os.rmdir_all(working)!
	assert !os.exists(working) && !os.is_link(working)
	equal(verified_canonical()!, all)!
	assert hash(source)! == source_pin && hash(os.executable())! == binary_pin
	receipt['completed_utc'] = time.utc().str()
	receipt['df_after'] = disk()!
	receipt['removed_authenticated_working_copy'] = true
	receipt['complete_canonical_tree_unchanged'] = true
	write_json(sidecar + '/receipt.json', receipt)!
	sealed := tree(sidecar)!
	os.write_file(sidecar + '/sha256.json', json2.encode(sealed, prettify: true) + '\n')!
	mut readback := tree(sidecar)!
	readback.delete('sha256.json')
	readback.delete('@mode:sha256.json')
	equal(readback, sealed)!
	println('COMPOUND258-WORKING-CLEANUP-PASS receipt=' + sidecar + '/receipt.json manifest=' + hash(sidecar + '/sha256.json')!)
}
