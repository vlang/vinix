module g17decode

import imageextract as image
import math.big
import traceanalysis as j

fn decoded_text(name string, word u32) string {
	return j.encode(decode(name, word, j.Value(0)), false)
}

fn pack(values []u32) []u8 {
	mut result := []u8{}
	for value in values { result << [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)] }
	return result
}

fn test_move_wide_and_zero_extended_w_constants() {
	assert decoded_text('decode_move_wide', 0xd2e00028) == '["movz",8,1,48]'
	assert decoded_text('decode_movn_w', 0x12800008) == '[8,4294967295]'
	assert decoded_text('decode_movk_w', 0x72a00028) == '[8,1,16]'
	assert decoded_text('decode_move_wide', 0x52800028) == 'null'
}

fn test_unsigned_loads_distinguish_integer_and_vector_widths() {
	assert decoded_text('decode_load_unsigned', 0x3dc00900) == '[0,8,32,16]'
	assert decoded_text('decode_integer_load_unsigned', 0x3dc00900) == 'null'
	assert decoded_text('decode_integer_store_unsigned', 0xbd000900) == 'null'
	assert decoded_text('decode_str_unsigned', 0xbd000900) == '[0,8,8,4]'
	assert decoded_text('decode_load_unsigned', 0xf9000900) == 'null'
}

fn test_pairs_and_unscaled_signed_offsets() {
	assert decoded_text('decode_ldp_x', 0xa97f0500) == '[0,1,8,-16]'
	assert decoded_text('decode_pair_q', 0xad3f0500) == '["store",0,1,8,-32]'
	assert decoded_text('decode_stur_x', 0xf81f8100) == '[0,8,-8]'
	assert decoded_text('decode_stur_d', 0xfc1f8100) == '[0,8,-8]'
}

fn test_shifted_register_reserved_predicates() {
	assert decoded_text('decode_add_register', 0x8bc10102) == '[2,8,1,0]'
	assert decoded_text('decode_register_copy', 0x2a0103e2) == '[2,1,4]'
	assert decoded_text('decode_register_copy', 0xaa0103e2) == '[2,1,8]'
	assert decoded_text('decode_orr_register', 0x2a0103e2) == '[2,31,1]'
	assert decoded_text('decode_orr_register', 0x2a0107e2) == 'null'
}

fn test_logical_immediates_expand_full_unsigned_width() {
	assert decoded_text('decode_logical_immediate_w', 0x32001be8) == '["orr",8,31,127]'
	assert decoded_text('decode_logical_immediate_x', 0xb240fbe8) == '["orr",8,31,9223372036854775807]'
	assert decoded_text('decode_logical_immediate_x', 0xb240ffe8) == 'null'
	assert decoded_text('decode_logical_immediate_w', 0x3200ffe8) == 'null'
}

fn test_branch_width_and_signed_unbounded_local_addresses() {
	assert j.encode(decode('decode_bl_target', 0x97ffffff, j.Value(0)), false) == '18446744073709551612'
	assert j.encode(decode('decode_local_branch_target', 0x54ffffe0, j.Value(0)), false) == '-4'
	assert j.encode(decode('decode_conditional_branch', 0x54ffffe0, j.Value(0)), false) == '[-4,"eq"]'
	assert j.encode(decode('decode_conditional_branch', 0x5400000e, j.Value(0)), false) == 'null'
	wide := j.Value(j.Number{'18446744073709551616'})
	assert j.encode(decode('decode_local_branch_target', 0x54000020, wide), false) == '18446744073709551620'
	assert j.encode(decode('decode_b_target', 0x14000001, wide), false) == '4'
}

fn test_adrp_wraps_page_arithmetic() {
	assert j.encode(decode('decode_adrp', 0xf0ffffe8, j.Value(0)), false) == '[8,18446744073709547520]'
	assert j.encode(decode('decode_adrp', 0x90000008, j.Value(0x1234)), false) == '[8,4096]'
}

fn test_materialized_constant_preserves_original_global_fallback() {
	code := pack([u32(0xd2800028), 0xd2800029])
	assert j.encode(j.Value(find_materialized_constant(code, j.Value(1))), false) == '[[0,4,8]]'
	updated := pack([u32(0xd2800028), 0xf2a00028])
	assert j.encode(j.Value(find_materialized_constant(updated, j.Value(65537))), false) == '[[0,8,8]]'
}

fn test_constant_targets_keep_typed_numeric_equality() {
	code := pack([u32(0xd2800028)])
	for token in ['1', '1.0', '1e0', 'true'] {
		assert find_materialized_constant(code, j.decode(token)!).len == 1
	}
	for token in ['"1"', 'false', 'null', '1.5', '-1', '[]', '{}'] {
		assert find_materialized_constant(code, j.decode(token)!).len == 0
	}
	assert !equal_integer(~u64(0), j.decode('1.8446744073709552e19')!)
	assert equal_integer(u64(1) << 63, j.decode('9.223372036854776e18')!)
	assert equal_integer(0, j.decode('-0.0')!)
}

