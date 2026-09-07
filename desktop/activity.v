// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// An activity monitor, built into the desktop.
//
// Like the file browser this is Vinix's own rather than a ui2 example, and it
// reads the real system: /dev/processes answers with one snapshot of every
// process, and two snapshots a second apart are what a percentage is made of.
//
// The kernel deliberately reports totals rather than rates — a running count of
// nanoseconds on a CPU, and a count of mapped bytes — because it has no idea
// what interval anyone cares about. Turning those into "percent of a CPU" is
// this file's job, and it is the only place in the desktop that has to
// remember what the previous frame saw.
module main

import ui2

// The node the kernel publishes. Absent on a kernel too old for it, which the
// window says rather than showing an empty list.
const activity_device = '/dev/processes'

// Mirrors of the kernel's ABI, field for field. procdev.v is the other half of
// this and the two must be changed together; `activity_table_version` is what
// catches it if they are not.
const activity_table_version = u32(1)
const activity_name_len = 64

// How many processes one read can bring back. The kernel caps its own answer
// at the same number, so a larger buffer here would only ever be empty space.
const activity_max_records = 512

struct ActivitySample {
mut:
	pid          int
	ppid         int
	threads      int
	reserved     int
	memory_bytes u64
	cpu_time_ns  u64
	name         [activity_name_len]u8
}

struct ActivityTable {
mut:
	version      u32
	record_size  u32
	count        u32
	total        u32
	sample_ns    u64
	total_memory u64
	free_memory  u64
}

// How often the list is re-read. A monitor that sampled every frame would
// spend its time measuring itself, and a CPU percentage taken over 16 ms is
// mostly noise: a process either did or did not get a timeslice in that
// window, so every figure would read 0% or 100%. A second is long enough to
// average several timeslices and short enough to feel live.
const activity_interval_ms = i64(1000)
const activity_mb_bytes = u64(1_000_000)

// ── The model ──────────────────────────────────────────────────────

// ActivityRow is one process as the window shows it. The formatted text is
// kept rather than rebuilt per frame: the tree is rebuilt sixty times a second
// and the numbers change once a second, and this target has no garbage
// collector to clean up the difference.
struct ActivityRow {
mut:
	pid         int
	cpu_percent f64
	memory_bytes u64
	name        string
	pid_text    string
	cpu_text    string
	mem_text    string
	// Hosted applications share the desktop process, so the kernel cannot
	// account for them separately. They still get a row, marked here so an
	// updated window list can replace them without touching process samples.
	is_app    bool
	window_id int
}

// previous holds what a pid's CPU counter read last time round, so the next
// sample can be turned into a rate. It is keyed by pid rather than by position
// because the list is sorted by usage and reorders constantly.
struct ActivityPrevious {
mut:
	pid         int
	cpu_time_ns u64
}

enum ActivitySort {
	cpu
	memory
	name
}

struct ActivityMonitor {
mut:
	rows         []ActivityRow
	scratch_rows []ActivityRow
	previous     []ActivityPrevious
	// The reading the last sample was taken at, and the clock then, so the
	// next one knows how wide the interval was.
	sampled_ns   u64
	last_poll_ms i64
	sort         ActivitySort = .cpu
	scroll       int
	visible_rows int = 1
	// Summary text, rebuilt with the rows for the same reason.
	summary       string
	error         string
	process_total u32
	used_memory   u64
	total_memory  u64
	app_count     int
	// The buffer a read lands in, allocated once. A snapshot is a few tens of
	// kilobytes and reading it into a fresh allocation every second would be a
	// steady leak.
	buffer []u8
}

fn activity_buffer_size() int {
	return int(sizeof(ActivityTable)) + activity_max_records * int(sizeof(ActivitySample))
}

// ── Reading the kernel's snapshot ──────────────────────────────────

