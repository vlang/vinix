// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Cmd-W is CSI-u's lower-case W codepoint plus the Super modifier (8, then
// one-based in the protocol). The ARM64 keyboard driver emits this for the
// Command key on a Mac keyboard and Super-W on other keyboards.
const key_cmd_w = '\x1b[119;9u'
// Alt+F4 uses xterm's modified F4 encoding. Plain F4 remains app input.
const key_alt_f4 = '\x1b[1;3S'
// Modified arrows use xterm's CSI 1;<modifier><final> form. The modifier value
// follows the same one-based mask as CSI-u: Super is 9.
const key_super_up = '\x1b[1;9A'
const key_super_down = '\x1b[1;9B'
const key_super_right = '\x1b[1;9C'
const key_super_left = '\x1b[1;9D'
const key_super_m = '\x1b[109;9u'
const key_super_shift_m = '\x1b[77;10u'
const key_super_alt_h = '\x1b[104;11u'
const key_super_home = '\x1b[1;9H'
const key_super_workspaces = ['\x1b[49;9u', '\x1b[50;9u', '\x1b[51;9u', '\x1b[52;9u']
// The keyboard protocol carries the shifted character as its codepoint, so
// Shift+1..4 arrive as !, @, # and $ while the modifier still records Shift.
const key_super_shift_workspaces = ['\x1b[33;10u', '\x1b[64;10u', '\x1b[35;10u', '\x1b[36;10u']
const window_shortcut_keys = [key_cmd_w, key_alt_f4, key_super_d, key_super_m, key_super_shift_m,
	key_super_alt_h, key_super_home, key_super_left, key_super_right, key_super_up, key_super_down]

// The switcher's earlier stream parser retains incomplete global chords;
// actions stay here, after its completed packets have passed through.
fn window_shortcut_prefix(input string, at int) bool {
	for key in window_shortcut_keys {
		if match_at(input, at, key) == seq_partial {
			return true
		}
	}
	for workspace in 0 .. workspace_count {
		if match_at(input, at, key_super_workspaces[workspace]) == seq_partial
			|| match_at(input, at, key_super_shift_workspaces[workspace]) == seq_partial {
			return true
		}
	}
	return false
}

fn window_shortcut_sequence(sequence string) bool {
	for key in window_shortcut_keys {
		if sequence == key { return true }
	}
	for workspace in 0 .. workspace_count {
		if sequence == key_super_workspaces[workspace]
			|| sequence == key_super_shift_workspaces[workspace] { return true }
	}
	return false
}

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
				.none_ { d.minimize(window.id) }
			}
		}
	}
	if direction == .left || direction == .right {
		d.open_window_snap_assist(window.id)
	}
}

// take_window_shortcuts removes the global window-management chords from an
// input batch and performs their action. CSI-u chords are normally delivered
// atomically by the keyboard driver, but scan the full batch so Cmd-W still
// works beside ordinary typed input.
fn (mut d Desktop) take_window_shortcuts(keys string) string {
	// A filename editor temporarily owns typing before normal window/app
	// shortcuts. Once rename ends, Files receives ordinary keys again.
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
		if matched <= seq_none {
			matched = match_at(keys, i, key_alt_f4)
		}
		if matched > seq_none {
			if d.focus != 0 {
				d.close_window(d.focus)
			}
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_d)
		if matched > seq_none {
			d.toggle_show_desktop()
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_m)
		if matched > seq_none {
			d.minimize(d.focus)
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_shift_m)
		if matched > seq_none {
			d.restore_isolated_windows()
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_alt_h)
		if matched <= seq_none {
			matched = match_at(keys, i, key_super_home)
		}
		if matched > seq_none {
			d.toggle_window_isolation(d.focus)
			i += matched
			continue
		}
		matched = match_at(keys, i, key_super_left)
		mut horizontal := TileDirection.left
		if matched <= seq_none {
			matched = match_at(keys, i, key_super_right)
			horizontal = .right
		}
		if matched > seq_none {
			d.tile_focused(horizontal)
			i += matched
			if d.snap_assist.active {
				// The chooser opened after the central keyboard router ran.
				// It owns the rest of this same read, including its selection.
				if i < keys.len {
					remainder := unsafe { tos(keys.str + i, keys.len - i) }
					result := d.take_window_overlay_keys(remainder)
					if result.len > 0 && result.str != remainder.str {
						unsafe { result.free() }
					}
				}
				if kept.len == 0 {
					unsafe { kept.free() }
					return ''
				}
				result := kept.bytestr()
				unsafe { kept.free() }
				return result
			}
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
	if kept.len == 0 {
		unsafe { kept.free() }
		return ''
	}
	text := kept.bytestr()
	unsafe { kept.free() }
	return text
}