fn test_constant_register_rejects_runtime_writers() {
	items := words(pack([u32(0x52800028), 0x11000509]))
	assert resolve_static_w_register(items, 2, 9, 0)? == 2
	assert resolve_static_x_register(words(pack([u32(0x92800000)])), 1, 0, 0)? == ~u64(0)
	assert resolve_static_w_register(words(pack([u32(0x52800028), 0xb9400108])), 2, 8, 0) == none
	assert resolve_static_w_register(items, 2, 9, 9) == none
}

fn test_constant_register_call_clobber_and_dead_path() {
	items := words(pack([u32(0x52800028), 0x94000001, 0x14000003, 0x94000001, 0xd503201f]))
	assert resolve_static_w_register(items, 5, 8, 0) == none
	dead := words(pack([u32(0x52800028), 0x94000001, 0x14000003, 0xd503201f]))
	assert resolve_static_w_register(dead, 3, 8, 0)? == 1
	assert resolve_static_x_register(dead, 4, 8, 0) == none
}

fn test_store_covering_spans_include_pairs_and_vectors() {
	code := pack([u32(0xf9000500), 0xad000500, 0xf81f8100])
	assert stores_covering(code, 8, 15) == [0, 4]
	assert stores_covering(code, 8, 31) == [4]
	assert stores_covering(code, 8, -1) == [8]
	assert stores_covering(code, 9, 15).len == 0
	assert stores_covering(code, 8, 32).len == 0
}

fn test_utf8_replacement_consumes_only_valid_prefixes() {
	assert utf8_replace([u8(0xf0), 0x90, 0x80]) == '�'
	assert utf8_replace([u8(0xe0), 0x80, 0x80]) == '���'
	assert utf8_replace([u8(0xed), 0xa0, 0x80]) == '���'
	assert utf8_replace([u8(0xe1), 0x80, `x`]) == '�x'
	assert utf8_replace([u8(0xc2), 0xa3, 0]) == '£\x00'
}

fn test_instruction_sequences_allow_unaligned_matches_and_empty() {
	mut code := [u8(1)]
	code << pack([u32(0x12345678)])
	require_instruction_sequence(code, 'fixture', [u32(0x12345678)])!
	require_instruction_sequence(code, 'fixture', []u32{})!
	require_instruction_sequence(code, 'fixture', [u32(0)]) or {
		assert err.msg() == 'missing fixture instruction sequence'
		return
	}
	assert false
}

fn test_instruction_word_failures_keep_exact_labels_and_offsets() {
	code := pack([u32(1)])
	require_instruction_words_at(code, 'fixture', {
		0: u32(2)
	}) or {
		assert err.msg() == 'unexpected fixture instruction at 0x0: 0x00000001, expected 0x00000002'
		return
	}
	assert false
}

fn test_authenticated_rebase_preserves_top_bit_predicate() {
	assert decode_kernel_auth_rebase(j.Value(u64(0x8000000012345678)))! == kernel_collection_base + 0x12345678
	assert find_authenticated_target_references([u8(0)], j.Value(0)).len == 0
	decode_kernel_auth_rebase(j.Value(u64(0xc000000000000001))) or {
		assert err.msg() == 'not an authenticated kernel rebase: 0xc000000000000001'
		return
	}
	assert false
}

fn test_macho_header_and_uuid_validation() {
	mut data := pack([image.macho_magic_64, u32(0), 0, 0, 0, 0, 0, 0])
	assert j.encode(macho_uuid(data)!, false) == 'null'
	data[16] = 1
	data[20] = 8
	data << pack([image.lc_uuid, u32(8)])
	macho_uuid(data) or {
		assert err.msg() == 'truncated LC_UUID'
		return
	}
	assert false
}

fn test_missing_symbol_table_remains_distinct_from_bad_header() {
	data := pack([image.macho_magic_64, u32(0), 0, 0, 0, 0, 0, 0])
	macho_symbols(data) or {
		assert err.msg() == 'Mach-O has no symbol table'
		return
	}
	assert false
}

fn test_unmapped_virtual_address_keeps_arbitrary_width() {
	data := pack([image.macho_magic_64, u32(0), 0, 0, 0, 0, 0, 0])
	virtual_to_file(data, big.integer_from_string('-18446744073709551616')!) or {
		assert err.msg() == 'virtual address -0x10000000000000000 is not backed by a Mach-O segment'
		return
	}
	assert false
}
