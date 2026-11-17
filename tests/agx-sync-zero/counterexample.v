// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 3, 'usage: counterexample ASYNC_RUNNER FRESH_EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	mut old := os.new_process('git')
	old.set_args(['-C', repo, 'show',
		'bf309feea4dc9ef2cde667d02ed83fcc5464216c:kernel/gpu/agx/submission/modern.v'])
	old.set_redirect_stdio_merged()
	old.run()
	source := old.stdout_slurp()
	old.wait()
	assert old.code == 0 && source.contains('drops the captured fence')
	old.close()
	os.write_file(state + '/original-modern.v', source)!
	os.setenv('AGX_ASYNC_TEST_BINARY', state + '/test', true)
	os.setenv('AGX_ASYNC_TEST_C', state + '/test.c', true)
	os.setenv('ASAN_OPTIONS', 'detect_stack_use_after_return=1', true)
	mut negative := os.new_process(os.abs_path(os.args[1]))
	negative.set_args(['--modern-sync-source', state + '/original-modern.v'])
	negative.set_redirect_stdio_merged()
	negative.run()
	output := negative.stdout_slurp()
	negative.wait()
	code := negative.code
	negative.close()
	os.write_file(state + '/output.log', output)!
	assert code != 0 && os.is_file(state + '/test')
	assert output.contains('FAIL: fn file.run_modern_zero_checks')
	assert output.contains('zero-point dependency must block publication')
	println('Original committed stager compiled and was rejected by the zero-point scheduler dependency assertion; compilation failure does not count.')
}
