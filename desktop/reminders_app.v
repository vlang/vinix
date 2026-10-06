// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded local task list. Due status updates only while this app is open.
module main

const reminders_limit = 256
const reminders_title_limit = 256
const reminders_record_limit = 128 * 1024
const reminders_record_header = 'VINIX-REMINDERS 2\n'
const reminders_record_header_v1 = 'VINIX-REMINDERS 1\n'
const reminders_filename = '.vinix-reminders'

enum ReminderPriority { none low medium high }

fn reminders_priority_key(priority ReminderPriority) string {
	return match priority {
		.none { 'reminders.priority.none' }
		.low { 'reminders.priority.low' }
		.medium { 'reminders.priority.medium' }
		.high { 'reminders.priority.high' }
	}
}

struct ReminderTask {
mut:
	title string
	due string
	completed bool
	priority ReminderPriority
}

struct RemindersData {
mut:
	items [reminders_limit]ReminderTask
	count int
}

enum RemindersFilter { all open completed overdue }
enum RemindersSort { manual priority due title }

fn reminders_sort_key(order RemindersSort) string {
	return match order {
		.manual { 'reminders.sort.manual' }
		.priority { 'reminders.sort.priority' }
		.due { 'reminders.sort.due' }
		.title { 'reminders.sort.title' }
	}
}

// UTF-8 byte order is deterministic and case-sensitive, without allocating
// normalized copies. A shorter prefix sorts first; valid UTF-8 preserves code
// point order. The same rule orders fixed-width dates and all-day prefixes.
fn reminders_compare_text(left string, right string) int {
	length := if left.len < right.len { left.len } else { right.len }
	for at in 0 .. length {
		if left[at] < right[at] { return -1 }
		if left[at] > right[at] { return 1 }
	}
	if left.len < right.len { return -1 }
	if left.len > right.len { return 1 }
	return 0
}

struct RemindersApp {
mut:
	data RemindersData
	record string
	home_fd int = -1
	title_input []u8
	due_input []u8
	search_input []u8
	export_input []u8
	row_actions [reminders_limit]string
	matches [reminders_limit]int
	match_count int
	count_text string
	filter RemindersFilter
	sort RemindersSort
	selected int = -1
	scroll int
	page_rows int = 7
	editing bool
	edit_index int = -1
	edit_priority ReminderPriority
	confirming_delete bool
	focus int = -1
	select_all bool
	pending [4]u8
	pending_len int
	status string = 'reminders.ready'
	read_failed bool
	tz_offset i64
	shown_minute i64 = -1
	today int
	minute_of_day int
	clock_valid bool
	sequence u64
}

fn reminders_clean_title(title string) bool {
	if title.len == 0 || title.len > reminders_title_limit { return false }
	mut at := 0
	mut nonspace := false
	for at < title.len {
		lead := title[at]
		length := editor_utf8_length(lead)
		if lead < 0x20 || lead == 0x7f || length == 0 || at + length > title.len { return false }
		for index in 1 .. length {
			if !editor_utf8_follows(lead, index, title[at + index]) { return false }
		}
		if length == 2 && lead == 0xc2 && title[at + 1] <= 0x9f { return false }
		if lead != ` ` { nonspace = true }
		at += length
	}
	return nonspace
}

// Fixed-width civil dates are deliberately independent of libc/time_t range.
fn reminders_due_valid(due string) bool {
	if due.len == 0 { return true }
	if due.len != 10 && due.len != 16 { return false }
	if due[4] != `-` || due[7] != `-` { return false }
	for index in 0 .. due.len {
		if index == 4 || index == 7 || index == 10 || index == 13 { continue }
		if due[index] < `0` || due[index] > `9` { return false }
	}
	year := reminders_digits(due, 0, 4)
	month := reminders_digits(due, 5, 2)
	day := reminders_digits(due, 8, 2)
	if year < 1 || month < 1 || month > 12 || day < 1 || day > calendar_days_in_month(year, month) { return false }
	if due.len == 16 {
		if due[10] != ` ` || due[13] != `:` || reminders_digits(due, 11, 2) > 23 || reminders_digits(due, 14, 2) > 59 { return false }
	}
	return true
}

fn reminders_digits(text string, start int, length int) int {
	mut number := 0
	for index in start .. start + length { number = number * 10 + int(text[index] - `0`) }
	return number
}

fn (mut data RemindersData) free_items() {
	for index in 0 .. data.count {
		unsafe { data.items[index].title.free() data.items[index].due.free() }
		data.items[index] = ReminderTask{}
	}
	data.count = 0
}

