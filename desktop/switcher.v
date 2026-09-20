// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Cmd-Tab: the window switcher, and the global Cmd-Space keyboard hook.
//
// A tap moves to the window under the one on top, the way Alt-Tab and Cmd-Tab
// have always worked. Holding Cmd down instead asks the question "what else is
// open?", and after a moment the desktop answers it: a panel in the middle of
// the screen with a tile for every window, the selection moving along it on
// each further Tab, and the window it lands on raised when Cmd is let go.
//
// A terminal has no way to say "Cmd", so the keyboard drivers say it for it.
// Cmd-Tab and Cmd-Space arrive in CSI-u form with the super bit set, and the
// release of Cmd — which no terminal has ever had a reason to report — arrives
// as the encoding of the left Super key with an event type of "released".
// These sequences are taken out before focused applications see them, so both
// window switching and Quick Launch remain desktop-global shortcuts.
module main

import ui2

// How long Cmd must stay down before the panel appears. A tap is a switch and
// shows nothing; holding on is a question, and gets the answer.
const switcher_reveal_ms = i64(400)

// The action ids of the tiles. A click on one switches to that window, which
// is the one thing the panel can do that the keyboard cannot say faster.
const action_switch_prefix = 'switch.'

// SwitcherKey is one sequence the drivers send and what it does to the
// selection: forwards, backwards, Quick Launch, or `commit` when Cmd is let go.
struct SwitcherKey {
	bytes string
	step  int
}

const switch_commit = 0
const switch_quick_launch = 2

const switcher_keys = [
	SwitcherKey{quick_launch_key, switch_quick_launch},
	SwitcherKey{'\x1b[9;9u', 1},
	SwitcherKey{'\x1b[9;10u', -1},
	SwitcherKey{quick_launch_cmd_release, switch_commit},
]

// The arrows move the selection too, as they do on macOS, but only while a
// session is open. At any other time they are the focused application's and
// must arrive there untouched.
const switcher_arrows = [
	SwitcherKey{'\x1b[C', 1},
	SwitcherKey{'\x1b[D', -1},
]

// What a sequence lookup found: how many bytes it took, nothing, or that the
// read ended inside one and the rest has yet to arrive.
const seq_none = 0
const seq_partial = -1

// Switcher is one press-and-hold of Cmd. It is `active` from the first Tab
// until Cmd is let go, and `shown` once the hold has gone on long enough for
// the panel to be worth drawing. Quick Launch borrows the same modal overlay
// and keyboard parser, but remains shown after Cmd is released.
struct Switcher {
mut:
	active  bool
	shown   bool
	started i64
	index   int
	// The windows, most recently raised first, taken once when the session
	// opens. The painting order it comes from changes as windows are raised,
	// and a row that reshuffled under the selection while it was being read
	// would be unusable.
	order []int
	// Tile action ids. They depend only on a position in the row, so they are
	// built once and kept: the tree is rebuilt every frame, this target has no
	// garbage collector, and the count is however many windows or app results
	// have ever needed to be shown at once.
	ids []string
	// Quick Launch lives inside the switcher's global-input path so it can own
	// typing even when the focused application normally consumes the keyboard.
	quick_launch            bool
	quick_launch_chord_held bool
	query                   []u8
	// The start of a sequence that the read ended inside, held until the next
	// read completes it.
	pending string
}

// ── The keys ───────────────────────────────────────────────────────

// take_switcher_keys acts on every desktop-global Cmd sequence in the input
// and returns what is left. An empty read still goes through, because a
// held-back partial sequence has to be let go when nothing arrives to complete
// it. While Quick Launch is active, all remaining input belongs to its query.
fn (mut d Desktop) take_switcher_keys(keys string) string {
	mut input := keys
	if d.switcher.pending.len > 0 {
		if keys.len == 0 {
			// Nothing completed it, so it was not one of ours after all.
			held := d.switcher.pending
			d.switcher.pending = ''
			if d.switcher.quick_launch {
				// There is no focused application to release this escape to while
				// Quick Launch owns input. Treat it as Escape and dismiss instead
				// of storing the same partial sequence again forever.
				d.switcher_close()
				return ''
			}
			return held
		}
		input = d.switcher.pending + keys
		d.switcher.pending = ''
	}

	if d.switcher.quick_launch {
		return d.quick_launch_take_keys(input)
	}

	// Every sequence starts with an escape, so a string without one is nothing
	// of ours and is returned as it came rather than rebuilt -- there is no
	// garbage collector here, and this runs on every frame that has input.
	if input.index_u8(0x1b) < 0 {
		return input
	}

	mut kept := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		if input[i] == 0x1b {
			taken := d.take_switcher_sequence(input, i)
			if taken > seq_none {
				i += taken
				if d.switcher.quick_launch {
					// A console read can contain Cmd-Space, its release and the
					// first typed character together. Everything after the chord
					// belongs to the newly opened launcher; bytes before it still
					// belong to the previously focused application.
					if i < input.len {
						d.quick_launch_take_keys(input[i..])
					}
					if kept.len == 0 {
						unsafe { kept.free() }
						return ''
					}
					return kept.bytestr()
				}
				continue
			}
			if taken == seq_partial {
				// The read ended inside one of ours. Hold it back rather than
				// hand an application half a sequence: what follows decides
				// whether these bytes were a chord or an escape someone typed.
				d.switcher.pending = input[i..]
				break
			}
		}
		kept << input[i]
		i++
	}
	if kept.len == input.len {
		unsafe { kept.free() }
		return input
	}
	return kept.bytestr()
}

