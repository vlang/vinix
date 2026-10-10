// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn test_a_package_length_counts_itself() {
	assert aml_length(0) == [u8(1)]
	assert aml_length(62) == [u8(63)]
	// 63 bytes of body no longer fit one byte: two, and the count grows by one.
	assert aml_length(63) == [u8(0x41), 0x04]
	assert aml_length(0xffd) == [u8(0x4f), 0xff]
	assert aml_length(0xffe) == [u8(0x81), 0x00, 0x01]
}

fn test_names_are_padded_and_paths_prefixed() {
	assert aml_name('BAT0') == 'BAT0'.bytes()
	assert aml_name('_SB') == '_SB_'.bytes()
	assert aml_name('\\_SB') == '\\_SB_'.bytes()
	mut two := [u8(`\\`), 0x2e]
	two << '_SB_BAT0'.bytes()
	assert aml_name('\\_SB.BAT0') == two
	mut three := [u8(`\\`), 0x2f, 3]
	three << '_SB_BAT0TICK'.bytes()
	assert aml_name('\\_SB.BAT0.TICK') == three
}

fn test_integers_take_the_shortest_form() {
	assert aml_integer(0) == [u8(0x00)]
	assert aml_integer(1) == [u8(0x01)]
	assert aml_integer(0x80) == [u8(0x0a), 0x80]
	assert aml_integer(48000) == [u8(0x0b), 0x80, 0xbb]
	assert aml_integer(0xffffffff) == [u8(0x0c), 0xff, 0xff, 0xff, 0xff]
	assert aml_integer(0x100000000).len == 9
}

fn test_a_method_is_its_name_flags_and_body() {
	// Method (_STA) { Return (0x1F) }
	assert aml_method('_STA', [aml_return(aml_integer(0x1f))]) == [u8(0x14), 0x09, `_`, `S`, `T`,
		`A`, 0x00, 0xa4, 0x0a, 0x1f]
}

fn test_a_table_sums_to_zero_and_says_its_length() {
	table := acpi_table('power-bench')!
	assert table[..4].bytestr() == 'SSDT'
	length := int(table[4]) | (int(table[5]) << 8) | (int(table[6]) << 16) | (int(table[7]) << 24)
	assert length == table.len
	mut sum := u8(0)
	for b in table {
		sum += b
	}
	assert sum == 0
	assert table.bytestr().contains('PNP0C0A')
	assert table.bytestr().contains('ACPI0003')
	assert table.bytestr().contains('PNP0C0D')
	if _ := acpi_table('nonesuch') {
		assert false, 'an unknown table was made'
	}
}