// Version 1 remains readable without rewriting it. The first successful user
// save publishes version 2 through the same lock and snapshot conflict guard.
fn reminders_parse(record string) ?RemindersData {
	if record.len > reminders_record_limit { return none }
	version := if record.starts_with(reminders_record_header) { 2 } else if record.starts_with(reminders_record_header_v1) { 1 } else { return none }
	mut data := RemindersData{}
	mut complete := false
	defer { if !complete { data.free_items() } }
	mut start := if version == 1 { reminders_record_header_v1.len } else { reminders_record_header.len }
	for start < record.len {
		if data.count >= reminders_limit { return none }
		mut end := start
		for end < record.len && record[end] != `\n` { end++ }
		if end >= record.len || end - start < 4 || record[start + 1] != `\t` { return none }
		if record[start] != `0` && record[start] != `1` { return none }
		mut due_start := start + 2
		mut priority := ReminderPriority.none
		if version == 2 {
			if end - start < 6 || record[start + 2] < `0` || record[start + 2] > `3` || record[start + 3] != `\t` { return none }
			priority = match record[start + 2] {
				`1` { ReminderPriority.low }
				`2` { ReminderPriority.medium }
				`3` { ReminderPriority.high }
				else { ReminderPriority.none }
			}
			due_start = start + 4
		}
		mut split := due_start
		for split < end && record[split] != `\t` { split++ }
		if split >= end { return none }
		due := console_borrow(record, due_start, split)
		title := console_borrow(record, split + 1, end)
		if !reminders_due_valid(due) || !reminders_clean_title(title) { return none }
		data.items[data.count] = ReminderTask{ title: title.clone(), due: due.clone(), completed: record[start] == `1`, priority: priority }
		data.count++
		start = end + 1
	}
	complete = true
	return data
}

fn new_reminders_app(home string, tz_offset i64) RemindersApp {
	mut app := RemindersApp{
		title_input: []u8{cap: reminders_title_limit}
		due_input: []u8{cap: 16}
		search_input: []u8{cap: reminders_title_limit}
		export_input: []u8{cap: 4096}
		tz_offset: tz_offset
	}
	unsafe {
		app.title_input.flags |= .noslices
		app.due_input.flags |= .noslices
		app.search_input.flags |= .noslices
		app.export_input.flags |= .noslices
	}
	// Registered users can have an intentional HOME alias. Resolve that trusted
	// path once, then hold the opened directory and refuse linked record names.
	canonical := reminders_canonical_home(home)
	if canonical == '/' { app.home_fd = C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0) }
	else if canonical.len > 0 { app.home_fd = backup_open_directory(canonical) }
	export_path := if canonical == '/' { '/vinix-reminders-export.txt'.clone() } else if canonical.len > 0 { '${canonical}/vinix-reminders-export.txt' } else { '' }
	editor_append(mut app.export_input, export_path)
	unsafe { canonical.free() export_path.free() }
	for index in 0 .. reminders_limit {
		text := index.str()
		app.row_actions[index] = 'reminders.row.${text}'
		unsafe { text.free() }
	}
	app.refresh_time()
	app.reload()
	return app
}

fn open_reminders_app(mut desktop Desktop) !NativeApp {
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	app := new_reminders_app(home, desktop.tz_offset_seconds)
	return &app
}

fn (mut app RemindersApp) reload() {
	if app.home_fd < 0 { app.read_failed = true app.status = 'reminders.read_failed' return }
	record, state := reminders_read_record(app.home_fd)
	defer { unsafe { record.free() } }
	if state == .invalid { app.read_failed = true app.status = 'reminders.read_failed' return }
	mut next := if state == .missing { RemindersData{} } else {
		reminders_parse(record) or { app.read_failed = true app.status = 'reminders.read_failed' return }
	}
	app.data.free_items()
	app.data = next
	unsafe { app.record.free() }
	app.record = record.clone()
	app.read_failed = false
	app.status = 'reminders.ready'
	app.cancel_edit()
	app.selected = -1
	app.scroll = 0
	app.refilter()
}

fn (mut app RemindersApp) refilter() {
	app.match_count = 0
	mut selected_visible := false
	query := editor_bytes_text(app.search_input)
	for index in 0 .. app.data.count {
		item := &app.data.items[index]
		if query.len > 0 && !item.title.contains(query) { continue }
		include := match app.filter { .all { true } .open { !item.completed } .completed { item.completed } .overdue { app.is_overdue(index) } }
		if include {
			app.matches[app.match_count] = index
			app.match_count++
			if index == app.selected { selected_visible = true }
		}
	}
	app.sort_matches()
	if !selected_visible { app.selected = -1 app.confirming_delete = false }
	unsafe { app.count_text.free() }
	matched := app.match_count.str()
	total := app.data.count.str()
	app.count_text = '${matched} / ${total}'
	unsafe { matched.free() total.free() }
	app.clamp_scroll()
}

