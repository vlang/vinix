// SPDX-License-Identifier: GPL-2.0-or-later
module muslabi

import mapsaccountstage

fn put(mut bytes []u8, at int, length int, value u64) {
	for i in 0 .. length { bytes[at + i] = u8(value >> (8 * i)) }
}

fn fixture(defined bool) []u8 {
	mut bytes := []u8{len: 1024}
	for i, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = value }
	put(mut bytes, 16, 2, 3)
	put(mut bytes, 18, 2, 183)
	put(mut bytes, 20, 4, 1)
	put(mut bytes, 32, 8, 64)
	put(mut bytes, 40, 8, 768)
	put(mut bytes, 52, 2, 64)
	put(mut bytes, 54, 2, 56)
	put(mut bytes, 56, 2, 2)
	put(mut bytes, 58, 2, 64)
	put(mut bytes, 60, 2, 3)
	put(mut bytes, 64, 4, 1)
	put(mut bytes, 80, 8, 0x1000)
	put(mut bytes, 96, 8, 1024)
	put(mut bytes, 104, 8, 1024)
	put(mut bytes, 120, 4, 2)
	put(mut bytes, 128, 8, 192)
	put(mut bytes, 136, 8, 0x10c0)
	put(mut bytes, 152, 8, 96)
	for at, value in {
		192: u64(5)
		200: 0x1280
		208: 6
		216: 0x1200
		224: 10
		232: 64
		240: 11
		248: 24
	} {
		put(mut bytes, at, 8, value)
	}
	put(mut bytes, 536, 4, 1)
	bytes[540] = 0x12
	put(mut bytes, 542, 2, if defined { u64(1) } else { u64(0) })
	for i, value in '\x00clock_gettime\x00'.bytes() { bytes[640 + i] = value }
	for at, value in {
		836: u64(11)
		848: 0x1200
		856: 512
		864: 48
		872: 2
		888: 24
		900: 3
		912: 0x1280
		920: 640
		928: 64
	} {
		put(mut bytes, at, 8, value)
	}
	return bytes
}

fn test_imports_require_compatible_exports_in_both_musl_implementations() {
	engine := inspect(fixture(false))!
	runtime := inspect(fixture(true))!
	assert verify(engine, runtime, runtime)! == ['clock_gettime']
	for candidate in [Table{ exports: {
		'other': Symbol{ kind: 2 }
	} }, Table{ exports: {
		'clock_gettime': Symbol{ kind: 1 }
	} }] {
		if _ := verify(engine, candidate, runtime) {
			assert false, 'bad toolchain ABI accepted'
		}
		if _ := verify(engine, runtime, candidate) {
			assert false, 'bad runtime ABI accepted'
		}
	}
	data := Table{ imports: {
		'data': Symbol{ kind: 1, size: 8 }
	} }
	small := Table{ exports: {
		'data': Symbol{ kind: 1, size: 4 }
	} }
	if _ := verify(data, small, small) {
		assert false, 'undersized data symbol accepted'
	}
}

fn test_weak_imports_can_be_absent_but_present_symbols_must_match() {
	engine := Table{ imports: {
		'optional': Symbol{ kind: 2, weak: true }
	} }
	absent := Table{ exports: {
		'other': Symbol{ kind: 2 }
	} }
	assert verify(engine, absent, absent)! == ['optional']
	wrong := Table{ exports: {
		'optional': Symbol{ kind: 1 }
	} }
	if _ := verify(engine, wrong, absent) {
		assert false
	}
}

fn test_executable_copy_data_definitions_require_exact_provider_size() {
	engine := Table{
		imports: {'clock': Symbol{kind: 2}}
		exports: {'stdout': Symbol{kind: 1, size: 8}}
	}
	good := Table{exports: {'clock': Symbol{kind: 2}, 'stdout': Symbol{kind: 1, size: 8}}}
	assert verify(engine, good, good)! == ['clock', 'stdout']
	for size in [u64(0), 4, 16] {
		bad := Table{exports: {'clock': Symbol{kind: 2}, 'stdout': Symbol{kind: 1, size: size}}}
		if _ := verify(engine, good, bad) { assert false, 'incompatible COPY data accepted' }
	}
}

