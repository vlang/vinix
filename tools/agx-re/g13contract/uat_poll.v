// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_uat_poll_local(manager string, scheduler string) ! {
	flush := section(manager, 'pub fn (mut mgr GpuManager) flush_g13_uat_range(', '// Notify one of the four priority instances', 'UAT flush wait')!
	poll := section(flush, 'for mgr.channels.fw_ctrl.read_pointer() != token', '\n\tif !uat_mgr.complete_flush(slot)', 'UAT completion poll')!
	require(!poll.contains('sched.yield('), 'A live UAT transaction must not enter a scheduler handoff')!
	require_order(flush, ['mgr.fwctl_lock.acquire()', 'mgr.fwctl_lock.release()', 'uat_mgr.begin_flush(slot, addr, size)',
		'enqueue_with_token(voidptr(&message))', 'uat_mgr.abort_unpublished_flush(slot)',
		'mgr.send_role_message(0, u8(ep_doorbell), msg_fwctl)', 'started := timer.get_ns()',
		'for mgr.channels.fw_ctrl.read_pointer() != token', 'mgr.state != .running',
		'timer.get_ns() - started >= u64(1_000_000_000)', 'katomic.sync()',
		'uat_mgr.complete_flush(slot)', 'return true'], 'Returning UAT wait preserves publication, timeout, handoff and deferred unlock gates')!
	yield_body := section(scheduler, 'pub fn yield(save_ctx bool)', '\n\tcpu.interrupt_toggle(false)', 'ARM scheduler handoff')!
	require_order(yield_body, ['if save_ctx == false', 'idle_after_dying_thread(false)'], 'The false scheduler branch abandons its caller')!
	require(scheduler.contains('@[noreturn]\nfn idle_after_dying_thread('), 'The ARM dying-thread handoff must stay non-returning')!
}
