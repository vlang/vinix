// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn run(args []string, log string, expected int) !string {
	mut p := os.new_process(os.getenv_opt('V') or { 'v' })
	p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	os.write_file(log, out)!
	assert p.code == expected, log + ': ' + out
	p.close()
	return out
}

fn main() {
	assert os.args.len == 3, 'usage: verify host|negative|native EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	if os.args[1] == 'native' {
		_ = run(['run', repo + '/tests/drm-timeline-chain/check.v',
			'/Users/alex/.local/state/vinix/omarchy-m1-sync-storage-20261117', state], state + '/native-check.log', 0)!
		_ = run(['run', repo + '/tests/agx-modern-ioctl/check.v', '--selftest', state + '/blob-aarch64.c'], state + '/adapter-check.log', 0)!
		println('Both architecture C guards and the original 18-body adapter guard (including six negative controls) pass.')
		return
	}
	if os.args[1] == 'negative' {
		source := os.read_file(repo + '/kernel/drm/syncobj/chain.v')!
		for index, pair in [
			['(f.chain_prev == unsafe { nil } || katomic.load(&f.chain_prev.signaled))', 'true'],
			['if point == 0 { return fence }', 'if point == 0 { return unsafe { nil } }'],
		] {
			assert source.count(pair[0]) == 1
			path := state + '/mutant-${index}.v'
			os.write_file(path, source.replace(pair[0], pair[1]))!
			os.setenv('CHAIN_SOURCE', path, true)
			out := run(['run', repo + '/tests/drm-timeline-chain/run.v', state + '/case-${index}'], state + '/case-${index}.log', 1)!
			assert os.exists(state + '/case-${index}/check'), 'negative must compile'
			assert out.contains(if index == 0 { 'assert !is_signaled(n3)' } else { 'assert get_chain_fence(&obj, 0)' })
		}
		os.unsetenv('CHAIN_SOURCE')
		storage := os.read_file(repo + '/kernel/gpu/agx/submission/sync_storage.v')!
		token := 'syncobj.release_chain_reservation(chain)'
		assert storage.count(token) == 1
		path := state + '/missing-cleanup.v'
		os.write_file(path, storage.replace(token, '// omitted reservation cleanup'))!
		os.setenv('AGX_ASYNC_TEST_BINARY', state + '/missing-cleanup', true)
		out := run(['run', repo + '/tests/agx-async/run.v', '--sync-storage-source', path], state + '/missing-cleanup.log', 1)!
		assert os.exists(state + '/missing-cleanup') && out.contains('memory.outstanding_chains() == before')
		os.unsetenv('AGX_ASYNC_TEST_BINARY')
		println('Three compiled negatives fail designated cumulative-readiness, zero-snapshot and reservation-cleanup assertions.')
		return
	}
	assert os.args[1] == 'host'
	_ = run(['run', repo + '/tests/drm-timeline-chain/run.v', state + '/host'], state + '/host.log', 0)!
	_ = run(['run', repo + '/tests/drm-timeline-chain/reference.v',
		'/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117/references/linux', state + '/host/check', state + '/reference'], state + '/reference.log', 0)!
	os.setenv('AGX_ASYNC_TEST_BINARY', state + '/async', true)
	os.setenv('AGX_ASYNC_TEST_C', state + '/async.c', true)
	_ = run(['run', repo + '/tests/agx-async/run.v'], state + '/async.log', 0)!
	os.setenv('AGX_ASYNC_TEST_BINARY', state + '/measure', true)
	os.setenv('AGX_ASYNC_TEST_C', state + '/measure.c', true)
	_ = run(['run', repo + '/tests/agx-async/run.v', '--measure-chain'], state + '/measure.log', 0)!
	os.unsetenv('AGX_ASYNC_TEST_BINARY'); os.unsetenv('AGX_ASYNC_TEST_C')
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/drm-wait', true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/drm-wait.c', true)
	_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/drm-wait.log', 0)!
	os.unsetenv('DRM_SYNCOBJ_WAIT_TEST_BINARY'); os.unsetenv('DRM_SYNCOBJ_WAIT_TEST_C')
	os.setenv('DRM_FENCE_TEST_BINARY', state + '/drm-fence', true)
	_ = run(['run', repo + '/tests/drm-fence/run.v'], state + '/drm-fence.log', 0)!
	println('Sanitized chain/oracle/async/DRM/fence checks and unpublished reservation heap measurement pass; binaries, generated C and complete logs preserved.')
}
