// SPDX-License-Identifier: GPL-2.0-or-later
module main

const notes_history_limit = 32

// The active draft owns its buffers. Each history slot owns one alternate
// draft; undo/redo swaps that ownership rather than allocating another copy.
// The two directions share the same 32 slots, scoped to the current note.
struct NotesHistoryEntry {
mut:
	title       []u8
	body        []u8
	cursor      int
	focus       int
	select_all  bool
	body_scroll int
}

fn (mut a NotesApp) free_history_entry(index int) {
	unsafe {
		a.history[index].title.free()
		a.history[index].body.free()
	}
	a.history[index] = NotesHistoryEntry{}
}

fn (mut a NotesApp) clear_history() {
	for index in 0 .. a.history_count { a.free_history_entry(index) }
	a.history_count = 0
	a.history_position = 0
}

// Call only once a validated edit is known to change title or body. Search,
// export paths, navigation, rejected text and no-op edits never enter history.
fn (mut a NotesApp) record_history() {
	for index in a.history_position .. a.history_count { a.free_history_entry(index) }
	a.history_count = a.history_position
	if a.history_count == notes_history_limit {
		a.free_history_entry(0)
		for index in 0 .. notes_history_limit - 1 {
			a.history[index] = NotesHistoryEntry{ ...a.history[index + 1] }
		}
		a.history[notes_history_limit - 1] = NotesHistoryEntry{}
		a.history_count--
	}
	a.history[a.history_count] = NotesHistoryEntry{
		title: a.title.clone()
		body: a.body.clone()
		cursor: a.cursor
		focus: a.focus
		select_all: a.select_all
		body_scroll: a.body_scroll
	}
	unsafe {
		a.history[a.history_count].title.flags |= .noslices
		a.history[a.history_count].body.flags |= .noslices
	}
	a.history_count++
	a.history_position = a.history_count
}

fn (a &NotesApp) can_undo() bool { return a.selected >= 0 && a.history_position > 0 }

fn (a &NotesApp) can_redo() bool {
	return a.selected >= 0 && a.history_position < a.history_count
}

fn (mut a NotesApp) restore_history(redo bool) {
	if redo {
		if !a.can_redo() { return }
	} else if !a.can_undo() {
		return
	}
	index := if redo { a.history_position } else { a.history_position - 1 }
	saved := NotesHistoryEntry{
		title: a.title
		body: a.body
		cursor: a.cursor
		focus: a.focus
		select_all: a.select_all
		body_scroll: a.body_scroll
	}
	a.title = a.history[index].title
	a.body = a.history[index].body
	a.cursor = a.history[index].cursor
	a.focus = a.history[index].focus
	a.select_all = a.history[index].select_all
	a.body_scroll = a.history[index].body_scroll
	a.history[index] = NotesHistoryEntry{ ...saved }
	a.history_position += if redo { 1 } else { -1 }
	a.pending_len = 0
	a.mark_dirty()
	a.refilter()
	a.show_cursor()
	a.clamp_body_scroll()
}
