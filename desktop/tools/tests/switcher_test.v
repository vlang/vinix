// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

// The window switcher, driven by the exact byte sequences the keyboard drivers
// send. A terminal has no way to say "Cmd", so these three strings are the
// whole of the contract between the kernel and the desktop, and a test that
// stated them any other way would not be testing the thing that ships.
const cmd_tab = '\x1b[9;9u'
const cmd_shift_tab = '\x1b[9;10u'
const cmd_released = '\x1b[57444;1:3u'

// Three windows, opened oldest first, so the painting order is One, Two,
// Three and the switcher's own order -- most recently raised first -- is the
// reverse of it.
fn fixture_desktop() Desktop {
	mut desktop := Desktop{
		canvas: new_canvas(1024, 768)
	}
	desktop.spawn('One', .welcome, 10, 10, 300, 200)
	desktop.spawn('Two', .system, 20, 20, 300, 200)
	desktop.spawn('Three', .notes, 30, 30, 300, 200)
	return desktop
}

fn switcher_element_named(root ui2.Element, id string) ?ui2.Element {
	if root.id == id {
		return root
	}
	for child in root.children {
		found := switcher_element_named(child, id) or { continue }
		return found
	}
	return none
}

fn title_of(desktop &Desktop, id int) string {
	index := desktop.window_index(id) or { return '' }
	return desktop.windows[index].title
}

fn test_drag_redraws_only_after_pointer_motion() {
	mut desktop := fixture_desktop()
	id := desktop.focus
	index := desktop.window_index(id) or { panic('missing focused window') }
	desktop.pointer_x = 100
	desktop.pointer_y = 90
	desktop.buttons = button_left
	desktop.drag = Drag{
		kind: .move
		window_id: id
		offset_x: desktop.pointer_x - desktop.windows[index].x
		offset_y: desktop.pointer_y - desktop.windows[index].y
	}
	desktop.dirty = false

	// Re-reading the same held-click snapshot must not force another full
	// frame. The resulting sleep is what lets ARM64 poll the next input report.
	desktop.on_pointer_move(100, 90)
	assert !desktop.dirty
	assert desktop.windows[index].x == 30 && desktop.windows[index].y == 30

	desktop.on_pointer_move(120, 105)
	assert desktop.dirty
	assert desktop.pointer_x == 120 && desktop.pointer_y == 105
	assert desktop.windows[index].x == 50 && desktop.windows[index].y == 45
}

// hold_past_reveal takes the session back in time rather than sleeping for
// most of a second: what is being tested is that the panel waits for the hold,
// not that the clock runs.
fn hold_past_reveal(mut desktop Desktop) {
	desktop.switcher.started -= switcher_reveal_ms
	desktop.update_switcher()
}

// A tap: one Cmd-Tab and Cmd let go again raises the window under the one on
// top, and nothing is ever drawn.
fn test_switcher_tap_raises_the_window_underneath() {
	mut desktop := fixture_desktop()
	assert title_of(desktop, desktop.focus) == 'Three'

	assert desktop.take_switcher_keys(cmd_tab) == ''
	assert desktop.switcher.active
	assert !desktop.switcher.shown
	assert desktop.switcher_title() == 'Two'

	assert desktop.take_switcher_keys(cmd_released) == ''
	assert !desktop.switcher.active
	assert title_of(desktop, desktop.focus) == 'Two'
	assert desktop.windows.last().title == 'Two'

	// And again, which is what makes a tap a way back and forth between two
	// windows rather than a walk down the whole list.
	desktop.take_switcher_keys(cmd_tab)
	desktop.take_switcher_keys(cmd_released)
	assert title_of(desktop, desktop.focus) == 'Three'
}

// Held down: each further Tab walks on, the list wraps, and Shift walks back.
fn test_switcher_walks_the_list_and_wraps() {
	mut desktop := fixture_desktop()
	desktop.take_switcher_keys(cmd_tab)
	assert desktop.switcher_title() == 'Two'
	desktop.take_switcher_keys(cmd_tab)
	assert desktop.switcher_title() == 'One'
	desktop.take_switcher_keys(cmd_tab)
	assert desktop.switcher_title() == 'Three'
	desktop.take_switcher_keys(cmd_shift_tab)
	assert desktop.switcher_title() == 'One'
	// The arrows move the selection too, while the panel is up.
	desktop.take_switcher_keys('\x1b[C')
	assert desktop.switcher_title() == 'Three'
	desktop.take_switcher_keys('\x1b[D')
	assert desktop.switcher_title() == 'One'

	// Opening the session with Shift held starts at the other end.
	mut backwards := fixture_desktop()
	backwards.take_switcher_keys(cmd_shift_tab)
	assert backwards.switcher_title() == 'One'
}

