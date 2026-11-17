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
		_ = run(['run', repo + '/tests/drm-binary-transfer/check.v',
			'/Users/alex/.local/state/vinix/omarchy-m1-timeline-wait-20261117/bundle', state], state + '/native-check.log', 0)!
		println('Native binary TRANSFER guards pass on both architectures.')
		return
	}
	assert !os.exists(state)
	os.mkdir_all(state)!
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	if os.args[1] == 'negative' {
		for index, spec in [
			['kernel/drm/syncobj_find.v', 'defer { syncobj.release_timeline_capture(capture) }', '', 'DRM_SYNCOBJ_FIND_SOURCE', 'transfer capture must detach before returning'],
			['kernel/drm/syncobj_transfer.v', 'syncobj.replace_fence(destination, source.fence)', 'syncobj.replace_fence(destination, syncobj.shared_timeline_stub())', 'DRM_SYNCOBJ_TRANSFER_SOURCE', 'current(bt_destination) == bt_leaf'],
			['kernel/drm/syncobj_find.v', 'capture, point,', 'capture, u64(0),', 'DRM_SYNCOBJ_FIND_SOURCE', 'ioctl_syncobj_transfer(voidptr(11), unsafe { &request }) == -22'],
		] {
			source := os.read_file(repo + '/' + spec[0])!
			assert source.contains(spec[1])
			path := state + '/mutant-${index}.v'
			os.write_file(path, source.replace(spec[1], spec[2]))!
			os.setenv(spec[3], path, true)
			os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/case-${index}', true)
			os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/case-${index}.c', true)
			out := run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/case-${index}.log', 1)!
			assert os.exists(state + '/case-${index}'), 'negative must compile'
			assert out.contains(spec[4]) || (index == 0 && out.contains('AddressSanitizer: stack-use-after-return')), out
			os.unsetenv(spec[3])
		}
		println('Three compiled binary TRANSFER negatives fail designated stack-borrow cleanup, exact pending payload and source-point assertions.')
		return
	}
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/drm-wait', true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/drm-wait.c', true)
	if os.args[1] == 'measure' {
		os.setenv('DRM_BINARY_TRANSFER_MEASURE', '1', true)
		_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/measure.log', 0)!
		println('Warmed binary TRANSFER batches retain zero malloc blocks and bytes; published metadata excluded.')
		return
	}
	assert os.args[1] == 'host'
	_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/drm-wait.log', 0)!
	_ = run(['run', repo + '/tests/drm-binary-transfer/reference.v',
		'/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117/references/linux', state + '/drm-wait', state + '/reference'], state + '/reference.log', 0)!
	println('Sanitized binary TRANSFER and full DRM regression suites, pinned compiled oracle and unchanged prior bundle checks pass.')
}
