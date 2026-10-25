// Compile without -prod. All generated fixtures/results belong outside Git.
// selftest OUTDIR | benchmark OUTDIR | pin FILE SHA256 [portable] | inspect FILE
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

// Canonical file hash used by artifact tools. C owns the context layout/alignment;
// each 1 MiB update fits CC_LONG (uint32_t). Required work never occurs in assert.
fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('CC_SHA256_Init failed') }
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 {
				return error('CC_SHA256_Update failed')
			}
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 {
			return error('CC_SHA256_Final failed')
		}
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		defer { unsafe { state.free() } }
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			if state.write(buffer[..n])! != n { return error('SHA256 short write') }
		}
		mut result := []u8{len: 32}
		defer { unsafe { result.free() } }
		state.checksum_into(mut result)
		return result.hex()
	}
}

// This forced backend exercises portable streaming on Darwin as well.
fn portable_hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut state := sha256.new()
	defer { unsafe { state.free() } }
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		if state.write(buffer[..n])! != n { return error('SHA256 short write') }
	}
	mut result := []u8{len: 32}
	defer { unsafe { result.free() } }
	state.checksum_into(mut result)
	return result.hex()
}

struct Result {
	path string
	backend string
	sha256 string
	elapsed_ns i64
	size_before u64
	size_after u64
	mtime_before i64
	mtime_after i64
}

fn backend(portable bool) string {
	$if macos {
		return if portable { 'v-crypto.sha256' } else { 'darwin-commoncrypto' }
	} $else {
		return 'v-crypto.sha256'
	}
}

fn measured_hash(path string, portable bool) !Result {
	if !os.is_file(path) { return error('regular file required: ${path}') }
	before_size := os.file_size(path)
	before_mtime := os.file_last_mod_unix(path)
	started := time.sys_mono_now()
	answer := if portable { portable_hash(path)! } else { hash(path)! }
	elapsed := time.sys_mono_now() - started
	after_size := os.file_size(path)
	after_mtime := os.file_last_mod_unix(path)
	if before_size != after_size || before_mtime != after_mtime {
		return error('file metadata changed while hashing')
	}
	return Result{path, backend(portable), answer, elapsed,
		before_size, after_size, before_mtime, after_mtime}
}

fn bytes_digest(data []u8, chunk int) string {
	assert chunk > 0 && chunk <= 1024 * 1024
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(unsafe { &state }) != 1 { panic('CC_SHA256_Init failed') }
		mut offset := 0
		for offset < data.len {
			end := if offset + chunk > data.len { data.len } else { offset + chunk }
			if C.CC_SHA256_Update(unsafe { &state }, unsafe { &data[offset] }, u32(end - offset)) != 1 {
				panic('CC_SHA256_Update failed')
			}
			offset = end
		}
		mut result := [32]u8{}
		if C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) != 1 {
			panic('CC_SHA256_Final failed')
		}
		return result[..].hex()
	} $else {
		return sha256.sum(data).hex()
	}
}

fn selftest(out string) ! {
	os.mkdir_all(out)!
	vectors := {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
		'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq': '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
	}
	for text, expected in vectors {
		assert sha256.sum(text.bytes()).hex() == expected
		for chunk in [1, 7, 63, 64, 65, 1024 * 1024] {
			assert bytes_digest(text.bytes(), chunk) == expected
		}
		path := out + '/known-vector.bin'
		os.write_file_array(path, text.bytes())!
		assert hash(path)! == expected && portable_hash(path)! == expected
	}
	million_a := []u8{len: 1000000, init: `a`}
	expected_a := 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'
	assert sha256.sum(million_a).hex() == expected_a
	assert bytes_digest(million_a, 65) == expected_a
	os.write_file_array(out + '/million-a.bin', million_a)!
	assert hash(out + '/million-a.bin')! == expected_a
	for size in [0, 1, 55, 56, 63, 64, 65, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1] {
		data := []u8{len: size, init: u8((index * 37 + index / 251) & 255)}
		expected := sha256.sum(data).hex()
		path := out + '/binary-${size}.bin'
		os.write_file_array(path, data)!
		for chunk in [1, 7, 63, 64, 65, 1024 * 1024] {
			assert bytes_digest(data, chunk) == expected
		}
		assert hash(path)! == expected
		assert portable_hash(path)! == expected
	}
	missing := out + '/absent-file'
	if os.exists(missing) { return error('selftest requires absent-file to be absent') }
	hash(missing) or {
		println('SHA256-MISSING-INPUT-PASS')
		println('SHA256-KNOWN-VECTORS-PASS')
		println('SHA256-BINARY-BOUNDARIES-PASS')
		return
	}
	return error('missing file accepted')
}

// Observed warm-file timings under host load, not a controlled throughput claim.
fn benchmark(out string) ! {
	os.mkdir_all(out)!
	path := out + '/benchmark-64m.bin'
	mut output := os.create(path)!
	block := []u8{len: 1024 * 1024, init: u8((index * 37 + index / 251) & 255)}
	for _ in 0 .. 64 {
		if output.write(block)! != block.len { return error('benchmark short write') }
	}
	output.close()
	fast := measured_hash(path, false)!
	portable := measured_hash(path, true)!
	assert fast.sha256 == portable.sha256
	os.write_file(out + '/benchmark.json', json2.encode([fast, portable], prettify: true))!
	println(json2.encode([fast, portable]))
	println('SHA256-BENCHMARK-EQUALITY-PASS')
}

fn main() {
	$if prod { eprintln('artifact SHA checks require assertions'); exit(2) }
	assert os.args.len >= 3, 'selftest OUTDIR | benchmark OUTDIR | pin FILE SHA256 [portable] | inspect FILE'
	match os.args[1] {
		'selftest' { assert os.args.len == 3; selftest(os.args[2]) or { panic(err) } }
		'benchmark' { assert os.args.len == 3; benchmark(os.args[2]) or { panic(err) } }
		'pin' {
			assert os.args.len in [4, 5]
			if os.args.len == 5 { assert os.args[4] == 'portable' }
			expected := os.args[3]
			assert expected.len == 64 && expected.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
			result := measured_hash(os.args[2], os.args.len == 5) or { panic(err) }
			assert result.sha256 == expected, 'expected pin mismatch: ${json2.encode(result)}'
			println(json2.encode(result, prettify: true))
			println('SHA256-PIN-PASS')
		}
		'inspect' {
			assert os.args.len == 3
			result := measured_hash(os.args[2], false) or { panic(err) }
			println(json2.encode(result, prettify: true))
		}
		else { panic('unknown mode') }
	}
}