// sample reads one snapshot and turns it into rows. It reports whether
// anything changed, which is what tells the compositor to redraw.
fn (mut m ActivityMonitor) sample() bool {
	fd := desktop_open_ro_nonblock(activity_device)
	if fd < 0 {
		return m.fail('${activity_device} is not there.\nThis kernel does not report processes.')
	}
	got := desktop_read(fd, m.buffer.data, u64(m.buffer.len))
	desktop_close(fd)

	if got < i64(sizeof(ActivityTable)) {
		return m.fail('Could not read ${activity_device}.')
	}

	header := unsafe { &ActivityTable(m.buffer.data) }
	if header.version != activity_table_version
		|| header.record_size != u32(sizeof(ActivitySample)) {
		return m.fail('${activity_device} speaks version ${header.version}, not ${activity_table_version}.')
	}

	// Trust the byte count that actually arrived over the header's own claim:
	// a short read must not send the loop below off the end of the buffer.
	available := (got - i64(sizeof(ActivityTable))) / i64(sizeof(ActivitySample))
	mut count := int(header.count)
	if i64(count) > available {
		count = int(available)
	}

	records := unsafe { &ActivitySample(voidptr(&u8(m.buffer.data) + sizeof(ActivityTable))) }
	m.apply_snapshot(header, records, count)
	return true
}

// apply_snapshot owns the allocation-heavy half of sampling separately from
// the device read. Besides making the lifetime rules explicit, this lets the
// manual-free regression feed it deterministic kernel records.
fn (mut m ActivityMonitor) apply_snapshot(header &ActivityTable, records &ActivitySample, count int) {

	// The width of the interval these rates are measured over. The first
	// sample has nothing before it, so every process reads 0% until the second
	// one lands — which is honest: nothing is yet known about the interval.
	elapsed_ns := if m.sampled_ns != 0 && header.sample_ns > m.sampled_ns {
		header.sample_ns - m.sampled_ns
	} else {
		u64(0)
	}

	m.scratch_rows.clear()
	unsafe { m.scratch_rows.flags.set(.noslices) }
	for i := 0; i < count; i++ {
		record := unsafe { &records[i] }
		cpu_percent := m.rate_for(record.pid, record.cpu_time_ns, elapsed_ns)
		old_index := m.process_row_index(record.pid)
		mut row := ActivityRow{}
		if old_index >= 0 {
			// Transfer the strings to the scratch row. Clearing the source makes
			// the final unmatched-row sweep safe under manual memory management.
			row = m.rows[old_index]
			m.rows[old_index] = ActivityRow{}
		} else {
			row.pid = record.pid
			row.pid_text = record.pid.str()
		}
		row.pid = record.pid
		row.cpu_percent = cpu_percent
		row.memory_bytes = record.memory_bytes
		row.name = replace_activity_text(row.name, activity_name_of(record))
		row.cpu_text = replace_activity_text(row.cpu_text, percent_text(cpu_percent))
		row.mem_text = replace_activity_text(row.mem_text, memory_mb_text(record.memory_bytes))
		m.scratch_rows << row
	}

	// Hosted applications are independent of the kernel snapshot. Carry them
	// across unchanged so sync_open_apps can see that the window set still
	// matches instead of cloning the same four strings every second.
	for index in 0 .. m.rows.len {
		if !m.rows[index].is_app {
			continue
		}
		m.scratch_rows << m.rows[index]
		m.rows[index] = ActivityRow{}
	}
	for index in 0 .. m.rows.len {
		m.free_row(index)
	}
	m.rows.clear()
	old_rows := m.rows
	m.rows = m.scratch_rows
	m.scratch_rows = old_rows

	m.remember(records, count)
	m.sampled_ns = header.sample_ns
	m.sort_rows()
	m.clamp_scroll()

	used := if header.total_memory > header.free_memory {
		header.total_memory - header.free_memory
	} else {
		u64(0)
	}
	m.process_total = header.total
	m.used_memory = used
	m.total_memory = header.total_memory
	m.update_summary()
	m.set_error('')
}

fn (m &ActivityMonitor) process_row_index(pid int) int {
	for index, row in m.rows {
		if !row.is_app && row.pid == pid {
			return index
		}
	}
	return -1
}

fn replace_activity_text(current string, next string) string {
	if current == next {
		unsafe { next.free() }
		return current
	}
	unsafe { current.free() }
	return next
}

