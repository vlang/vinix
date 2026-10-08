module t6050power

import traceanalysis as j

fn call_offsets(body Function, target j.Value) ![]int {
	mut offsets := []int{}
	for offset := 0; offset <= body.code.len - 4; offset += 4 {
		if branch_at_equal(body, offset, target)! { offsets << offset }
	}
	return offsets
}

fn unique_call_offset(body Function, target j.Value, diagnostic string) !int {
	offsets := call_offsets(body, target)!
	if offsets.len != 1 { return error(diagnostic) }
	return offsets[0]
}

fn sorted_offsets(offsets []int) []int {
	mut ordered := offsets.clone()
	ordered.sort()
	return ordered
}

fn words_at_offsets(code []u8, expected map[int]u32) bool {
	for offset, word in expected {
		if offset < 0 || offset > code.len - 4 || word_at(code, offset) != word { return false }
	}
	return true
}

fn all_calls_at(body Function, offsets []int, target j.Value) !bool {
	for offset in offsets {
		if !branch_at_equal(body, offset, target)! { return false }
	}
	return true
}

fn word_offsets(code []u8, word u32) []int {
	mut offsets := []int{}
	for offset := 0; offset <= code.len - 4; offset += 4 {
		if word_at(code, offset) == word { offsets << offset }
	}
	return offsets
}

fn python_word_at(code []u8, offset int) u32 {
	// Callers subtract four from a decoded in-bounds branch offset. Python's
	// unpack_from permits -4, meaning the final word in that same buffer.
	actual := if offset < 0 { code.len + offset } else { offset }
	return word_at(code, actual)
}

struct MandatoryPatch {
	tag        string
	property   string
	node       string
	derivation string
	offset     u32
	checked    bool
}

fn mandatory_patch_metadata() []j.Value {
	patches := [
		MandatoryPatch{'BDID', 'board-id', pmp_chosen_path, 'value', 0xc8, true},
		MandatoryPatch{'DVID', 'dram-vendor-id', pmp_chosen_path, 'value', 0xcc, true},
		MandatoryPatch{'DCAP', 'dram-capacity', pmp_provider_node, 'value', 0xd0, false},
		MandatoryPatch{'DCHD', 'dram-channel-disable', pmp_provider_node, 'value', 0xd4, false},
		MandatoryPatch{'PMC_', 'pmc', pmp_pmgr_path, 'value', 0xd8, true},
		MandatoryPatch{'PMCV', 'pmc-pmgr', pmp_pmgr_path, 'value & 1', 0xdc, true},
		MandatoryPatch{'PMCB', 'pmc-pmgr', pmp_pmgr_path, '(value >> 3) & 1', 0xe0, true},
		MandatoryPatch{'PMCX', 'pmc-msg-disabled', pmp_provider_node, 'value', 0xe4, false},
		MandatoryPatch{'CVAR', 'soc-chip-variant', pmp_provider_node, 'value', 0xe8, false},
	]
	mut result := []j.Value{cap: patches.len}
	for patch in patches {
		result << j.Value(map[string]j.Value{
			'tag':                   j.Value(patch.tag)
			'property':              j.Value(patch.property)
			'node':                  j.Value(patch.node)
			'derivation':            j.Value(patch.derivation)
			'service_object_offset': j.Value(patch.offset)
			'value_bits':            j.Value(32)
			'rejects_wrong_width':   j.Value(patch.checked)
		})
	}
	return result
}