fn test_malformed_versioned_or_ambiguous_symbol_tables_are_rejected() {
	for at, value in {
		40:  u64(0xffffffffffffffff)
		58:  32
		60:  0
		216: 0x1208
		248: 16
		536: 64
		836: 1
		864: 49
		872: 3
		888: 8
		912: 0x1288
		920: 99999
		900: 0x6fffffff
		256: 0x6ffffffe
	} {
		mut bytes := fixture(false)
		put(mut bytes, at, if at in [58, 60] {
			2
		} else if at in [536, 836, 872, 900] {
			4
		} else {
			8
		}, value)
		if _ := inspect(bytes) {
			assert false, 'bad ABI metadata accepted at ${at}'
		}
	}
	mut versioned := fixture(false)
	versioned[641] = `@`
	if _ := inspect(versioned) {
		assert false, 'versioned symbol accepted'
	}
	bytes := fixture(false)
	for length in 0 .. 960 {
		if _ := inspect(bytes[..length]) {
			assert false, 'truncated ABI accepted: ${length}'
		}
	}
}

fn test_section_file_offsets_must_match_loader_symbol_and_string_mappings() {
	// Keep valid tables in alternative file locations while leaving their
	// advertised virtual addresses unchanged. The loader never sees these copies.
	for symbol_table in [false, true] {
		mut bytes := fixture(false)
		from, to, size, header := if symbol_table { 512, 568, 48, 856 } else { 640, 960, 64, 920 }
		copied := bytes[from..from + size].clone()
		for i, value in copied { bytes[to + i] = value }
		put(mut bytes, header, 8, u64(to))
		assert mapsaccountstage.inspect_elf(bytes)!.needed.len == 0
		if _ := inspect(bytes) { assert false, 'unmapped section table copy accepted' }
	}
}

fn with_extra_load(address u64, file_size u64, memory_size u64) []u8 {
	mut bytes := fixture(false)
	// Move PT_DYNAMIC beyond the new third program header.
	dynamic := bytes[192..288].clone()
	for i in 192 .. 288 { bytes[i] = 0 }
	for i, value in dynamic { bytes[320 + i] = value }
	put(mut bytes, 128, 8, 320)
	put(mut bytes, 136, 8, 0x1140)
	put(mut bytes, 56, 2, 3)
	put(mut bytes, 176, 4, 1)
	put(mut bytes, 184, 8, 512)
	put(mut bytes, 192, 8, address)
	put(mut bytes, 208, 8, file_size)
	put(mut bytes, 216, 8, memory_size)
	return bytes
}

fn test_symbol_span_rejects_duplicate_partial_and_zero_fill_load_overlaps() {
	for bytes in [with_extra_load(0x1200, 48, 48), with_extra_load(0x1210, 16, 16),
		with_extra_load(0x1210, 0, 16)] {
		assert mapsaccountstage.inspect_elf(bytes)!.needed.len == 0
		if _ := inspect(bytes) { assert false, 'overlapping symbol LOAD accepted' }
	}
	// Adjacent spans do not intersect the dynamic symbols or dynamic strings.
	assert 'clock_gettime' in inspect(with_extra_load(0x1230, 16, 16))!.imports
	assert 'clock_gettime' in inspect(with_extra_load(0x1210, 0, 0))!.imports
	// A symbol table starting in a LOAD must also end inside its file bytes.
	mut truncated := fixture(false)
	strings := truncated[640..704].clone()
	for i, value in strings { truncated[432 + i] = value }
	put(mut truncated, 200, 8, 0x11b0)
	put(mut truncated, 912, 8, 0x11b0)
	put(mut truncated, 920, 8, 432)
	put(mut truncated, 96, 8, 536)
	assert mapsaccountstage.inspect_elf(truncated)!.needed.len == 0
	if _ := inspect(truncated) { assert false, 'partially file-backed symbol table accepted' }
}
