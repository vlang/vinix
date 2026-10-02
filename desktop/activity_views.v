// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

enum ActivityView {
	processes
	resources
	gpu
	energy
	startup
}

fn (a &ActivityApp) build_view_tabs(mut children []ui2.Element, width int) {
	keys := ['activity.view.processes', 'activity.view.resources', 'activity.view.gpu',
		'activity.view.energy', 'activity.view.startup']!
	if width < 480 {
		if a.search_focused { return }
		children << ui2.Element{
			...activity_toolbar_button('activity.view.next', tr(keys[int(a.view)]), 112, 36, width - 122, true)
			tooltip: tr('activity.view.next')
		}
		return
	}
	left := if width >= 640 { 360 } else { 270 }
	button_width := (width - left - 8) / 5
	for index, key in keys {
		children << activity_toolbar_button(key, tr(key), left + index * button_width, 36,
			button_width - 2, int(a.view) == index && !a.inspector_open)
	}
}

fn (mut a ActivityApp) build_view_body(mut children []ui2.Element, width int, height int) {
	top := activity_toolbar_height
	a.panel_height = if height > top { height - top } else { 1 }
	minimum := if a.inspector_open { 240 } else {
		match a.view {
			.resources, .gpu { 220 }
			.energy { 210 }
			.startup { 150 }
			else { 1 }
		}
	}
	a.panel_content_height = if a.panel_height > minimum { a.panel_height } else { minimum }
	a.clamp_panel_scroll()
	inner_height := a.panel_content_height
	overflow := inner_height > a.panel_height
	inner_width := if overflow { width - 12 } else { width }
	body := if a.inspector_open {
		a.inspector.build(inner_width, inner_height - 70)
	} else {
		match a.view {
			.resources { a.resources.build(inner_width, inner_height) }
			.gpu { a.gpu.build(inner_width, inner_height) }
			.energy { a.energy.build(inner_width, inner_height) }
			.startup { a.startup.build(inner_width, inner_height) }
			else { ui2.Element{} }
		}
	}
	if !overflow {
		children << ui2.Element{ ...body frame: ui2.rect(0, f64(top), body.frame.width, body.frame.height) }
		if a.inspector_open { a.controls.build(mut children, &a.monitor, width, height - 66) }
		return
	}
	// The compositor clips view children. A short window gets a viewport over
	// complete panel content, so scrolling can reach every action and note.
	mut pane := frame_elements(10)
	pane << ui2.Element{ ...body frame: ui2.rect(0, -f64(a.panel_scroll), body.frame.width, body.frame.height) }
	if a.inspector_open { a.controls.build(mut pane, &a.monitor, inner_width, inner_height - 66 - a.panel_scroll) }
	children << ui2.view('activity.panel.viewport', ui2.rect(0, f64(top), f64(inner_width), f64(a.panel_height)),
		ui2.BoxStyle{ bg: app_surface }, pane)
	position, thumb := activity_scroll_thumb(a.panel_height, a.panel_height, inner_height, a.panel_scroll)
	mut marks := frame_elements(1)
	marks << ui2.view('', ui2.rect(1, f64(position), 6, f64(thumb)), ui2.BoxStyle{ bg: body_muted, radius: 3 }, [])
	children << ui2.clickable_view('activity.panel.scrollbar', ui2.rect(f64(width - 10), f64(top), 8, f64(a.panel_height)),
		ui2.BoxStyle{ bg: body_rule, radius: 4 }, marks)
}

fn (mut a ActivityApp) clamp_panel_scroll() {
	maximum := a.panel_content_height - a.panel_height
	if a.panel_scroll > maximum { a.panel_scroll = maximum }
	if a.panel_scroll < 0 { a.panel_scroll = 0 }
}

fn (a &ActivityApp) panel_overflows() bool {
	return (a.inspector_open || a.view != .processes) && a.panel_content_height > a.panel_height
}

fn (mut a ActivityApp) panel_key_input(input string) bool {
	if !a.panel_overflows() { return false }
	before := a.panel_scroll
	match input {
		'\x1b[A' { a.panel_scroll -= activity_row_height }
		'\x1b[B' { a.panel_scroll += activity_row_height }
		'\x1b[5~' { a.panel_scroll -= a.panel_height }
		'\x1b[6~' { a.panel_scroll += a.panel_height }
		'\x1b[H', '\x1b[1~' { a.panel_scroll = 0 }
		'\x1b[F', '\x1b[4~' { a.panel_scroll = a.panel_content_height }
		else { return false }
	}
	a.clamp_panel_scroll()
	return a.panel_scroll != before
}

fn (mut a ActivityApp) panel_pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int,
	x int, y int, width int) bool {
	if phase == .up {
		a.panel_dragging = false
		return false
	}
	if !a.panel_overflows() { return false }
	if phase == .scroll && y >= activity_toolbar_height {
		before := a.panel_scroll
		a.panel_scroll -= scroll * 33
		a.clamp_panel_scroll()
		return before != a.panel_scroll
	}
	if phase == .move && a.panel_dragging {
		_, thumb := activity_scroll_thumb(a.panel_height, a.panel_height, a.panel_content_height, a.panel_drag_scroll)
		travel := a.panel_height - thumb
		if travel > 0 {
			a.panel_scroll = a.panel_drag_scroll + (y - a.panel_drag_y) * (a.panel_content_height - a.panel_height) / travel
			a.clamp_panel_scroll()
		}
		return true
	}
	if phase != .down || button != .left || x < width - 12 || y < activity_toolbar_height
		|| y >= activity_toolbar_height + a.panel_height { return false }
	position, thumb := activity_scroll_thumb(a.panel_height, a.panel_height, a.panel_content_height, a.panel_scroll)
	offset := y - activity_toolbar_height
	if offset < position || offset >= position + thumb {
		a.panel_scroll += if offset < position { -a.panel_height } else { a.panel_height }
		a.clamp_panel_scroll()
	}
	a.panel_dragging = true
	a.panel_drag_y = y
	a.panel_drag_scroll = a.panel_scroll
	return true
}

fn (mut a ActivityApp) handle_view(action string) bool {
	if action == 'activity.view.next' {
		a.view = unsafe { ActivityView((int(a.view) + 1) % 5) }
		a.inspector_open = false
		a.columns_open = false
		a.search_focused = false
		a.panel_scroll = 0
		a.panel_dragging = false
		return true
	}
	keys := ['activity.view.processes', 'activity.view.resources', 'activity.view.gpu',
		'activity.view.energy', 'activity.view.startup']!
	for index, key in keys {
		if action == key {
			a.view = unsafe { ActivityView(index) }
			a.inspector_open = false
			a.columns_open = false
			a.search_focused = false
			a.panel_scroll = 0
			a.panel_dragging = false
			return true
		}
	}
	if action == activity_inspect_close {
		a.inspector_open = false
		a.panel_scroll = 0
		return true
	}
	if action == 'activity.panel.scrollbar' { return true }
	if a.inspector_open && a.inspector.handle(action) { return true }
	if a.view == .resources && a.resources.handle(action) { return true }
	if a.view == .startup && a.startup.handle(action) { return true }
	return false
}