// sync_open_apps adds the applications hosted inside vinix-desktop. They are
// real open applications, but not separate kernel processes, so /dev/processes
// cannot discover Calculator, Text Editor, or the other hosted windows on its
// own. CPU and RAM remain labelled as shared instead of duplicating the
// desktop process' figures and pretending they can be attributed per app.
fn (mut m ActivityMonitor) sync_open_apps(desktop &Desktop) bool {
	if m.open_apps_match(desktop) {
		return false
	}

	for index := m.rows.len - 1; index >= 0; index-- {
		if !m.rows[index].is_app {
			continue
		}
		m.free_row(index)
		m.rows.delete(index)
	}

	desktop_pid := m.desktop_process_pid()
	for window in desktop.windows {
		if window.page != .app {
			continue
		}
		m.rows << ActivityRow{
			pid: desktop_pid
			name: window.title.clone()
			pid_text: if desktop_pid > 0 { desktop_pid.str() } else { '-'.clone() }
			cpu_text: 'shared'.clone()
			mem_text: 'shared'.clone()
			is_app: true
			window_id: window.id
		}
	}

	m.app_count = activity_hosted_window_count(desktop)
	m.update_summary()
	m.sort_rows()
	m.clamp_scroll()
	return true
}

fn (m &ActivityMonitor) open_apps_match(desktop &Desktop) bool {
	mut count := 0
	for row in m.rows {
		if !row.is_app {
			continue
		}
		mut found := false
		for window in desktop.windows {
			if window.page == .app && window.id == row.window_id && window.title == row.name {
				found = true
				break
			}
		}
		if !found {
			return false
		}
		count++
	}
	return count == activity_hosted_window_count(desktop)
}

fn activity_hosted_window_count(desktop &Desktop) int {
	mut count := 0
	for window in desktop.windows {
		if window.page == .app {
			count++
		}
	}
	return count
}

fn (m &ActivityMonitor) desktop_process_pid() int {
	for row in m.rows {
		if !row.is_app && row.name == 'vinix-desktop' {
			return row.pid
		}
	}
	return 0
}

fn (mut m ActivityMonitor) update_summary() {
	process_noun := if m.process_total == 1 { 'process' } else { 'processes' }
	app_noun := if m.app_count == 1 { 'app' } else { 'apps' }
	// The values are named rather than interpolated in place so every owned
	// string can be released explicitly on the manual-free desktop target.
	process_count := m.process_total.str()
	app_count := m.app_count.str()
	used_text := human_size(m.used_memory)
	total_text := human_size(m.total_memory)
	unsafe { m.summary.free() }
	m.summary = '${process_count} ${process_noun}   ${app_count} open ${app_noun}   ${used_text} of ${total_text} used'
	unsafe {
		process_count.free()
		app_count.free()
		used_text.free()
		total_text.free()
	}
}

// set_error replaces the reason the window is empty, releasing the one before
// it. Assigning over a string that was built by interpolation would strand it.
fn (mut m ActivityMonitor) set_error(message string) {
	if m.error == message {
		unsafe { message.free() }
		return
	}
	unsafe { m.error.free() }
	m.error = message
}

// rate_for turns a process' running CPU total into a share of one CPU over the
// interval just measured. A pid that was not in the previous sample is new, and
// a new process is shown at 0% rather than credited with everything it did
// before anyone was watching.
fn (m &ActivityMonitor) rate_for(pid int, cpu_time_ns u64, elapsed_ns u64) f64 {
	if elapsed_ns == 0 {
		return 0.0
	}
	for entry in m.previous {
		if entry.pid != pid {
			continue
		}
		// A counter that went backwards means the pid was recycled onto a
		// different process between samples. Nothing useful can be said about
		// an interval that spans two different programs, so say nothing.
		if cpu_time_ns <= entry.cpu_time_ns {
			return 0.0
		}
		return f64(cpu_time_ns - entry.cpu_time_ns) * 100.0 / f64(elapsed_ns)
	}
	return 0.0
}

