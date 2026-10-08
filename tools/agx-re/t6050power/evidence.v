module t6050power

import appleadt as a
import g17decode as g
import math.big
import traceanalysis as j

// Primitive readers are called only during a synchronous instruction proof.
// Returned metadata owns its strings/tables and never contains the provider.
pub interface EvidenceReader {
	read_cstring(body Function, adrp_offset int, add_offset int) !string
	read_table(address u64, count int) ![]u32
}

pub struct MachOEvidence {
pub:
	image []u8
}

pub fn (source MachOEvidence) read_cstring(body Function, adrp_offset int, add_offset int) !string {
	return g.read_adrp_add_cstring(source.image, body.address, body.code, adrp_offset, add_offset)!
}

pub fn (source MachOEvidence) read_table(address u64, count int) ![]u32 {
	return g.read_virtual_u32_table(source.image, big.integer_from_u64(address), big.integer_from_int(count))!
}

struct PropertyProof {
	offset   int
	expected string
}

fn sorted_words(words []u32) []u32 {
	mut sorted := words.clone()
	sorted.sort()
	return sorted
}

fn unique_words(words []u32) []u32 {
	mut seen := map[u32]bool{}
	mut result := []u32{}
	for word in words {
		if word !in seen {
			seen[word] = true
			result << word
		}
	}
	return result
}

fn branch_at_present(body Function, offset int) !bool {
	if offset < 0 || offset > body.code.len - 4 { return false }
	if word_at(body.code, offset) & 0x7c000000 != 0x14000000 { return false }
	branch_count(Function{body.address, encoded_words([word_at(body.code, offset)])}, j.Value(0))!
	a.direct_branch_target_at(body.address, body.code, offset) or { return false }
	return true
}

pub fn query_evidence(reader EvidenceReader, operation string, request map[string]j.Value) !j.Value {
	functions := functions_from_json(j.value(request, 'functions'))!
	result := match operation {
		'recover_pmgr_interrupt_config' {
			recover_pmgr_interrupt_config_evidence(reader, functions)!
		}
		'recover_rtbuddy_patchbay_contract' {
			recover_rtbuddy_patchbay_contract_evidence(reader, functions, j.value(request, 'symbols').as_map())!
		}
		'recover_rtbuddy_firmware_source_contract' {
			recover_rtbuddy_firmware_source_contract_evidence(reader, functions, j.value(request, 'symbols').as_map(), j.value(request, 'preload_vtable_target'))!
		}
		'recover_apple_a7iop_code_contract' {
			recover_apple_a7iop_code_contract_evidence(reader, functions, j.value(request, 'vtable_targets').as_map())!
		}
		else { return error('unknown T6050 image evidence operation ${operation}') }
	}
	return j.Value(result)
}

pub fn query_image(data []u8, operation string, request map[string]j.Value) !j.Value {
	if operation in ['_macho_segment_table', 'recover_t6050_pmp_patchbay'] {
		return query_patchbay(data, operation, request)!
	}
	if operation in ['recover_t6050_power', 'recover_t6050_pmp_darts'] {
		return query_topology(operation, request)!
	}
	if operation in ['recover_pmgr_interrupt_config', 'recover_rtbuddy_patchbay_contract',
		'recover_rtbuddy_firmware_source_contract', 'recover_apple_a7iop_code_contract'] {
		return query_evidence(MachOEvidence{data}, operation, request)!
	}
	return query(operation, request)
}
