// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

// Complete native modules and their failed executions remain outside Git.
// The ordinary fixture and its assertions are identical for every variant.
fn main() {
	assert os.args.len == 3, 'usage: run_detach_counterexamples CLOSE_RUNNER FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	runner := os.abs_path(os.args[1])
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	source := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	mut receipts := []string{}
	for name, pair in {
		'busy-destroy': ['q.detached = true', 'if katomic.load(&f.inflight_by_vm[q.vm_id]) != 0 { f.lock.release(); return -16 }\n\t\t\t\tq.detached = true'],
		'vm-wide-retention': ['if ownership.resources.has_file_references() { continue }', 'if katomic.load(&f.inflight_by_vm[ownership.vm_id]) != 0 { continue }'],
		'visible-name': ['if queue.id != queue_id || queue.detached { continue }', 'if queue.id != queue_id { continue }'],
		'no-retry': ['owned.reap_detached_g13_queues_locked()', '']
	} {
		assert source.count(pair[0]) == 1, name
		directory := state + '/' + name
		os.mkdir_all(directory)!
		mutant := source.replace(pair[0], pair[1])
		os.write_file(directory + '/file.v', mutant)!
		os.setenv('AGX_CLOSE_TEST_BINARY', directory + '/test', true)
		mut p := os.new_process(runner)
		p.set_args(['--file-source', directory + '/file.v']); p.set_redirect_stdio(); p.run()
		log := p.stdout_slurp() + p.stderr_slurp(); p.wait()
		os.write_file(directory + '/run.log', log)!
		assert p.code != 0 && log.contains('FAIL: fn file.check_detached_queues:') && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		p.close()
		receipts << name + ' native module sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; expected queue-detach assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