// remember replaces the previous sample's counters with this one's. The array
// is reused rather than reallocated: it is rewritten once a second forever.
fn (mut m ActivityMonitor) remember(records &ActivitySample, count int) {
	m.previous.clear()
	unsafe { m.previous.flags.set(.noslices) }
	for i := 0; i < count; i++ {
		record := unsafe { &records[i] }
		m.previous << ActivityPrevious{
			pid: record.pid
			cpu_time_ns: record.cpu_time_ns
		}
	}
}

// fail puts the window into its "nothing to show" state and says why. The rows
// go with it: a stale list under an error message would look like the truth.
fn (mut m ActivityMonitor) fail(message string) bool {
	changed := m.error != message || m.rows.len > 0
	m.free_rows()
	m.rows = []ActivityRow{}
	m.previous.clear()
	m.sampled_ns = 0
	m.set_error(message)
	return changed
}

// free_rows releases the strings the last sample built. Nothing else refers to
// them: the element tree is thrown away every frame and free_tree does not
// touch the text it was handed.
fn (mut m ActivityMonitor) free_rows() {
	for index in 0 .. m.rows.len {
		m.free_row(index)
	}
	for index in 0 .. m.scratch_rows.len {
		unsafe {
			m.scratch_rows[index].name.free()
			m.scratch_rows[index].pid_text.free()
			m.scratch_rows[index].cpu_text.free()
			m.scratch_rows[index].mem_text.free()
		}
	}
	unsafe {
		m.rows.free()
		m.scratch_rows.free()
		m.summary.free()
	}
	m.rows = []ActivityRow{}
	m.scratch_rows = []ActivityRow{}
	m.summary = ''
}

fn (mut m ActivityMonitor) free_row(index int) {
	unsafe {
		m.rows[index].name.free()
		m.rows[index].pid_text.free()
		m.rows[index].cpu_text.free()
		m.rows[index].mem_text.free()
	}
}

// activity_name_of copies a record's name out of its fixed field and reduces
// it to what is worth reading in a column.
//
// The kernel stores a process' name as the path it was executed from with its
// own pid in brackets after it — `/usr/bin/foo[12]`. Both parts are redundant
// here: the pid has a column of its own, and the directory is the same for
// nearly everything on the image. What is left is the basename, which is the
// name a person would use for the program.
//
// The field is NUL-terminated by the kernel, but a name that filled it exactly
// would leave no terminator to find, so the length is bounded either way.
fn activity_name_of(record &ActivitySample) string {
	mut length := 0
	for length < activity_name_len && record.name[length] != 0 {
		length++
	}
	// Drop the trailing `[pid]` groups. There can be more than one: a fork
	// names the child after its parent and appends again, so the shell the
	// terminal starts is `/bin/busybox[2]`, and the loop it runs is
	// `/bin/busybox[2][3]`. Every one of those numbers is an ancestor's pid
	// and none of them is this process', which has a column of its own — so
	// they all come off, and two copies of a program showing the same name is
	// exactly what a process list should do.
	for length > 0 && record.name[length - 1] == `]` {
		mut open_bracket := length - 2
		for open_bracket >= 0 && record.name[open_bracket] >= `0`
			&& record.name[open_bracket] <= `9` {
			open_bracket--
		}
		// Only when there was at least one digit between the brackets.
		// Anything else in brackets is part of the real name; stop there.
		if open_bracket < 0 || open_bracket >= length - 2 || record.name[open_bracket] != `[` {
			break
		}
		length = open_bracket
	}
	// Then the basename. A name that is all directory — a path ending in a
	// slash — keeps what it had rather than becoming nothing.
	mut start := 0
	for i := 0; i < length; i++ {
		if record.name[i] == `/` && i + 1 < length {
			start = i + 1
		}
	}
	if length <= start {
		return '(unnamed)'
	}
	return unsafe { tos(&u8(&record.name[start]), length - start).clone() }
}

