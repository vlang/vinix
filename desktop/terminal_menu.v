// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const terminal_action_context_dismiss = 'term.context.dismiss'
const terminal_action_context_panel = 'term.context.panel'

fn (a &TerminalApp) build_context_menu(mut children []ui2.Element, width int, height int) {
	if !a.context_open || width <= 0 || height <= 0 { return }
	rows := if !a.alternate_screen && a.lines.len > 0 { 6 } else { 4 }
	menu_width := terminal_clamp(width, 1, 220)
	padding := if height >= rows + 8 && menu_width > 8 { 4 } else { 0 }
	row_height := terminal_clamp((height - 2 * padding) / rows, 1, 28)
	menu_height := rows * row_height + 2 * padding
	x := terminal_clamp(a.context_x, 0, width - menu_width)
	y := terminal_clamp(a.context_y, 0, height - menu_height)
	actions := [terminal_action_find, terminal_action_copy, terminal_action_selection_mode,
		terminal_action_clear_history, terminal_action_scroll_up, terminal_action_scroll_down]!
	keys := ['terminal.find', 'terminal.selection.copy',
		if a.selection_block { 'terminal.selection.block' } else { 'terminal.selection.text' },
		'terminal.history.clear', 'activity.scroll_up', 'activity.scroll_down']!
	copy_status := a.copy_client.status_key()
	mut items := frame_elements(rows)
	for index in 0 .. rows {
		enabled := index != 1 || a.has_selection()
		items << ui2.Element{
			...ui2.button(actions[index], tr(keys[index]),
				ui2.rect(f64(padding), f64(padding + index * row_height), f64(menu_width - 2 * padding), f64(row_height)),
				ui2.BoxStyle{bg: app_surface, radius: 4},
				ui2.TextStyle{color: if enabled { body_text } else { body_muted }, size: 13})
			enabled: enabled
			checked: index == 2 && a.selection_block
			tooltip: if index == 1 && copy_status.len > 0 { tr(copy_status) }
				else if index == 2 { tr('terminal.selection.mode.help') } else { '' }
		}
	}
	// Catch clicks outside the panel before they can start a new selection.
	children << ui2.clickable_view(terminal_action_context_dismiss, ui2.rect(0, 0, f64(width), f64(height)),
		ui2.BoxStyle{transparent: true}, [])
	children << ui2.clickable_view(terminal_action_context_panel, ui2.rect(f64(x), f64(y), f64(menu_width), f64(menu_height)),
		ui2.BoxStyle{bg: app_surface, radius: 7, border_color: body_rule,
			border_left: 1, border_top: 1, border_right: 1, border_bottom: 1}, items)
}
