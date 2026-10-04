// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

import os

fn activity_controls_child() &os.Process {
	mut child := os.new_process('/bin/sleep')
	child.set_args(['60'])
	child.run()
	assert child.status == .running && child.pid > 1
	return child
}

fn activity_controls_cleanup(mut child os.Process) {
	C.kill(child.pid, C.SIGCONT)
	C.kill(child.pid, C.SIGKILL)
	child.wait()
	child.close()
}

fn activity_controls_monitor(pid int) ActivityMonitor {
	return ActivityMonitor{
		selected_pid: pid
		rows: [ActivityRow{pid: pid, ppid: int(C.getpid()), name: 'sleep'}]
	}
}

fn test_activity_controls_reject_init_and_group_pids() {
	for pid in [-1, -40, 0, 1] {
		assert activity_signal_process(pid, int(C.SIGTERM)) == int(C.EINVAL)
		assert activity_signal_process(pid, int(C.SIGSTOP)) == int(C.EINVAL)
		assert activity_set_priority(pid, 5) == int(C.EINVAL)
	}
	mut own := activity_controls_monitor(int(C.getpid()))
	defer { unsafe { own.rows.free() } }
	assert !own.can_kill_selected()
}

fn test_activity_controls_sampling_observes_external_priority_changes_and_exit() {
	mut child := activity_controls_child()
	defer { child.close() }
	mut app := ActivityApp{ monitor: activity_controls_monitor(child.pid) }
	defer { app.close_app() }
	app.sample_panels()
	before := app.controls.priority
	assert app.controls.priority_known && before < 19
	assert activity_set_priority(child.pid, before + 1) == 0
	app.sample_panels()
	assert app.controls.priority_known && app.controls.priority == before + 1
	assert C.kill(child.pid, C.SIGKILL) == 0
	child.wait()
	app.sample_panels()
	assert !app.controls.priority_known && app.controls.priority_text == '?'
}

fn test_activity_controls_quit_sends_sigterm_without_reaping() {
	mut child := activity_controls_child()
	defer { child.close() }
	mut m := activity_controls_monitor(child.pid)
	defer { unsafe { m.rows.free() } }
	mut controls := ActivityControls{}
	defer { controls.free() }
	assert controls.handle(activity_action_quit, mut m)
	assert !controls.failed
	assert controls.result_key == 'activity.control.sent'
	mut status := 0
	assert C.waitpid(child.pid, &status, 0) == child.pid
	assert status & 0x7f == int(C.SIGTERM)
	assert !controls.handle('unrelated.action', mut m)
}

fn test_activity_controls_suspend_resume_owned_child() {
	mut child := activity_controls_child()
	defer { activity_controls_cleanup(mut child) }
	mut m := activity_controls_monitor(child.pid)
	defer { unsafe { m.rows.free() } }
	mut controls := ActivityControls{}
	defer { controls.free() }
	assert controls.handle(activity_action_suspend, mut m)
	assert !controls.failed
	mut status := 0
	assert C.waitpid(child.pid, &status, C.WUNTRACED) == child.pid
	assert status & 0xff == 0x7f && status >> 8 == int(C.SIGSTOP)
	assert controls.handle(activity_action_continue, mut m)
	assert !controls.failed
	assert C.kill(child.pid, 0) == 0
}

fn test_activity_controls_change_owned_child_priority_and_reject_invalid_values() {
	mut child := activity_controls_child()
	defer { activity_controls_cleanup(mut child) }
	before, known := activity_priority(child.pid)
	assert known && before < 19
	mut m := activity_controls_monitor(child.pid)
	defer { unsafe { m.rows.free() } }
	mut controls := ActivityControls{}
	defer { controls.free() }
	assert controls.handle(activity_action_priority_down, mut m)
	assert !controls.failed
	after, after_known := activity_priority(child.pid)
	assert after_known && after == before + 1
	assert controls.priority == after
	assert activity_set_priority(child.pid, -21) == int(C.EINVAL)
	assert activity_set_priority(child.pid, 20) == int(C.EINVAL)
}

fn test_activity_controls_error_is_visible_for_an_already_reaped_owned_pid() {
	mut child := os.new_process('/usr/bin/true')
	child.run()
	child.wait()
	defer { child.close() }
	mut m := activity_controls_monitor(child.pid)
	defer { unsafe { m.rows.free() } }
	mut controls := ActivityControls{}
	defer { controls.free() }
	assert controls.handle(activity_action_quit, mut m)
	assert controls.failed
	assert controls.result_key == 'activity.control.gone'
	controls.select(1)
	assert controls.result_key == '' && !controls.failed
}

fn test_activity_controls_tree_signals_only_selected_owned_pids() {
	mut first := activity_controls_child()
	mut second := activity_controls_child()
	mut spared := activity_controls_child()
	defer {
		activity_controls_cleanup(mut first)
		activity_controls_cleanup(mut second)
		activity_controls_cleanup(mut spared)
	}
	mut m := ActivityMonitor{
		selected_pid: first.pid
		rows: [ActivityRow{pid: first.pid, ppid: int(C.getpid())},
			ActivityRow{pid: second.pid, ppid: first.pid},
			ActivityRow{pid: spared.pid, ppid: int(C.getpid())},
			ActivityRow{pid: 1, ppid: first.pid}]
	}
	defer { unsafe { m.rows.free() } }
	assert activity_signal_tree(&m, int(C.SIGKILL)) == 0
	mut status := 0
	assert C.waitpid(first.pid, &status, 0) == first.pid
	assert status & 0x7f == int(C.SIGKILL)
	assert C.waitpid(second.pid, &status, 0) == second.pid
	assert status & 0x7f == int(C.SIGKILL)
	assert C.kill(spared.pid, 0) == 0
}
