// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn windows_shortcut_fixture() Desktop {
	mut desktop := Desktop{ canvas: Canvas{ width: 1024, height: 768 } }
	desktop.spawn('One', .welcome, 10, 10, 300, 200)
	desktop.spawn('Two', .system, 20, 20, 300, 200)
	return desktop
}

// Follow the desktop stream order. Overlay parsers hold a lone ESC; the
// switcher retains ambiguous CSI prefixes for later window actions.
fn windows_shortcut_stream(mut desktop Desktop, keys string) string {
	controls := desktop.take_window_overlay_keys(keys)
	return desktop.take_window_shortcuts(controls)
}

fn test_alt_f4_and_cmd_w_close_focused_windows_without_eating_ordinary_input() {
	for chord in [key_alt_f4, key_cmd_w] {
		mut desktop := windows_shortcut_fixture()
		id := desktop.focus
		assert windows_shortcut_stream(mut desktop, 'a${chord}b') == 'ab'
		assert desktop.window_index(id) == none
		assert desktop.windows.len == 1
		assert desktop.focus == desktop.windows[0].id
	}
	mut empty := Desktop{ canvas: new_canvas(1024, 768) }
	assert windows_shortcut_stream(mut empty, key_alt_f4) == ''
	assert empty.windows.len == 0
}

fn test_windows_global_chords_survive_every_console_split_in_the_parser_chain() {
	for chord in [key_alt_f4, key_cmd_w] {
		for split in 1 .. chord.len {
			mut desktop := windows_shortcut_fixture()
			id := desktop.focus
			assert windows_shortcut_stream(mut desktop, 'a${chord[..split]}') == 'a'
			assert desktop.window_index(id) != none
			assert windows_shortcut_stream(mut desktop, '${chord[split..]}b') == 'b'
			assert desktop.window_index(id) == none
		}
	}
	for chord in [key_alt_tab, key_alt_shift_tab] {
		for split in 1 .. chord.len {
			mut desktop := windows_shortcut_fixture()
			assert windows_shortcut_stream(mut desktop, chord[..split]) == ''
			assert !desktop.switcher.active
			assert windows_shortcut_stream(mut desktop, chord[split..]) == ''
			assert desktop.switcher.active && desktop.switcher.alt_held
			assert windows_shortcut_stream(mut desktop, key_alt_released) == ''
			assert !desktop.switcher.active
		}
	}
	for split in 1 .. key_alt_released.len {
		mut desktop := windows_shortcut_fixture()
		windows_shortcut_stream(mut desktop, key_alt_tab)
		assert windows_shortcut_stream(mut desktop, key_alt_released[..split]) == ''
		assert desktop.switcher.active
		assert windows_shortcut_stream(mut desktop, key_alt_released[split..]) == ''
		assert !desktop.switcher.active
	}
}

fn test_incomplete_or_unrelated_csi_packets_return_to_the_application_intact() {
	mut desktop := windows_shortcut_fixture()
	id := desktop.focus
	assert windows_shortcut_stream(mut desktop, 'a\x1b[1;') == 'a'
	assert windows_shortcut_stream(mut desktop, '5Sb') == '\x1b[1;5Sb'
	assert desktop.window_index(id) != none
	assert windows_shortcut_stream(mut desktop, '\x1b[1;3') == ''
	assert windows_shortcut_stream(mut desktop, '') == '\x1b[1;3'
	assert windows_shortcut_stream(mut desktop, '') == ''
	assert windows_shortcut_stream(mut desktop, '\x1bOS\x1bf\t\x1b[9;7u') == '\x1bOS\x1bf\t\x1b[9;7u'
	assert desktop.window_index(id) != none
	assert !desktop.switcher.active
}

fn test_unfinished_overlay_prefixes_and_a_lone_escape_eventually_pass_through_once() {
	for sequence in ['\x1b', '\x1b[', '\x1b[1;'] {
		mut desktop := windows_shortcut_fixture()
		mut returned := windows_shortcut_stream(mut desktop, sequence)
		for _ in 0 .. 5 {
			returned += windows_shortcut_stream(mut desktop, '')
		}
		assert returned == sequence
		assert windows_shortcut_stream(mut desktop, '') == ''
		assert !desktop.window_overlay_active()
		assert !desktop.switcher.active
	}
}

fn test_global_switching_and_launching_cancel_modals_at_every_split_boundary() {
	for chord in [key_alt_tab, key_alt_shift_tab, '\x1b[9;9u', quick_launch_key] {
		for modal in 0 .. 4 {
			for split in 1 .. chord.len {
				mut desktop := windows_shortcut_fixture()
				match modal {
					0 { desktop.open_window_actions(desktop.focus) }
					1 { desktop.open_window_overview() }
					2 { desktop.open_window_layout(desktop.focus) }
					else { desktop.tile_focused(.left) }
				}
				assert desktop.window_overlay_active()
				assert windows_shortcut_stream(mut desktop, 'ignored${chord[..split]}') == ''
				assert windows_shortcut_stream(mut desktop, '${chord[split..]}queued') == ''
				assert !desktop.window_overlay_active()
				assert desktop.switcher.active
				if chord == quick_launch_key {
					assert desktop.switcher.quick_launch
				} else {
					assert !desktop.switcher.quick_launch
				}
			}
		}
	}
}