fn (app &RemindersApp) match_before(left int, right int) bool {
	a := &app.data.items[left]
	b := &app.data.items[right]
	order := match app.sort {
		.manual { 0 }
		.priority { int(b.priority) - int(a.priority) }
		.due {
			if a.due.len == 0 && b.due.len > 0 { 1 }
			else if a.due.len > 0 && b.due.len == 0 { -1 }
			else { reminders_compare_text(a.due, b.due) }
		}
		.title { reminders_compare_text(a.title, b.title) }
	}
	return order < 0 || (order == 0 && left < right)
}

// Only the bounded view indices move. Persisted rows, editor indices and delete
// guards retain their identities; equal keys retain original insertion order.
fn (mut app RemindersApp) sort_matches() {
	if app.sort == .manual { return }
	for slot := 1; slot < app.match_count; slot++ {
		index := app.matches[slot]
		mut position := slot
		for position > 0 && app.match_before(index, app.matches[position - 1]) {
			app.matches[position] = app.matches[position - 1]
			position--
		}
		app.matches[position] = index
	}
}

fn (mut app RemindersApp) set_sort(order RemindersSort) {
	if app.sort == order { return }
	app.sort = order
	app.refilter()
	app.scroll = 0
	for slot in 0 .. app.match_count {
		if app.matches[slot] == app.selected {
			if slot >= app.page_rows { app.scroll = slot - app.page_rows + 1 }
			break
		}
	}
	app.clamp_scroll()
}

fn (mut app RemindersApp) cycle_sort(backward bool) {
	app.set_sort(match app.sort {
		.manual { if backward { RemindersSort.title } else { RemindersSort.priority } }
		.priority { if backward { RemindersSort.manual } else { RemindersSort.due } }
		.due { if backward { RemindersSort.priority } else { RemindersSort.title } }
		.title { if backward { RemindersSort.due } else { RemindersSort.manual } }
	})
}

fn (mut app RemindersApp) clamp_scroll() {
	maximum := if app.match_count > app.page_rows { app.match_count - app.page_rows } else { 0 }
	if app.scroll > maximum { app.scroll = maximum }
	if app.scroll < 0 { app.scroll = 0 }
}

fn (app &RemindersApp) is_overdue(index int) bool {
	if index < 0 || index >= app.data.count || !app.clock_valid { return false }
	item := &app.data.items[index]
	if item.completed || item.due.len == 0 { return false }
	date := reminders_digits(item.due, 0, 4) * 10000 + reminders_digits(item.due, 5, 2) * 100 + reminders_digits(item.due, 8, 2)
	return date < app.today || (date == app.today && item.due.len == 16 && reminders_digits(item.due, 11, 2) * 60 + reminders_digits(item.due, 14, 2) < app.minute_of_day)
}

fn (app &RemindersApp) due_status(index int) string {
	item := &app.data.items[index]
	if item.completed { return 'reminders.completed' }
	if app.is_overdue(index) { return 'reminders.overdue' }
	if item.due.len == 0 { return 'reminders.no_due' }
	date := reminders_digits(item.due, 0, 4) * 10000 + reminders_digits(item.due, 5, 2) * 100 + reminders_digits(item.due, 8, 2)
	if app.clock_valid && date == app.today { return 'reminders.due_today' }
	return 'reminders.open'
}

fn (mut app RemindersApp) poll_time(seconds i64) bool {
	minute := if seconds < 0 { i64(-1) } else { (seconds + app.tz_offset) / 60 }
	valid := seconds >= 0
	if minute == app.shown_minute && valid == app.clock_valid { return false }
	app.shown_minute = minute
	app.clock_valid = valid
	if valid {
		civil := civil_from_epoch(seconds + app.tz_offset)
		app.today = civil.year * 10000 + civil.month * 100 + civil.day
		app.minute_of_day = civil.hour * 60 + civil.minute
	}
	app.refilter()
	return true
}

fn (mut app RemindersApp) refresh_time() {
	seconds, _ := desktop_realtime()
	app.poll_time(seconds)
}

fn (mut app RemindersApp) poll() bool {
	seconds, _ := desktop_realtime()
	return app.poll_time(seconds)
}

fn (app &RemindersApp) next_poll_ms() u64 { return 1000 }

