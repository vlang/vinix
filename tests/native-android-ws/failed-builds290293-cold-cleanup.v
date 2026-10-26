// SPDX-License-Identifier: GPL-2.0-or-later
// Archive, restore and audit fixed obsolete build bundles before cold cleanup.
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
const candidates = {
	'inflater-trace290-failed-build-2026-10-25': '58cd4c6b5b52ad20b0df7d5b6b4ea891018b0873f6197c3d519349253b0739ff'
	'bitmap-png293-failed-build-2026-10-25': '5d4e2bcba3406b25ce34a18ca38333bf441aa42f033055516afdf47f7cbed82d'
	'frame-metrics287-build-2026-10-25': '39f63782befd24554ee509501ea0252e27508af694c8792e223b8d041af555ff'
	'frame-metrics288-build-2026-10-25': 'f52a1338edd143717a718e23cb1e2c7d4e3249a87f080fcfe8af8ff0bea2f27d'
	'path-ops296-framework-build-2026-10-25': '00e7253ab04c5e102e8e09f8b12cec308f31af6ccecf82c88349b3562a5154eb'
	'path-ops296b-framework-build-2026-10-25': 'b8d69c2b136873eb75d8891099295cf6b99d56e6144fdae394771d87078442e5'
	'drawable-optical306-framework-build-2026-10-25': '392477ecf7d7b8d3b87fb13940b2e4f8fb3daf4229e05df7790bfbb59ab7f469'
}
const auditor = repo + '/build/android-maps/build-bundle-check290'
const auditor_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'
const auditor_source = repo + '/tests/native-android-ws/build-bundle-check.v'
const auditor_source_pin = 'bcd7728897d10baeb50f13122a1c3ad7282a110dc1506a5b99a9eab2a30a2594'
const reader_pin = '9ab7f0793033dc9dc4809d83d695118801bd687cbacda59a0cbbf151ba25dc2b'
const source = repo + '/tests/native-android-ws/failed-builds290293-cold-cleanup.v'

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
	assert os.is_dir(root) && !os.is_link(root) && os.real_path(root) == root
	mut entries := map[string]string{}
	inventory(root, '', mut entries)!
	entries['@root-mode'] = (os.lstat(root)!.mode & 0o7777).str()
	return entries
}

fn equal(actual map[string]string, expected map[string]string) ! {
	assert actual.len == expected.len, 'typed entry count differs'
	for key, value in expected {
		assert key in actual && actual[key] == value, 'typed entry differs: ' + key
	}
}

