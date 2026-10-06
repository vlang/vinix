// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

struct SnapAssistPointerTestApp {
mut:
	presses  int
	releases int
}

fn (mut app SnapAssistPointerTestApp) build(_ ui2.Rect) !ui2.Element {
	return ui2.screen(0, [])
}

fn (mut app SnapAssistPointerTestApp) handle(_ string) ! {}

fn (mut app SnapAssistPointerTestApp) pointer_input_enabled() bool {
	return true
}

fn (mut app SnapAssistPointerTestApp) pointer_event(phase AppPointerPhase, _ AppPointerButton,
	_ int, _ int, _ int, _ int, _ int) {
	if phase == .down { app.presses++ }
	if phase == .up { app.releases++ }
}

fn snap_assist_fixture() Desktop {
	return Desktop{ canvas: Canvas{ width: 801, height: 601 } }
}

fn snap_assist_named(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		found := snap_assist_named(child, id) or { continue }
		return found
	}
	return none
}

fn snap_assist_has_image(element ui2.Element, path string) bool {
	if element.image_path == path { return true }
	for child in element.children {
		if snap_assist_has_image(child, path) { return true }
	}
	return false
}

fn test_snap_assist_offers_visible_workspace_candidates_without_moving_them() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	candidate := desktop.spawn('Candidate', .system, 250, 140, 340, 220)
	hidden := desktop.spawn('Hidden', .welcome, 200, 100, 300, 200)
	desktop.minimize(hidden)
	offscreen := desktop.spawn('Outside', .welcome, 900, 100, 300, 200)
	desktop.switch_workspace(1)
	other_workspace := desktop.spawn('Other workspace', .welcome, 100, 70, 300, 200)
	desktop.switch_workspace(0)
	desktop.snap_window(anchor, .left)
	desktop.open_window_snap_assist(anchor)
	assert desktop.snap_assist.active
	assert desktop.snap_assist.target == .right
	assert desktop.snap_assist.anchor_id == anchor
	assert desktop.snap_assist.selected_id == candidate
	assert desktop.focus == anchor
	assert desktop.window_snap_assist_count() == 1
	for excluded in [anchor, hidden, offscreen, other_workspace] {
		assert desktop.window_snap_assist_position(excluded) == none
	}
	index := desktop.window_index(candidate) or { panic('missing untouched candidate') }
	assert desktop.windows[index].x == 250
	assert desktop.windows[index].y == 140
	assert desktop.windows[index].width == 340
	assert desktop.windows[index].height == 220
	assert desktop.windows[index].snap == .none_
	assert !desktop.windows[index].minimized
	root := desktop.window_snap_assist_element() or { panic('missing assist') }
	panel := snap_assist_named(root, window_snap_assist_panel) or { panic('missing assist panel') }
	assert panel.frame.x >= 400
	assert panel.frame.x + panel.frame.width <= 801
	assert panel.frame.y + panel.frame.height <= desktop_usable_height(601)
	assert snap_assist_named(root, desktop.windows[index].id_preview) != none
	free_tree(root)
	assert desktop.window_snap_assist_pointer_down(window_snap_assist_dismiss, .desktop)
	assert !desktop.snap_assist.active
	assert desktop.windows[index].x == 250
	assert desktop.windows[index].snap == .none_
}

fn test_snap_assist_skips_nonhalves_empty_workspaces_and_filled_opposite_half() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	desktop.snap_window(anchor, .left)
	desktop.open_window_snap_assist(anchor)
	assert !desktop.snap_assist.active
	other := desktop.spawn('Other', .system, 250, 140, 340, 220)
	for snap in [WindowSnap.top_left, .top_right, .bottom_left, .bottom_right] {
		desktop.snap_window(anchor, snap)
		desktop.open_window_snap_assist(anchor)
		assert !desktop.snap_assist.active
	}
	desktop.maximize(anchor)
	desktop.open_window_snap_assist(anchor)
	assert !desktop.snap_assist.active
	desktop.snap_window(anchor, .left)
	desktop.snap_window(other, .right)
	desktop.open_window_snap_assist(anchor)
	assert !desktop.snap_assist.active
	desktop.minimize(other)
	desktop.open_window_snap_assist(anchor)
	assert !desktop.snap_assist.active
	desktop.spawn('Candidate', .welcome, 250, 140, 340, 220)
	desktop.open_window_snap_assist(anchor)
	assert desktop.snap_assist.active
}