// percent_text renders a share to one decimal place, which is as fine as a
// figure sampled once a second deserves. Anything at or over 100 loses the
// decimal: a process pinning several CPUs is interesting for the fact, not for
// the tenth.
fn percent_text(value f64) string {
	if value < 0.05 {
		return '0'
	}
	if value >= 100.0 {
		return int(value).str()
	}
	// V's generic floating-point formatter keeps scratch storage alive under
	// `-manualfree`. Percentages need only one decimal, so fixed-point integer
	// formatting is both cheaper and has explicit ownership.
	tenths := int(value * 10.0 + 0.5)
	whole := (tenths / 10).str()
	fraction := (tenths % 10).str()
	text := '${whole}.${fraction}'
	unsafe {
		whole.free()
		fraction.free()
	}
	return text
}

// memory_mb_text keeps the process list useful at both ends of the scale:
// small processes retain one decimal place while larger figures fit cleanly
// in the narrow numeric column. The monitor deliberately uses decimal MB,
// matching the label displayed to the user.
fn memory_mb_text(bytes u64) string {
	whole := bytes / activity_mb_bytes
	tenths := (bytes % activity_mb_bytes) * 10 / activity_mb_bytes
	if whole < 10 && tenths > 0 {
		whole_text := whole.str()
		tenths_text := tenths.str()
		text := '${whole_text}.${tenths_text} MB'
		unsafe {
			whole_text.free()
			tenths_text.free()
		}
		return text
	}
	whole_text := whole.str()
	text := '${whole_text} MB'
	unsafe { whole_text.free() }
	return text
}

fn (mut m ActivityMonitor) sort_rows() {
	match m.sort {
		.cpu {
			m.rows.sort_with_compare(fn (a &ActivityRow, b &ActivityRow) int {
				// Ties on CPU are common — most processes sit at zero — so
				// memory breaks them and the list stops shuffling every second.
				if a.cpu_percent != b.cpu_percent {
					return if a.cpu_percent > b.cpu_percent { -1 } else { 1 }
				}
				if a.memory_bytes != b.memory_bytes {
					return if a.memory_bytes > b.memory_bytes { -1 } else { 1 }
				}
				return a.pid - b.pid
			})
		}
		.memory {
			m.rows.sort_with_compare(fn (a &ActivityRow, b &ActivityRow) int {
				if a.memory_bytes != b.memory_bytes {
					return if a.memory_bytes > b.memory_bytes { -1 } else { 1 }
				}
				return a.pid - b.pid
			})
		}
		.name {
			m.rows.sort_with_compare(fn (a &ActivityRow, b &ActivityRow) int {
				order := compare_strings(a.name, b.name)
				return if order != 0 { order } else { a.pid - b.pid }
			})
		}
	}
}

fn (mut m ActivityMonitor) clamp_scroll() {
	max_scroll := m.rows.len - m.visible_rows
	if m.scroll > max_scroll {
		m.scroll = max_scroll
	}
	if m.scroll < 0 {
		m.scroll = 0
	}
}

// ── The hosted application ────────────────────────────────────────

const activity_action_cpu = 'activity.sort.cpu'
const activity_action_memory = 'activity.sort.memory'
const activity_action_name = 'activity.sort.name'
const activity_action_scroll_up = 'activity.scroll.up'
const activity_action_scroll_down = 'activity.scroll.down'

const activity_row_height = 22
const activity_header_height = 46
const activity_footer_height = 26
const activity_padding = 10

// Column widths, measured from the right edge so the process name takes
// whatever is left over and a narrow window still shows the numbers.
const activity_cpu_column = 62
const activity_mem_column = 62
const activity_pid_column = 52

struct ActivityApp {
mut:
	desktop &Desktop = unsafe { nil }
	monitor ActivityMonitor
}

fn open_activity(mut desktop Desktop) !HostedApp {
	mut app := &ActivityApp{
		desktop: desktop
	}
	app.monitor.buffer = []u8{len: activity_buffer_size()}
	app.monitor.sample()
	// A missing device is worth refusing to open for: the window would have
	// nothing in it but the reason it is empty, and the message reads better
	// where the desktop puts the rest of its launch failures.
	if app.monitor.error != '' {
		return error(app.monitor.error)
	}
	app.monitor.sync_open_apps(desktop)
	app.monitor.last_poll_ms = monotonic_millis()
	return app
}

