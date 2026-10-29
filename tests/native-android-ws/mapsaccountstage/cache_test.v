// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import crypto.sha256
import os

fn cache_policy_at_size(path string, size i64) !bool {
	os.truncate(path, u64(size))!
	mut input := os.open(path)!
	defer { input.close() }
	return prepare_hash_input(input.fd)
}

fn test_hash_cache_policy_is_per_open_input_and_size_bounded() ! {
	path := os.join_path(os.real_path(os.temp_dir()), 'maps-hash-cache-' + os.getpid().str())
	if os.exists(path) { return error('fresh cache-policy fixture required') }
	os.write_file(path, '')!
	defer { os.rm(path) or {} }
	for size in [i64(0), i64(1), uncached_hash_min_size - 1, uncached_hash_min_size, uncached_hash_min_size + 17] {
		applied := cache_policy_at_size(path, size)!
		$if macos {
			if applied != (size >= uncached_hash_min_size) { return error('macOS regular-file cache threshold differs') }
		} $else {
			if applied { return error('non-macOS hash policy changed') }
		}
	}
	$if macos {
		if _ := prepare_hash_input(-1) { return error('invalid input descriptor accepted') }
		mut special := os.open('/dev/null')!
		defer { special.close() }
		if prepare_hash_input(special.fd)! { return error('nonregular input policy changed') }
		if digest('/dev/null')! != sha256.sum([]u8{}).hex() { return error('special-file empty digest differs') }
	} $else {
		if prepare_hash_input(-1)! { return error('non-macOS descriptor policy changed') }
	}
}

fn test_uncached_large_sparse_hash_preserves_all_bytes_and_unaligned_tail() ! {
	path := os.join_path(os.real_path(os.temp_dir()), 'maps-hash-sparse-' + os.getpid().str())
	if os.exists(path) { return error('fresh sparse-hash fixture required') }
	os.write_file(path, '')!
	defer { os.rm(path) or {} }
	os.truncate(path, u64(uncached_hash_min_size))!
	tail := []u8{len: 17, init: u8(index * 131 + 17)}
	mut output := os.open_file(path, 'r+')!
	defer { output.close() }
	output.seek(uncached_hash_min_size, .start)!
	if output.write(tail)! != tail.len { return error('sparse hash fixture short write') }
	output.close()
	if os.lstat(path)!.size != u64(uncached_hash_min_size) + u64(tail.len) { return error('sparse hash fixture length differs') }
	mut expected := sha256.new()
	defer { unsafe { expected.free() } }
	zeros := []u8{len: 1024 * 1024}
	for _ in 0 .. 64 { if expected.write(zeros)! != zeros.len { return error('reference SHA short zero write') } }
	if expected.write(tail)! != tail.len { return error('reference SHA short tail write') }
	mut result := []u8{len: 32}
	expected.checksum_into(mut result)
	if digest(path)! != result.hex() { return error('large sparse binary-tail digest differs from independent SHA') }
}

fn test_hash_cache_policy_preserves_small_binary_digests() ! {
	path := os.join_path(os.real_path(os.temp_dir()), 'maps-hash-small-' + os.getpid().str())
	if os.exists(path) { return error('fresh small-hash fixture required') }
	defer { os.rm(path) or {} }
	for size in [0, 1, 1024 * 1024 + 17] {
		bytes := []u8{len: size, init: u8(index * 67)}
		os.write_file_array(path, bytes)!
		if digest(path)! != sha256.sum(bytes).hex() { return error('small binary digest differs from reference SHA') }
	}
}