fn write_json(path string, value map[string]json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(label string, argv []string, mut commands []json2.Any) !string {
	sidecar := state + '/' + os.args[1] + '-cold-cleanup-2026-10-26'
	started := time.utc().str()
	result := os.exec(argv)
	output := sidecar + '/' + label + '.log'
	os.write_file(output, result.output)!
	commands << json2.Any({
		'label': json2.Any(label)
		'argv': json2.Any(argv)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(result.exit_code)
		'output_sha256': json2.Any(hash(output)!)
	})
	write_json(sidecar + '/commands.json', {'commands': json2.Any(commands)})!
	assert result.exit_code == 0, label + ' failed'
	return result.output
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 3 && os.args[1] in candidates && os.args[2] == 'archive-restore-audit-remove-expanded'
	bundle_name := os.args[1]
	bundle_pin := candidates[bundle_name]
	original := state + '/' + bundle_name
	archive := original + '.tar.gz'
	sidecar := state + '/' + bundle_name + '-cold-cleanup-2026-10-26'
	assert os.getwd() == repo && !os.exists(sidecar) && !os.is_link(sidecar)
	assert os.real_path(original) == original && os.is_dir(original) && !os.is_link(original)
	assert !os.exists(archive) && !os.is_link(archive)
	assert !os.exists(archive + '.sha256') && !os.is_link(archive + '.sha256')
	assert hash(original + '/sha256.json')! == bundle_pin
	assert hash(auditor)! == auditor_pin && hash(auditor_source)! == auditor_source_pin
	assert hash('/usr/bin/tar')! == reader_pin
	started := time.utc().str()
	source_pin := hash(source)!
	binary_pin := hash(os.executable())!
	os.mkdir_all(sidecar + '/consumed-tooling')!
	for input in [source, os.executable(), auditor, auditor_source] {
		output := sidecar + '/consumed-tooling/' + os.base(input)
		os.cp(input, output)!
		assert hash(input)! == hash(output)!
	}
	mut commands := []json2.Any{}
	before := command('df-before', ['/bin/df', '-k', state], mut commands)!
	command('original-audit', [auditor, original, bundle_pin, sidecar + '/original-check.json'], mut commands)!
	original_tree := tree(original)!
	os.write_file(sidecar + '/expanded-typed-sha256.json', json2.encode(original_tree, prettify: true) + '\n')!
	command('archive-create', ['/usr/bin/tar', '-czpf', archive, '--options', 'gzip:compression-level=6', '-C', state, bundle_name], mut commands)!
	assert os.real_path(archive) == archive && !os.is_link(archive)
	archive_pin := hash(archive)!
	os.write_file(archive + '.sha256', archive_pin + '  ' + os.base(archive) + '\n')!
	checksum_pin := hash(archive + '.sha256')!
	listing := command('archive-list', ['/usr/bin/tar', '-tzf', archive], mut commands)!
	for entry in listing.split_into_lines() {
		assert entry == bundle_name + '/' || entry.starts_with(bundle_name + '/'), 'unexpected archive root'
		assert !entry.split('/').any(it == '..'), 'unsafe archive path'
	}
	restore_parent := sidecar + '/restore'
	restored := restore_parent + '/' + bundle_name
	os.mkdir(restore_parent)!
	command('archive-restore', ['/usr/bin/tar', '-xSzpf', archive, '-C', restore_parent], mut commands)!
	assert os.ls(restore_parent)! == [bundle_name]
	assert hash(restored + '/sha256.json')! == bundle_pin
	equal(tree(restored)!, original_tree)!
	command('restored-audit', [auditor, restored, bundle_pin, sidecar + '/restored-check.json'], mut commands)!
	// Requalify both complete trees after the unchanged historical audits.
	equal(tree(original)!, original_tree)!
	equal(tree(restored)!, original_tree)!
	assert hash(archive)! == archive_pin && hash(archive + '.sha256')! == checksum_pin
	assert hash(auditor)! == auditor_pin && hash(auditor_source)! == auditor_source_pin
	assert hash('/usr/bin/tar')! == reader_pin
	assert hash(source)! == source_pin && hash(os.executable())! == binary_pin
	mut receipt := {
		'started_utc': json2.Any(started)
		'archive': json2.Any(archive)
		'archive_sha256': json2.Any(archive_pin)
		'archive_size': json2.Any(os.file_size(archive))
		'checksum_sha256': json2.Any(checksum_pin)
		'original_expanded': json2.Any(original)
		'restored_expanded': json2.Any(restored)
		'bundle_manifest_sha256': json2.Any(bundle_pin)
		'complete_typed_entries': json2.Any(original_tree.len)
		'typed_manifest_sha256': json2.Any(hash(sidecar + '/expanded-typed-sha256.json')!)
		'auditor_binary_sha256': json2.Any(auditor_pin)
		'auditor_source_sha256': json2.Any(auditor_source_pin)
		'archive_reader': json2.Any('/usr/bin/tar')
		'archive_reader_sha256': json2.Any(reader_pin)
		'cleanup_source_sha256': json2.Any(source_pin)
		'cleanup_binary_sha256': json2.Any(binary_pin)
		'commands': json2.Any(commands)
		'df_before': json2.Any(before)
	}
	write_json(sidecar + '/qualified-before-removal.json', receipt)!
	for path in [original, restored] {
		assert path in [state + '/' + bundle_name, sidecar + '/restore/' + bundle_name]
		assert os.real_path(path) == path && os.is_dir(path) && !os.is_link(path)
		os.rmdir_all(path)!
		assert !os.exists(path) && !os.is_link(path)
	}
	assert os.ls(restore_parent)!.len == 0
	os.rmdir(restore_parent)!
	assert hash(archive)! == archive_pin && hash(archive + '.sha256')! == checksum_pin
	receipt['df_after'] = command('df-after', ['/bin/df', '-k', state], mut commands)!
	receipt['commands'] = commands
	receipt['completed_utc'] = time.utc().str()
	receipt['expanded_copies_removed'] = true
	receipt['original_archive_unchanged'] = true
	write_json(sidecar + '/receipt.json', receipt)!
	sealed := tree(sidecar)!
	os.write_file(sidecar + '/sha256.json', json2.encode(sealed, prettify: true) + '\n')!
	mut readback := tree(sidecar)!
	readback.delete('sha256.json')
	readback.delete('@mode:sha256.json')
	equal(readback, sealed)!
	println('OLD-BUILD-COLD-CLEANUP-PASS typed_entries=' + original_tree.len.str() + ' manifest=' + hash(sidecar + '/sha256.json')!)
}
