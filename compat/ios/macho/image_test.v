// SPDX-License-Identifier: GPL-2.0-or-later
module macho

import os

fn put(mut data []u8, off int, value u64, size int) {
	for i in 0 .. size { data[off + i] = u8(value >> (i * 8)) }
}

fn put_be(mut data []u8, off int, value u64, size int) {
	for i in 0 .. size { data[off + i] = u8(value >> ((size - i - 1) * 8)) }
}

fn put_string(mut data []u8, off int, value string) {
	for i, byte in value.bytes() { data[off + i] = byte }
}

// A documented ARM64 Mach-O layout, built without any host SDK/linker.
// Its chain has one internal pointer and one import on a 16K page.
fn fixture_image() []u8 {
	mut data := []u8{len: 0x8000}
	put(mut data, 0, 0xfeedfacf, 4)
	put(mut data, 4, 0x100000c, 4)
	put(mut data, 12, 2, 4)
	put(mut data, 16, 7, 4)
	put(mut data, 20, 3 * 72 + 24 + 24 + 56 + 16, 4)
	put(mut data, 24, 0x200000, 4)
	for index, name in ['__PAGEZERO', '__TEXT', '__DATA'] {
		off := 32 + index * 72
		put(mut data, off, 0x19, 4)
		put(mut data, off + 4, 72, 4)
		put_string(mut data, off + 8, name)
		if index == 0 {
			put(mut data, off + 32, 0x100000000, 8)
			continue
		}
		put(mut data, off + 24, 0x100000000 + u64(index - 1) * 0x4000, 8)
		put(mut data, off + 32, 0x4000, 8)
		put(mut data, off + 40, u64(index - 1) * 0x4000, 8)
		put(mut data, off + 48, 0x4000, 8)
		put(mut data, off + 56, if index == 1 { 5 } else { 3 }, 4)
		put(mut data, off + 60, if index == 1 { 5 } else { 3 }, 4)
	}
	put(mut data, 248, 0x80000028, 4)
	put(mut data, 252, 24, 4)
	put(mut data, 256, 0x200, 8)
	put(mut data, 272, 0x32, 4)
	put(mut data, 276, 24, 4)
	put(mut data, 280, 2, 4)
	put(mut data, 284, 0xf0000, 4)
	put(mut data, 296, 0xc, 4)
	put(mut data, 300, 56, 4)
	put(mut data, 304, 24, 4)
	put_string(mut data, 320, '/usr/lib/libSystem.B.dylib')
	put(mut data, 352, 0x80000034, 4)
	put(mut data, 356, 16, 4)
	put(mut data, 360, 0x7000, 4)
	put(mut data, 364, 128, 4)
	put(mut data, 0x4000, 0x200 | (u64(2) << 51), 8)
	put(mut data, 0x4008, u64(1) << 63, 8)
	put(mut data, 0x7004, 28, 4) // starts
	put(mut data, 0x7008, 68, 4) // imports
	put(mut data, 0x700c, 72, 4) // symbols
	put(mut data, 0x7010, 1, 4)
	put(mut data, 0x7014, 1, 4)
	put(mut data, 0x701c, 3, 4)
	put(mut data, 0x7028, 16, 4)
	put(mut data, 0x702c, 24, 4) // starts_in_segment.size
	put(mut data, 0x7030, 0x4000, 2)
	put(mut data, 0x7032, 6, 2)
	put(mut data, 0x7034, 0x4000, 8)
	put(mut data, 0x7040, 1, 2)
	put(mut data, 0x7044, 1, 4) // import: library ordinal 1, symbol offset 0
	put_string(mut data, 0x7048, '_puts')
	return data
}

fn fixture_resolver(library string, symbol string) !u64 {
	assert library == '/usr/lib/libSystem.B.dylib'
	if symbol == '_puts' { return 0x12345678 }
	return error('unimplemented: ${symbol}')
}

