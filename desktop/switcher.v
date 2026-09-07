// Cmd-Tab: the window switcher.
//
// A tap moves to the window under the one on top, the way Alt-Tab and Cmd-Tab
// have always worked. Holding Cmd down instead asks the question "what else is
// open?", and after a moment the desktop answers it: a panel in the middle of
// the screen with a tile for every window, the selection moving along it on
// each further Tab, and the window it lands on raised when Cmd is let go.
//
// A terminal has no way to say "Cmd", so the keyboard drivers say it for it.
// Cmd-Tab arrives as the CSI-u encoding of Tab with the super bit set, which
// is what a terminal that reports modified keys at all uses, and the release
// of Cmd — which no terminal has ever had a reason to report — as the encoding
// of the left Super key with an event type of "released". Both are taken out
// of the stream before anything else sees them: Cmd-Tab belongs to the window
// manager whoever is typing, exactly as it does on the machine this borrows
// the gesture from.
module main

import ui2

// How long Cmd must stay down before the panel appears. A tap is a switch and
// shows nothing; holding on is a question, and gets the answer.
const switcher_reveal_ms = i64(400)

// The action ids of the tiles. A click on one switches to that window, which
// is the one thing the panel can do that the keyboard cannot say faster.
const action_switch_prefix = 'switch.'

// SwitcherKey is one sequence the drivers send and what it does to the
// selection: forwards, backwards, or `commit`, which is Cmd being let go.
struct SwitcherKey {
	bytes string
	step  int
}

const switch_commit = 0

const switcher_keys = [
	SwitcherKey{'\x1b[9;9u', 1},
	SwitcherKey{'\x1b[9;10u', -1},
	SwitcherKey{'\x1b[57444;1:3u', switch_commit},
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
// the panel to be worth drawing.
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
	// garbage collector, and the count is however many windows have ever been
	// open at once.
	ids []string
	// The start of a sequence that the read ended inside, held until the next
	// read completes it.
	pending string
}

// ── The keys ───────────────────────────────────────────────────────

// take_switcher_keys acts on every switcher sequence in the input and returns
// what is left. An empty read still goes through, because a held-back partial
// sequence has to be let go when nothing arrives to complete it.
fn (mut d Desktop) take_switcher_keys(keys string) string {
	mut input := keys
	if d.switcher.pending.len > 0 {
		if keys.len == 0 {
			// Nothing completed it, so it was not one of ours after all.
			held := d.switcher.pending
			d.switcher.pending = ''
			return held
		}
		input = d.switcher.pending + keys
		d.switcher.pending = ''
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
				d.switcher_commit()
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
// somewhere else means.
fn (mut d Desktop) switcher_close() {
	if !d.switcher.active {
		return
	}
	d.switcher.active = false
	d.switcher.shown = false
	d.dirty = true
}

// switcher_select is a click on a tile: it switches to that window whatever the
// keyboard had landed on.
fn (mut d Desktop) switcher_select(index int) {
	if !d.switcher.active || index < 0 || index >= d.switcher.order.len {
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
// one of them, and its title underneath.
fn (d &Desktop) switcher_element() ui2.Element {
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
	panel_height := rows * switcher_tile + (rows - 1) * switcher_gap + 2 * switcher_padding +
		switcher_label_height

	mut children := []ui2.Element{cap: count + 1}
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
		children << ui2.clickable_view(d.switcher.ids[i], ui2.rect(f64(x), f64(y), f64(switcher_tile),
			f64(switcher_tile)), ui2.BoxStyle{
			bg: theme.accent
			radius: switcher_select_radius
			transparent: !selected
		}, [
			ui2.button_with_image('', '', window.icon, ui2.rect(f64(icon_inset), f64(icon_inset),
				f64(switcher_icon_size), f64(switcher_icon_size)), ui2.BoxStyle{
				transparent: true
			}, ui2.TextStyle{
				color: icon_color
			}),
		])
	}

	children << ui2.label('switcher.title', d.switcher_title(), ui2.rect(0, f64(panel_height -
		switcher_label_height - switcher_padding / 2), f64(panel_width), f64(switcher_label_height)),
		ui2.TextStyle{
		color: switcher_text
		size: 15
		bold: true
		align: .center
		lines: 1
	})

	return ui2.view(switcher_panel_id, ui2.rect(f64((d.canvas.width - panel_width) / 2),
		f64((d.canvas.height - panel_height) / 2), f64(panel_width), f64(panel_height)),
		ui2.BoxStyle{
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
