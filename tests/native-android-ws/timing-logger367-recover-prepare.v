// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the interrupted preparation without inventing a command exit.
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

const state = '/Users/alex/.local/state/vinix/android/timing-logger367-fixture-2026-10-26'
const receipt = '/Users/alex/.local/state/vinix/android/timing-logger367-fixture-prepare-2026-10-26-before.json'
const output = '/Users/alex/.local/state/vinix/android/timing-logger367-prepare-recovery-2026-10-26.json'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut context := C.CC_SHA256_CTX{}
	assert C.CC_SHA256_Init(unsafe { &context }) == 1
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		assert C.CC_SHA256_Update(unsafe { &context }, buffer.data, u32(n)) == 1
	}
	mut digest := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &digest[0] }, unsafe { &context }) == 1
	return digest[..].hex()
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		info := os.lstat(path)!
		match info.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { entries[key] = 'directory'; inventory(root, key, mut entries)! }
			else { return error('nonregular interrupted evidence: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn main() {
	archive := state + '-interrupted-prepare-01'
	archived_receipt := receipt + '-interrupted-01'
	for path in [archive, archived_receipt, output] { assert !os.exists(path) && !os.is_link(path) }
	assert os.real_path(state) == state && os.is_dir(state) && !os.is_link(state)
	assert os.lstat(receipt)!.get_filetype() == .regular
	assert !os.exists(receipt.replace('-before.json', '-command.json'))
	assert !os.exists(receipt.replace('-before.json', '.log'))
	assert !os.exists(state + '/build-pins.json') && !os.exists(state + '/tools/checked-runner')
	assert !os.exists(state + '/sha256.json')
	processes := os.exec(['/bin/ps', '-axo', 'pid=,ppid=,command='])
	assert processes.exit_code == 0
	for line in processes.output.split_into_lines() {
		assert !line.contains('/timing-logger367-run prepare '), 'preparation still running'
		assert !line.contains('qemu-system-'), 'QEMU still running'
	}
	mut before := map[string]string{}
	inventory(state, '', mut before)!
	receipt_pin := hash(receipt)!
	os.rename(state, archive)!
	os.rename(receipt, archived_receipt)!
	mut after := map[string]string{}
	inventory(archive, '', mut after)!
	assert before == after && hash(archived_receipt)! == receipt_pin
	assert !os.exists(state) && !os.exists(receipt)
	mut preserved := map[string]json2.Any{}
	for key, value in before { preserved[key] = value }
	data := {'status': json2.Any('interrupted-without-completed-host-exit'),
		'created_utc': json2.Any(time.utc().str()), 'original_root': json2.Any(state),
		'archived_root': json2.Any(archive), 'original_before_receipt': json2.Any(receipt),
		'archived_before_receipt': json2.Any(archived_receipt),
		'before_receipt_sha256': json2.Any(receipt_pin), 'preserved_entries': json2.Any(preserved),
		'source_sha256': json2.Any(hash(@FILE)!), 'binary_sha256': json2.Any(hash(os.executable())!),
		'process_snapshot': json2.Any(processes.output), 'process_snapshot_exit': json2.Any(processes.exit_code)}
	os.write_file(output, json2.encode(data, prettify: true) + '\n')!
	println('TIMING367-PREPARE-RECOVERY-PASS entries=' + before.len.str())
}