fn (mut app RemindersApp) begin_edit(index int) {
	if app.read_failed { app.status = 'reminders.read_failed' return }
	if index < -1 || index >= app.data.count { app.status = 'reminders.select_task' return }
	if index == -1 && app.data.count >= reminders_limit { app.status = 'reminders.limit' return }
	app.editing = true
	app.confirming_delete = false
	app.edit_index = index
	app.focus = 0
	app.select_all = false
	app.pending_len = 0
	app.title_input.clear()
	app.due_input.clear()
	app.edit_priority = .none
	if index >= 0 {
		app.edit_priority = app.data.items[index].priority
		editor_append(mut app.title_input, app.data.items[index].title)
		editor_append(mut app.due_input, app.data.items[index].due)
	}
}

fn (mut app RemindersApp) cancel_edit() {
	app.editing = false
	app.edit_index = -1
	app.edit_priority = .none
	app.confirming_delete = false
	app.focus = -1
	app.select_all = false
	app.pending_len = 0
	app.title_input.clear()
	app.due_input.clear()
}

fn reminders_append_row(mut bytes []u8, title string, due string, completed bool, priority ReminderPriority) {
	bytes << if completed { u8(`1`) } else { u8(`0`) }
	bytes << `\t`
	bytes << u8(`0`) + u8(priority)
	bytes << `\t`
	editor_append(mut bytes, due)
	bytes << `\t`
	editor_append(mut bytes, title)
	bytes << `\n`
}

// Build a prospective snapshot first. The live rows are changed only after
// publication succeeds; conflicts and I/O errors leave edits and tasks intact.
fn (app &RemindersApp) candidate(index int, title string, due string, completed bool, priority ReminderPriority, deleting bool) string {
	mut bytes := []u8{cap: reminders_record_limit}
	unsafe { bytes.flags |= .noslices }
	editor_append(mut bytes, reminders_record_header)
	for at in 0 .. app.data.count {
		if at == index {
			if !deleting { reminders_append_row(mut bytes, title, due, completed, priority) }
		} else {
			item := &app.data.items[at]
			reminders_append_row(mut bytes, item.title, item.due, item.completed, item.priority)
		}
	}
	if index == -1 && !deleting { reminders_append_row(mut bytes, title, due, completed, priority) }
	result := editor_bytes_text(bytes).clone()
	unsafe { bytes.free() }
	return result
}

fn (mut app RemindersApp) publish(record string) bool {
	if app.read_failed { app.status = 'reminders.read_failed' return false }
	mut next := reminders_parse(record) or { app.status = 'reminders.save_failed' return false }
	status := app.save_record(record)
	app.status = status
	if status != 'reminders.saved' && status != 'reminders.saved_unsynced' { next.free_items() return false }
	app.data.free_items()
	app.data = next
	unsafe { app.record.free() }
	app.record = record.clone()
	app.refilter()
	return true
}

fn (mut app RemindersApp) save_edit() {
	if !app.editing { return }
	title := editor_bytes_text(app.title_input)
	due := editor_bytes_text(app.due_input)
	if !reminders_clean_title(title) { app.status = 'reminders.title_required' return }
	if !reminders_due_valid(due) { app.status = 'reminders.invalid_due' return }
	completed := app.edit_index >= 0 && app.data.items[app.edit_index].completed
	record := app.candidate(app.edit_index, title, due, completed, app.edit_priority, false)
	defer { unsafe { record.free() } }
	if app.publish(record) {
		app.selected = if app.edit_index >= 0 { app.edit_index } else { app.data.count - 1 }
		app.cancel_edit()
		app.refilter()
	}
}

fn (mut app RemindersApp) toggle_selected() {
	if app.selected < 0 || app.selected >= app.data.count { app.status = 'reminders.select_task' return }
	item := &app.data.items[app.selected]
	record := app.candidate(app.selected, item.title, item.due, !item.completed, item.priority, false)
	defer { unsafe { record.free() } }
	app.publish(record)
}

fn (mut app RemindersApp) delete_selected() {
	if !app.confirming_delete || app.selected < 0 || app.selected >= app.data.count { return }
	record := app.candidate(app.selected, '', '', false, .none, true)
	defer { unsafe { record.free() } }
	if app.publish(record) { app.selected = -1 app.cancel_edit() }
}

fn (mut app RemindersApp) close_app() {
	app.data.free_items()
	if app.home_fd >= 0 { desktop_close(app.home_fd) }
	for index in 0 .. reminders_limit { unsafe { app.row_actions[index].free() } app.row_actions[index] = '' }
	unsafe {
		app.record.free()
		app.count_text.free()
		app.title_input.free()
		app.due_input.free()
		app.search_input.free()
		app.export_input.free()
	}
	app = RemindersApp{}
}
