// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_timestamp_inputs_local(native string) ! {
	require(native.contains('return mgr.prepare_g13_render_job_with_timestamps(resources, input, [2]u64{}, [2]u64{})'), 'Legacy render must provide empty user destinations')!
	require(native.contains('return mgr.prepare_g13_compute_job_with_timestamps(resources, ctx, input, [2]u64{})'), 'Legacy compute must provide empty user destinations')!
	for kind in ['vertex', 'fragment', 'compute'] {
		pair := if kind == 'compute' { 'user_timestamps' } else { kind + '_user_timestamps' }
		require(native.contains(kind + '_timestamps := input.has_result || ' + pair + '[0] != 0 || ' + pair + '[1] != 0'), 'Timestamp selection must accept either phase independently: ' + kind)!
		require(native.count('if ' + kind + '_timestamps {') == 4, 'Both size variants and both timestamp instructions must use the same engine selection: ' + kind)!
		command := if kind == 'compute' { 'command' } else { kind }
		require(native.count('write_g13_timestamp_pair(voidptr(u64(job.' + command + '.cpu_address()) + ' + kind + '_user_ts_offset), ' + pair + ')') == 1, 'Resolved destinations must bind to their own command: ' + kind)!
	}
	render := section(native, 'pub fn (mut mgr GpuManager) prepare_g13_render_job_with_timestamps(', 'fn (mut mgr GpuManager) publish_g13_render_job_locked(', 'Render timestamp command population')!
	require_order(render, ['fw.make_g13_vertex_v13_5(', 'fw.make_g13_fragment_v13_5(',
		'write_g13_timestamp_pair(voidptr(u64(job.vertex', 'write_g13_timestamp_pair(voidptr(u64(job.fragment',
		'mgr.flush_g13_kernel_buffer(&job.vertex)', 'mgr.flush_g13_kernel_buffer(&job.fragment)'], 'Version conversion precedes destination writes and publication flushes')!
	compute := section(native, 'pub fn (mut mgr GpuManager) prepare_g13_compute_job_with_timestamps(', 'pub fn (mut mgr GpuManager) release_g13_compute_job(', 'Compute timestamp command population')!
	require_order(compute, ['fw.make_g13_compute_v13_5(', 'write_g13_timestamp_pair(voidptr(u64(job.command',
		'mgr.flush_g13_kernel_buffer(&job.command)'], 'Compute conversion precedes destination write and publication flush')!
}

pub fn timestamp_input_sizes_v(microseq string, pair TimestampPairModel) !string {
	require(microseq.contains('pub(crate) struct OpHeader(u32)') && microseq.contains('pub(crate) struct WaitForIdle(OpHeader)') && microseq.contains('pub(crate) struct RetireStamp(OpHeader)'), 'Simple microsequence operations changed')!
	contracts := microseq_field_contracts(microseq)!
	mut out := 'const reference_sizes = [\n'
	for kind in ['vertex', 'fragment', 'compute'] {
		mut sizes := [2]int{init: 8} // WaitForIdle and RetireStamp, both OpHeader
		mut found := 0
		for contract in contracts {
			if contract.kind in ['start_' + kind, 'finalize_' + kind] { sizes[0] += contract.old_size; sizes[1] += contract.new_size; found++ }
		}
		require(found == 2, 'Incomplete timestamp command sequence')!
		out += '[u64(${sizes[0]}), ${sizes[1]}]!,\n'
	}
	out += ']\nconst reference_timestamp_sizes = [u64(${pair.old_size}), ${pair.new_size}]!\n'
	return out
}
