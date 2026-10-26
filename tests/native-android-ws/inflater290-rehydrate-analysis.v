// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only donor qualification for rehydrating the complete failed290 archive.
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
const bundle_name = 'inflater-trace290-failed-build-2026-10-25'
const cold = state + '/' + bundle_name + '-cold-cleanup-2026-10-26'
const typed_pin = '7178fc2249c9ca0d8feb8bfa2953bed8d236b4e1da5998376ed53eb4d656de55'
const archive_pin = '03e1870821cc12b3722bd79161aee1c9d9ad6fe2955ffd6809ae44fcdef15646'
const donors = {
	'inflater-trace290-build-2026-10-25': '63050cca1e3b6c263e6cdb77774d517437dda869db7caa5bbfb71bbdc7292138'
	'frame-metrics288-build-2026-10-25': 'f52a1338edd143717a718e23cb1e2c7d4e3249a87f080fcfe8af8ff0bea2f27d'
}

fn hash(path string) !string {
	before := os.lstat(path)!
	assert before.get_filetype() == .regular && !os.is_link(path)
	mut input := os.open(path)!
	defer { input.close() }
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	mut buffer := []u8{len: 1024 * 1024}
	mut size := u64(0)
	for {
		n := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		size += u64(n)
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	after := os.lstat(path)!
	assert before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.size == after.size && before.size == size && before.mtime == after.mtime
		&& before.ctime == after.ctime
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) == 1
	return result[..].hex()
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'inflater290-rehydrate-analysis NEW_RECEIPT'
	output := os.args[1]
	assert os.abs_path(output) == output
	assert !os.exists(output) && !os.is_link(output)
	assert !output.starts_with(cold + '/')
	for donor_name, _ in donors { assert !output.starts_with(state + '/' + donor_name + '/') }
	archive := state + '/' + bundle_name + '.tar.gz'
	assert hash(archive)! == archive_pin
	typed_path := cold + '/expanded-typed-sha256.json'
	assert hash(typed_path)! == typed_pin
	expected := json2.decode[map[string]string](os.read_file(typed_path)!)!
	mut candidates := map[string][]string{}
	mut donor_manifest_paths := []string{}
	mut donor_records := map[string]json2.Any{}
	for donor_name, pin in donors {
		donor_records[donor_name] = pin
		root := state + '/' + donor_name
		assert os.real_path(root) == root && !os.is_link(root)
		manifest := root + '/sha256.json'
		assert hash(manifest)! == pin
		donor_manifest_paths << manifest
		entries := json2.decode[map[string]string](os.read_file(manifest)!)!
		for path, digest in entries {
			assert path != '' && !path.starts_with('/') && !path.split('/').any(it in ['', '.', '..'])
			candidates[digest] << root + '/' + path
		}
	}
	// Listing only: no member is extracted or changed by this reader.
	listing := os.exec(['/usr/bin/tar', '-tvzf', archive])
	assert listing.exit_code == 0
	mut sizes := map[string]u64{}
	for line in listing.output.split_into_lines() {
		if !line.starts_with('-') { continue }
		fields := line.fields()
		assert fields.len >= 9 && line.contains(bundle_name + '/')
		path := line.all_after(bundle_name + '/')
		assert path in expected && expected[path].len == 64
		sizes[path] = fields[4].u64()
	}
	mut records := []json2.Any{}
	mut unmatched := []json2.Any{}
	mut validated := map[string]bool{}
	mut regular_count := 0
	mut matched_bytes := u64(0)
	mut unmatched_bytes := u64(0)
	for path, digest in expected {
		if path.starts_with('@') || digest == 'directory' || digest.starts_with('symlink:') { continue }
		assert path in sizes && digest.len == 64
		regular_count++
		mut selected := ''
		for candidate in candidates[digest] {
			if candidate !in validated {
				assert hash(candidate)! == digest
				validated[candidate] = true
			}
			assert os.file_size(candidate) == sizes[path]
			selected = candidate
			break
		}
		item := {
			'path': json2.Any(path)
			'sha256': json2.Any(digest)
			'bytes': json2.Any(sizes[path])
			'mode': json2.Any(expected['@mode:' + path])
			'validated_donor': json2.Any(selected)
		}
		records << json2.Any(item)
		if selected == '' {
			unmatched << json2.Any(item)
			unmatched_bytes += sizes[path]
		} else {
			matched_bytes += sizes[path]
		}
	}
	assert sizes.len == regular_count
	assert hash(archive)! == archive_pin && hash(typed_path)! == typed_pin
	for manifest in donor_manifest_paths { assert hash(manifest)! == donors[os.base(os.dir(manifest))] }
	result := {
		'completed_utc': json2.Any(time.utc().str())
		'archive': json2.Any(archive)
		'archive_sha256': json2.Any(archive_pin)
		'expected_typed_manifest_sha256': json2.Any(typed_pin)
		'donor_manifests': json2.Any(donor_records)
		'regular_files': json2.Any(regular_count)
		'matched_files': json2.Any(regular_count - unmatched.len)
		'matched_logical_bytes': json2.Any(matched_bytes)
		'unmatched_files': json2.Any(unmatched.len)
		'unmatched_logical_bytes': json2.Any(unmatched_bytes)
		'records': json2.Any(records)
		'unmatched': json2.Any(unmatched)
		'source_sha256': json2.Any(hash(repo + '/tests/native-android-ws/inflater290-rehydrate-analysis.v')!)
		'binary_sha256': json2.Any(hash(os.executable())!)
		'qualification': json2.Any('Read-only content matches. No clone, restore, archive replacement or deletion was performed. Rehydration requires full typed and unchanged original checker qualification before changing archive retention.')
	}
	os.write_file(output, json2.encode(result, prettify: true) + '\n')!
	println('INFLATER290-REHYDRATE-ANALYSIS regular=' + regular_count.str() + ' matched=' + (regular_count - unmatched.len).str() + ' matched_bytes=' + matched_bytes.str() + ' unmatched=' + unmatched.len.str() + ' unmatched_bytes=' + unmatched_bytes.str())
	for item in unmatched { println(json2.encode(item)) }
}
