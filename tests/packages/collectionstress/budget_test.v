// SPDX-License-Identifier: GPL-2.0-or-later
module collectionstress

fn test_file_reservation_counter_requires_exact_unambiguous_unsigned_fields() {
	assert file_bytes('Limit: 42\nKind Objects Bytes\nfile 8314 51480252\nmapping 327 8483584\n')! == 51480252
	assert file_bytes('file\t0 0\r\n')! == 0
	assert file_bytes('file 18446744073709551615 18446744073709551615\n')! == ~u64(0)
	for text in ['Limit: 0\n', 'file', 'file 1', 'file 1 2 3', 'file 1 2\nfile 1 2\n',
		'file -1 2', 'file 1 -2', 'file 1 +2', 'file 1 2.0', 'file 1 0x10',
		'file 18446744073709551616 2', 'file 1 18446744073709551616'] {
		mut refused := false
		file_bytes(text) or {
			refused = true; message := err.msg(); assert message.len != 0
			unsafe { message.free(); err.free() }
		}
		assert refused, text
	}
	println('COLLECTION STRESS counter accepts full-width unsigned values and rejects missing, duplicate, coerced and overflowing fields PASS')
}

fn test_reservation_ceiling_cannot_wrap_or_accumulate_allowances() {
	assert reservation_ceiling(141604)! == 272676
	assert reservation_ceiling(~u64(0) - 131072)! == ~u64(0)
	mut refused := false
	reservation_ceiling(~u64(0) - 131071) or { refused = true }
	assert refused
	println('COLLECTION STRESS fixed reservation ceiling preserves its allowance and rejects overflow PASS')
}