// poll re-reads the snapshot once the interval is up. Satisfying PollingApp is
// what makes the numbers move without anyone touching the window.
fn (mut a ActivityApp) poll() bool {
	now := monotonic_millis()
	if now - a.monitor.last_poll_ms < activity_interval_ms {
		return false
	}
	a.monitor.last_poll_ms = now
	sampled := a.monitor.sample()
	apps_changed := if unsafe { a.desktop != nil } {
		a.monitor.sync_open_apps(a.desktop)
	} else {
		false
	}
	return sampled || apps_changed
}

fn (mut a ActivityApp) build(size ui2.Rect) !ui2.Element {
	// Opening, closing, or renaming a window already caused this build. Sync
	// here as well as on the timer so the app list changes in that same frame.
	if unsafe { a.desktop != nil } {
		a.monitor.sync_open_apps(a.desktop)
	}
	width := int(size.width)
	height := int(size.height)
	inner := width - 2 * activity_padding

	list_top := activity_header_height
	list_height := height - list_top - activity_footer_height
	a.monitor.visible_rows = if list_height > activity_row_height {
		list_height / activity_row_height
	} else {
		1
	}
	a.monitor.clamp_scroll()

	mut children := frame_elements(a.monitor.visible_rows + 11)

	// What the list is ordered by. Three buttons rather than clickable column
	// headings: a heading that is also a button has to look like one, and at
	// eleven point there is no room to show that it does.
	mut sort_x := activity_padding
	for option in activity_sort_options {
		children << ui2.button(activity_action_of(option), activity_sort_title(option), ui2.rect(f64(sort_x), 5, f64(activity_sort_width), 20), ui2.BoxStyle{
			bg: if a.monitor.sort == option { app_accent } else { activity_sort_idle }
			radius: 5
		}, ui2.TextStyle{
			color: if a.monitor.sort == option { app_on_accent } else { body_text }
			size: 11
			align: .center
		})
		sort_x += activity_sort_width + 4
	}

	// Column headings, then the rule the list hangs from.
	headings := activity_headings(width)
	for heading in headings {
		children << heading
	}
	unsafe { headings.free() }
	children << ui2.view('', ui2.rect(0, f64(list_top - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if a.monitor.error != '' {
		children << ui2.label('', a.monitor.error, ui2.rect(f64(activity_padding), f64(list_top + 10), f64(inner), 40), ui2.TextStyle{
			color: files_error
			size: 12
		})
		return ui2.screen(app_surface, children)
	}

	mut row := 0
	for index := a.monitor.scroll; index < a.monitor.rows.len && row < a.monitor.visible_rows; index++ {
		entry := a.monitor.rows[index]
		y := list_top + row * activity_row_height
		// A quiet stripe every other row. With twenty-odd rows of four columns
		// it is the difference between reading across a line and losing it.
		children << ui2.view('', ui2.rect(0, f64(y), f64(width), f64(activity_row_height)), ui2.BoxStyle{
			bg: activity_row_alt
			transparent: index % 2 == 0
		}, activity_row_cells(entry, width))
		row++
	}

	if a.monitor.rows.len > a.monitor.visible_rows {
		button_size := 18
		right := width - activity_padding - button_size
		children << ui2.button(activity_action_scroll_up, '-', ui2.rect(f64(right - button_size - 4), 6, f64(button_size), 18), ui2.BoxStyle{
			bg: files_up
			radius: 4
		}, ui2.TextStyle{
			color: app_on_accent
			size: 11
			align: .center
		})
		children << ui2.button(activity_action_scroll_down, '+', ui2.rect(f64(right), 6, f64(button_size), 18), ui2.BoxStyle{
			bg: files_up
			radius: 4
		}, ui2.TextStyle{
			color: app_on_accent
			size: 11
			align: .center
		})
	}

	// The footer: what the machine as a whole is doing.
	children << ui2.view('', ui2.rect(0, f64(height - activity_footer_height), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << ui2.label('', a.monitor.summary, ui2.rect(f64(activity_padding), f64(height - activity_footer_height + 5), f64(inner), 16), ui2.TextStyle{
		color: body_muted
		size: 11
	})

	return ui2.screen(app_surface, children)
}

const activity_sort_width = 52
const activity_sort_options = [ActivitySort.cpu, .memory, .name]

fn activity_action_of(sort ActivitySort) string {
	return match sort {
		.cpu { activity_action_cpu }
		.memory { activity_action_memory }
		.name { activity_action_name }
	}
}

fn activity_sort_title(sort ActivitySort) string {
	return match sort {
		.cpu { 'CPU' }
		.memory { 'RAM' }
		.name { 'Name' }
	}
}

// activity_headings labels the columns. The strings are constants, so building
// these each frame allocates nothing.
fn activity_headings(width int) []ui2.Element {
	y := f64(activity_header_height - 19)
	right := ui2.TextStyle{
		color: body_muted
		size: 10
		bold: true
		align: .right
	}
	name_width := width - activity_padding * 2 - activity_pid_column - activity_cpu_column - activity_mem_column
	mut headings := frame_elements(3)
	headings << ui2.label('', 'PID', ui2.rect(f64(activity_padding + name_width), y, f64(activity_pid_column), 14), right)
	headings << ui2.label('', '% CPU', ui2.rect(f64(activity_padding + name_width + activity_pid_column), y, f64(activity_cpu_column), 14), right)
	headings << ui2.label('', 'MB', ui2.rect(f64(activity_padding + name_width + activity_pid_column + activity_cpu_column), y, f64(activity_mem_column), 14), right)
	return headings
}

// activity_row_cells lays one process across the same four columns the
// headings above use.
fn activity_row_cells(entry ActivityRow, width int) []ui2.Element {
	name_width := width - activity_padding * 2 - activity_pid_column - activity_cpu_column - activity_mem_column
	number := ui2.TextStyle{
		color: body_text
		size: 11
		align: .right
	}
	// The busiest processes are the point of the window, so a process using a
	// real share of a CPU is marked rather than left to be found by reading.
	busy := entry.cpu_percent >= activity_busy_percent
	mut cells := frame_elements(4)
	cells << ui2.label('', entry.name, ui2.rect(f64(activity_padding), 0, f64(name_width), f64(activity_row_height)), ui2.TextStyle{
		color: body_heading
		size: 11
		bold: busy
	})
	cells << ui2.label('', entry.pid_text, ui2.rect(f64(activity_padding + name_width), 0, f64(activity_pid_column), f64(activity_row_height)), ui2.TextStyle{
		color: body_muted
		size: 11
		align: .right
	})
	cells << ui2.label('', entry.cpu_text, ui2.rect(f64(activity_padding + name_width + activity_pid_column), 0, f64(activity_cpu_column), f64(activity_row_height)), ui2.TextStyle{
		color: if busy { activity_busy } else { body_text }
		size: 11
		bold: busy
		align: .right
	})
	cells << ui2.label('', entry.mem_text, ui2.rect(f64(activity_padding + name_width + activity_pid_column + activity_cpu_column), 0, f64(activity_mem_column), f64(activity_row_height)), number)
	return cells
}

fn (mut a ActivityApp) handle(event_id string) ! {
	match event_id {
		activity_action_cpu {
			a.set_sort(.cpu)
		}
		activity_action_memory {
			a.set_sort(.memory)
		}
		activity_action_name {
			a.set_sort(.name)
		}
		activity_action_scroll_up {
			a.monitor.scroll -= a.monitor.visible_rows
			a.monitor.clamp_scroll()
		}
		activity_action_scroll_down {
			a.monitor.scroll += a.monitor.visible_rows
			a.monitor.clamp_scroll()
		}
		else {}
	}
}

// set_sort reorders the list at once rather than at the next sample: a second
// is a long time to wait to find out whether the button did anything.
fn (mut a ActivityApp) set_sort(sort ActivitySort) {
	if a.monitor.sort == sort {
		return
	}
	a.monitor.sort = sort
	a.monitor.scroll = 0
	a.monitor.sort_rows()
}
