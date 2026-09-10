// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

// Cmd-W is CSI-u's lower-case W codepoint plus the Super modifier (8, then
// one-based in the protocol). The ARM64 keyboard driver emits this for the
// Command key on a Mac keyboard and Super-W on other keyboards.
const key_cmd_w = '\x1b[119;9u'

// take_window_shortcuts removes the global window-management chords from an
// input batch and performs their action. CSI-u chords are normally delivered
// atomically by the keyboard driver, but scan the full batch so Cmd-W still
// works beside ordinary typed input.
fn (mut d Desktop) take_window_shortcuts(keys string) string {
	if keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len}
	mut i := 0
	for i < keys.len {
		matched := match_at(keys, i, key_cmd_w)
		if matched > seq_none {
			if d.focus != 0 {
				d.close_window(d.focus)
			}
			i += matched
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
