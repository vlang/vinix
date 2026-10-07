module g13layout

import os

const old_target = Target{ version: 'V12_3' }
const new_target = Target{ version: 'V13_5' }
const sample = '
#[versions(AGX)]
const IO_MAPPING_COUNT: usize = {
    #[ver(V < V13_0B4)]
    {
        0x14
    }
    #[ver(V >= V13_0B4)]
    {
        0x19
    }
};
#[repr(C)]
pub(crate) struct IOMapping {
    pub(crate) phys_addr: U64,
    pub(crate) virt_addr: U64,
    pub(crate) total_size: u32,
    pub(crate) element_size: u32,
    pub(crate) readwrite: U64,
}
#[versions(AGX)]
#[repr(C)]
pub(crate) struct Sample {
    pub(crate) first: u32,
    #[ver(V >= V13_0B4)]
    pub(crate) added: u32,
    #[ver(V < V13_0B4)]
    pub(crate) removed: Pad<0x8>,
    pub(crate) mappings: Array<IO_MAPPING_COUNT::ver, IOMapping>,
    pub(crate) native: [u32; 0x4],
}
'
const initdata_sample = '
    raw.unk_b38_4 = 1;
    #[ver(V >= V13_0B4 && V < V13_3)]
    raw.unk_c3c = 0x19;
    #[ver(V >= V13_3)]
    raw.unk_c3c = 0x1a;
    #[ver(V >= V13_0B4)]
    raw.avg_power_target_filter_tc_clks =
        period_ms * cfg.avg_power_target_filter_tc * base_clock_khz;
    raw.not_gated = 7;
'

fn lookup_field(layout Layout, name string) Member {
	for field in layout.fields { if field.name == name { return field } }
	panic('missing member ${name}')
}

fn test_default_input_uses_the_configurable_m1n1_checkout() {
	assert default_raw_rs() == os.join_path(default_m1n1(), 'rust/src/gpu/raw.rs')
}

fn test_generated_output_is_relative_to_the_script_not_the_cwd() {
	assert os.is_abs_path(default_output())
	assert default_output() == os.join_path(repo_root(), 'kernel/gpu/agx/fw/g13_initdata_layout.v')
}

fn test_extracts_a_simple_gate() {
	assert extract_gate('    #[ver(V >= V13_0B4)]')! == 'V >= V13_0B4'
}

fn test_extracts_a_nested_gate() {
	assert extract_gate('    #[ver((G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3))]')! == '(G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3)'
}

fn test_a_line_without_a_gate_yields_none() {
	assert extract_gate('    pub(crate) unk_10e50: u32,')! == ''
}

fn test_an_unterminated_gate_is_an_error() {
	if _ := extract_gate('    #[ver(V >= V13_0B4') {
		assert false
	} else {
		assert err.msg().contains('unterminated')
	}
}

fn test_comparisons_order_by_the_version_axis() {
	assert evaluate('V >= V12_3', old_target)!
	assert !evaluate('V >= V13_0B4', old_target)!
	assert evaluate('V >= V13_0B4', new_target)!
	assert evaluate('V < V13_0B4', old_target)!
}

fn test_conjunction_and_disjunction() {
	assert !evaluate('V >= V13_0B4 && V < V13_3', old_target)!
	assert !evaluate('V >= V13_0B4 && V < V13_3', new_target)!
	assert evaluate('V < V13_0B4 || V >= V13_5', old_target)!
	assert evaluate('V < V13_0B4 || V >= V13_5', new_target)!
}

fn test_the_nested_globals_pad_gate() {
	gate := '(G >= G14X && V < V13_3) || (G <= G14 && V >= V13_3)'
	assert !evaluate(gate, old_target)!
	assert evaluate(gate, new_target)!
}

fn test_absent_gate_is_unconditional() {
	assert evaluate('', old_target)!
}

fn test_unknown_axis_is_rejected_rather_than_assumed() {
	if _ := evaluate('Q >= V13_5', old_target) {
		assert false
	}
}

fn test_repr_c_alignment_matches_the_known_iomapping_size() {
	defs := parse(sample)!
	assert defs.lay_out('IOMapping', old_target)!.size == 0x20
}

fn test_versioned_const_selects_the_array_length() {
	defs := parse(sample)!
	assert lookup_field(defs.lay_out('Sample', old_target)!, 'mappings').size == 0x14 * 0x20
	assert lookup_field(defs.lay_out('Sample', new_target)!, 'mappings').size == 0x19 * 0x20
}

fn test_gated_fields_appear_and_disappear() {
	defs := parse(sample)!
	old := defs.lay_out('Sample', old_target)!.fields.map(it.name)
	new := defs.lay_out('Sample', new_target)!.fields.map(it.name)
	assert 'removed' in old
	assert 'added' !in old
	assert 'added' in new
	assert 'removed' !in new
}