fn expect_parse_failure(data []u8) {
	if _ := parse(data) {
		assert false, 'malformed input parsed successfully'
	}
}

fn expect_layout_failure(data []u8) {
	image := parse(data) or { panic(err) }
	if _ := image.layout(4096) {
		assert false, 'malformed layout accepted'
	}
}

fn expect_fixup_failure(data []u8) {
	image := parse(data) or { panic(err) }
	layout := image.layout(4096) or { panic(err) }
	if _ := image.plan_fixups(layout, 0x900000000, fixture_resolver) {
		assert false, 'malformed fixups accepted'
	}
}

fn test_arm64_metadata_layout_and_chains() {
	image := parse(fixture_image())!
	assert image.execution_issues().len == 0
	assert image.platform_name() == 'iOS'
	assert image.libraries.len == 1
	for page in [u64(4096), 16384] {
		layout := image.layout(page)!
		assert layout.base == 0x100000000
		assert layout.size == 0x8000
		assert layout.entry == 0x200
		plan := image.plan_fixups(layout, 0x900000000, fixture_resolver)!
		assert plan.len == 2
		assert plan[0].offset == 0x4000 && plan[0].value == 0x900000200
		assert plan[1].offset == 0x4008 && plan[1].value == 0x12345678
	}
}

fn fixture_symbol_imports() []u8 {
	mut data := fixture_image()
	put(mut data, 16, 8, 4)
	put(mut data, 20, 424 - 32, 4)
	put(mut data, 24, 0x200080, 4) // MH_PIE | MH_TWOLEVEL
	for i in 352 .. 424 { data[i] = 0 }
	put(mut data, 352, 2, 4) // LC_SYMTAB, replacing chained fixups
	put(mut data, 356, 24, 4)
	put(mut data, 360, 0x6000, 4)
	put(mut data, 364, 8, 4)
	put(mut data, 368, 0x6080, 4)
	put(mut data, 376, 0x80000022, 4) // LC_DYLD_INFO_ONLY
	put(mut data, 380, 48, 4)
	put(mut data, 392, 0x6100, 4) // bind offset/size
	put(mut data, 396, 1, 4)
	mut cursor := 1
	names := ['_puts', '_weak', '_flat', '_main', '_defined', '_local', '_debug', '_common']
	kinds := [u8(1), 1, 1, 1, 0xf, 0, 0xe1, 1]
	descriptions := [u16(0x100), 0x140, 0xfe00, 0xff00, 0x100, 0x100, 0x100, 0x100]
	for i, name in names {
		off := 0x6000 + i * 16
		put(mut data, off, u64(cursor), 4)
		put(mut data, off + 4, u64(kinds[i]), 1)
		put(mut data, off + 6, u64(descriptions[i]), 2)
		if i == 7 { put(mut data, off + 8, 8, 8) } // Common symbol, not an import.
		put_string(mut data, 0x6080 + cursor, name)
		cursor += name.len + 1
	}
	put(mut data, 372, u64(cursor), 4)
	return data
}

fn test_legacy_symbol_imports_remain_inspectable() {
	image := parse(fixture_symbol_imports())!
	assert image.legacy_fixups
	assert !image.execution_issues().any(it.contains('legacy dyld'))
	symbols := image.imported_symbols()!
	assert symbols.len == 4
	assert symbols[0].name == '_puts'
	assert symbols[0].library == '/usr/lib/libSystem.B.dylib'
	assert !symbols[0].weak
	assert symbols[1].name == '_weak' && symbols[1].weak
	assert symbols[1].library == '/usr/lib/libSystem.B.dylib'
	assert symbols[2].library == '<flat lookup>'
	assert symbols[3].library == '<main executable>'
	mut data := fixture_symbol_imports()
	put(mut data, 0x6006, 0, 2)
	assert parse(data)!.imported_symbols()![0].library == '<self>'
	put(mut data, 24, 0x200000, 4) // No MH_TWOLEVEL: every undefined import is flat.
	assert parse(data)!.imported_symbols()!.all(it.library == '<flat lookup>')
}

