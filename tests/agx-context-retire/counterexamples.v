// SPDX-License-Identifier: GPL-2.0-or-later
import os

fn main() {
	assert os.args.len == 4, 'usage: counterexamples RUNNER BASELINE_QUEUE_SOURCE FRESH_OUTPUT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); root := os.abs_path(os.args[3])
	assert !root.starts_with(repo + '/') && !os.exists(root); os.mkdir_all(root)!
	context := os.read_file(repo + '/kernel/gpu/agx/gpu/g13_context.v')!
	wire := os.read_file(repo + '/kernel/gpu/agx/fw/channels.v')!
	queue := os.read_file(repo + '/kernel/gpu/agx/gpu/g13.v')!
	variants := [
		['baseline-queue', '--queue-source', os.read_file(os.args[2])!, 'queue mappings must wait for acknowledged context retirement'],
		['missing-gate', '--queue-source', queue.replace('!mgr.invalidate_g13_context_locked(mut resources)\n\t\t|| ', ''), 'queue mappings must wait for acknowledged context retirement'],
		['replay-published', '--source', context.replace('if resources.context_retirement == .pending { return false }', ''), 'published retirement failure must never replay possibly recycled IDs'],
		['lost-complete', '--source', context.replace('if resources.context_retirement == .complete { return true }', ''), 'complete UAT retries must skip context bytes and repeated collection'],
		['late-pending', '--source', context.replace('resources.context_retirement = .pending\n', '').replace('if !mgr.ring_device_control() { return false }', 'if !mgr.ring_device_control() { return false }\n\tresources.context_retirement = .pending'), 'publication acceptance must preserve retirement state'],
		['failed-collection', '--source', context.replace('if !mgr.ring_device_control() { return false }', 'if !mgr.ring_device_control() { mgr.g13_private.collect_garbage(private_count); return false }'), 'only acknowledged context retirement may collect captured private garbage'],
		['collect-later', '--source', context.replace('mgr.g13_private.collect_garbage(private_count)', 'mgr.g13_private.gc()'), 'captured collection must preserve live and later-released pins'],
		['wrong-count', '--source', context.replace('mgr.g13_private.collect_garbage(private_count)', 'mgr.g13_private.collect_garbage(readonly_count)'), 'captured collection must preserve live and later-released pins'],
		['missing-collection', '--source', context.replace('mgr.g13_private.collect_garbage(private_count)', '// omitted prefix'), 'only acknowledged context retirement may collect captured private garbage'],
		['wrong-pointer', '--wire-source', wire.replace('pointer_offset := if abi == .v12_3 { 0x1c } else { 0x14 }', 'pointer_offset := if abi == .v12_3 { 0x18 } else { 0x14 }'), 'every context command byte must match the independent ABI model'],
		['wrong-id', '--wire-source', wire.replace('bytes[context_offset + 2] = data[4]', 'bytes[context_offset + 2] = data[5]'), 'every context command byte must match the independent ABI model'],
	]
	for item in variants {
		assert item[2] != match item[1] { '--source' { context } '--wire-source' { wire } else { queue } }
		dir := root + '/' + item[0]; os.mkdir_all(dir)!; os.write_file(dir + '/source.v', item[2])!
		os.setenv('AGX_CONTEXT_C', dir + '/test.c', true); os.setenv('AGX_CONTEXT_BINARY', dir + '/test', true)
		mut p := os.new_process(os.abs_path(os.args[1])); p.set_args([item[1], dir + '/source.v']); p.set_redirect_stdio_merged(); p.run()
		out := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(dir + '/run.log', out)!
		assert code != 0 && out.contains(item[3]) && !out.contains('error:'), item[0]
		assert os.is_file(dir + '/test.c') && os.is_file(dir + '/test')
		println(item[0] + ': compiled; designated context ABI/ownership/retry assertion rejected')
	}
}
