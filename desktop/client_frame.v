// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// UI2's optional hello tail describes client-side decorations without changing
// the version-11 headers. Old clients, empty/truncated hellos and unknown bits
// keep the compositor frame. The option is selected before run_window.
fn app_hello_client_frame(payload []u8) bool {
	return app_hello_extended(payload) & app_extended_client_frame != 0
		&& payload.len >= 12 && payload[8] == 1 && payload[9] == 0
		&& payload[10] == 0 && payload[11] == 0
}

fn (w &Window) has_client_frame() bool {
	// If the client fails, recovery supplies standard controls again.
	return w.client_frame && !w.recovery
}

fn (d &Desktop) window_title_height(w &Window) int {
	return if w.has_client_frame() { 0 } else { d.theme().title_height }
}

fn (mut d Desktop) client_frame_element(index int) ui2.Element {
	w := &d.windows[index]
	background, contents := d.window_contents(index, w.width, w.height)
	mut children := frame_elements(9)
	children << ui2.clickable_view(w.id_body, ui2.rect(0, 0, w.width, w.height),
		ui2.BoxStyle{ bg: background }, contents)
	if !w.maximized && w.snap == .none_ {
		// Keep resizing available without painting over the client's frame.
		e := window_resize_edge_size
		g := window_resize_grip_size
		children << resize_grip(w.id_resize_n, g, 0, w.width - 2 * g, e, ui2.cursor_resize_ns)
		children << resize_grip(w.id_resize_s, g, w.height - e, w.width - 2 * g, e, ui2.cursor_resize_ns)
		children << resize_grip(w.id_resize_w, 0, g, e, w.height - 2 * g, ui2.cursor_resize_ew)
		children << resize_grip(w.id_resize_e, w.width - e, g, e, w.height - 2 * g, ui2.cursor_resize_ew)
		children << resize_grip(w.id_resize_nw, 0, 0, g, e, ui2.cursor_resize_nwse)
		children << resize_grip(w.id_resize_ne, w.width - g, 0, g, e, ui2.cursor_resize_nesw)
		children << resize_grip(w.id_resize_sw, 0, w.height - e, g, e, ui2.cursor_resize_nesw)
		children << resize_grip(w.id_resize, w.width - g, w.height - e, g, e, ui2.cursor_resize_nwse)
	}
	// Transparent prevents theme renderers from painting Aero/Luna chrome on
	// this top-level window. The application's body supplies its own surface.
	return ui2.Element{
		...ui2.view(w.id_frame, w.frame_rect(), ui2.BoxStyle{ transparent: true }, children)
		focused: w.id == d.focus
	}
}

// Reserved UI2 actions always address the client window under the pointer.
// They never interpret an application's arbitrary win.<id> selectors.
fn (mut d Desktop) handle_client_window_action(action string, x int, y int) bool {
	if action !in ['ui2.window.close', 'ui2.window.minimize', 'ui2.window.maximize', 'ui2.window.move'] {
		return false
	}
	for i := d.windows.len - 1; i >= 0; i-- {
		w := d.windows[i]
		if w.workspace != d.current_workspace || w.minimized || x < w.x || y < w.y
			|| x >= w.x + w.width || y >= w.y + w.height {
			continue
		}
		if w.app_index < 0 || !w.has_client_frame() { return false }
		d.raise(w.id)
		d.pointer_capture = 0
		d.chrome_pointer_capture = true
		match action {
			'ui2.window.close' { d.close_window(w.id) }
			'ui2.window.minimize' { d.minimize(w.id) }
			'ui2.window.maximize' { d.toggle_maximize(w.id) }
			else {
				d.drag = Drag{
					kind:      .move
					window_id: w.id
					offset_x:  x - w.x
					offset_y:  y - w.y
					shake:     new_window_shake(x, y, monotonic_millis())
				}
				d.drag_damage = DamageRect{}
			}
		}
		d.mark_session_gesture()
		d.dirty = true
		return true
	}
	return false
}
