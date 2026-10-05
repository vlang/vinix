// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded, local plain-text notes. The draft is separate from the last saved
// model, so rejected saves never discard the user's current text.
module main

const notes_limit = 128
const notes_title_limit = 160
const notes_body_limit = 16384
const notes_record_limit = 1024 * 1024
const notes_autosave_ms = u64(750)

struct NotesEntry {
mut:
	id    u64
	title string
	body  string
}

struct NotesApp {
mut:
	items           [notes_limit]NotesEntry
	count           int
	next_id         u64 = 1
	selected        int = -1
	home_fd         int = -1
	record          string
	read_failed     bool
	dirty           bool
	status          string = 'notes.ready'
	export_status   string
	title           []u8
	body            []u8
	query           []u8
	export_path     []u8
	default_export  string
	actions         [notes_limit]string
	matches         [notes_limit]int
	matched         int
	list_scroll     int
	body_scroll     int
	page_rows       int = 12
	text_rows       int = 16
	text_columns    int = 65
	wrap_starts     [notes_body_limit + 1]int
	wrap_count      int = 1
	cursor          int
	focus           int = 2
	select_all      bool
	delete_pending  bool
	close_requested bool
	discard_pending bool
	discard_allowed bool
	pending         [4]u8
	pending_len     int
	last_edit       u64
}

fn new_notes_app(home string) NotesApp {
	mut a := NotesApp{
		title:       []u8{cap: notes_title_limit}
		body:        []u8{cap: notes_body_limit}
		query:       []u8{cap: 256}
		export_path: []u8{cap: 512}
	}
	unsafe {
		a.title.flags |= .noslices
		a.body.flags |= .noslices
		a.query.flags |= .noslices
		a.export_path.flags |= .noslices
	}
	for index in 0 .. notes_limit {
		text := index.str()
		a.actions[index] = 'notes.row.${text}'
		unsafe { text.free() }
	}
	// HOME may be a deliberate registration symlink. Anchor its directory,
	// then refuse links for every record, lock and temporary file beneath it.
	if home.len > 0 && home.len <= 4096 && home.index_u8(0) < 0 {
		a.home_fd = C.open(&char(home.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0)
	}
	if a.home_fd < 0 {
		a.read_failed = true
		a.status = 'notes.read_failed'
	} else {
		a.reload()
	}
	path := if home.ends_with('/') { '${home}vinix-note.txt' } else { '${home}/vinix-note.txt' }
	if path.len <= 512 { editor_append(mut a.export_path, path) }
	a.default_export = path.clone()
	unsafe { path.free() }
	return a
}

fn open_notes_app(mut _ Desktop) !NativeApp {
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	app := new_notes_app(home)
	return &app
}

fn notes_valid_text(text string, maximum int, multiline bool) bool {
	if text.len > maximum { return false }
	mut at := 0
	for at < text.len {
		ch := text[at]
		length := editor_utf8_length(ch)
		if length == 0 || at + length > text.len { return false }
		if (ch < 0x20 && !(multiline && (ch == `\n` || ch == `\t`))) || ch == 0x7f { return false }
		for index in 1 .. length {
			if !editor_utf8_follows(ch, index, text[at + index]) { return false }
		}
		if length == 2 && ch == 0xc2 && text[at + 1] <= 0x9f { return false }
		at += length
	}
	return true
}

fn notes_number(text string) ?u64 {
	if text.len == 0 || text.len > 20 { return none }
	mut value := u64(0)
	for ch in text {
		if ch < `0` || ch > `9` || value > (~u64(0) - u64(ch - `0`)) / 10 { return none }
		value = value * 10 + u64(ch - `0`)
	}
	return value
}

fn (mut a NotesApp) free_items() {
	for index in 0 .. a.count {
		unsafe {
			a.items[index].title.free()
			a.items[index].body.free()
		}
		a.items[index] = NotesEntry{}
	}
	a.count = 0
}

// Length prefixes preserve tabs/newlines without an escaping parser. Validate
// the entire record before adopting it; duplicate IDs and trailing junk fail.
fn (mut a NotesApp) decode(data string) bool {
	if data.len > notes_record_limit || !data.starts_with('VINIX-NOTES 1\n') { return false }
	mut at := 'VINIX-NOTES 1\n'.len
	mut end := at
	for end < data.len && data[end] != `\n` { end++ }
	if end == data.len { return false }
	next := notes_number(console_borrow(data, at, end)) or { return false }
	if next == 0 { return false }
	at = end + 1
	mut ids := [notes_limit]u64{}
	mut starts := [notes_limit]int{}
	mut titles := [notes_limit]int{}
	mut bodies := [notes_limit]int{}
	mut count := 0
	for at < data.len {
		if count == notes_limit { return false }
		mut cuts := [4]int{}
		cuts[0] = at
		mut fields := 1
		end = at
		for end < data.len && data[end] != `\n` {
			if data[end] == ` ` {
				if fields >= 3 { return false }
				cuts[fields] = end + 1
				fields++
			}
			end++
		}
		if end == data.len || fields != 3 { return false }
		cuts[3] = end + 1
		id := notes_number(console_borrow(data, cuts[0], cuts[1] - 1)) or { return false }
		tl := notes_number(console_borrow(data, cuts[1], cuts[2] - 1)) or { return false }
		bl := notes_number(console_borrow(data, cuts[2], end)) or { return false }
		if id == 0 || id >= next || tl == 0 || tl > notes_title_limit || bl > notes_body_limit {
			return false
		}
		for index in 0 .. count { if ids[index] == id { return false } }
		at = end + 1
		if u64(data.len - at) < tl + bl + 1 { return false }
		if !notes_valid_text(console_borrow(data, at, at + int(tl)), notes_title_limit, false)
			|| !notes_valid_text(console_borrow(data, at + int(tl), at + int(tl + bl)), notes_body_limit, true)
			|| data[at + int(tl + bl)] != `\n` {
			return false
		}
		ids[count] = id
		starts[count] = at
		titles[count] = int(tl)
		bodies[count] = int(bl)
		count++
		at += int(tl + bl) + 1
	}
	a.free_items()
	for index in 0 .. count {
		start := starts[index]
		a.items[index] = NotesEntry{
			id:    ids[index]
			title: console_borrow(data, start, start + titles[index]).clone()
			body:  console_borrow(data, start + titles[index], start + titles[index] + bodies[index]).clone()
		}
	}
	a.count = count
	a.next_id = next
	return true
}

fn (a &NotesApp) encode(skip int) string {
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, 'VINIX-NOTES 1\n')
	next := a.next_id.str()
	editor_append(mut bytes, next)
	unsafe { next.free() }
	bytes << `\n`
	for index in 0 .. a.count {
		if index == skip { continue }
		title := if index == a.selected { editor_bytes_text(a.title) } else { a.items[index].title }
		body := if index == a.selected { editor_bytes_text(a.body) } else { a.items[index].body }
		id := a.items[index].id.str()
		tlen := title.len.str()
		blen := body.len.str()
		header := '${id} ${tlen} ${blen}\n'
		editor_append(mut bytes, header)
		editor_append(mut bytes, title)
		editor_append(mut bytes, body)
		bytes << `\n`
		unsafe {
			id.free()
			tlen.free()
			blen.free()
			header.free()
		}
	}
	data := bytes.bytestr()
	unsafe { bytes.free() }
	return data
}

