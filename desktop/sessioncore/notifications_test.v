// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn test_application_withdrawal_is_owned_keyed_and_idempotent() {
	mut n := Notifications{}
	n.post('pid.10', 'android:42', 'One', '', .normal, -1, '', 100) or { panic(err) }
	n.post('pid.11', 'android:42', 'Other owner', '', .normal, -1, '', 100) or { panic(err) }
	n.post('pid.10', 'android:43', 'Other key', '', .normal, -1, '', 100) or { panic(err) }
	assert !n.withdraw('pid.12', 'android:42')
	assert !n.withdraw('pid.10', 'missing')
	assert n.withdraw('pid.10', 'android:42')
	assert n.items[0].dismissed && n.items[0].read
	assert !n.items[1].dismissed && !n.items[2].dismissed
	assert !n.withdraw('pid.10', 'android:42')
}

fn test_history_coalesces_progress_and_quiet_preserves_notifications() {
	mut n := Notifications{}
	id := n.post('editor', 'save', 'Saving', 'Document', .normal, 10, '', 100) or { panic(err) }
	assert n.post('editor', 'save', 'Saved', 'Document', .normal, 100, '', 101) or { panic(err) } == id
	assert n.count == 1 && n.items[0].progress == 100
	n.mode = .quiet
	assert !n.show_banner(n.items[0], 101)
	_ = n.post('clock', 'timer', 'Timer', '', .critical, -1, '', 101) or { panic(err) }
	assert n.show_banner(n.items[1], 101)
	n.allow_critical = false
	assert !n.show_banner(n.items[1], 101)
	n.focus_until = 102
	assert n.tick(102, 0)
	assert n.mode == .normal
}

fn test_alarms_survive_app_exit_and_restart_and_ignore_clock_steps_live() {
	mut n := Notifications{}
	n.schedule('clock', 'one', 'Tea', 105, 5000, 0) or { panic(err) }
	assert !n.tick(10000, 4999)
	assert n.tick(10000, 5000)
	assert n.count == 1 && !n.alarms[0].active
	assert !n.tick(10001, 5001)
	n.schedule('clock', 'repeat', 'Daily', 10010, 0, 60) or { panic(err) }
	record := n.encode()
	defer { unsafe { record.free() } }
	mut restored := decode_notifications(record) or { panic(err) }
	assert restored.tick(10200, 0)
	assert restored.count == 2
	assert restored.alarms[0].due_epoch == 10250
	assert restored.cancel('clock', 'repeat')
	assert !restored.tick(20000, 100000)
}

fn test_bounded_history_and_corrupt_records() {
	mut n := Notifications{}
	for i in 0 .. max_notifications + 10 {
		_ = n.post('app', '', 'Notice', '', .normal, -1, '', i64(i)) or { panic(err) }
	}
	assert n.count == max_notifications && n.items[0].id == 11
	assert n.dismiss(11)
	assert n.items[0].dismissed
	record := n.encode()
	defer { unsafe { record.free() } }
	decoded := decode_notifications(record) or { panic(err) }
	assert decoded.count == max_notifications
	if _ := decode_notifications(record.replace('notice\t11\t', 'notice\t0\t')) {
		assert false
	}
	if _ := n.post('bad/owner', '', 'Notice', '', .normal, -1, '', 0) {
		assert false
	}
}
