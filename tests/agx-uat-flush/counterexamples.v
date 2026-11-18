// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_MANAGER FRESH_EXTERNAL_DIRECTORY'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	root := os.abs_path(os.args[3]); assert !os.exists(root) && !root.starts_with(repo + '/')
	os.mkdir_all(root)!
	source := os.read_file(repo + '/kernel/gpu/agx/gpu/gpu.v')!
	publication := 'if !mgr.send_role_message(0, u8(ep_doorbell), msg_fwctl) {\n\t\tmgr.state = .error'
	// Feed the old scheduler path through the current message builder so
	// the wire check cannot mask the designated scheduler failure.
	baseline := os.read_file(os.args[2])!.replace('fw.make_g13_fwctl_invalidate(addr, slot)',
		'fw.make_g13_fwctl_invalidate(addr, slot, u16(size >> pgtable.uat_pg_shift))')
	variants := [
		['baseline', baseline, 'UAT wait entered the non-returning scheduler path'],
		['fixed-page-count', source.replace('make_g13_fwctl_invalidate(addr, slot, u16(pages))', 'make_g13_fwctl_invalidate(addr, slot, 1)'), 'FwCtl must publish the 16-bit page count'],
		['no-wait', source.replace('for mgr.channels.fw_ctrl.read_pointer() != token', 'for false'), 'UAT success requires both its ring token and completed handoff'],
		['ignore-handoff', source.replace('if !uat_mgr.complete_flush(slot)', 'if false'), 'published failures must retain their handoff slot'],
		['missing-abort', source.replace('uat_mgr.abort_unpublished_flush(slot)', '// omitted abort'), 'published failures must retain their handoff slot'],
		['abort-published', source.replace(publication, publication + '\n\t\tuat_mgr.abort_unpublished_flush(slot)'), 'published failures must retain their handoff slot'],
		['missing-unlock', source.replace('mgr.fwctl_lock.release()', '// omitted unlock'), 'every UAT return must release the firmware-control lock'],
		['zero-timeout', source.replace('>= u64(1_000_000_000)', '>= u64(0)'), 'UAT success requires both its ring token and completed handoff'],
		['wrong-token', source.replace('for mgr.channels.fw_ctrl.read_pointer() != token', 'for mgr.channels.fw_ctrl.read_pointer() == token'), 'UAT success requires both its ring token and completed handoff'],
	]
	for item in variants {
		assert item[1] != source
		directory := root + '/' + item[0]; os.mkdir_all(directory)!
		os.write_file(directory + '/gpu.v', item[1])!
		os.setenv('AGX_UAT_FLUSH_C', directory + '/test.c', true)
		os.setenv('AGX_UAT_FLUSH_BINARY', directory + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args(['--manager-source', directory + '/gpu.v']); p.set_redirect_stdio_merged(); p.run()
		output := p.stdout_slurp(); p.wait()
		os.write_file(directory + '/run.log', output)!
		assert p.code != 0 && output.contains(item[2]) && !output.contains('error:'), item[0] + ': ' + output
		assert os.is_file(directory + '/test') && os.is_file(directory + '/test.c')
		p.close(); println(item[0] + ': compiled; designated UAT wait/ownership assertion rejected')
	}
}
