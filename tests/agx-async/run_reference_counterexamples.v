// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

// Execute complete native source mutations against the unchanged async suite.
fn main() {
	assert os.args.len == 3, 'usage: run_reference_counterexamples ASYNC_RUNNER FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	runner := os.abs_path(os.args[1])
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	mut receipts := []string{}
	for name, spec in {
		'no-capture': ['file', 'resources.retain_file_reference()', ''],
		'no-error-release': ['file', 'defer { if !transferred { release_submission_queue(captured) } }', 'defer { if false && !transferred { release_submission_queue(captured) } }'],
		'no-transfer': ['file', 'transferred = true', 'transferred = false'],
		'no-retirement-release': ['pending', 'queue.release_file_reference()', 'assert voidptr(queue) != unsafe { nil }']
	} {
		source := os.read_file(repo + '/kernel/gpu/agx/file/' + spec[0] + '.v')!
		assert source.count(spec[1]) == 1, name
		directory := state + '/' + name
		os.mkdir_all(directory)!
		mutant := source.replace(spec[1], spec[2])
		path := directory + '/' + spec[0] + '.v'
		os.write_file(path, mutant)!
		os.setenv('AGX_ASYNC_TEST_BINARY', directory + '/test', true)
		mut p := os.new_process(runner)
		p.set_args(['--' + spec[0] + '-source', path]); p.set_redirect_stdio(); p.run()
		log := p.stdout_slurp() + p.stderr_slurp(); p.wait()
		os.write_file(directory + '/run.log', log)!
		assert p.code != 0 && log.contains('FAIL: fn ') && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		p.close()
		receipts << name + ' native module sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; expected reference ownership assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
