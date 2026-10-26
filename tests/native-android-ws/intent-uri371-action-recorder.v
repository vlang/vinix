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
	mut result := [32]u8{}
	assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &context }) == 1
	return result[..].hex()
}

fn main() {
	assert os.args.len >= 5
	label := os.args[1]
	assert label in ['prepare', 'new', 'qualify', 'seal']
	pin := os.args[2]
	assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
	argv := os.args[3..]
	assert argv[0].starts_with('/Users/alex/.local/state/vinix/android/intent-uri371-')
	assert argv[1] == label
	assert hash(argv[0])! == pin
	prefix := '/Users/alex/.local/state/vinix/android/intent-uri371-fixture-' + label + '-2026-10-26'
	for suffix in ['-before.json', '-command.json', '.log'] { assert !os.exists(prefix + suffix) }
	mut receipt := {'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(time.utc().str()), 'executable_sha256_before': json2.Any(pin),
		'recorder_source_sha256': json2.Any(hash(@FILE)!),
		'recorder_binary_sha256': json2.Any(hash(os.executable())!)}
	os.write_file(prefix + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	println('INTENT371-' + label.to_upper() + '-START')
	result := os.exec(argv)
	os.write_file(prefix + '.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	receipt['executable_sha256_after'] = hash(argv[0])!
	receipt['output_sha256'] = hash(prefix + '.log')!
	os.write_file(prefix + '-command.json', json2.encode(receipt, prettify: true) + '\n')!
	print(result.output)
	assert result.exit_code == 0, result.output
	assert hash(argv[0])! == pin
	println('INTENT371-' + label.to_upper() + '-PASS')
}
