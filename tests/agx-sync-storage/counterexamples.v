// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 3, 'usage: counterexamples ASYNC_RUNNER FRESH_EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	for index, spec in [
		['kernel/gpu/agx/submission/modern.v', 'if in_count > ~u32(0) - out_count',
			'if in_count > max_syncs || out_count > max_syncs { return -22, SyncArray{}, SyncArray{} }\n\tif in_count > ~u32(0) - out_count',
			'--modern-sync-source', 'file.run_large_sync_checks',
			'modern sync counts beyond 64 must be accepted'],
		['kernel/gpu/agx/submission/modern.v',
			'if inputs.items != unsafe { nil } { memory.free(voidptr(inputs.items)) }', '',
			'--modern-sync-source', 'file.check_large_sync_failures',
			'failed submit must free dynamic sync storage'],
		['kernel/gpu/agx/submission/sync_storage.v', 'if array.items == unsafe { nil }',
			'if array.count != 0 || array.items == unsafe { nil }', '--sync-storage-source',
			'file.run_large_sync_checks', 'pending dependency copy must own independent storage'],
		['kernel/gpu/agx/file/pending.v', 'submission.release_sync_array(item.dependencies)', '',
			'--pending-source', 'file.run_large_sync_checks',
			'retired pending work must free dynamic dependency storage'],
		['kernel/gpu/agx/file/file.v',
			'defer { if !dependencies_transferred { agxsubmission.release_sync_array(pending_inputs) } }',
			'', '--file-source', 'file.check_large_sync_failures',
			'failed submit must free dynamic sync storage'],
	] {
		folder := state + '/case-' + index.str()
		os.mkdir_all(folder)!
		source := os.read_file(repo + '/' + spec[0])!
		assert source.count(spec[1]) == 1
		os.write_file(folder + '/mutated.v', source.replace(spec[1], spec[2]))!
		os.setenv('AGX_ASYNC_TEST_BINARY', folder + '/test', true)
		os.setenv('AGX_ASYNC_TEST_C', folder + '/test.c', true)
		os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args([spec[3], folder + '/mutated.v'])
		p.set_redirect_stdio_merged()
		p.run()
		output := p.stdout_slurp()
		p.wait()
		code := p.code
		p.close()
		os.write_file(folder + '/output.log', output)!
		assert code != 0 && os.is_file(folder + '/test')
		assert output.contains('FAIL: fn ' + spec[4]) && output.contains(spec[5]), folder
		println('case-${index}: compiled mutation rejected by designated count, staging cleanup, copy ownership, worker free or failure cleanup assertion')
	}
}
