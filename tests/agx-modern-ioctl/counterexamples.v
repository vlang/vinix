// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples ASYNC_RUNNER CLOSE_RUNNER FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[3])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	for index, spec in [
		['kernel/gpu/agx/file/modern_submit.v', 'defer { memory.free(workspace) }', '',
			'--modern-source', 'file.run_modern_submission_checks'],
		['kernel/gpu/agx/file/file.v', 'usc_base: queue.usc_base', 'usc_base: 0', '--file-source',
			'file.run_modern_submission_checks'],
		['kernel/gpu/agx/file/modern.v', 'copy_from_user(storage, data.userptr, bytes)',
			'copy_from_user(storage, data.userptr, data.stride)', '--modern-source',
			'file.check_modern_binding'],
		['kernel/gpu/agx/file/modern.v', 'if f.ioctl_abi != 0 && f.ioctl_abi != abi', 'if false',
			'--modern-source', 'file.check_modern_transport'],
	] {
		folder := state + '/case-' + index.str()
		os.mkdir_all(folder)!
		source := os.read_file(repo + '/' + spec[0])!
		assert source.contains(spec[1])
		path := folder + '/mutated.v'
		os.write_file(path, source.replace(spec[1], spec[2]))!
		async_case := index < 2
		os.setenv(if async_case { 'AGX_ASYNC_TEST_BINARY' } else { 'AGX_CLOSE_TEST_BINARY' }, folder + '/test', true)
		os.setenv(if async_case { 'AGX_ASYNC_TEST_C' } else { 'AGX_CLOSE_TEST_C' }, folder + '/test.c', true)
		mut p := os.new_process(os.abs_path(os.args[if async_case { 1 } else { 2 }]))
		p.set_args([spec[3], path])
		p.set_redirect_stdio_merged()
		p.run()
		out := p.stdout_slurp()
		p.wait()
		code := p.code
		p.close()
		os.write_file(folder + '/output.log', out)!
		assert code != 0 && os.is_file(folder + '/test') && out.contains('FAIL: fn ' + spec[4]), folder
		println('case-${index}: compiled; designated modern ABI/copy/USC/cleanup assertion rejected')
	}
}
