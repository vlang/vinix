// SPDX-License-Identifier: GPL-2.0-or-later
module fontindex

import compress.gzip

fn put(mut bytes []u8, at int, value u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(value >> (8 * i)) }
}

fn named_fixture(name string) []u8 {
	strings := ('FONT\x00' + name + '\x00').bytes()
	mut table := []u8{len: 24}
	put(mut table, 4, 1)
	table[12] = 1
	put(mut table, 13, 5)
	put(mut table, 20, u32(strings.len))
	table << strings
	mut bytes := []u8{len: 24}
	bytes[0] = 1
	bytes[1] = `f`
	bytes[2] = `c`
	bytes[3] = `p`
	put(mut bytes, 4, 1)
	put(mut bytes, 8, 1)
	put(mut bytes, 16, u32(table.len))
	put(mut bytes, 20, 24)
	bytes << table
	return bytes
}

fn fixture() []u8 {
	return named_fixture('-misc-fixed-medium-r-normal--13-120-75-75-c-70-iso8859-1')
}

fn test_font_property_is_extracted_without_glyph_interpretation() {
	assert font_name(fixture())! == '-misc-fixed-medium-r-normal--13-120-75-75-c-70-iso8859-1'
	assert font_name(named_fixture('cursor'))! == 'cursor'
	mut rejected := false
	font_name(named_fixture('other-name')) or { rejected = true }
	assert rejected
}

fn test_zero_alignment_padding_is_bounded() {
	for padding in 1 .. 4 {
		mut valid := fixture()
		valid << []u8{len: padding}
		put(mut valid, 16, u32(valid.len - 24))
		assert font_name(valid)! == '-misc-fixed-medium-r-normal--13-120-75-75-c-70-iso8859-1'
		valid[valid.len - 1] = 1
		mut rejected := false
		font_name(valid) or { rejected = true }
		assert rejected
	}
	mut excessive := fixture()
	excessive << []u8{len: 4}
	put(mut excessive, 16, u32(excessive.len - 24))
	mut rejected := false
	font_name(excessive) or { rejected = true }
	assert rejected
}

fn test_concatenated_gzip_members_cannot_exceed_expansion_limit() {
	first := gzip.compress([u8(1), 2, 3, 4])!
	second := gzip.compress([u8(5), 6, 7, 8])!
	mut packed := first.clone()
	packed << second
	assert expand(packed, 8)! == [u8(1), 2, 3, 4, 5, 6, 7, 8]
	mut rejected := false
	expand(packed, 7) or { rejected = true }
	assert rejected
}

fn test_truncated_and_out_of_bounds_pcf_tables_are_rejected() {
	valid := fixture()
	for length in 0 .. valid.len {
		mut rejected := false
		font_name(valid[..length]) or { rejected = true }
		assert rejected, 'accepted truncated PCF at ${length}'
	}
	for at in [4, 16, 20, 28, 32, 37, 44] {
		mut malformed := valid.clone()
		put(mut malformed, at, 0xfffffff0)
		mut rejected := false
		font_name(malformed) or { rejected = true }
		assert rejected, 'accepted malformed PCF word at ${at}'
	}
}
