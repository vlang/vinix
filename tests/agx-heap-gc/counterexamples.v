// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 3, 'usage: counterexamples HEAP_GC_RUNNER FRESH_EXTERNAL_DIRECTORY'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	root := os.abs_path(os.args[2])
	assert !os.exists(root) && !root.starts_with(repo + '/')
	os.mkdir_all(root)!
	source := os.read_file(repo + '/kernel/gpu/agx/gpu/g13_garbage.v')!
	wire := os.read_file(repo + '/kernel/gpu/agx/fw/channels.v')!
	variants := [
		['no-collection', source.replace('if !g13_heap_garbage_needs_collection(', 'if true || !g13_heap_garbage_needs_collection('), '--source'],
		['inclusive-threshold', source.replace(' > g13_max_', ' >= g13_max_'), '--source'],
		['no-barrier', source.replace('if !mgr.flush_g13_fw_cache_locked()', 'if false'), '--source'],
		['ignore-doorbell-failure', source.replace('if !mgr.ring_device_control() { return false }', 'mgr.ring_device_control()'), '--source'],
		['ignore-ack', source.replace('for mgr.channels.device_ctrl.read_pointer() != token', 'for false'), '--source'],
		['collect-later', source.replace('mgr.g13_private.collect_garbage(private_count)', 'mgr.g13_private.gc()'), '--source'],
		['wrong-count', source.replace('mgr.g13_private.collect_garbage(private_count)', 'mgr.g13_private.collect_garbage(readonly_count)'), '--source'],
		['ignore-readonly', source.replace('readonly_bytes > g13_max_fw_garbage_bytes', 'false').replace('readonly_count > g13_max_fw_garbage_objects', 'false'), '--source'],
		['wrong-v13-tag', wire.replace('device_control_destroy_context_v13_5 = u32(0x18)', 'device_control_destroy_context_v13_5 = u32(0x17)'), '--wire-source'],
		['wrong-v13-offset', wire.replace('.v13_5_partial { 0x11 }', '.v13_5_partial { 0x14 }'), '--wire-source'],
	]
	for item in variants {
		assert item[1] != if item[2] == '--source' { source } else { wire }
		directory := root + '/' + item[0]; os.mkdir_all(directory)!
		os.write_file(directory + '/g13_garbage.v', item[1])!
		os.setenv('AGX_HEAP_GC_C', directory + '/test.c', true)
		os.setenv('AGX_HEAP_GC_BINARY', directory + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1]))
		p.set_args([item[2], directory + '/g13_garbage.v']); p.set_redirect_stdio_merged(); p.run()
		output := p.stdout_slurp(); p.wait()
		os.write_file(directory + '/run.log', output)!
		assert p.code != 0 && output.contains('FAIL: fn gpu.') && !output.contains('error:'), item[0] + ': ' + output
		assert os.is_file(directory + '/test.c') && os.is_file(directory + '/test')
		p.close(); println(item[0] + ': compiled; barrier/threshold/ownership assertion rejected')
	}
}