// The panel is not drawn until Cmd has been held past the reveal, and then it
// carries a tile for every window with the selection behind one of them.
fn test_switcher_panel_appears_only_after_the_hold() {
	mut desktop := fixture_desktop()
	desktop.take_switcher_keys(cmd_tab)
	assert !desktop.switcher.shown
	if _ := switcher_element_named(desktop.build_tree(), switcher_panel_id) {
		assert false, 'the panel was drawn before the hold'
	}

	hold_past_reveal(mut desktop)
	assert desktop.switcher.shown
	panel := switcher_element_named(desktop.build_tree(), switcher_panel_id) or {
		panic('the panel was not drawn after the hold')
	}
	// A tile per window, and the title of the selected one under them.
	assert panel.children.len == desktop.windows.len + 1
	assert panel.children.last().text == 'Two'
	// Centred: the same room either side of it and above and below it.
	assert int(panel.frame.x) * 2 + int(panel.frame.width) == desktop.canvas.width
	assert int(panel.frame.y) * 2 + int(panel.frame.height) == desktop.canvas.height

	selected := switcher_element_named(panel, desktop.switcher.ids[1]) or {
		panic('no tile for the selection')
	}
	assert !selected.box.transparent && selected.box.bg == desktop.theme().accent
	unselected := switcher_element_named(panel, desktop.switcher.ids[0]) or {
		panic('no tile for the window on top')
	}
	assert unselected.box.transparent

	// Letting go closes it, and what was selected is what comes up.
	desktop.take_switcher_keys(cmd_released)
	assert !desktop.switcher.shown && !desktop.switcher.active
	assert title_of(desktop, desktop.focus) == 'Two'
	if _ := switcher_element_named(desktop.build_tree(), switcher_panel_id) {
		assert false, 'the panel outlived the session'
	}
}

// A minimised window is in the panel like any other, and comes back rather
// than being switched to invisibly.
fn test_switcher_restores_a_minimised_window() {
	mut desktop := fixture_desktop()
	one := desktop.windows[0].id
	desktop.minimize(one)
	desktop.raise(desktop.windows.last().id)

	desktop.take_switcher_keys(cmd_tab)
	desktop.take_switcher_keys(cmd_tab)
	assert desktop.switcher_title() == 'One'
	desktop.take_switcher_keys(cmd_released)
	index := desktop.window_index(one) or { panic('the window went away') }
	assert !desktop.windows[index].minimized
	assert desktop.focus == one
}

// A click on a tile switches to that window; a click anywhere else puts the
// panel away and leaves the arrangement as it was.
fn test_switcher_click_selects_and_click_away_dismisses() {
	mut desktop := fixture_desktop()
	desktop.take_switcher_keys(cmd_tab)
	hold_past_reveal(mut desktop)
	desktop.switcher_select(2)
	assert !desktop.switcher.active
	assert title_of(desktop, desktop.focus) == 'One'

	desktop.take_switcher_keys(cmd_tab)
	hold_past_reveal(mut desktop)
	on_top := desktop.focus
	desktop.switcher_close()
	assert !desktop.switcher.active && !desktop.switcher.shown
	assert desktop.focus == on_top
}

// Everything that is not one of the switcher's own sequences comes back out
// untouched, because whatever is focused is still owed it.
fn test_switcher_passes_everything_else_through() {
	mut desktop := fixture_desktop()
	assert desktop.take_switcher_keys('hello') == 'hello'
	// A lone escape is a key someone pressed, not the start of a chord, and is
	// not held back for a frame.
	assert desktop.take_switcher_keys('\x1b') == '\x1b'
	assert desktop.take_switcher_keys('\x1b[A') == '\x1b[A'
	assert desktop.take_switcher_keys('\x1bOP') == '\x1bOP'
	// The arrows are only the switcher's while a session is open.
	assert desktop.take_switcher_keys('\x1b[C') == '\x1b[C'
	assert !desktop.switcher.active
	// A chord in the middle of typing takes only itself out of the stream.
	assert desktop.take_switcher_keys('ab${cmd_tab}cd') == 'abcd'
	assert desktop.switcher.active
}

// A sequence split across two reads is held back rather than handed to an
// application in halves, and is let go if nothing arrives to complete it.
fn test_switcher_sequence_split_across_two_reads() {
	mut desktop := fixture_desktop()
	assert desktop.take_switcher_keys('ab\x1b[9;') == 'ab'
	assert desktop.switcher.pending == '\x1b[9;'
	assert !desktop.switcher.active
	assert desktop.take_switcher_keys('9u') == ''
	assert desktop.switcher.pending == ''
	assert desktop.switcher.active
	assert desktop.switcher_title() == 'Two'

	// Nothing completed it, so it was not one of ours after all.
	mut typing := fixture_desktop()
	assert typing.take_switcher_keys('\x1b[') == ''
	assert typing.take_switcher_keys('') == '\x1b['
	assert typing.take_switcher_keys('') == ''
	// An escape sequence that only looked like the start of one comes back
	// whole, a frame later.
	assert typing.take_switcher_keys('\x1b[') == ''
	assert typing.take_switcher_keys('5~') == '\x1b[5~'
}

// With nothing open there is nothing to switch to, and no session opens.
fn test_switcher_with_no_windows() {
	mut desktop := Desktop{
		canvas: new_canvas(640, 480)
	}
	assert desktop.take_switcher_keys(cmd_tab) == ''
	assert !desktop.switcher.active
	assert desktop.take_switcher_keys(cmd_released) == ''
	assert desktop.focus == 0
}