fn test_modal_queued_partial_packets_do_not_reach_an_app_after_dismissal() {
	mut desktop := windows_shortcut_fixture()
	desktop.open_window_overview()
	assert windows_shortcut_stream(mut desktop, '\r\x1b[') == ''
	assert !desktop.window_overlay_active()
	assert windows_shortcut_stream(mut desktop, '5~new') == 'new'
	assert windows_shortcut_stream(mut desktop, '') == ''
}

fn test_half_placement_owns_a_coalesced_selection_and_supports_active_super_arrows() {
	mut desktop := windows_shortcut_fixture()
	anchor := desktop.focus
	other := desktop.windows[0].id
	assert windows_shortcut_stream(mut desktop, 'a${key_super_left}\rqueued') == 'a'
	assert !desktop.snap_assist.active
	first := desktop.window_index(anchor) or { panic('missing first window') }
	second := desktop.window_index(other) or { panic('missing second window') }
	assert desktop.windows[first].snap == .left
	assert desktop.windows[second].snap == .right

	mut quarter := windows_shortcut_fixture()
	id := quarter.focus
	assert windows_shortcut_stream(mut quarter, key_super_left) == ''
	assert quarter.snap_assist.active
	assert windows_shortcut_stream(mut quarter, key_super_up) == ''
	assert !quarter.snap_assist.active
	index := quarter.window_index(id) or { panic('missing quarter window') }
	assert quarter.windows[index].snap == .top_left
}

fn test_mixed_global_chords_apply_in_console_order_and_menus_use_the_new_focus() {
	for prefix in ['', key_super_left] {
		mut desktop := windows_shortcut_fixture()
		selected := desktop.windows[0].id
		assert windows_shortcut_stream(mut desktop,
			'a${prefix}${key_alt_tab}${key_alt_released}${key_window_actions}queued') == 'a'
		assert !desktop.switcher.active
		assert !desktop.snap_assist.active
		assert desktop.focus == selected
		assert desktop.window_actions.active
		assert desktop.window_actions.window_id == selected
	}
	mut closing := windows_shortcut_fixture()
	remaining := closing.windows[0].id
	assert windows_shortcut_stream(mut closing, '${key_alt_f4}${key_window_actions}') == ''
	assert closing.windows.len == 1
	assert closing.window_actions.active
	assert closing.window_actions.window_id == remaining
}

fn test_central_launcher_keeps_earlier_app_text_and_owns_later_query_text() {
	mut desktop := windows_shortcut_fixture()
	assert windows_shortcut_stream(mut desktop, 'a${quick_launch_key}fi') == 'a'
	assert desktop.switcher.quick_launch
	assert desktop.quick_launch_query_text() == 'fi'
	assert windows_shortcut_stream(mut desktop, 'les') == ''
	assert desktop.quick_launch_query_text() == 'files'
	assert windows_shortcut_stream(mut desktop, quick_launch_cmd_release) == ''
	assert desktop.switcher.quick_launch
	assert !desktop.switcher.quick_launch_chord_held
	assert windows_shortcut_stream(mut desktop, '\x1b') == ''
	assert windows_shortcut_stream(mut desktop, '') == ''
	assert !desktop.switcher.active
}

fn test_windows_menu_and_layout_chords_coexist_at_every_split_boundary() {
	for chord in [key_window_actions, key_window_actions_legacy, key_super_z] {
		for split in 1 .. chord.len {
			mut desktop := windows_shortcut_fixture()
			assert windows_shortcut_stream(mut desktop, 'a${chord[..split]}') == 'a'
			assert !desktop.window_overlay_active()
			assert windows_shortcut_stream(mut desktop, '${chord[split..]}queued') == ''
			assert !desktop.switcher.active
			if chord == key_super_z {
				assert desktop.window_layout.active
			} else {
				assert desktop.window_actions.active
			}
		}
	}
}

fn test_switcher_opening_cancels_keyboard_geometry_before_snapshotting_windows() {
	mut desktop := windows_shortcut_fixture()
	id := desktop.focus
	index := desktop.window_index(id) or { panic('missing focused window') }
	original := window_action_frame(&desktop.windows[index])
	desktop.open_window_actions(id)
	desktop.begin_window_action_geometry(.move)
	desktop.step_window_action_geometry(1, 0, false)
	assert desktop.windows[index].x != original.x
	desktop.take_switcher_keys(key_alt_tab)
	assert !desktop.window_actions.active
	assert window_action_frame(&desktop.windows[index]) == original
	assert desktop.switcher.active && desktop.switcher.alt_held
	desktop.take_switcher_keys(key_alt_released)
	desktop.tile_focused(.left)
	assert desktop.snap_assist.active
	desktop.take_switcher_keys(key_alt_tab)
	assert !desktop.snap_assist.active
	assert desktop.switcher.active
}