fn test_snap_assist_keyboard_selects_opposite_half_and_preserves_restore_frame() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	one := desktop.spawn('One', .welcome, 250, 140, 340, 220)
	two := desktop.spawn('Two', .system, 300, 170, 300, 210)
	desktop.snap_window(anchor, .right)
	desktop.open_window_snap_assist(anchor)
	assert desktop.snap_assist.selected_id == two
	assert desktop.take_window_snap_assist_keys('\x1b[C\rqueued typing') == ''
	assert !desktop.snap_assist.active
	assert desktop.focus == one
	index := desktop.window_index(one) or { panic('missing selected companion') }
	assert desktop.windows[index].snap == .left
	assert desktop.windows[index].x == 0
	assert desktop.windows[index].y == 0
	assert desktop.windows[index].width == 400
	assert desktop.windows[index].height == desktop_usable_height(601)
	assert desktop.windows[index].restore_x == 250
	assert desktop.windows[index].restore_y == 140
	assert desktop.windows[index].restore_width == 340
	assert desktop.windows[index].restore_height == 220
	other := desktop.window_index(two) or { panic('missing untouched companion') }
	assert desktop.windows[other].snap == .none_
	desktop.restore_window(one)
	assert desktop.windows[index].x == 250
	assert desktop.windows[index].y == 140
	assert desktop.windows[index].width == 340
	assert desktop.windows[index].height == 220
}

fn test_snap_assist_super_arrows_keep_quarter_workflow_on_stable_anchor() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	candidate := desktop.spawn('Candidate', .system, 250, 140, 340, 220)
	desktop.raise(anchor)
	assert desktop.take_window_shortcuts(key_super_left) == ''
	assert desktop.snap_assist.active
	assert desktop.snap_assist.anchor_id == anchor
	desktop.raise(candidate)
	assert desktop.take_window_snap_assist_keys(key_super_up) == ''
	assert !desktop.snap_assist.active
	assert desktop.focus == anchor
	index := desktop.window_index(anchor) or { panic('missing quarter anchor') }
	assert desktop.windows[index].snap == .top_left
	assert desktop.windows[index].restore_x == 100
	assert desktop.windows[index].restore_y == 70
	other := desktop.window_index(candidate) or { panic('missing untouched candidate') }
	assert desktop.windows[other].snap == .none_
	assert desktop.take_window_shortcuts(key_super_down) == ''
	assert desktop.windows[index].snap == .bottom_left
}

fn test_snap_assist_keyboard_handles_fragmented_arrows_escape_and_modifier_release() {
	for sequence in ['\x1b[C', '\x1bOC'] {
		for split in 1 .. sequence.len {
			mut desktop := snap_assist_fixture()
			anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
			one := desktop.spawn('One', .welcome, 250, 140, 340, 220)
			two := desktop.spawn('Two', .system, 300, 170, 300, 210)
			desktop.snap_window(anchor, .left)
			desktop.open_window_snap_assist(anchor)
			assert desktop.take_window_snap_assist_keys(sequence[..split]) == ''
			assert desktop.snap_assist.selected_id == two
			assert desktop.take_window_snap_assist_keys(sequence[split..]) == ''
			assert desktop.snap_assist.selected_id == one
			assert desktop.snap_assist.pending_len == 0
		}
	}
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	candidate := desktop.spawn('Candidate', .system, 250, 140, 340, 220)
	desktop.snap_window(anchor, .left)
	desktop.open_window_snap_assist(anchor)
	assert desktop.take_window_snap_assist_keys(quick_launch_cmd_release) == ''
	assert desktop.snap_assist.active
	assert desktop.take_window_snap_assist_keys('\x1b') == ''
	assert desktop.snap_assist.active
	assert desktop.take_window_snap_assist_keys('') == ''
	assert !desktop.snap_assist.active
	assert desktop.take_window_snap_assist_keys('app text') == 'app text'
	desktop.open_window_snap_assist(anchor)
	assert desktop.take_window_snap_assist_keys('\x1bqueued typing') == ''
	assert !desktop.snap_assist.active
	index := desktop.window_index(candidate) or { panic('missing dismissed candidate') }
	assert desktop.windows[index].snap == .none_
}

