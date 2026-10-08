module t6050power

import os
import traceanalysis as j

struct FixtureEvidence {
	strings map[string]j.Value
	tables  []u32
}

fn (source FixtureEvidence) read_cstring(body Function, adrp_offset int, add_offset int) !string {
	_ = body
	_ = add_offset
	value := source.strings[adrp_offset.str()] or {
		return error('missing fixture string')
	}
	return j.string_value(value)
}

fn (source FixtureEvidence) read_table(address u64, count int) ![]u32 {
	_ = address
	_ = count
	return source.tables.clone()
}

fn check_image_proof_family(name string) ! {
	controls := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/image-proofs.json'))!)!.arr()
	mut checked := 0
	for item in controls {
		control := item.as_map()
		if j.string_value(j.value(control, 'function')) != name { continue }
		provider := j.value(control, 'provider').as_map()
		reader := FixtureEvidence{j.value(provider, 'strings').as_map(), j.value(provider, 'tables').arr().map(u32(it.u64()))}
		actual := query_evidence(reader, name, j.value(control, 'arguments').as_map()) or {
			assert err.msg() == j.string_value(j.value(control, 'error'))
			assert j.value(control, 'kind') == j.Value('ValueError')
			checked++
			continue
		}
		assert 'result' in control
		assert j.encode(actual, false) == j.encode(j.value(control, 'result'), false)
		checked++
	}
	assert checked != 0
}

fn test_original_pmgr_interrupt_property_and_ready_name() {
	check_image_proof_family('recover_pmgr_interrupt_config')!
}

fn test_original_rtbuddy_firmware_provenance_and_service_selection() {
	check_image_proof_family('recover_rtbuddy_firmware_source_contract')!
}

fn test_original_apple_a7iop_wrapper_and_sram_resource_ownership() {
	check_image_proof_family('recover_apple_a7iop_code_contract')!
}

fn test_original_rtkit_identity_block_candidates_and_patchbay_walk() {
	check_image_proof_family('recover_rtbuddy_patchbay_contract')!
}

fn test_candidate_order_helpers_leave_reader_storage_unchanged() {
	words := [u32(8), u32(4), u32(8), u32(12)]
	assert unique_words(words) == [u32(8), u32(4), u32(12)]
	assert sorted_words(words) == [u32(4), u32(8), u32(8), u32(12)]
	assert words == [u32(8), u32(4), u32(8), u32(12)]
}

fn test_branch_presence_keeps_short_reads_and_arbitrary_addresses_bounded() {
	assert !branch_at_present(Function{j.Value(0), []u8{}}, 0)!
	assert !branch_at_present(Function{j.Value('bad'), encoded_words([u32(0xd503201f)])}, 0)!
	assert branch_at_present(Function{j.Value(j.Number{'123456789012345678901234567890'}), encoded_words([u32(0x94000001)])}, 0)!
	assert !branch_at_present(Function{j.Value(0), encoded_words([u32(0x94000001)])}, -4)!
}
