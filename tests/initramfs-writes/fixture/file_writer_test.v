// SPDX-License-Identifier: GPL-2.0-or-later
module initramfs

import resource

struct Writer {
mut:
	output     []u8
	chunks     []int
	calls      int
	done       u64
	fail_after int = -1
}

fn (mut writer Writer) write(_ voidptr, buffer voidptr, offset u64, count u64) ?i64 {
	if writer.fail_after >= 0 && writer.calls >= writer.fail_after {
		writer.calls++
		return none
	}
	assert offset == writer.done
	assert count == u64(writer.output.len) - offset
	limit := writer.chunks[writer.calls % writer.chunks.len]
	amount := if count < u64(limit) { count } else { u64(limit) }
	unsafe { C.memcpy(voidptr(u64(writer.output.data) + offset), buffer, amount) }
	writer.done += amount
	writer.calls++
	return i64(amount)
}

fn payload(size int) []u8 {
	mut bytes := []u8{len: size}
	for index in 0 .. bytes.len { bytes[index] = u8((index * 17 + index / 251) & 0xff) }
	return bytes
}

fn test_large_archive_file_survives_one_megabyte_transaction_limit() {
	bytes := payload(3 * 1024 * 1024 + 137)
	mut writer := Writer{ output: []u8{len: bytes.len}, chunks: [1024 * 1024] }
	mut destination := resource.Resource(&writer)
	assert write_archive_file(mut destination, bytes.data, u64(bytes.len))
	assert writer.output == bytes
	assert writer.calls == 4
}

fn test_irregular_short_writes_preserve_binary_data_and_offsets() {
	bytes := payload(1027)
	mut writer := Writer{ output: []u8{len: bytes.len}, chunks: [7, 1, 33, 128, 3] }
	mut destination := resource.Resource(&writer)
	assert write_archive_file(mut destination, bytes.data, u64(bytes.len))
	assert writer.output == bytes
}

fn test_backend_error_after_progress_fails_the_archive_entry() {
	bytes := payload(128)
	mut writer := Writer{ output: []u8{len: bytes.len}, chunks: [32], fail_after: 1 }
	mut destination := resource.Resource(&writer)
	assert !write_archive_file(mut destination, bytes.data, u64(bytes.len))
	assert writer.calls == 2
	assert writer.done == 32
}

struct InvalidWriter {
mut:
	result i64
	calls  int
}

fn (mut writer InvalidWriter) write(_ voidptr, _ voidptr, _ u64, _ u64) ?i64 {
	writer.calls++
	return writer.result
}

fn test_zero_negative_and_excess_counts_fail_without_another_call() {
	bytes := payload(16)
	for result in [i64(0), -1, 17] {
		mut writer := InvalidWriter{ result: result }
		mut destination := resource.Resource(&writer)
		assert !write_archive_file(mut destination, bytes.data, u64(bytes.len))
		assert writer.calls == 1
	}
}

fn test_empty_file_requires_no_backend_write() {
	mut writer := InvalidWriter{}
	mut destination := resource.Resource(&writer)
	assert write_archive_file(mut destination, unsafe { nil }, 0)
	assert writer.calls == 0
}
