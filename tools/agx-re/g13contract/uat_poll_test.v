module g13contract

import g13layout

fn test_uat_wait_returns_without_scheduler_handoff() {
	root := g13layout.repo_root()
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	scheduler := read(root + '/kernel/sched/sched_arm64.v')!
	check_uat_poll_local(manager, scheduler)!
	flush := section(manager, 'pub fn (mut mgr GpuManager) flush_g13_uat_range(', '// Notify one of the four priority instances', 'test')!
	for call in ['sched.yield(false)', 'sched.yield(true)', '// omitted barrier'] {
		changed := manager.replace(flush, flush.replace('katomic.sync()', call))
		if _ := check_uat_poll_local(changed, scheduler) { assert false, call }
	}
	for guard in ['mgr.state != .running', 'mgr.channels.fw_ctrl.serialized_token_consumed(token)',
		'if consumed { break }'] {
		changed := manager.replace(flush, flush.replace(guard, '// omitted completion guard'))
		assert changed != manager
		if _ := check_uat_poll_local(changed, scheduler) { assert false, guard }
	}
}
