// SPDX-License-Identifier: GPL-2.0-or-later
// Remove only exact Maps360 working copies; retain the complete canonical bundle.
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
const canonical = '/Users/alex/.local/state/vinix/android/maps360-2026-10-25'
const manifest_pin = '591cdedd2514425b7f53e565d1550d3d261a66aeef92792eda3028d44b2b7068'
const sidecar = '/Users/alex/.local/state/vinix/android/maps360-working-cleanup-2026-10-26'
const source = repo + '/tests/native-android-ws/maps360-working-cleanup.v'

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
			.directory {
				entries[key] = 'directory'
				inventory(root, key, mut entries)!
			}
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			else { return error('unexpected artifact: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn tree(root string) !map[string]string {
	assert os.is_dir(root) && !os.is_link(root), 'ordinary directory required: ' + root
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	return entries
}

fn equal(actual map[string]string, expected map[string]string) ! {
	if actual.len != expected.len {
		mut differences := []string{}
		for key, value in actual {
			if key !in expected || expected[key] != value { differences << key }
		}
		for key in expected.keys() { if key !in actual { differences << 'missing:' + key } }
		return error('typed entry count differs actual=' + actual.len.str() + ' expected=' + expected.len.str() + ' differences=' + differences.str())
	}
	for key, value in expected {
		if key !in actual || actual[key] != value { return error('typed entry differs: ' + key) }
	}
}

fn selected(all map[string]string, prefix string) map[string]string {
	mut entries := map[string]string{}
	for key, value in all {
		if key.starts_with(prefix + '/') {
			entries[key.all_after(prefix + '/')] = value
		} else if key.starts_with('@mode:' + prefix + '/') {
			entries['@mode:' + key.all_after('@mode:' + prefix + '/')] = value
		}
	}
	assert entries.len > 0, 'nonempty authenticated subtree required'
	return entries
}

fn supplemental() map[string]string {
	// The failed details capture finished after the canonical results snapshot.
	return {
		'google-maps/interaction.log': '97d1faf02edcae4a00c57c05280ed64d4664dd7d9bb99ef841d32a92a842a590'
		'google-maps/command-64536-1792973814794433000-44333.stdout.log': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'google-maps/command-64536-1792973814794433000-44333.stderr.log': '7833838098dff21a62433384c486ade9ca1da78ee9f7995fa051640e4a6db5e4'
	}
}

fn qualify(all map[string]string) !map[string]json2.Any {
	mut maps := selected(all, 'prelaunch/maps360')
	for key in maps.keys() {
		if key == 'vm' || key == '@mode:vm' || key.starts_with('vm/') || key.starts_with('@mode:vm/') {
			maps.delete(key)
		}
	}
	maps['vm'] = all['postrun-vm']!
	maps['@mode:vm'] = all['@mode:postrun-vm']!
	for key, value in selected(all, 'postrun-vm') {
		mapped := if key.starts_with('@mode:') { '@mode:vm/' + key.all_after('@mode:') } else { 'vm/' + key }
		maps[mapped] = value
	}
	mut counts := map[string]json2.Any{}
	for relative, wanted in {
		'maps360': maps
		'attempt360': selected(all, 'results/attempt360')
	} {
		mut expected := wanted.clone()
		if relative == 'attempt360' {
			for key, pin in supplemental() {
				expected[key] = pin
				expected['@mode:' + key] = '420'
			}
		}
		path := repo + '/build/android-maps/' + relative
		assert os.real_path(path) == path, 'linked working path refused'
		equal(tree(path)!, expected) or { return error(path + ': ' + err.msg()) }
		sealed := if relative == 'maps360' { 'prelaunch/maps360' } else { 'results/attempt360' }
		assert (os.lstat(path)!.mode & 0o7777).str() == all['@mode:' + sealed]!, 'working root mode differs'
		counts[path] = expected.len
	}
	return counts
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
	equal({'file': 'abc', '@mode:file': '420'}, {'file': 'abc', '@mode:file': '420'})!
	for changed in [
		{'file': 'different', '@mode:file': '420'},
		{'file': 'abc', '@mode:file': '493'},
		{'file': 'symlink:abc', '@mode:file': '420'},
		{'@mode:file': '420'},
		{'file': 'abc', '@mode:file': '420', 'extra': 'abc'},
	] {
		mut rejected := false
		equal(changed, {'file': 'abc', '@mode:file': '420'}) or { rejected = true }
		assert rejected, 'changed hash, type, mode or file set must be rejected'
	}
	println('MAPS360-CLEANUP-GUARD-PASS')
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2
	if os.args[1] == '--self-test' { guard_test()!; return }
	assert os.args[1] in ['check', 'remove-authenticated-working-copies']
	assert os.getwd() == repo && os.real_path(canonical) == canonical
	started := time.utc().str()
	before := disk()!
	assert hash(canonical + '/sha256.json')! == manifest_pin, 'canonical manifest pin differs'
	all := json2.decode[map[string]string](os.read_file(canonical + '/sha256.json')!)!
	mut actual := tree(canonical)!
	actual.delete('sha256.json')
	actual.delete('@mode:sha256.json')
	equal(actual, all)!
	assert all.len == 84812, 'complete canonical inventory required'
	counts := qualify(all)!
	assert hash(canonical + '/sha256.json')! == manifest_pin
	if os.args[1] == 'check' {
		println('MAPS360-CLEANUP-CHECK-PASS canonical_entries=' + all.len.str() + ' working=' + json2.encode(counts))
		return
	}
	assert !os.exists(sidecar) && !os.is_link(sidecar), 'fresh cleanup sidecar required'
	source_pin := hash(source)!
	binary_pin := hash(os.executable())!
	os.mkdir_all(sidecar + '/consumed-tooling')!
	for input in [source, os.executable()] {
		output := sidecar + '/consumed-tooling/' + os.base(input)
		os.cp(input, output)!
		assert hash(output)! == hash(input)!
	}
	os.mkdir_all(sidecar + '/late-attempt360/google-maps')!
	for key, pin in supplemental() {
		output := sidecar + '/late-attempt360/' + key
		os.cp(repo + '/build/android-maps/attempt360/' + key, output)!
		assert hash(output)! == pin && (os.lstat(output)!.mode & 0o7777) == 0o644
	}
	late := tree(sidecar + '/late-attempt360')!
	os.write_file(sidecar + '/late-attempt360-sha256.json', json2.encode(late, prettify: true) + '\n')!
	equal(tree(sidecar + '/late-attempt360')!, late)!
	mut late_pins := map[string]json2.Any{}
	for key, pin in supplemental() { late_pins[key] = pin }
	mut receipt := {
		'started_utc': json2.Any(started)
		'canonical_root': json2.Any(canonical)
		'canonical_manifest_sha256': json2.Any(manifest_pin)
		'canonical_typed_entries': json2.Any(all.len)
		'qualified_working_typed_entries': json2.Any(counts)
		'source_sha256': json2.Any(source_pin)
		'binary_sha256': json2.Any(binary_pin)
		'preserved_late_files': json2.Any(late_pins)
		'late_typed_manifest_sha256': json2.Any(hash(sidecar + '/late-attempt360-sha256.json')!)
		'df_before': json2.Any(before)
	}
	write_json(sidecar + '/qualified-before-removal.json', receipt)!
	// Recheck both working trees after preserving the consumed tool and receipt.
	rechecked := qualify(all)!
	assert rechecked.len == counts.len
	for path, count in counts { assert rechecked[path]!.str() == count.str() }
	assert hash(canonical + '/sha256.json')! == manifest_pin
	for relative in ['maps360', 'attempt360'] {
		path := repo + '/build/android-maps/' + relative
		assert os.real_path(path) == path && os.is_dir(path) && !os.is_link(path)
		os.rmdir_all(path)!
		assert !os.exists(path) && !os.is_link(path)
	}
	assert hash(canonical + '/sha256.json')! == manifest_pin
	assert hash(source)! == source_pin && hash(os.executable())! == binary_pin
	receipt['completed_utc'] = time.utc().str()
	receipt['df_after'] = disk()!
	receipt['removed_working_copies'] = true
	receipt['canonical_manifest_unchanged'] = true
	write_json(sidecar + '/receipt.json', receipt)!
	sealed := tree(sidecar)!
	os.write_file(sidecar + '/sha256.json', json2.encode(sealed, prettify: true) + '\n')!
	mut readback := tree(sidecar)!
	readback.delete('sha256.json')
	readback.delete('@mode:sha256.json')
	equal(readback, sealed)!
	println('MAPS360-WORKING-CLEANUP-PASS receipt=' + sidecar + '/receipt.json manifest=' + hash(sidecar + '/sha256.json')!)
}
