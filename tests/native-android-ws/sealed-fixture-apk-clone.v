// SPDX-License-Identifier: GPL-2.0-or-later
// Share six identical APK extents without changing the original sealed evidence.
module main

import json2
import encoding.binary
import os
import time

#include <CommonCrypto/CommonDigest.h>
#include <stdio.h>
#include <sys/xattr.h>
#include <sys/attr.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32
fn C.rename(&char, &char) i32
fn C.listxattr(&char, &char, usize, int) isize
fn C.getxattr(&char, &char, voidptr, usize, u32, int) isize
struct C.attrlist {
mut:
	bitmapcount u16
	reserved u16
	commonattr u32
	volattr u32
	dirattr u32
	fileattr u32
	forkattr u32
}
fn C.getattrlist(&char, voidptr, voidptr, usize, u32) i32

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const source = repo + '/tests/native-android-ws/sealed-fixture-apk-clone.v'
const donor = state + '/bundle-parcel365-fixture-2026-10-26/run-old/module/opt/android-test/maps-application.apk'
const apk_pin = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const apk_size = u64(304176297)
const cp_pin = '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9'
const probe = repo + '/build/android-maps/apfs-private-size-hardened'
const probe_pin = '369b19fe3c2093c7aa7f0133981ae355f21cccbe208c380bf7c337503fe87a5b'
const checker = repo + '/build/android-maps/build-bundle-check290'
const checker_pin = '52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004'

fn profile(name string) !(string, string) {
	match name {
		'363' { return state + '/bundle-parcel363-fixture-2026-10-26', '3c3fea1c43bef44399b69cc11dabe44d17fcad382978bb2a425e1b4ba05f4f94' }
		'361' { return state + '/service-stop361-fixture-2026-10-26', 'df542fd682eb4530a895f102b29554ddadc33dd1fa7f48d351b291832e3e4582' }
		'359' { return state + '/permission-info359-fixture-2026-10-26', '01aa44a3e5ca9281379329c185e38aa43ca148c00cb5e0edd2382946d1a43661' }
		else { return error('only the fixed363/361/359 profiles are permitted') }
	}
}

fn flags(path string) !u32 {
	mut attrs := C.attrlist{bitmapcount: 5, commonattr: 0x00040000}
	mut packed := [8]u8{}
	assert C.getattrlist(&char(path.str), unsafe { &attrs }, unsafe { &packed[0] }, 8, 1) == 0
	assert binary.little_endian_u32(packed[..4]) == 8
	return binary.little_endian_u32(packed[4..])
}

fn identity(info os.Stat) string {
	return '${info.dev}:${info.inode}:${info.mode}:${info.uid}:${info.gid}:${info.nlink}:${info.size}:${info.mtime}:${info.ctime}'
}

fn metadata(info os.Stat) string {
	return '${info.mode}:${info.uid}:${info.gid}:${info.nlink}:${info.size}:${info.mtime}'
}

