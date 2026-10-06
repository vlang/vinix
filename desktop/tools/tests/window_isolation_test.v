// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn isolation_fixture() Desktop {
	return Desktop{
		canvas: Canvas{
			width: 801
			height: 647
		}
	}
}

fn isolation_minimized(d &Desktop, id int) bool {
	index := d.window_index(id) or { panic('missing window') }
	return d.windows[index].minimized
}

fn test_shake_requires_deliberate_reversals_and_fires_once_per_drag() {
	mut shake := new_window_shake(300, 100, 1000)
	assert !shake.sample(350, 100, 1100)
	assert !shake.sample(300, 101, 1200)
	assert !shake.sample(350, 99, 1300)
	assert shake.sample(300, 100, 1400)
	assert !shake.sample(350, 100, 1500)
	assert !shake.sample(300, 100, 1600)
}

fn test_shake_ignores_jitter_slow_motion_and_vertical_drags() {
	mut jitter := new_window_shake(300, 100, 0)
	for i in 0 .. 20 {
		assert !jitter.sample(300 + if i % 2 == 0 { 5 } else { -5 }, 100, i64(i * 20))
	}
	mut slow := new_window_shake(300, 100, 0)
	assert !slow.sample(350, 100, 200)
	assert !slow.sample(300, 100, 1200)
	assert !slow.sample(350, 100, 2400)
	assert !slow.sample(300, 100, 3600)
	mut vertical := new_window_shake(300, 100, 0)
	assert !vertical.sample(350, 100, 100)
	assert !vertical.sample(300, 160, 200)
	assert !vertical.sample(350, 220, 300)
	assert !vertical.sample(300, 280, 400)
}

fn test_hide_others_restores_only_its_own_windows_and_keeps_focus_order() {
	mut d := isolation_fixture()
	one := d.spawn('One', .welcome, 20, 20, 300, 200)
	two := d.spawn('Two', .welcome, 30, 30, 300, 200)
	before := d.spawn('Already minimized', .welcome, 40, 40, 300, 200)
	d.minimize(before)
	d.raise(two)
	d.toggle_window_isolation(two)
	assert isolation_minimized(&d, one)
	assert isolation_minimized(&d, before)
	assert !isolation_minimized(&d, two)
	assert d.focus == two
	d.toggle_window_isolation(two)
	assert !isolation_minimized(&d, one)
	assert isolation_minimized(&d, before)
	assert d.focus == two
	assert d.windows[d.windows.len - 1].id == two
}

fn test_hide_others_sessions_are_independent_between_workspaces() {
	mut d := isolation_fixture()
	one := d.spawn('One', .welcome, 20, 20, 300, 200)
	two := d.spawn('Two', .welcome, 30, 30, 300, 200)
	d.toggle_window_isolation(two)
	d.switch_workspace(1)
	three := d.spawn('Three', .welcome, 20, 20, 300, 200)
	four := d.spawn('Four', .welcome, 30, 30, 300, 200)
	d.toggle_window_isolation(four)
	d.restore_isolated_windows()
	assert !isolation_minimized(&d, three)
	assert isolation_minimized(&d, one)
	d.switch_workspace(0)
	d.restore_isolated_windows()
	assert !isolation_minimized(&d, one)
	assert d.focus == two
}

fn test_manual_minimizing_moving_and_closing_do_not_resurrect_windows() {
	mut d := isolation_fixture()
	one := d.spawn('One', .welcome, 20, 20, 300, 200)
	two := d.spawn('Two', .welcome, 30, 30, 300, 200)
	three := d.spawn('Three', .welcome, 40, 40, 300, 200)
	four := d.spawn('Four', .welcome, 50, 50, 300, 200)
	d.toggle_window_isolation(four)
	d.activate(one)
	d.minimize(one)
	d.move_window_to_workspace(two, 1)
	d.close_window(three)
	d.restore_isolated_windows()
	assert isolation_minimized(&d, one)
	assert isolation_minimized(&d, two)
	assert d.window_index(three) == none
	assert d.focus == four
}

fn test_isolation_works_with_show_desktop_and_windows_opened_later() {
	mut d := isolation_fixture()
	one := d.spawn('One', .welcome, 20, 20, 300, 200)
	two := d.spawn('Two', .welcome, 30, 30, 300, 200)
	d.toggle_window_isolation(two)
	d.toggle_show_desktop()
	assert d.visible_window_count() == 0
	d.toggle_show_desktop()
	assert isolation_minimized(&d, one)
	assert !isolation_minimized(&d, two)
	three := d.spawn('Opened later', .welcome, 40, 40, 300, 200)
	d.toggle_window_isolation(three)
	assert !isolation_minimized(&d, one)
	assert !isolation_minimized(&d, two)
	assert !isolation_minimized(&d, three)
	assert d.focus == three
}

fn test_window_shortcuts_minimize_hide_restore_and_preserve_unrelated_typing() {
	mut d := isolation_fixture()
	one := d.spawn('One', .welcome, 20, 20, 300, 200)
	two := d.spawn('Two', .welcome, 30, 30, 300, 200)
	assert d.take_window_shortcuts('a${key_super_home}b') == 'ab'
	assert isolation_minimized(&d, one)
	assert d.take_window_shortcuts(key_super_shift_m) == ''
	assert !isolation_minimized(&d, one)
	assert d.take_window_shortcuts(key_super_alt_h) == ''
	assert isolation_minimized(&d, one)
	d.take_window_shortcuts(key_super_alt_h)
	assert !isolation_minimized(&d, one)
	assert d.take_window_shortcuts(key_super_m) == ''
	assert isolation_minimized(&d, two)
	assert d.focus == one
	assert d.take_window_shortcuts(key_super_down) == ''
	assert isolation_minimized(&d, one)
	assert d.focus == 0
}

fn test_titlebar_shake_is_integrated_into_pointer_motion_and_repaint_damage() {
	mut d := isolation_fixture()
	one := d.spawn('One', .welcome, 20, 20, 300, 200)
	two := d.spawn('Two', .welcome, 200, 80, 300, 200)
	index := d.window_index(two) or { panic('missing window') }
	d.targets << HitTarget{
		action_id: d.windows[index].id_titlebar
		x: 200
		y: 80
		width: 300
		height: d.theme().title_height
	}
	d.on_pointer_down(300, 90)
	d.buttons = button_left
	d.on_pointer_move(350, 90)
	d.on_pointer_move(300, 90)
	d.on_pointer_move(350, 90)
	d.on_pointer_move(300, 90)
	assert isolation_minimized(&d, one)
	assert d.focus == two
	assert d.drag_damage.valid
	assert d.drag_damage.w >= d.canvas.width
	assert d.drag_damage.h >= d.canvas.height
	d.buttons = 0
	d.on_pointer_up(300, 90)
	assert d.drag.kind == .none_
}
