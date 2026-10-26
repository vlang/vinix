// SPDX-License-Identifier: GPL-2.0-or-later
// Consolidate exactly two identical extracted APKs; original sealing follows.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
fn C.rename(&char, &char) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/bundle-parcel365-fixture-2026-10-26'
const suffix = '/module/opt/android-test/maps-application.apk'
const donor = root + '/run-old' + suffix
const targets = [root + '/run-new' + suffix, root + '/interrupted-new-01/run-new' + suffix]
const apk_pin = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const apk_size = u64(304176297)
const cp_pin = '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9'
const probe = repo + '/build/android-maps/apfs-private-size-hardened'
const probe_pin = '369b19fe3c2093c7aa7f0133981ae355f21cccbe208c380bf7c337503fe87a5b'
const source = repo + '/tests/native-android-ws/bundle-parcel-apk-clone.v'

fn identity(info os.Stat) string {
	return '${info.dev}:${info.inode}:${info.mode}:${info.uid}:${info.gid}:${info.nlink}:${info.size}:${info.mtime}:${info.ctime}'
}

fn metadata(info os.Stat) string {
	return '${info.mode}:${info.uid}:${info.gid}:${info.nlink}:${info.size}:${info.mtime}'
}

fn regular(path string) !os.Stat {
	assert os.real_path(path) == path && !os.is_link(path), 'canonical path required: ' + path
	info := os.lstat(path)!
	assert info.get_filetype() == .regular && info.nlink == 1
	return info
}

fn hash(path string) !string {
	before := regular(path)!
	mut input := os.open(path)!
	defer { input.close() }
	mut digest := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &digest }) == 1
	mut buffer := []u8{len: 1024 * 1024}
	mut bytes := u64(0)
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		bytes += u64(n)
		assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
	}
	assert bytes == before.size && identity(before) == identity(regular(path)!)
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &digest }) == 1
	return result[..].hex()
}

fn write_json(path string, value map[string]json2.Any) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(receipt string, label string, argv []string, mut commands []json2.Any) !string {
	result := os.exec(argv)
	os.write_file(receipt + '/' + label + '.log', result.output)!
	commands << json2.Any({'label': json2.Any(label), 'argv': json2.Any(argv),
		'exit_code': json2.Any(result.exit_code), 'completed_utc': json2.Any(time.utc().str()),
		'output_sha256': json2.Any(hash(receipt + '/' + label + '.log')!)})
	write_json(receipt + '/commands.json', {'commands': json2.Any(commands)})!
	assert result.exit_code == 0, label + ' failed'
	return result.output
}

fn main() {
	$if prod { panic('assertions required') }
	$if !macos { panic('APFS clone required') }
	assert os.args.len == 3 && os.args[1] == 'apply-quiescent'
	receipt := os.args[2]
	assert os.getwd() == repo && os.dir(receipt) == state
	assert os.base(receipt).starts_with('bundle-parcel365-apk-clone-')
	assert !os.exists(receipt) && !os.is_link(receipt)
	assert os.real_path(state) == state && !os.is_link(state)
	assert !os.exists(root + '/sha256.json'), 'hold original seal until swaps finish'
	assert hash('/bin/cp')! == cp_pin && hash(probe)! == probe_pin
	source_pin := hash(source)!
	binary_pin := hash(os.executable())!
	donor_info := regular(donor)!
	assert donor_info.size == apk_size && hash(donor)! == apk_pin
	mut originals := map[string]string{}
	mut original_records := map[string]json2.Any{}
	for target in targets {
		info := regular(target)!
		assert info.dev == donor_info.dev && info.inode != donor_info.inode
		assert metadata(info) == metadata(donor_info) && info.size == apk_size
		assert hash(target)! == apk_pin
		assert !os.exists(target + '.clone-tmp') && !os.is_link(target + '.clone-tmp')
		originals[target] = identity(info)
		original_records[target] = identity(info)
	}
	os.mkdir(receipt)!
	write_json(receipt + '/plan.json', {'donor': json2.Any(donor), 'targets': json2.Any(targets),
		'donor_identity': json2.Any(identity(donor_info)), 'target_identities': json2.Any(original_records),
		'apk_sha256': json2.Any(apk_pin), 'apk_bytes': json2.Any(apk_size),
		'source_sha256': json2.Any(source_pin), 'binary_sha256': json2.Any(binary_pin),
		'cp_sha256': json2.Any(cp_pin), 'private_size_probe_sha256': json2.Any(probe_pin),
		'started_utc': json2.Any(time.utc().str()),
		'qualification': json2.Any('Quiescent unsealed fixture only; original complete seal and readback must follow.')})!
	mut commands := []json2.Any{}
	mut completed := []string{}
	command(receipt, 'df-before', ['/bin/df', '-k', state], mut commands)!
	for index, target in targets {
		temp := target + '.clone-tmp'
		assert identity(regular(donor)!) == identity(donor_info)
		assert identity(regular(target)!) == originals[target]
		assert !os.exists(temp) && !os.is_link(temp)
		command(receipt, 'clone-' + index.str(), ['/bin/cp', '-cp', donor, temp], mut commands)!
		cloned := regular(temp)!
		assert cloned.dev == donor_info.dev && cloned.inode != donor_info.inode
		assert metadata(cloned) == metadata(donor_info) && hash(temp)! == apk_pin
		// cp -c may fall back to copying. Require actual shared storage before replacement.
		measured := command(receipt, 'temp-private-' + index.str(), [probe, temp], mut commands)!
		assert measured.trim_space() == 'APFS-PRIVATE-TOTAL bytes=0 logical_bytes=${apk_size} files=1 directories=0 skipped_symlinks=0 path=${temp}'
		assert identity(regular(target)!) == originals[target]
		assert hash('/bin/cp')! == cp_pin && hash(probe)! == probe_pin
		status := C.rename(&char(temp.str), &char(target.str))
		write_json(receipt + '/rename-' + index.str() + '.json', {'target': json2.Any(target),
			'temporary': json2.Any(temp), 'rename_status': json2.Any(status),
			'completed_utc': json2.Any(time.utc().str())})!
		assert status == 0
		assert !os.exists(temp) && !os.is_link(temp)
		after := regular(target)!
		assert after.inode == cloned.inode && metadata(after) == metadata(donor_info)
		assert hash(target)! == apk_pin
		completed << target
		write_json(receipt + '/actual.json', {'completed_targets': json2.Any(completed),
			'completed_utc': json2.Any(time.utc().str()), 'post_swap_hashes_match': json2.Any(true)})!
	}
	assert identity(regular(donor)!) == identity(donor_info) && hash(donor)! == apk_pin
	assert hash(source)! == source_pin && hash(os.executable())! == binary_pin
	assert !os.exists(root + '/sha256.json')
	command(receipt, 'df-after', ['/bin/df', '-k', state], mut commands)!
	println('BUNDLE365-APK-CLONE-PASS targets=${completed.len}; original seal/readback still required')
}
