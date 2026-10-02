// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

import ui2

#include <sys/resource.h>

fn C.getpriority(which int, who u32) int
fn C.setpriority(which int, who u32, priority int) int

const activity_action_quit = 'activity.control.quit'
const activity_action_suspend = 'activity.control.suspend'
const activity_action_continue = 'activity.control.continue'
const activity_action_priority_up = 'activity.control.priority.up'
const activity_action_priority_down = 'activity.control.priority.down'
const activity_action_kill_tree = 'activity.control.kill_tree'
const activity_controls_height = 62

// No waitpid: the monitor does not own the inspected processes. Actions only
// send a signal or change a scheduler parameter, then request a fresh sample.
struct ActivityControls {
mut:
	selected_pid int
	priority int
	priority_known bool
	priority_text string
	result_key string
	failed bool
}

fn activity_signal_process(pid int, signal int) int {
	if pid <= 1 { return int(C.EINVAL) }
	if C.kill(pid, signal) == 0 { return 0 }
	return int(C.errno)
}

fn activity_set_priority(pid int, priority int) int {
	if pid <= 1 || priority < -20 || priority > 19 { return int(C.EINVAL) }
	if C.setpriority(int(C.PRIO_PROCESS), u32(pid), priority) == 0 { return 0 }
	return int(C.errno)
}

fn activity_priority(pid int) (int, bool) {
	if pid <= 1 { return 0, false }
	C.errno = 0
	priority := C.getpriority(int(C.PRIO_PROCESS), u32(pid))
	return priority, C.errno == 0
}

fn (mut c ActivityControls) select(pid int) {
	if c.selected_pid == pid { return }
	c.selected_pid = pid
	c.result_key = ''
	c.failed = false
	c.refresh_priority()
}

fn (mut c ActivityControls) refresh_priority() {
	c.priority, c.priority_known = activity_priority(c.selected_pid)
	unsafe { c.priority_text.free() }
	c.priority_text = if c.priority_known { c.priority.str() } else { '?' }
}

// Polling, rather than rendering, observes changes made by another program.
fn (mut c ActivityControls) sample(m &ActivityMonitor) {
	if c.selected_pid == m.selected_pid {
		c.refresh_priority()
	} else {
		c.select(m.selected_pid)
	}
}

fn activity_control_button(action string, key string, x int, y int, width int, enabled bool) ui2.Element {
	label := tr(key)
	return ui2.Element{
		...ui2.button(action, label, ui2.rect(f64(x), f64(y), f64(width), 25), ui2.BoxStyle{
			bg: if enabled { files_up } else { files_up_disabled }
			radius: 4
		}, ui2.TextStyle{ color: if enabled { app_on_accent } else { body_muted }, size: 11, align: .center })
		enabled: enabled
		tooltip: label
		accessibility_label: label
	}
}

// A two-row action panel, usually drawn beneath the inspector. Widths scale
// with the window so every action remains reachable in a narrow monitor.
fn (mut c ActivityControls) build(mut children []ui2.Element, m &ActivityMonitor, width int, y int) {
	c.select(m.selected_pid)
	enabled := m.can_kill_selected() && m.selected_pid != int(C.getpid())
	button_width := (width - 2 * activity_padding - 18) / 4
	keys := ['activity.control.quit', 'activity.control.suspend', 'activity.control.continue',
		'activity.control.kill_tree']!
	actions := [activity_action_quit, activity_action_suspend, activity_action_continue,
		activity_action_kill_tree]!
	for index in 0 .. 4 {
		children << activity_control_button(actions[index], keys[index], activity_padding + index * (button_width + 6),
			y, button_width, enabled)
	}
	children << activity_control_button(activity_action_priority_up, 'activity.control.priority_up',
		activity_padding, y + 29, button_width, enabled && c.priority_known && c.priority > -20)
	children << activity_control_button(activity_action_priority_down, 'activity.control.priority_down',
		activity_padding + button_width + 6, y + 29, button_width,
		enabled && c.priority_known && c.priority < 19)
	children << ui2.label('', tr('activity.control.nice'), ui2.rect(f64(activity_padding + 2 * (button_width + 6)),
		f64(y + 34), f64(button_width - 25), 16), ui2.TextStyle{ color: body_muted, size: 11 })
	children << ui2.label('', c.priority_text, ui2.rect(f64(activity_padding + 3 * button_width - 18),
		f64(y + 34), 24, 16), ui2.TextStyle{ color: body_text, size: 11 })
	if c.result_key != '' {
		children << ui2.label('', tr(c.result_key), ui2.rect(f64(activity_padding + 3 * (button_width + 6)),
			f64(y + 29), f64(button_width), 27), ui2.TextStyle{
			color: if c.failed { files_error } else { body_muted }, size: 10
		})
	}
}

fn (mut c ActivityControls) report(code int) {
	c.failed = code != 0
	c.result_key = if code == 0 { 'activity.control.sent' }
		else if code == int(C.EPERM) || code == int(C.EACCES) { 'activity.control.permission' }
		else if code == int(C.ESRCH) { 'activity.control.gone' }
		else { 'activity.control.failed' }
}

// Explicit positive PIDs, children before parents. A snapshot cannot turn a
// tree action into kill(-1), a session/group broadcast, or a signal to init.
fn activity_signal_tree(m &ActivityMonitor, signal int) int {
	root := m.selected_pid
	if root <= 1 || root == int(C.getpid()) || m.process_row_index(root) < 0 { return int(C.EINVAL) }
	mut pids := [activity_max_records]int{}
	pids[0] = root
	mut count := 1
	mut next := 0
	for next < count {
		for row in m.rows {
			if row.ppid != pids[next] || row.pid <= 1 || row.pid == int(C.getpid()) { continue }
			mut duplicate := false
			for index in 0 .. count { if pids[index] == row.pid { duplicate = true break } }
			if !duplicate && count < pids.len { pids[count] = row.pid count++ }
		}
		next++
	}
	mut error_code := 0
	for index := count - 1; index >= 0; index-- {
		code := activity_signal_process(pids[index], signal)
		// A child already gone has completed the requested termination.
		if code != 0 && code != int(C.ESRCH) && error_code == 0 { error_code = code }
	}
	return error_code
}

fn (mut c ActivityControls) handle(event_id string, mut m ActivityMonitor) bool {
	if event_id !in [activity_action_quit, activity_action_suspend, activity_action_continue,
		activity_action_priority_up, activity_action_priority_down, activity_action_kill_tree] {
		return false
	}
	c.select(m.selected_pid)
	if !m.can_kill_selected() || m.selected_pid == int(C.getpid()) { return true }
	mut code := 0
	match event_id {
		activity_action_quit { code = activity_signal_process(m.selected_pid, int(C.SIGTERM)) }
		activity_action_suspend { code = activity_signal_process(m.selected_pid, int(C.SIGSTOP)) }
		activity_action_continue { code = activity_signal_process(m.selected_pid, int(C.SIGCONT)) }
		activity_action_kill_tree { code = activity_signal_tree(m, int(C.SIGKILL)) }
		else {
			c.refresh_priority()
			if !c.priority_known { code = int(C.ESRCH) }
			else {
				priority := c.priority + if event_id == activity_action_priority_up { -1 } else { 1 }
				code = activity_set_priority(m.selected_pid, priority)
				if code == 0 { c.refresh_priority() }
			}
		}
	}
	c.report(code)
	if code == 0 { m.last_poll_ms = monotonic_millis() - m.interval_ms }
	return true
}

fn (mut c ActivityControls) free() {
	unsafe { c.priority_text.free() }
	c.priority_text = ''
}
