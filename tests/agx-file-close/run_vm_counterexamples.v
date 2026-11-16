// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn main() {
	assert os.args.len == 4, 'usage: run_vm_counterexamples CLOSE_RUNNER ASYNC_RUNNER FRESH_EXTERNAL_DIR'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[3])
	assert !os.exists(state) && !state.starts_with(repo + '/')
	os.mkdir_all(state)!
	source := os.read_file(repo + '/kernel/gpu/agx/file/file.v')!
	mut receipts := []string{}
	for name, spec in {
		'busy-name-removal': ['close', 'f.detached_vms[vm.id] = true', 'if f.queues.len != 0 { return -16 }; f.detached_vms[vm.id] = true', 'file.identity_result:'],
		'visible-name': ['close', 'if vm_id < mmu.uat_num_contexts && f.detached_vms[vm_id] { return none }', '', 'file.identity_result:'],
		'visible-retirement-lookup': ['close', 'ctx := f.find_owned_vm(mapping.vm_id)', 'ctx := f.find_vm(mapping.vm_id)', 'file.check_detached_vms:'],
		'lost-queue-owner': ['close', 'if retained { continue }', 'assert retained || !retained', 'file.check_identity_lookups:'],
		'live-bo-bindings-retained': ['close', '!f.detached_vms[vm_id] && !mapping.retiring', '!mapping.retiring', 'file.check_detached_vms:'],
		'no-worker-retry': ['close', 'owned.reap_detached_vms_locked()', '', 'file.check_detached_vms:'],
		'visible-submit-lookup': ['async', 'vm := f.find_owned_vm(vm_id)', 'vm := f.find_vm(vm_id)', 'file.check_detached_vm_submissions:']
	} {
		assert source.count(spec[1]) == 1, name
		directory := state + '/' + name
		os.mkdir_all(directory)!
		mutant := source.replace(spec[1], spec[2])
		path := directory + '/file.v'
		os.write_file(path, mutant)!
		asynchronous := spec[0] == 'async'
		os.setenv(if asynchronous { 'AGX_ASYNC_TEST_BINARY' } else { 'AGX_CLOSE_TEST_BINARY' }, directory + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[if asynchronous { 2 } else { 1 }]))
		p.set_args(['--file-source', path]); p.set_redirect_stdio(); p.run()
		log := p.stdout_slurp() + p.stderr_slurp(); p.wait()
		os.write_file(directory + '/run.log', log)!
		assert p.code != 0 && log.contains('FAIL: fn ' + spec[3]) && !log.contains('error:'), name + ': ' + log
		assert os.is_file(directory + '/test'), name + ' must compile before failing'
		p.close()
		receipts << name + ' native module sha256 ' + sha256.sum(mutant.bytes()).hex()
		println(name + ': compiled; expected VM ownership assertion failed')
	}
	os.write_file(state + '/sources.txt', receipts.join('\n') + '\n')!
}