fn test_symbol_table_and_import_names_are_bounded() {
	for position, value in {
		356: u64(32)
		360: 0xffffffff
		364: 1048577
		368: 0xffffffff
		372: 0xffffffff
	} {
		mut bad := fixture_symbol_imports()
		put(mut bad, position, value, 4)
		expect_parse_failure(bad)
	}
	mut bad := fixture_symbol_imports()
	put(mut bad, 376, 2, 4)
	put(mut bad, 380, 24, 4)
	put(mut bad, 20, 400 - 32, 4)
	expect_parse_failure(bad) // Duplicate LC_SYMTAB, even if the second table is empty.
	for invalid in ['offset', 'empty', 'unterminated', 'ordinal'] {
		bad = fixture_symbol_imports()
		match invalid {
			'offset' { put(mut bad, 0x6000, 0xffffffff, 4) }
			'empty' { put(mut bad, 0x6000, 0, 4) }
			'ordinal' { put(mut bad, 0x6006, 0x200, 2) }
			else {
				for i in 0x6080 .. 0x6100 { bad[i] = `x` }
			}
		}
		image := parse(bad)!
		if _ := image.imported_symbols() {
			assert false, 'invalid symbol import accepted'
		}
	}
}

fn test_chained_imports_take_precedence_over_symbol_table() {
	mut data := fixture_symbol_imports()
	put(mut data, 376, 0x80000034, 4)
	put(mut data, 380, 16, 4)
	put(mut data, 384, 0x7000, 4)
	put(mut data, 388, 128, 4)
	put(mut data, 20, 392 - 32, 4)
	symbols := parse(data)!.imported_symbols()!
	assert symbols.len == 1
	assert symbols[0].name == '_puts'
}

fn test_truncated_headers_and_commands_fail_without_reading_outside_input() {
	data := fixture_image()
	for size in 0 .. 368 { expect_parse_failure(data[..size]) }
	mut bad := data.clone()
	put(mut bad, 36, 0, 4)
	expect_parse_failure(bad)
	put(mut bad, 36, 0xfffffff8, 4)
	expect_parse_failure(bad)
	put(mut bad, 36, 73, 4)
	expect_parse_failure(bad)
}

fn test_segment_and_entry_validation() {
	mut bad := fixture_image()
	put(mut bad, 176 + 24, 0xffffffffffffc000, 8)
	expect_parse_failure(bad)
	bad = fixture_image()
	put(mut bad, 176 + 48, 0x4001, 8)
	expect_parse_failure(bad)
	bad = fixture_image()
	put(mut bad, 176 + 24, 0x100000000, 8)
	expect_layout_failure(bad)
	bad = fixture_image()
	put(mut bad, 104 + 56, 7, 4)
	put(mut bad, 104 + 60, 7, 4)
	expect_layout_failure(bad)
	bad = fixture_image()
	put(mut bad, 256, 0x4000, 8)
	expect_layout_failure(bad)
	bad = fixture_image()
	put(mut bad, 256, 0x201, 8)
	expect_layout_failure(bad)
	image := parse(fixture_image())!
	if _ := image.layout(3000) {
		assert false
	}
}

fn test_required_commands_and_unimplemented_platforms_are_explicit() {
	mut bad := fixture_image()
	put(mut bad, 272, 0x80000070, 4)
	assert parse(bad)!.execution_issues().any(it.contains('required load command'))
	bad = fixture_image()
	put(mut bad, 8, 0x80000002, 4)
	assert parse(bad)!.execution_issues().any(it.contains('ARM64e'))
	bad = fixture_image()
	put(mut bad, 280, 1, 4)
	assert parse(bad)!.execution_issues().any(it.contains('macOS'))
	bad = fixture_image()
	put(mut bad, 280, 7, 4)
	assert parse(bad)!.execution_issues().len == 0
	bad = fixture_image()
	put_string(mut bad, 320, '/unimplemented/library.a')
	assert parse(bad)!.execution_issues().any(it.contains('framework/library'))
}

