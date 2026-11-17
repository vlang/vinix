// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_worker_scheduling_local(manager string, g17 string, fake string, arm string, x86 string) ! {
	g13_worker := section(manager, 'fn event_worker(', '// Shutdown the GPU', 'G13 worker')!
	g17_worker := section(g17, 'fn g17_event_worker(', '// Apple decodes bits 53:48.', 'G17 worker')!
	wait := section(fake, 'fn wait_staged_syncs(', 'fn mapped(', 'Fake dependency wait')!
	for code in [g13_worker, g17_worker, wait] {
		require(code.count('sched.reschedule()') == 1 && !code.contains('sched.yield('), 'Active AGX work must use the returning scheduler API')!
	}
	require_order(g13_worker, ['reap_g13_render_jobs()', 'reap_g13_compute_jobs()', 'reap_file_resources()',
		'sched.reschedule()', 'if mgr.state == .error', 'mgr.shutdown()', 'mgr.reap_file_resources()'], 'G13 cleanup remains reachable after rescheduling')!
	require_order(g17_worker, ['mgr.handle_g17_akf_callback()', 'if !serviced {', 'sched.reschedule()',
		'if mgr.state == .error', 'mgr.shutdown()'], 'G17 idle rescheduling preserves sweep and failure cleanup')!
	require_order(wait, ['for !syncobj.is_signaled(fence)', 'syncobj.wait(fence, 1_000_000)',
		'sched.reschedule()', 'syncobj.get_error(fence)', 'return -5', 'return 0'], 'Fake waits retain dependency and error checks')!
	terminal := section(fake, 'fn fake_completion_worker(', 'fn next_unused_vm_id(', 'Terminal completion worker')!
	require_order(terminal, ['finish_pending_job', 'free(voidptr(completion.item))', 'free(voidptr(completion))',
		'sched.dequeue_and_die()'], 'Actual thread termination remains terminal after ownership release')!
	arm_helper := section(arm, 'pub fn reschedule()', 'pub fn new_kernel_thread(', 'ARM reschedule')!
	require_order(arm_helper, ['current_thread.yield_requested = true', 'C.yield_dispatch(voidptr(scheduler_timer_handler))',
		'arm_thread_timer(effective_timeslice(current_thread))', 'cpu.interrupt_toggle(true)'], 'ARM reschedule saves the runnable thread and returns')!
	require(!arm_helper.contains('dequeue_') && !arm_helper.contains('idle_after_dying_thread'), 'ARM reschedule must preserve the run queue owner')!
	x86_helper := section(x86, 'pub fn reschedule()', 'pub fn new_kernel_thread(', 'AMD64 reschedule')!
	require(x86_helper.contains('yield(true)') && !x86_helper.contains('yield(false)') && !x86_helper.contains('dequeue_'), 'AMD64 reschedule saves context without dequeuing')!
}
