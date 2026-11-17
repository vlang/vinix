// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_job_dependencies(copy string, file string) ! {
	require_order(copy, ['code, copied := copy_sync_array(source)', 'if code != 0',
		'incoming := source.item(index)', 'if incoming.fence == unsafe { nil } { continue }', 'existing < count',
		'previous.context != incoming.fence.context', 'incoming.fence.seqno > previous.seqno', 'break',
		'if !replace { continue }', 'copied.items[target] = incoming', 'copied.fences[target] = incoming.fence',
		'if target == count { count++ }', 'copied.count = count', 'return 0, copied'], 'Private stable-context dedup with latest unsigned sequence and first ties')!
	require(!copy.contains('memory.') && !copy.contains('free('), 'Reduction must add no allocator or metadata-release operation')!
	stage := section(file, 'fn (mut f GpuFile) submit_g13_staged(', 'fn dispatch(', 'G13 dependency capture')!
	require_order(stage, ['g13_submission_status()', 'agxsubmission.copy_job_dependencies(input_syncs)',
		'defer { if !dependencies_transferred { agxsubmission.release_sync_array(pending_inputs) } }',
		'f.new_g13_submission_timestamps(commands)', 'dependencies: pending_inputs', 'dependencies_transferred = true'], 'Reduction before publication with unchanged pending ownership')!
}

fn test_job_dependency_dedup_ownership_and_integration() {
	r := g13layout.repo_root(); c := read(r + '/kernel/gpu/agx/submission/dependencies.v')!; f := read(r + '/kernel/gpu/agx/file/file.v')!
	check_job_dependencies(c, f)!
	for token in ['code, copied := copy_sync_array(source)', 'if incoming.fence == unsafe { nil } { continue }',
		'previous.context != incoming.fence.context', 'incoming.fence.seqno > previous.seqno', 'copied.count = count'] {
		if _ := check_job_dependencies(c.replace(token, ''), f) { assert false, token }
	}
	if _ := check_job_dependencies(c, f.replace('agxsubmission.copy_job_dependencies(input_syncs)', 'agxsubmission.copy_sync_array(input_syncs)')) { assert false }
}