fn test_library_strings_and_sections_are_bounded_by_their_command() {
	mut bad := fixture_image()
	put(mut bad, 304, 4, 4)
	expect_parse_failure(bad)
	bad = fixture_image()
	for i in 320 .. 352 { bad[i] = `x` }
	expect_parse_failure(bad)
	bad = fixture_image()
	put(mut bad, 104 + 64, 1, 4)
	expect_parse_failure(bad)
}

fn universal(data []u8, wide bool, big bool) []u8 {
	mut result := []u8{len: 0x1000 + data.len}
	magic := if wide { u64(0xcafebabf) } else { u64(0xcafebabe) }
	if big {
		put_be(mut result, 0, magic, 4)
		put_be(mut result, 4, 1, 4)
		put_be(mut result, 8, 0x100000c, 4)
		put_be(mut result, 16, 0x1000, if wide { 8 } else { 4 })
		put_be(mut result, if wide { 24 } else { 20 }, u64(data.len), if wide { 8 } else { 4 })
	} else {
		put(mut result, 0, magic, 4)
		put(mut result, 4, 1, 4)
		put(mut result, 8, 0x100000c, 4)
		put(mut result, 16, 0x1000, if wide { 8 } else { 4 })
		put(mut result, if wide { 24 } else { 20 }, u64(data.len), if wide { 8 } else { 4 })
	}
	for i, byte in data { result[0x1000 + i] = byte }
	return result
}

fn test_universal_headers_in_both_widths_and_byte_orders() {
	data := fixture_image()
	for wide in [false, true] {
		for big in [false, true] {
			fat := universal(data, wide, big)
			image := parse(fat)!
			assert image.data == data
			assert image.layout(4096)!.entry == 0x200
		}
	}
	mut bad := universal(data, false, true)
	put_be(mut bad, 16, 8, 4)
	expect_parse_failure(bad)
	bad = universal(data, true, true)
	put_be(mut bad, 24, 0xffffffffffffffff, 8)
	expect_parse_failure(bad)
	bad = universal(data, false, true)
	put_be(mut bad, 8, 0x1000007, 4)
	expect_parse_failure(bad)
}

fn test_chained_fixup_tables_and_pointer_formats_are_bounded() {
	for position, value in {
		0x7004: u64(0xffffffff)
		0x7008: 0xffffffff
		0x700c: 0xffffffff
		0x7010: 65537
		0x7014: 4
		0x7018: 1
		0x701c: 4
		0x7028: 0xffffffff
		0x702c: 0xffffffff
	} {
		mut bad := fixture_image()
		put(mut bad, position, value, 4)
		expect_fixup_failure(bad)
	}
	for position, value in {
		0x7030: u64(8192)
		0x7032: 12
		0x7040: 2
		0x7042: 0x8000
	} {
		mut bad := fixture_image()
		put(mut bad, position, value, 2)
		expect_fixup_failure(bad)
	}
	mut bad := fixture_image()
	put(mut bad, 0x7034, 0x8000, 8)
	expect_fixup_failure(bad)
}

fn test_chains_cannot_escape_pages_or_reference_unmapped_memory() {
	for word in [u64(0x8000), 0x200 | (u64(0xfff) << 51), 0x200 | (u64(1) << 36)] {
		mut bad := fixture_image()
		put(mut bad, 0x4000, word, 8)
		expect_fixup_failure(bad)
	}
	mut bad := fixture_image()
	put(mut bad, 0x4008, (u64(1) << 63) | 1, 8)
	expect_fixup_failure(bad)
	bad = fixture_image()
	put(mut bad, 0x7042, 0x3ffc, 2)
	expect_fixup_failure(bad)
}