fn regular(path string) !os.Stat {
	assert os.real_path(path) == path && !os.is_link(path), 'canonical file required: ' + path
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

fn xattrs(path string) !map[string]string {
	n := C.listxattr(&char(path.str), unsafe { nil }, 0, 1) // XATTR_NOFOLLOW
	assert n >= 0
	mut names := []u8{len: int(n)}
	assert C.listxattr(&char(path.str), &char(names.data), usize(n), 1) == n
	mut values := map[string]string{}
	for name in names.bytestr().split('\x00') {
		if name == '' { continue }
		count := C.getxattr(&char(path.str), &char(name.str), unsafe { nil }, 0, 0, 1)
		assert count >= 0 && count <= 1024 * 1024
		mut data := []u8{len: int(count)}
		assert C.getxattr(&char(path.str), &char(name.str), data.data, usize(count), 0, 1) == count
		values[name] = data.hex()
	}
	return values
}

// Full typed metadata inventory supplements the unchanged original file-hash
// auditor. Directory timestamps/inodes/ctime are excluded: rename changes them.
fn typed(path string, prefix string, mut entries map[string]string) ! {
	before := os.lstat(path)!
	match before.get_filetype() {
		.directory {
			entries[prefix] = 'directory:${before.mode}:${before.uid}:${before.gid}:${before.nlink}'
			for name in os.ls(path)!.sorted() { typed(path + '/' + name, prefix + '/' + name, mut entries)! }
		}
		.regular { entries[prefix] = 'regular:' + metadata(before) }
		.symbolic_link { entries[prefix] = 'symlink:${before.mode}:${before.uid}:${before.gid}:' + os.readlink(path)! }
		else { return error('unexpected artifact: ' + path) }
	}
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn any_map(values map[string]string) map[string]json2.Any {
	mut result := map[string]json2.Any{}
	for key, value in values { result[key] = value }
	return result
}

fn command(receipt string, label string, argv []string, mut commands []json2.Any) !string {
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(receipt + '/' + label + '.log', result.output)!
	commands << json2.Any({'label': json2.Any(label), 'argv': json2.Any(argv),
		'exit_code': json2.Any(result.exit_code), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()),
		'output_sha256': json2.Any(hash(receipt + '/' + label + '.log')!)})
	write_json(receipt + '/commands.json', {'commands': json2.Any(commands)})!
	assert result.exit_code == 0, label + ' failed; actual status retained'
	return result.output
}

fn tools() ! {
	assert hash('/bin/cp')! == cp_pin && hash(probe)! == probe_pin && hash(checker)! == checker_pin
}

fn main() {
	$if prod { panic('assertions required') }
	$if !macos { panic('APFS clone required') }
	assert os.args.len == 4 && os.args[1] == 'apply-quiescent'
	root, manifest_pin := profile(os.args[2])!
	receipt := os.args[3]
	assert os.getwd() == repo && os.real_path(state) == state
	assert os.dir(receipt) == state && os.base(receipt).starts_with('sealed-apk-clone-')
	assert !os.exists(receipt) && !os.is_link(receipt), 'fresh external receipt required'
	assert os.real_path(root) == root && !os.is_link(root)
	tools()!
	assert hash(root + '/sha256.json')! == manifest_pin
	source_pin := hash(source)!
	binary_pin := hash(os.executable())!
	donor_info := regular(donor)!
	assert donor_info.size == apk_size && hash(donor)! == apk_pin
	donor_xattrs := xattrs(donor)!
	donor_flags := flags(donor)!
	targets := ['run-old', 'run-new'].map(root + '/' + it + '/module/opt/android-test/maps-application.apk')
	mut originals := map[string]string{}
	for target in targets {
		info := regular(target)!
		assert info.dev == donor_info.dev && info.inode != donor_info.inode
		assert metadata(info) == metadata(donor_info) && hash(target)! == apk_pin
		assert xattrs(target)! == donor_xattrs
		assert flags(target)! == donor_flags
		assert !os.exists(target + '.clone-tmp') && !os.is_link(target + '.clone-tmp')
		originals[target] = identity(info)
	}
	os.mkdir(receipt)!
	os.cp(source, receipt + '/helper.v')!
	os.cp(os.executable(), receipt + '/helper')!
	write_json(receipt + '/plan.json', {'root': json2.Any(root), 'manifest_sha256': json2.Any(manifest_pin),
		'donor': json2.Any(donor), 'targets': json2.Any(targets), 'target_identities': json2.Any(any_map(originals)),
		'donor_identity': json2.Any(identity(donor_info)), 'apk_sha256': json2.Any(apk_pin),
		'apk_bytes': json2.Any(apk_size), 'source_sha256': json2.Any(source_pin),
		'binary_sha256': json2.Any(binary_pin), 'donor_and_targets_xattrs': json2.Any(any_map(donor_xattrs)),
		'donor_and_targets_flags': json2.Any(donor_flags),
		'checker_sha256': json2.Any(checker_pin), 'cp_sha256': json2.Any(cp_pin),
		'private_probe_sha256': json2.Any(probe_pin), 'started_utc': json2.Any(time.utc().str())})!
	mut commands := []json2.Any{}
	command(receipt, 'df-before', ['/bin/df', '-k', state], mut commands)!
	command(receipt, 'complete-before', [checker, root, manifest_pin, receipt + '/complete-before.json'], mut commands)!
	mut before := map[string]string{}
	typed(root, '', mut before)!
	write_json(receipt + '/typed-before.json', before)!
	mut completed := []string{}
	for index, target in targets {
		temp := target + '.clone-tmp'
		assert identity(regular(donor)!) == identity(donor_info)
		assert identity(regular(target)!) == originals[target]
		command(receipt, 'private-before-' + index.str(), [probe, target], mut commands)!
		command(receipt, 'clone-' + index.str(), ['/bin/cp', '-cp', donor, temp], mut commands)!
		cloned := regular(temp)!
		assert cloned.dev == donor_info.dev && cloned.inode != donor_info.inode
		assert metadata(cloned) == metadata(donor_info) && hash(temp)! == apk_pin
		assert xattrs(temp)! == donor_xattrs
		assert flags(temp)! == donor_flags
		measured := command(receipt, 'temp-private-' + index.str(), [probe, temp], mut commands)!
		assert measured.trim_space() == 'APFS-PRIVATE-TOTAL bytes=0 logical_bytes=${apk_size} files=1 directories=0 skipped_symlinks=0 path=${temp}'
		assert identity(regular(target)!) == originals[target]
		tools()!
		status := C.rename(&char(temp.str), &char(target.str))
		write_json(receipt + '/rename-' + index.str() + '.json', {'target': target, 'rename_status': status.str()})!
		assert status == 0 && !os.exists(temp) && !os.is_link(temp)
		after := regular(target)!
		assert after.inode == cloned.inode && metadata(after) == metadata(donor_info)
		assert hash(target)! == apk_pin && xattrs(target)! == donor_xattrs
		assert flags(target)! == donor_flags
		command(receipt, 'private-after-' + index.str(), [probe, target], mut commands)!
		completed << target
		write_json(receipt + '/actual.json', {'completed_targets': json2.Any(completed),
			'completed_utc': json2.Any(time.utc().str()), 'post_swap_hashes_match': json2.Any(true)})!
	}
	mut after := map[string]string{}
	typed(root, '', mut after)!
	write_json(receipt + '/typed-after.json', after)!
	assert before == after, 'complete typed/metadata inventory changed'
	assert identity(regular(donor)!) == identity(donor_info) && hash(donor)! == apk_pin
	assert xattrs(donor)! == donor_xattrs && hash(root + '/sha256.json')! == manifest_pin
	assert flags(donor)! == donor_flags
	command(receipt, 'complete-after', [checker, root, manifest_pin, receipt + '/complete-after.json'], mut commands)!
	tools()!
	assert hash(source)! == source_pin && hash(os.executable())! == binary_pin
	command(receipt, 'df-after', ['/bin/df', '-k', state], mut commands)!
	write_json(receipt + '/result.json', {'profile': json2.Any(os.args[2]), 'complete_before_and_after': json2.Any(true),
		'full_typed_metadata_unchanged': json2.Any(true), 'original_manifest_unchanged': json2.Any(manifest_pin),
		'completed_targets': json2.Any(completed), 'completed_utc': json2.Any(time.utc().str())})!
	println('SEALED-APK-CLONE-PASS profile=${os.args[2]} targets=${completed.len}; original complete evidence unchanged')
}
