module g13contract

import g13layout
import os

fn test_tib_contract_rejects_legacy_input_rounding_overflow_and_reference_drift() {
	root := g13layout.repo_root()
	local := os.read_file(root + '/kernel/gpu/agx/gpu/g13.v')!
	firmware := os.read_file(root + '/kernel/gpu/agx/fw/fragment.v')!
	reference := 'let pixels_per_utile: u32 = (cmdbuf.utile_width_px as u32) * (cmdbuf.utile_height_px as u32);\n' +
		'let samples_per_utile: u32 = pixels_per_utile << samples_log2;\n' +
		'let utile_size_bytes: u32 = (cmdbuf.sample_size_B as u32) * samples_per_utile;\n' +
		'let block_size_bytes: u32 = 2048;\n' +
		'let blocks_per_utile: u32 = utile_size_bytes.div_ceil(block_size_bytes);\n' +
		'job_params2 <- tib_blocks: blocks_per_utile, job_params3 <- tib_blocks: blocks_per_utile'
	check_fragment_tib_contract(local, firmware, reference)!
	for token in ['tib_blocks: blocks_per_utile', 'input.samples, input.sample_size) or { return none }'] {
		if _ := check_fragment_tib_contract(local.replace(token, 'tib_blocks: input.tib_blocks'), firmware, reference) { assert false }
	}
	for token in ['u64(utile_width)', 'bytes + 2047', 'if blocks > u64(~u32(0)) { return none }'] {
		if _ := check_fragment_tib_contract(local, firmware.replace(token, ''), reference) { assert false }
	}
	if _ := check_fragment_tib_contract(local, firmware, reference.replace('2048', '4096')) { assert false }
}