fn test_unknown_symbols_fail_and_weak_imports_resolve_to_zero() {
	mut bad := fixture_image()
	put_string(mut bad, 0x7048, '_unknown')
	expect_fixup_failure(bad)
	put(mut bad, 0x7044, 0x101, 4)
	image := parse(bad)!
	fixups := image.plan_fixups(image.layout(4096)!, 0x900000000, fixture_resolver)!
	assert fixups[1].value == 0
}

fn test_absolute_pointer_format_and_import_addends() {
	mut data := fixture_image()
	put(mut data, 0x7032, 2, 2)
	put(mut data, 0x4000, 0x100000200 | (u64(2) << 51), 8)
	put(mut data, 0x7014, 2, 4)
	put(mut data, 0x700c, 76, 4)
	put(mut data, 0x7048, 0xfffffff0, 4) // signed -16 import addend
	put_string(mut data, 0x704c, '_puts')
	put(mut data, 0x4008, (u64(1) << 63) | (u64(255) << 24), 8)
	image := parse(data)!
	plan := image.plan_fixups(image.layout(4096)!, 0x900000000, fixture_resolver)!
	assert plan[0].value == 0x900000200
	assert plan[1].value == 0x12345678 - 16 + 255
}

fn test_wide_import_addends_and_inspection_of_authenticated_images() {
	mut data := fixture_image()
	put(mut data, 0x7014, 3, 4)
	put(mut data, 0x700c, 84, 4)
	put(mut data, 0x7044, 1, 8)
	put(mut data, 0x704c, 0xfffffffffffffff0, 8)
	put_string(mut data, 0x7054, '_puts')
	image := parse(data)!
	plan := image.plan_fixups(image.layout(4096)!, 0x900000000, fixture_resolver)!
	assert plan[1].value == 0x12345678 - 16
	put(mut data, 8, 2, 4)
	put(mut data, 0x7032, 12, 2)
	inspected := parse(data)!.imported_symbols()!
	assert inspected.len == 1
	assert inspected[0].library == '/usr/lib/libSystem.B.dylib'
	assert inspected[0].name == '_puts'
	expect_fixup_failure(data)
}

fn test_executables_must_allow_relocation_and_supported_segment_flags() {
	mut bad := fixture_image()
	put(mut bad, 24, 0, 4)
	assert parse(bad)!.execution_issues().any(it.contains('MH_PIE'))
	bad = fixture_image()
	put(mut bad, 176 + 68, 1, 4)
	assert parse(bad)!.execution_issues().any(it.contains('segment flags'))
	bad = fixture_image()
	put(mut bad, 264, 0x80000, 8)
	assert parse(bad)!.execution_issues().any(it.contains('stack sizes'))
	bad = fixture_image()
	put(mut bad, 176 + 68, 0x10, 4)
	assert parse(bad)!.execution_issues().len == 0
}
fn legacy_fixture(rebase []u8, bind []u8, weak []u8, lazy []u8, exports []u8) []u8 {
	mut data := fixture_image()
	put(mut data, 20, 400 - 32, 4)
	for i in 352 .. 400 { data[i] = 0 }
	put(mut data, 352, 0x80000022, 4)
	put(mut data, 356, 48, 4)
	for index, stream in [rebase, bind, weak, lazy, exports] {
		position := 0x6000 + index * 0x100
		put(mut data, 360 + index * 8, u64(position), 4)
		put(mut data, 364 + index * 8, u64(stream.len), 4)
		for i, byte in stream { data[position + i] = byte }
	}
	put(mut data, 0x4000, 0x100000200, 8)
	put(mut data, 0x4008, 0x100000204, 8)
	return data
}