fn test_native_rust_arrays_are_sized() {
	defs := parse(sample)!
	assert lookup_field(defs.lay_out('Sample', old_target)!, 'native').size == 0x10
}

fn test_unknown_type_is_an_error() {
	defs := parse(sample)!
	if _, _ := defs.size_align('Mystery', old_target) {
		assert false
	} else {
		assert err.msg().contains('unknown type')
	}
}

fn test_gated_assignment_picks_the_arm_for_13_5() {
	assert assignment_for(initdata_sample, 'unk_c3c')! == '0x1a'
}

fn test_ungated_assignment_is_taken_as_is() {
	assert assignment_for(initdata_sample, 'not_gated')! == '7'
	assert assignment_for(initdata_sample, 'unk_b38_4')! == '1'
}

fn test_assignment_spanning_lines_is_joined() {
	assert assignment_for(initdata_sample, 'avg_power_target_filter_tc_clks')! == 'period_ms * cfg.avg_power_target_filter_tc * base_clock_khz'
}

fn test_absent_field_has_no_assignment() {
	assert assignment_for(initdata_sample, 'never_here')! == ''
}

fn test_generation_verifies_against_the_tree() {
	if !os.is_file(default_raw_rs()) { return }
	source := generate(default_raw_rs())!
	assert source.contains('g13_v12_3_hw_data_b_size = u64(0xb6c)')
	assert source.contains('g13_v12_3_globals_size = u64(0x11d40)')
	assert source.contains('g13_v12_3_io_mapping_count = u32(20)')
	assert source.contains('g13_v13_5_hw_data_b_size = u64(0x1884)')
	assert source.contains('g13_v13_5_io_mapping_count = u32(25)')
	assert source == os.read_file(default_output())!
}

fn test_a_wrong_expected_size_is_caught() {
	if !os.is_file(default_raw_rs()) { return }
	mut expected := known_v12_3.clone()
	expected['HwDataB'] = 0xb70
	if _ := generate_checked(default_raw_rs(), expected) {
		assert false
	} else {
		assert err.msg().contains('HwDataB')
	}
}

fn test_nested_arrays_and_alignment() {
	defs := parse('struct Nested {\n a: u8,\n b: Array<2, Array<3, u64>>,\n c: [u16; 2],\n}')!
	layout := defs.lay_out('Nested', old_target)!
	assert layout.size == 64
	assert lookup_field(layout, 'b').offset == 8
	assert lookup_field(layout, 'b').size == 48
	assert lookup_field(layout, 'c').offset == 56
}

fn test_layout_sizes_keep_native_64_bit_rust_counts() {
	defs := parse('struct Wide {\n padding: Pad<0x100000000>,\n words: [u64; 0x20000000],\n}')!
	layout := defs.lay_out('Wide', old_target)!
	assert lookup_field(layout, 'padding').size == i64(0x100000000)
	assert lookup_field(layout, 'words').offset == i64(0x100000000)
	assert layout.size == i64(0x200000000)
	assert defs.translate_offset(i64(0x100000000), layout, layout, 'Wide')! == i64(0x100000000)
}

fn test_offset_remaps_recurse_drop_and_reject_changed_opaque_extent() {
	defs := parse('struct Inner {\n a: u32,\n #[ver(V >= V13_3)]\n added: u32,\n b: u32,\n}\nstruct Outer {\n inner: Inner,\n #[ver(V < V13_3)]\n dropped: u32,\n #[ver(V < V13_3)]\n resized: Pad<8>,\n #[ver(V >= V13_3)]\n resized: Pad<16>,\n}')!
	old := defs.lay_out('Outer', old_target)!
	new := defs.lay_out('Outer', new_target)!
	assert defs.translate_offset(4, old, new, 'Outer')! == 8
	if _ := defs.translate_offset(8, old, new, 'Outer') {
		assert false
	} else {
		assert err.code() == 2
	}
	if _ := defs.translate_offset(13, old, new, 'Outer') {
		assert false
	} else {
		assert err.msg().contains('changes size')
	}
	if _ := defs.translate_offset(100, old, new, 'Outer') {
		assert false
	} else {
		assert err.msg().contains('addresses no field')
	}
}

fn test_written_offsets_include_native_16_64_bit_and_helper_arguments() {
	text := 'put32(mut data, 0x10, x) put64(mut data, abi, 0x20, x) put16(mut data, 0x30, x) filter(mut data, abi, 0x40, 0x50, x) filter(mut data, 0x60, 0x70, x) filter(mut data, 0x80, variable, x)'
	assert written_offsets(text, ['put32', 'put64', 'put16'], {
		'filter': 2
	})! == [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70]
}
