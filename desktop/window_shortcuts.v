// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Cmd-W is CSI-u's lower-case W codepoint plus the Super modifier (8, then
// one-based in the protocol). The ARM64 keyboard driver emits this for the
// Command key on a Mac keyboard and Super-W on other keyboards.
const key_cmd_w = '\x1b[119;9u'
// Modified arrows use xterm's CSI 1;<modifier><final> form. The modifier value
// follows the same one-based mask as CSI-u: Super is 9.
const key_super_up = '\x1b[1;9A'
const key_super_down = '\x1b[1;9B'
const key_super_right = '\x1b[1;9C'
const key_super_left = '\x1b[1;9D'
const key_super_workspaces = ['\x1b[49;9u', '\x1b[50;9u', '\x1b[51;9u', '\x1b[52;9u']
// The keyboard protocol carries the shifted character as its codepoint, so
// Shift+1..4 arrive as !, @, # and $ while the modifier still records Shift.
const key_super_shift_workspaces = ['\x1b[33;10u', '\x1b[64;10u', '\x1b[35;10u', '\x1b[36;10u']

enum TileDirection {
	up
	down
	left
	right
}

// tile_focused implements the familiar Super+Arrow arrangement. Horizontal
// arrows occupy a half; following one with Up or Down makes a quarter. Up on
// a floating window maximizes it, while Down restores arranged windows.
fn (mut d Desktop) tile_focused(direction TileDirection) {
	if d.focus == 0 {
		return
	}
	index := d.window_index(d.focus) or { return }
	window := d.windows[index]
	match direction {
		.left {
			next := match window.snap {
				.top_right { WindowSnap.top_left }
				.bottom_right { WindowSnap.bottom_left }
				else { WindowSnap.left }
			}
			d.snap_window(window.id, next)
		}
		.right {
			next := match window.snap {
				.top_left { WindowSnap.top_right }
				.bottom_left { WindowSnap.bottom_right }
				else { WindowSnap.right }
			}
			d.snap_window(window.id, next)
		}
		.up {
			match window.snap {
				.left, .bottom_left { d.snap_window(window.id, .top_left) }
				.right, .bottom_right { d.snap_window(window.id, .top_right) }
				.top_left, .top_right {}
				.none_ { d.maximize(window.id) }
			}
		}
		.down {
			if window.maximized {
				d.restore_window(window.id)
				return
			}
			match window.snap {
				.left, .top_left { d.snap_window(window.id, .bottom_left) }
				.right, .top_right { d.snap_window(window.id, .bottom_right) }
				.bottom_left, .bottom_right { d.restore_window(window.id) }
				.none_ {}
			}
		}
	}
}

// take_window_shortcuts removes the global window-management chords from an
// input batch and performs their action. CSI-u chords are normally delivered
// atomically by the keyboard driver, but scan the full batch so Cmd-W still
// works beside ordinary typed input.
fn (mut d Desktop) take_window_shortcuts(keys string) string {
	// A filename editor temporarily owns typing before normal window/app
	// shortcuts. Files is otherwise not a KeyboardApp, so the moment rename
	// ends the desktop's regular shortcut routing is unchanged.
	if desktop_directory_state.rename_path.len > 0 || create_context_menu.rename_app_index >= 0 {
		d.file_context_rename_key_input(keys)
		return ''
	}
	if keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len}
	mut i := 0
	for i < keys.len {
		mut matched := match_at(keys, i, key_cmd_w)
		if matched > seq_none {
			if d.focus != 0 {
				d.close_window(d.focus)
			}
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_left)
		if matched > seq_none {
			d.tile_focused(.left)
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_right)
		if matched > seq_none {
			d.tile_focused(.right)
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_up)
		if matched > seq_none {
			d.tile_focused(.up)
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_down)
		if matched > seq_none {
			d.tile_focused(.down)
			i += matched
			continue
		}
		mut workspace_taken := false
		for workspace in 0 .. workspace_count {
			matched = match_at(keys, i, key_super_workspaces[workspace])
			if matched > seq_none {
				d.switch_workspace(workspace)
				i += matched
				workspace_taken = true
				break
			}
			matched = match_at(keys, i, key_super_shift_workspaces[workspace])
			if matched > seq_none {
				if d.focus != 0 {
					d.move_window_to_workspace(d.focus, workspace)
				}
				i += matched
				workspace_taken = true
				break
			}
		}
		if workspace_taken {
			continue
		}
		kept << keys[i]
		i++
	}
	if kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	return kept.bytestr()
}
