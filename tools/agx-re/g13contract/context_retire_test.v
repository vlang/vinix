module g13contract

import g13layout

fn test_context_acknowledgement_gates_unmapping_and_snapshot_collection() {
	root := g13layout.repo_root()
	wire := read(root + '/kernel/gpu/agx/fw/channels.v')!
	garbage := read(root + '/kernel/gpu/agx/gpu/g13_context.v')!
	queues := read(root + '/kernel/gpu/agx/gpu/g13.v')!
	check_context_retire_local(wire, garbage, queues)!
	for token in ['pointer_offset := if abi == .v12_3 { 0x1c } else { 0x14 }', 'bytes[8] = data[0x23]', 'bytes[context_offset + 2] = data[4]'] {
		if _ := check_context_retire_local(wire.replace(token, ''), garbage, queues) { assert false, token }
	}
	for token in ['if resources.context_retirement == .complete { return true }', 'if resources.context_retirement == .pending { return false }',
		'resources.context_retirement = .pending', 'if !mgr.wait_g13_device_control_locked(token) { return false }',
		'mgr.g13_private.collect_garbage(private_count)'] {
		if _ := check_context_retire_local(wire, garbage.replace(token, ''), queues) { assert false, token }
	}
	if _ := check_context_retire_local(wire, garbage, queues.replace('!mgr.defer_g13_context_locked(mut resources)\n\t\t|| ', '')) { assert false }
}
