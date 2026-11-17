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
		_ = run(['run', repo + '/tests/drm-timeline-transfer/check.v',
			'/Users/alex/.local/state/vinix/omarchy-m1-binary-transfer-20261117/bundle', state], state + '/native-check.log', 0)!
		println('Native timeline TRANSFER guards pass on both architectures.')
		return
	}
	assert !os.exists(state)
	os.mkdir_all(state)!
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	if os.args[1] == 'negative' {
		for index, spec in [
			['kernel/drm/syncobj/merge.v', 'if owned { memory.free(storage) }', 'if false { memory.free(storage) }', 'DRM_MERGE_SOURCE', 'unpublished merge owners must unwind'],
			['kernel/drm/syncobj/merge.v', 'a.seqno > b.seqno', 'a.seqno < b.seqno', 'DRM_MERGE_SOURCE', 'equal contexts keep greatest unsigned seqno'],
			['kernel/drm/syncobj/array.v', 'katomic.cas(mut &f.array_error, i64(1), i64(error_code))', 'katomic.store(mut &f.array_error, i64(error_code))', 'DRM_ARRAY_SOURCE', 'assert get_error(array) == if enabled'],
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
		println('Three compiled timeline TRANSFER negatives fail designated private-table cleanup, latest-sequence dedup and first-error assertions.')
		return
	}
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_BINARY', state + '/drm-wait', true)
	os.setenv('DRM_SYNCOBJ_WAIT_TEST_C', state + '/drm-wait.c', true)
	if os.args[1] == 'measure' {
		os.setenv('DRM_TIMELINE_TRANSFER_MEASURE', '1', true)
		_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/measure.log', 0)!
		println('Warmed timeline TRANSFER batches retain zero malloc blocks and bytes; published metadata excluded.')
		return
	}
	assert os.args[1] == 'host'
	_ = run(['run', repo + '/tests/drm-syncobj-wait/run.v'], state + '/drm-wait.log', 0)!
	_ = run(['run', repo + '/tests/drm-timeline-transfer/reference.v',
		'/Users/alex/.local/state/vinix/omarchy-m1-signoff-20261117/references/linux', state + '/drm-wait', state + '/reference'], state + '/reference.log', 0)!
	println('Sanitized timeline TRANSFER and full DRM regression suites, pinned compiled oracle and unchanged prior bundle checks pass.')
}