// take_switcher_sequence tries every sequence at one position, acts on the one
// that matches, and answers with how many bytes it took.
fn (mut d Desktop) take_switcher_sequence(input string, at int) int {
	mut partial := false
	for key in switcher_keys {
		found := match_at(input, at, key.bytes)
		if found > seq_none {
			if key.step == switch_commit {
				d.switcher.quick_launch_chord_held = false
				d.switcher_commit()
			} else if key.step == switch_quick_launch {
				// Key repeat must not alternate open/closed while Cmd-Space is
				// held. The explicit Cmd-release sequence arms the next press.
				if !d.switcher.quick_launch_chord_held {
					d.switcher.quick_launch_chord_held = true
					d.toggle_quick_launch()
				}
			} else {
				d.switcher_step(key.step)
			}
			return found
		}
		partial = partial || found == seq_partial
	}
	// The arrows are only the switcher's while a session is open. At any other
	// time they are the focused application's and must arrive untouched.
	if d.switcher.active {
		for key in switcher_arrows {
			found := match_at(input, at, key.bytes)
			if found > seq_none {
				d.switcher_step(key.step)
				return found
			}
			partial = partial || found == seq_partial
		}
	}
	return if partial { seq_partial } else { seq_none }
}

// match_at answers with the length of `seq` if it is at `at`. It compares
// without slicing: this is on the path every keystroke takes, and a substring
// per escape byte would allocate for nothing.
fn match_at(input string, at int, seq string) int {
	for i := 0; i < seq.len; i++ {
		if at + i >= input.len {
			// A lone escape is a key someone pressed, not the start of a
			// chord, and holding it back for a frame would be felt. Anything
			// longer is only ever the beginning of a sequence.
			return if i > 1 { seq_partial } else { seq_none }
		}
		if input[at + i] != seq[i] {
			return seq_none
		}
	}
	return seq.len
}

// ── The session ────────────────────────────────────────────────────

// switcher_step opens a session if none is open and moves the selection along
// it. Opening it leaves the selection on the window on top and then steps once,
// so the first Cmd-Tab lands on the one underneath -- which is the whole of
// what a tap is for.
fn (mut d Desktop) switcher_step(step int) {
	if !d.switcher.active {
		d.switcher.order.clear()
		for i := d.windows.len - 1; i >= 0; i-- {
			d.switcher.order << d.windows[i].id
		}
		if d.switcher.order.len == 0 {
			return
		}
		for d.switcher.ids.len < d.switcher.order.len {
			d.switcher.ids << '${action_switch_prefix}${d.switcher.ids.len}'
		}
		d.switcher.active = true
		d.switcher.shown = false
		d.switcher.index = 0
		d.switcher.started = monotonic_millis()
	}
	count := d.switcher.order.len
	if count == 0 {
		return
	}
	d.switcher.index = ((d.switcher.index + step) % count + count) % count
	d.dirty = true
}

// switcher_commit raises what the selection landed on and closes the session.
// A minimised window comes back rather than being switched to invisibly.
fn (mut d Desktop) switcher_commit() {
	if !d.switcher.active {
		return
	}
	if d.switcher.quick_launch {
		// Cmd release does not commit Quick Launch; this guard only protects
		// callers that deliberately ask to commit its current selection.
		return
	}
	mut id := 0
	if d.switcher.index >= 0 && d.switcher.index < d.switcher.order.len {
		id = d.switcher.order[d.switcher.index]
	}
	d.switcher_close()
	index := d.window_index(id) or { return }
	d.windows[index].minimized = false
	d.raise(id)
}