fn (mut a NotesApp) reload() {
	a.discard_pending = false
	a.discard_allowed = false
	if a.dirty {
		a.status = 'notes.unsaved'
		return
	}
	lock_fd := notes_lock(a.home_fd)
	if lock_fd < 0 {
		a.status = 'notes.read_failed'
		return
	}
	defer { desktop_close(lock_fd) }
	data, state := notes_read(a.home_fd)
	defer { unsafe { data.free() } }
	if state < 0 || (state == 1 && !a.decode(data)) {
		a.read_failed = true
		a.status = 'notes.corrupt'
		return
	}
	if state == 0 {
		a.free_items()
		a.next_id = 1
	}
	a.read_failed = false
	unsafe { a.record.free() }
	a.record = data.clone()
	a.selected = -1
	a.title.clear()
	a.body.clear()
	a.cursor = 0
	if a.count > 0 { a.load_selected(0) }
	a.refilter()
	a.status = 'notes.ready'
}

fn (mut a NotesApp) save() bool {
	if !a.dirty { return true }
	a.discard_pending = false
	a.discard_allowed = false
	if a.read_failed {
		a.status = 'notes.corrupt'
		return false
	}
	if a.selected >= 0 && a.title.len == 0 {
		a.status = 'notes.title_required'
		return false
	}
	data := a.encode(-1)
	defer { unsafe { data.free() } }
	if data.len > notes_record_limit {
		a.status = 'notes.limit'
		return false
	}
	state := notes_publish(a.home_fd, a.record, data)
	if state < 0 {
		a.status = if state == -2 { 'notes.conflict' } else { 'notes.save_failed' }
		return false
	}
	unsafe { a.record.free() }
	a.record = data.clone()
	if a.selected >= 0 {
		unsafe {
			a.items[a.selected].title.free()
			a.items[a.selected].body.free()
		}
		a.items[a.selected].title = editor_bytes_text(a.title).clone()
		a.items[a.selected].body = editor_bytes_text(a.body).clone()
	}
	a.dirty = false
	a.close_requested = false
	a.status = if state == 1 { 'notes.durability_failed' } else { 'notes.saved' }
	a.refilter()
	return true
}

fn (mut a NotesApp) new_note() {
	if !a.save() { return }
	if a.read_failed {
		a.status = 'notes.corrupt'
		return
	}
	if a.count >= notes_limit || a.next_id == ~u64(0) {
		a.status = 'notes.limit'
		return
	}
	a.items[a.count] = NotesEntry{ id: a.next_id, title: tr('notes.untitled').clone() }
	a.next_id++
	a.count++
	a.load_selected(a.count - 1)
	a.mark_dirty()
	a.refilter()
	a.focus = 1
	a.select_all = true
}