fn test_legacy_rebase_bind_lazy_and_signed_addends() {
	rebase := [u8(0x11), 0x22, 0, 0x52, 0]
	mut bind := [u8(0x11), 0x40]
	bind << '_puts'.bytes()
	bind << [u8(0), 0x51, 0x72, 0x10, 0x60, 0x7c, 0x90, 0] // -4
	mut lazy := [u8(0x11), 0x40]
	lazy << '_puts'.bytes()
	lazy << [u8(0), 0x72, 0x18, 0x90, 0, 0x11, 0x40]
	lazy << '_puts'.bytes()
	lazy << [u8(0), 0x72, 0x20, 0x90, 0]
	image := parse(legacy_fixture(rebase, bind, [], lazy, []))!
	layout := image.layout(4096)!
	plan := image.plan_fixups(layout, 0x900000000, fixture_resolver)!
	assert plan == [Fixup{0x4000, 0x900000200}, Fixup{0x4008, 0x900000204},
		Fixup{0x4010, 0x12345674}, Fixup{0x4018, 0x12345678}, Fixup{0x4020, 0x12345678}]
}

fn test_export_trie_and_weak_coalescing_override_rebase() {
	// root -> "_local" -> terminal (weak definition, address 0x200).
	exports := [u8(0), 1, `_`, `l`, `o`, `c`, `a`, `l`, 0, 10, 3, 4, 0x80, 4, 0]
	mut weak := [u8(0x40)]
	weak << '_local'.bytes()
	weak << [u8(0), 0x72, 0, 0x90, 0]
	image := parse(legacy_fixture([u8(0x11), 0x22, 0, 0x51, 0], [], weak, [], exports))!
	layout := image.layout(4096)!
	assert image.exported_address('_local', layout, 0x900000000)! == 0x900000200
	assert image.exported_address('_absent', layout, 0x900000000)! == 0
	plan := image.plan_fixups(layout, 0x900000000, fixture_resolver)!
	assert plan.len == 2
	assert plan[0] == plan[1]
	mut cycle := exports.clone()
	cycle[9] = 0
	bad := parse(legacy_fixture([], [], [], [], cycle))!
	if _ := bad.exported_address('_local', layout, 0x900000000) { assert false }
}

fn test_legacy_rejects_bad_ranges_types_counts_and_opcodes() {
	for stream in [
		[u8(0x11), 0x22, 0x80], // truncated ULEB
		[u8(0x12), 0x22, 0, 0x51, 0], // text relocation
		[u8(0x11), 0x20, 0, 0x51, 0], // PAGEZERO
		[u8(0x11), 0x21, 0, 0x51, 0], // executable segment
		[u8(0x11), 0x22, 0xff, 0x7f, 0x51, 0], // segment overrun
		[u8(0x11), 0x22, 0, 0x60, 0xff, 0xff, 0xff, 0xff, 0x7f], // huge count
		[u8(0x11), 0x22, 0, 0x30, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 2],
		[u8(0xf0)],
	] {
		expect_fixup_failure(legacy_fixture(stream, [], [], [], []))
	}
	expect_fixup_failure(legacy_fixture([], [u8(0x72), 0, 0x90], [], [], []))
	expect_fixup_failure(legacy_fixture([], [u8(0xd0)], [], [], []))
	mut bad := legacy_fixture([], [], [], [], [])
	put(mut bad, 360, 0xffffffff, 4)
	put(mut bad, 364, 1, 4)
	expect_parse_failure(bad)
}

fn probe_resolver(_ string, _ string) !u64 { return 0x12345678 }

// Optional regression against the exact downloaded, unmodified upstream IPA.
// Fake addresses are used only to validate the linker; no code is executed.
fn test_upstream_ppsspp_streams_when_available() {
	path := os.getenv('VINIX_IOS_PPSSPP_BINARY')
	if path == '' { return }
	image := parse(os.read_bytes(path)!)!
	layout := image.layout(4096)!
	plan := image.plan_fixups(layout, 0x900000000, probe_resolver)!
	assert plan.len > 30000
	assert plan.all(it.offset < layout.size - 7)
	println('PPSSPP legacy relocation plan: ${plan.len} writes')
}
