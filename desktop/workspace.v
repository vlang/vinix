// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Virtual desktops. Windows keep running on the workspace that owns them;
// composition, focus, the taskbar and Cmd-Tab expose only the active one.
module main

const workspace_count = 4
const action_workspace_prefix = 'workspace.'
const workspace_action_ids = ['workspace.0', 'workspace.1', 'workspace.2', 'workspace.3']
const workspace_labels = ['1', '2', '3', '4']

fn workspace_valid(workspace int) bool {
	return workspace >= 0 && workspace < workspace_count
}

fn (d &Desktop) workspace_window_count(workspace int) int {
	mut count := 0
	for window in d.windows {
		if window.workspace == workspace {
			count++
		}
	}
	return count
}

// focus_top_window_in_current_workspace chooses the most recently raised
// visible window. Minimized windows remain on their workspace but do not take
// focus merely because the user arrived there.
fn (mut d Desktop) focus_top_window_in_current_workspace() {
	d.focus = 0
	for i := d.windows.len - 1; i >= 0; i-- {
		if d.windows[i].workspace == d.current_workspace && !d.windows[i].minimized {
			d.focus = d.windows[i].id
			return
		}
	}
}

fn (mut d Desktop) switch_workspace(workspace int) {
	if !workspace_valid(workspace) || workspace == d.current_workspace {
		return
	}
	// Modal compositor UI belongs to the old view. Dropping pointer capture also
	// prevents a drag begun there from moving an invisible window afterwards.
	d.switcher_close()
	if d.start_menu_open {
		d.close_start_menu()
	}
	d.drag = Drag{}
	d.drag_damage = DamageRect{}
	d.pointer_capture = 0
	d.chrome_pointer_capture = false
	d.current_workspace = workspace
	d.focus_top_window_in_current_workspace()
	d.set_hover('')
	d.dirty = true
}

fn (mut d Desktop) move_window_to_workspace(id int, workspace int) {
	if !workspace_valid(workspace) {
		return
	}
	index := d.window_index(id) or { return }
	if d.windows[index].workspace == workspace {
		return
	}
	// A switcher snapshot may contain the window being moved. Close compositor
	// overlays before changing ownership so a later Cmd release cannot focus an
	// invisible window from that stale snapshot.
	d.switcher_close()
	if d.start_menu_open {
		d.close_start_menu()
	}
	was_focused := d.focus == id
	d.windows[index].workspace = workspace
	if d.drag.window_id == id {
		d.drag = Drag{}
		d.drag_damage = DamageRect{}
		d.chrome_pointer_capture = false
	}
	if d.pointer_capture == id {
		d.pointer_capture = 0
	}
	if was_focused {
		d.focus_top_window_in_current_workspace()
	}
	d.dirty = true
}