fn (mut a NotesApp) load_selected(index int) {
	if index < 0 || index >= a.count { return }
	a.selected = index
	a.title.clear()
	a.body.clear()
	editor_append(mut a.title, a.items[index].title)
	editor_append(mut a.body, a.items[index].body)
	a.cursor = a.body.len
	a.body_scroll = 0
	a.delete_pending = false
	a.select_all = false
	a.pending_len = 0
	a.rewrap()
}

fn (mut a NotesApp) select_note(index int) {
	if index == a.selected || !a.save() { return }
	a.load_selected(index)
	a.focus = 2
}

fn (mut a NotesApp) delete_note() {
	if a.selected < 0 { return }
	if !a.save() { return }
	if !a.delete_pending {
		a.delete_pending = true
		a.status = 'notes.confirm_delete'
		return
	}
	data := a.encode(a.selected)
	defer { unsafe { data.free() } }
	state := notes_publish(a.home_fd, a.record, data)
	if state < 0 {
		a.status = if state == -2 { 'notes.conflict' } else { 'notes.save_failed' }
		return
	}
	unsafe { a.record.free() }
	a.record = data.clone()
	index := a.selected
	unsafe {
		a.items[index].title.free()
		a.items[index].body.free()
	}
	for at in index .. a.count - 1 { a.items[at] = a.items[at + 1] }
	a.count--
	a.items[a.count] = NotesEntry{}
	a.selected = -1
	a.title.clear()
	a.body.clear()
	a.cursor = 0
	a.delete_pending = false
	if a.count > 0 { a.load_selected(if index < a.count { index } else { a.count - 1 }) }
	a.refilter()
	a.status = if state == 1 { 'notes.durability_failed' } else { 'notes.deleted' }
}

fn (mut a NotesApp) refilter() {
	a.matched = 0
	query := editor_bytes_text(a.query)
	for index in 0 .. a.count {
		title := if index == a.selected { editor_bytes_text(a.title) } else { a.items[index].title }
		body := if index == a.selected { editor_bytes_text(a.body) } else { a.items[index].body }
		if query.len == 0 || title.contains(query) || body.contains(query) {
			a.matches[a.matched] = index
			a.matched++
		}
	}
	if a.list_scroll >= a.matched { a.list_scroll = 0 }
}

fn (mut a NotesApp) mark_dirty() {
	a.reset_close_choice()
	a.dirty = true
	a.status = 'notes.unsaved'
	a.last_edit = desktop_monotonic_ms()
	a.delete_pending = false
	a.export_status = ''
}

fn (mut a NotesApp) poll_at(now u64) bool {
	if !a.dirty || a.discard_allowed || now == ~u64(0) || now < a.last_edit || now - a.last_edit < notes_autosave_ms {
		return false
	}
	// A failed save stays visible, and retries are bounded instead of touching
	// a broken/read-only/conflicting store on every compositor tick.
	a.last_edit = now
	previous := a.status
	saved := a.save()
	return saved || a.status != previous
}

fn (mut a NotesApp) poll() bool { return a.poll_at(desktop_monotonic_ms()) }

fn (a &NotesApp) next_poll_ms() u64 {
	if !a.dirty || a.discard_allowed { return 2000 }
	now := desktop_monotonic_ms()
	if now == ~u64(0) || now < a.last_edit { return notes_autosave_ms }
	elapsed := now - a.last_edit
	return if elapsed < notes_autosave_ms { notes_autosave_ms - elapsed } else { u64(1) }
}

fn (mut a NotesApp) reset_close_choice() {
	a.close_requested = false
	a.discard_pending = false
	a.discard_allowed = false
	if a.status == 'notes.discard_ready' {
		a.status = if a.dirty { 'notes.unsaved' } else { 'notes.ready' }
	}
}

fn (mut a NotesApp) prepare_close() bool {
	if !a.dirty || a.discard_allowed { return true }
	if a.save() { return true }
	a.close_requested = true
	a.discard_pending = false
	a.export_status = ''
	return false
}

fn (mut a NotesApp) close_app() {
	// Forced process termination still bypasses the guard. An ordinary close
	// reaches destruction only after save or the explicit discard confirmation.
	if a.dirty && !a.discard_allowed { a.save() }
	a.free_items()
	for index in 0 .. notes_limit {
		unsafe { a.actions[index].free() }
		a.actions[index] = ''
	}
	unsafe {
		a.record.free()
		a.title.free()
		a.body.free()
		a.query.free()
		a.export_path.free()
		a.default_export.free()
	}
	a.record = ''
	a.title = []u8{}
	a.body = []u8{}
	a.query = []u8{}
	a.export_path = []u8{}
	a.default_export = ''
	a.dirty = false
	a.reset_close_choice()
	a.selected = -1
	if a.home_fd >= 0 {
		desktop_close(a.home_fd)
		a.home_fd = -1
	}
}