fn test_snap_assist_pointer_uses_stable_ids_and_consumes_application_collisions() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	one := desktop.spawn('One', .welcome, 250, 140, 340, 220)
	two := desktop.spawn('Two', .system, 300, 170, 300, 210)
	desktop.snap_window(anchor, .left)
	desktop.open_window_snap_assist(anchor)
	index := desktop.window_index(two) or { panic('missing disappearing companion') }
	stale := desktop.windows[index].id_preview.clone()
	desktop.close_window(two)
	assert desktop.window_snap_assist_pointer_down(stale, .desktop)
	assert desktop.snap_assist.active
	assert desktop.snap_assist.selected_id == one
	unsafe { stale.free() }
	current := desktop.window_index(one) or { panic('missing remaining companion') }
	assert desktop.window_snap_assist_pointer_down(desktop.windows[current].id_preview, .application)
	assert !desktop.snap_assist.active
	assert desktop.windows[current].snap == .none_
	desktop.open_window_snap_assist(anchor)
	assert desktop.window_snap_assist_pointer_down(window_snap_assist_panel, .desktop)
	assert desktop.snap_assist.active
	assert desktop.window_snap_assist_pointer_down(desktop.windows[current].id_preview, .desktop)
	assert !desktop.snap_assist.active
	committed := desktop.window_index(one) or { panic('missing placed companion') }
	assert desktop.windows[committed].snap == .right
	assert desktop.windows[committed].width == 401
	assert desktop.focus == one
}

fn test_snap_assist_revalidates_anchor_and_target_before_committing() {
	for invalidate in 0 .. 4 {
		mut desktop := snap_assist_fixture()
		anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
		candidate := desktop.spawn('Candidate', .system, 250, 140, 340, 220)
		desktop.snap_window(anchor, .left)
		desktop.open_window_snap_assist(anchor)
		match invalidate {
			0 { desktop.minimize(anchor) }
			1 { desktop.close_window(anchor) }
			2 { desktop.snap_window(anchor, .top_left) }
			else { desktop.snap_window(candidate, .right) }
		}
		desktop.commit_window_snap_assist(candidate)
		assert !desktop.snap_assist.active
		index := desktop.window_index(candidate) or { panic('missing candidate after invalidation') }
		if invalidate < 3 {
			assert desktop.windows[index].snap == .none_
		}
	}
}

fn test_snap_assist_borrows_thumbnail_and_has_icon_fallback() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	candidate := desktop.spawn('Candidate', .system, 250, 140, 340, 220)
	icon_only := desktop.spawn('Icon only', .welcome, 300, 170, 300, 210)
	desktop.snap_window(anchor, .left)
	index := desktop.window_index(candidate) or { panic('missing thumbnail candidate') }
	desktop.windows[index].thumbnail = []u32{len: 8, init: 0x123456}
	desktop.windows[index].thumbnail_width = 4
	desktop.windows[index].thumbnail_height = 2
	desktop.windows[index].thumbnail_scale = 1
	thumbnail := desktop.windows[index].thumbnail.data
	fallback := desktop.window_index(icon_only) or { panic('missing fallback candidate') }
	desktop.windows[fallback].icon = ''
	desktop.open_window_snap_assist(anchor)
	root := desktop.window_snap_assist_element() or { panic('missing thumbnail assist') }
	assert snap_assist_has_image(root, desktop.windows[index].id_thumbnail)
	assert snap_assist_has_image(root, 'builtin:window')
	free_tree(root)
	assert desktop.windows[index].thumbnail.data == thumbnail
	assert desktop.windows[index].thumbnail.len == 8
}

