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
	assert os.args.len == 3, 'usage: run host|negative|native EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/')
	if os.args[1] == 'native' {
		_ = run(['run', repo + '/tests/drm-syncobj-query/check.v',
			'/Users/alex/.local/state/vinix/omarchy-m1-timeline-chain-20261117/bundle/qualified', state], state + '/native-check.log', 0)!
		println('Both native QUERY C guards and nineteen unchanged ownership/completion paths pass.')
		return
	}
	assert !os.exists(state)
	os.mkdir_all(state)!
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	if os.args[1] == 'negative' {
		source := os.read_file(repo + '/kernel/drm/syncobj_query.v')!
		for index, pair in [
			['}, last_submitted)', '}, true)'],
			['defer { buffer.free_owned() }', '// omitted cleanup'],
			['or { return -2 }', 'or { unsafe { nil } }'],
		] {
			assert source.count(pair[0]) == 1
			path := state + '/mutant-${index}.v'
			os.write_file(path, source.replace(pair[0], pair[1]))!
			os.setenv('DRM_QUERY_SOURCE', path, true)
			os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/case-${index}', true)
			os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/case-${index}.c', true)
			out := run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/case-${index}.log', 1)!
			assert os.exists(state + '/case-${index}')
			assert out.contains(['assert points[index] == expected', 'assert memory.outstanding() == before', 'assert ioctl_syncobj_query(voidptr(11), unsafe { &request }) == -2'][index])
		}
		println('Three compiled QUERY negatives fail designated progress, owned-buffer cleanup and all-handles-before-output assertions.')
		return
	}
	assert os.args[1] == 'host'
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/drm-wait', true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/drm-wait.c', true)
	_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/drm-wait.log', 0)!
	_ = run(['run', repo + '/tests/drm-syncobj-query/reference.v',
		'/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117/references/linux', state + '/drm-wait', state + '/reference'], state + '/reference.log', 0)!
	println('Sanitized QUERY and full DRM regression suites pass; pinned compiled query/chain oracle and complete prior bundle checks pass.')
}
