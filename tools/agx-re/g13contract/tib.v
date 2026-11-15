// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_fragment_tib_contract(local string, firmware string, reference string) ! {
	calculation := section(firmware, 'pub fn g13_fragment_tib_blocks(',
		'pub fn g13_fragment_active_size(', 'Vinix fragment TIB calculation')!
	require_order(calculation, ['utile_width == 32 && utile_height == 32',
		'utile_width == 32 && utile_height == 16', 'utile_width == 16 && utile_height == 16',
		'samples != 1 && samples != 2 && samples != 4',
		'bytes := u64(utile_width) * utile_height * samples * sample_size',
		'blocks := (bytes + 2047) / 2048', 'if blocks > u64(~u32(0)) { return none }',
		'return u32(blocks)'], 'Vinix checked fragment TIB calculation')!
	prepare := section(local, 'pub fn (mut mgr GpuManager) prepare_g13_render_job(',
		'pub fn (mut mgr GpuManager) release_g13_render_job(', 'Vinix native TIB sizing')!
	require_order(prepare, ['blocks_per_utile := fw.g13_fragment_tib_blocks(input.utile_width, input.utile_height,',
		'input.samples, input.sample_size) or { return none }', 'mgr.lock.acquire()',
		'job_params_2: fw.G13FragmentJobParameters2{', 'tib_blocks: blocks_per_utile',
		'job_params_3: fw.G13FragmentJobParameters3{', 'tib_blocks: blocks_per_utile',
		'fw.make_g13_fragment_v13_5(fragment, fragment_counter)'], 'Vinix derived TIB sizing before allocation and ABI conversion')!
	require(prepare.count('tib_blocks: blocks_per_utile') == 2 && !prepare.contains('input.tib_blocks'),
		'Native G13 must derive both TIB words rather than trust the redundant legacy field')!
	require_order(reference, ['let pixels_per_utile: u32 =',
		'(cmdbuf.utile_width_px as u32) * (cmdbuf.utile_height_px as u32)',
		'let samples_per_utile: u32 = pixels_per_utile << samples_log2',
		'let utile_size_bytes: u32 = (cmdbuf.sample_size_B as u32) * samples_per_utile',
		'let block_size_bytes: u32 = 2048',
		'let blocks_per_utile: u32 = utile_size_bytes.div_ceil(block_size_bytes)',
		'job_params2 <-', 'tib_blocks: blocks_per_utile',
		'job_params3 <-', 'tib_blocks: blocks_per_utile'], 'Asahi fragment TIB footprint calculation and both command fields')!
}