fn test_snap_assist_pages_keep_every_candidate_reachable_on_small_screen() {
	mut desktop := Desktop{ canvas: Canvas{ width: 320, height: 240 } }
	anchor := desktop.spawn('Anchor', .welcome, 20, 20, 240, 140)
	for _ in 0 .. 12 { desktop.spawn('Candidate', .welcome, 30, 30, 220, 130) }
	desktop.snap_window(anchor, .left)
	desktop.open_window_snap_assist(anchor)
	layout := window_snap_assist_layout(.right, 320, 240)
	assert layout.capacity() == 1
	assert layout.x >= 160
	assert layout.x + layout.width <= 320
	assert layout.y + layout.height <= desktop_usable_height(240)
	first := desktop.snap_assist.selected_id
	for page in 0 .. 12 {
		assert desktop.snap_assist.page == page
		root := desktop.window_snap_assist_element() or { panic('missing paged assist') }
		panel := snap_assist_named(root, window_snap_assist_panel) or { panic('missing paged panel') }
		index := desktop.window_index(desktop.snap_assist.selected_id) or { panic('missing selected card') }
		card := snap_assist_named(panel, desktop.windows[index].id_preview) or { panic('missing paged card') }
		assert card.frame.x + card.frame.width <= panel.frame.width
		assert card.frame.y + card.frame.height <= panel.frame.height
		for action in [window_snap_assist_previous, window_snap_assist_next] {
			button := snap_assist_named(panel, action) or { panic('missing page control') }
			assert button.frame.x + button.frame.width <= panel.frame.width
			assert button.frame.y + button.frame.height <= panel.frame.height
		}
		free_tree(root)
		assert desktop.window_snap_assist_pointer_down(window_snap_assist_next, .desktop)
	}
	assert desktop.snap_assist.page == 0
	assert desktop.snap_assist.selected_id == first
}

fn test_snap_assist_cancels_held_raw_pointer_and_closes_other_overlays() {
	mut desktop := snap_assist_fixture()
	anchor := desktop.spawn('Anchor', .welcome, 100, 70, 360, 250)
	desktop.apps << SnapAssistPointerTestApp{}
	id := desktop.spawn('Pointer', .app, 450, 70, 300, 230)
	index := desktop.window_index(id) or { panic('missing pointer window') }
	desktop.windows[index].app_index = 0
	desktop.snap_window(anchor, .left)
	desktop.buttons = button_left
	desktop.on_pointer_down(500, 160)
	assert desktop.pointer_capture == id
	desktop.window_actions.active = true
	desktop.overview.active = true
	desktop.window_layout.active = true
	desktop.open_window_snap_assist(anchor)
	assert desktop.snap_assist.active
	assert !desktop.window_actions.active
	assert !desktop.overview.active
	assert !desktop.window_layout.active
	assert desktop.pointer_capture == 0
	assert desktop.buttons == button_left
	assert desktop.drag.kind == .none_
	desktop.buttons = 0
	desktop.on_pointer_move(500, 160)
	desktop.on_pointer_up(500, 160)
	assert desktop.snap_assist.active
	app := desktop.apps[0]
	if app is SnapAssistPointerTestApp {
		assert app.presses == 1
		assert app.releases == 1
	} else {
		panic('missing pointer fixture')
	}
}