// switcher_close ends the session without switching, which is what a click
// somewhere else means. Quick Launch also owns a manual query buffer that must
// be released when its overlay goes away.
fn (mut d Desktop) switcher_close() {
	if !d.switcher.active {
		return
	}
	if d.switcher.quick_launch {
		d.quick_launch_free_query()
		d.switcher.quick_launch = false
	}
	d.switcher.active = false
	d.switcher.shown = false
	d.dirty = true
}

// switcher_select is a click on a tile. Normal mode switches windows; Quick
// Launch maps the visible result back to available_apps and uses the existing
// application launcher.
fn (mut d Desktop) switcher_select(index int) {
	if !d.switcher.active {
		return
	}
	if d.switcher.quick_launch {
		if index == -2 {
			d.switcher_close()
			return
		}
		if index < 0 {
			return
		}
		app_index := d.quick_launch_app_index(index) or { return }
		d.switcher.index = index
		d.switcher_close()
		d.launch_index(app_index)
		return
	}
	if index < 0 || index >= d.switcher.order.len {
		return
	}
	d.switcher.index = index
	d.switcher_commit()
}

// update_switcher reveals the panel once Cmd has been held long enough. It is
// the one thing on screen that changes without an event to change it, so the
// frame loop asks every time round rather than waiting to be told.
fn (mut d Desktop) update_switcher() {
	if !d.switcher.active || d.switcher.shown {
		return
	}
	if monotonic_millis() - d.switcher.started >= switcher_reveal_ms {
		d.switcher.shown = true
		d.dirty = true
	}
}

// ── The panel ──────────────────────────────────────────────────────

// switcher_element is the panel: a tile per open window, the selection behind
// one of them, and its title underneath. Quick Launch uses the same top-most
// compositor slot for its Spotlight-style search panel.
fn (d &Desktop) switcher_element() ui2.Element {
	if d.switcher.quick_launch {
		return d.quick_launch_element()
	}

	theme := d.theme()
	count := d.switcher.order.len

	// One row if the tiles fit, and as many as it takes if they do not. The
	// panel is a picture of everything that is open, so dropping windows off
	// the end of it is the one thing it must not do.
	room := d.canvas.width - 2 * switcher_margin
	mut columns := (room + switcher_gap) / (switcher_tile + switcher_gap)
	if columns > count {
		columns = count
	}
	if columns < 1 {
		columns = 1
	}
	rows := (count + columns - 1) / columns

	panel_width := columns * switcher_tile + (columns - 1) * switcher_gap + 2 * switcher_padding
	panel_height := rows * switcher_tile + (rows - 1) * switcher_gap + 2 * switcher_padding + switcher_label_height

	mut children := frame_elements(count + 1)
	for i, id in d.switcher.order {
		index := d.window_index(id) or { continue }
		window := d.windows[index]
		x := switcher_padding + (i % columns) * (switcher_tile + switcher_gap)
		y := switcher_padding + (i / columns) * (switcher_tile + switcher_gap)
		selected := i == d.switcher.index
		icon_inset := (switcher_tile - switcher_icon_size) / 2
		// A minimised window is dimmed rather than marked with a character, as
		// its taskbar entry is: the baked faces are ASCII, so a nice bullet
		// would come out blank.
		icon_color := if selected {
			switcher_icon_selected
		} else if window.minimized {
			switcher_icon_minimized
		} else {
			switcher_icon
		}
		children << ui2.clickable_view(d.switcher.ids[i], ui2.rect(f64(x), f64(y), f64(switcher_tile), f64(switcher_tile)), ui2.BoxStyle{
			bg: theme.accent
			radius: switcher_select_radius
			transparent: !selected
		}, frame_child(ui2.button_with_image('', '', window.icon, ui2.rect(f64(icon_inset), f64(icon_inset), f64(switcher_icon_size), f64(switcher_icon_size)), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: icon_color
		})))
	}

	children << ui2.label('switcher.title', d.switcher_title(), ui2.rect(0, f64(panel_height - switcher_label_height - switcher_padding / 2), f64(panel_width), f64(switcher_label_height)), ui2.TextStyle{
		color: switcher_text
		size: 15
		bold: true
		align: .center
		lines: 1
	})

	return ui2.view(switcher_panel_id, ui2.rect(f64((d.canvas.width - panel_width) / 2), f64((d.canvas.height - panel_height) / 2), f64(panel_width), f64(panel_height)), ui2.BoxStyle{
		bg: switcher_bg
		radius: switcher_radius
	}, children)
}

fn (d &Desktop) switcher_title() string {
	if d.switcher.index < 0 || d.switcher.index >= d.switcher.order.len {
		return ''
	}
	index := d.window_index(d.switcher.order[d.switcher.index]) or { return '' }
	return d.windows[index].title
}
