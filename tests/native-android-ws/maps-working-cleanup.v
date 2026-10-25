// SPDX-License-Identifier: GPL-2.0-or-later
// Remove only completed Maps300/304 working copies authenticated by sealed evidence.
module main

import crypto.sha256
import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

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
			else { return error('unexpected working artifact: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn selected(all map[string]string, prefix string) map[string]string {
	mut result := map[string]string{}
	for key, value in all {
		if key.starts_with(prefix + '/') {
			result[key.all_after(prefix + '/')] = value
		} else if key.starts_with('@mode:' + prefix + '/') {
			result['@mode:' + key.all_after('@mode:' + prefix + '/')] = value
		}
	}
	return result
}

fn qualify(number string, pin string, supplemental map[string]string) !map[string]json2.Any {
	state := '/Users/alex/.local/state/vinix/android/maps' + number + '-2026-10-25'
	assert hash(state + '/sha256.json')! == pin, 'sealed manifest pin differs'
	all := json2.decode[map[string]string](os.read_file(state + '/sha256.json')!)!
	mut expected := selected(all, 'prelaunch/maps' + number)
	for key in expected.keys() {
		if key.starts_with('vm/') || key.starts_with('@mode:vm/') { expected.delete(key) }
	}
	for key, value in selected(all, 'postrun-vm') {
		mapped := if key.starts_with('@mode:') {
			'@mode:vm/' + key.all_after('@mode:')
		} else {
			'vm/' + key
		}
		expected[mapped] = value
	}
	mut counts := map[string]json2.Any{}
	for relative, wanted in {
		'maps' + number:    expected
		'attempt' + number: selected(all, 'results/attempt' + number)
	} {
		mut accepted := wanted.clone()
		if relative == 'attempt300' {
			for key, value in supplemental {
				accepted[key] = value
				accepted['@mode:' + key] = '420'
			}
		}
		path := 'build/android-maps/' + relative
		assert os.is_dir(path) && !os.is_link(path), 'ordinary working directory required'
		mut actual := map[string]string{}
		inventory(path, '', mut actual)!
		for key, value in actual {
			if key !in accepted || accepted[key] != value {
				eprintln('DIFFERENCE ' + path + '/' + key + ' expected=' + (accepted[key] or { '<absent>' }) + ' actual=' + value)
			}
		}
		assert actual.len == accepted.len, 'working typed count differs: ' + path
		for key, value in actual {
			assert accepted[key]! == value, 'working typed content differs: ' + path + '/' + key
		}
		sealed_root := if relative.starts_with('maps') {
			'prelaunch/' + relative
		} else {
			'results/' + relative
		}
		assert (os.lstat(path)!.mode & 0o7777).str() == all['@mode:' + sealed_root]!
		counts[path] = actual.len
	}
	return counts
}

fn disk() !string {
	r := os.exec(['/bin/df', '-k', '/Users/alex/.local/state/vinix/android'])
	assert r.exit_code == 0
	return r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2 && os.args[1] == 'remove-authenticated-working-copies'
	sidecar := '/Users/alex/.local/state/vinix/android/maps300-304-working-cleanup-2026-10-25'
	receipt := sidecar + '/receipt.json'
	assert !os.exists(sidecar) && !os.is_link(sidecar), 'fresh cleanup sidecar required'
	before := disk()!
	// Preserve the exact late failed-capture receipts without changing the seal.
	supplemental := {
		'google-maps/interaction.log':                                    'a690674bbb81804b83fc28980fb523e54c03c242a7bd989110333bf77efefb3b'
		'google-maps/command-26552-1792914652805411000-42208.stdout.log': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'google-maps/command-26552-1792914652805411000-42208.stderr.log': '7833838098dff21a62433384c486ade9ca1da78ee9f7995fa051640e4a6db5e4'
	}
	mut counts := qualify('300', 'a057de6a1985810275ef2947725f3f7f9e0177b7cc09dd740b39f31c2d6fa36a', supplemental)!
	for path, count in qualify('304', '0575e5e50abb3a6d5228e6137bb99c0401c4639a934298e44e9a658f7c1458c2', map[string]string{})! {
		counts[path] = count
	}
	os.mkdir_all(sidecar + '/late-attempt300/google-maps')!
	for key, pin in supplemental {
		os.cp('build/android-maps/attempt300/' + key, sidecar + '/late-attempt300/' + key)!
		assert hash(sidecar + '/late-attempt300/' + key)! == pin
	}
	os.write_file(sidecar + '/supplemental-sha256.json', json2.encode(supplemental, prettify: true) + '\n')!
	mut supplemental_receipt := map[string]json2.Any{}
	for key, pin in supplemental { supplemental_receipt[key] = pin }
	for path in counts.keys() { os.rmdir_all(path)! }
	os.write_file(receipt, json2.encode({
		'completed_utc':         json2.Any(time.utc().str())
		'qualified_and_removed': json2.Any(counts)
		'preserved_late_files':  json2.Any(supplemental_receipt)
		'df_before':             json2.Any(before)
		'df_after':              json2.Any(disk()!)
		'source_sha256':         json2.Any(sha256.sum(os.read_bytes('tests/native-android-ws/maps-working-cleanup.v')!).hex())
		'binary_sha256':         json2.Any(hash(os.executable())!)
	}, prettify: true) + '\n')!
	println('MAPS300-304-WORKING-CLEANUP-PASS receipt=' + receipt)
}
