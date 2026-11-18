// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
	assert os.args.len == 3, 'usage: run_orphan_counterexamples CLOSE_RUNNER FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	source := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	start := source.index('fn (mut f GpuFile) reap_orphaned_g13_queues_locked()') or { panic('orphan reaper') }
	end := source.index_after('// The registry lock pins', start) or { panic('registry') }
	body := source[start..end]
	mut receipts := []string{}
	for name, pair in {
		'missing-retry': ['owned.reap_orphaned_g13_queues_locked()', ''],
		'discard-stopped-constructor': ['if retained != unsafe { nil } {', 'if retained != unsafe { nil } && !retained.released {'],
		'ignore-logical-owner': ['if named || ownership.resources.has_file_references() { continue }', 'if (named && false) || ownership.resources.has_file_references() { continue }'],
		'ignore-reference': ['if named || ownership.resources.has_file_references() { continue }', 'if named { continue }'],
		'compare-vm-identity': ['if queue.id == ownership.queue_id { named = true; break }', 'if queue.vm_id == ownership.vm_id { named = true; break }'],
		'vm-wide-retention': ['ownership := f.g13_queues[index]', 'ownership := f.g13_queues[index]\n\t\tvm := f.find_owned_vm(ownership.vm_id) or { unsafe { nil } }; if vm != unsafe { nil } && katomic.load(&vm.inflight) != 0 { continue }'],
		'forget-failed-release': ['if !gpu_manager.release_g13_queue_resources(ownership.resources) { continue }', '_ = gpu_manager.release_g13_queue_resources(ownership.resources)'],
		'delete-wrong-owner': ['f.g13_queues.delete(index)', 'f.g13_queues.delete(0)']
	} {
		mut mutant := ''
		if name in ['missing-retry', 'discard-stopped-constructor'] {
			assert source.count(pair[0]) == 1
			mutant = source.replace(pair[0], pair[1])
		} else {
			assert body.count(pair[0]) == 1, name
			mutant = source[..start] + body.replace(pair[0], pair[1]) + source[end..]
		}
		directory := state + '/' + name
		os.mkdir_all(directory)!
		os.write_file(directory + '/file.v', mutant)!
		os.setenv('AGX_CLOSE_TEST_BINARY', directory + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args(['--file-source', directory + '/file.v']); p.set_redirect_stdio(); p.run()
		log := p.stdout_slurp() + p.stderr_slurp(); p.wait()
		os.write_file(directory + '/run.log', log)!
		target := match name {
			'discard-stopped-constructor' { 'file.check_stopped_constructor_adoption:' }
			'ignore-logical-owner' { 'file.check_detached_queues:' }
			'forget-failed-release', 'delete-wrong-owner' {
				'gpu.agx.gpu.free_g13_queue_record: assert resources.released'
			}
			else { 'file.check_orphaned_queues:' }
		}
		assert p.code != 0 && log.contains('FAIL: fn ' + target) && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		p.close()
		receipts << name + ' native module sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; expected orphan ownership assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
