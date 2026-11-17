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
	assert os.args.len == 3, 'usage: run host|negative|measure|native EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/')
	if os.args[1] == 'native' {
		_ = run(['run', repo + '/tests/drm-timeline-signal/check.v',
			'/Users/alex/.local/state/vinix/omarchy-m1-syncobj-query-20261117/bundle', state], state + '/native-check.log', 0)!
		println('Native timeline SIGNAL guards pass on both architectures.')
		return
	}
	assert !os.exists(state)
	os.mkdir_all(state)!
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	if os.args[1] == 'negative' {
		source := os.read_file(repo + '/kernel/drm/syncobj_timeline_signal.v')!
		for index, pair in [
			['syncobj.release_chain_reservation(unsafe { chains[index] })', '// omitted reservation cleanup'],
			['payload := syncobj.shared_timeline_stub()', 'payload := syncobj.shared_timeline_stub()\n\tfor index := u32(0); index < count; index++ { syncobj.replace_fence(unsafe { &syncobj.SyncObj(buffer.objects[index]) }, unsafe { nil }) }'],
			['if request.points == 0 { unsafe { C.memset(points_storage, 0, bytes) } }', 'if request.points == 0 { return -14 }'],
		] {
			assert source.count(pair[0]) == 1
			path := state + '/mutant-${index}.v'
			os.write_file(path, source.replace(pair[0], pair[1]))!
			os.setenv('DRM_TIMELINE_SIGNAL_SOURCE', path, true)
			os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/case-${index}', true)
			os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/case-${index}.c', true)
			out := run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/case-${index}.log', 1)!
			assert os.exists(state + '/case-${index}'), 'negative must compile'
			assert out.contains(['assert memory.outstanding() == before', 'assert !syncobj.is_signaled(current(obj))', 'null points must synthesize zeroes'][index])
		}
		println('Three compiled timeline SIGNAL negatives fail designated reservation cleanup, pending-prefix and null-points assertions.')
		return
	}
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/drm-wait', true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/drm-wait.c', true)
	if os.args[1] == 'measure' {
		os.setenv('DRM_TIMELINE_SIGNAL_MEASURE', '1', true)
		_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/measure.log', 0)!
		println('Nine warmed failure-reservation batches retain zero malloc blocks and bytes; published metadata excluded.')
		return
	}
	assert os.args[1] == 'host'
	_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/drm-wait.log', 0)!
	_ = run(['run', repo + '/tests/drm-timeline-signal/reference.v',
		'/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117/references/linux', state + '/drm-wait', state + '/reference'], state + '/reference.log', 0)!
	println('Sanitized timeline SIGNAL and full DRM regression suites, pinned compiled oracle and unchanged prior bundle checks pass.')
}
