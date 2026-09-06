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

// ── The model ──────────────────────────────────────────────────────

// ActivityRow is one process as the window shows it. The formatted text is
// kept rather than rebuilt per frame: the tree is rebuilt sixty times a second
// and the numbers change once a second, and this target has no garbage
// collector to clean up the difference.
struct ActivityRow {
mut:
	pid         int
	cpu_percent f64
	mem_percent f64
	name        string
	pid_text    string
	cpu_text    string
	mem_text    string
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
	rows     []ActivityRow
	previous []ActivityPrevious
	// The reading the last sample was taken at, and the clock then, so the
	// next one knows how wide the interval was.
	sampled_ns   u64
	last_poll_ms i64
	sort         ActivitySort = .cpu
	scroll       int
	visible_rows int = 1
	// Summary text, rebuilt with the rows for the same reason.
	summary string
	error   string
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

	// The width of the interval these rates are measured over. The first
	// sample has nothing before it, so every process reads 0% until the second
	// one lands — which is honest: nothing is yet known about the interval.
	elapsed_ns := if m.sampled_ns != 0 && header.sample_ns > m.sampled_ns {
		header.sample_ns - m.sampled_ns
	} else {
		u64(0)
	}

	m.free_rows()
	mut rows := []ActivityRow{cap: count}
	for i := 0; i < count; i++ {
		record := unsafe { &records[i] }
		cpu_percent := m.rate_for(record.pid, record.cpu_time_ns, elapsed_ns)
		mem_percent := if header.total_memory > 0 {
			f64(record.memory_bytes) * 100.0 / f64(header.total_memory)
		} else {
			0.0
		}
		rows << ActivityRow{
			pid:         record.pid
			cpu_percent: cpu_percent
			mem_percent: mem_percent
			name:        activity_name_of(record)
			pid_text:    record.pid.str()
			cpu_text:    percent_text(cpu_percent)
			mem_text:    percent_text(mem_percent)
		}
	}

	m.remember(records, count)
	m.sampled_ns = header.sample_ns
	m.rows = rows
	m.sort_rows()
	m.clamp_scroll()

	used := if header.total_memory > header.free_memory {
		header.total_memory - header.free_memory
	} else {
		u64(0)
	}
	noun := if header.total == 1 { 'process' } else { 'processes' }
	// The two sizes are named rather than interpolated in place so that the
	// strings human_size() builds can be handed back. Interpolating a call
	// copies its result into the sentence and drops the original on the
	// floor, which on a target with no garbage collector is a leak that
	// happens once a second for as long as the window is open.
	used_text := human_size(used)
	total_text := human_size(header.total_memory)
	m.summary = '${header.total} ${noun}   ${used_text} of ${total_text} used'
	unsafe {
		used_text.free()
		total_text.free()
	}
	m.set_error('')
	return true
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
	for i := 0; i < count; i++ {
		record := unsafe { &records[i] }
		m.previous << ActivityPrevious{
			pid:         record.pid
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
	for row in m.rows {
		unsafe {
			row.name.free()
			row.pid_text.free()
			row.cpu_text.free()
			row.mem_text.free()
		}
	}
	unsafe {
		m.rows.free()
		m.summary.free()
	}
	m.summary = ''
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
		return '${int(value)}'
	}
	return '${value:.1f}'
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
				if a.mem_percent != b.mem_percent {
					return if a.mem_percent > b.mem_percent { -1 } else { 1 }
				}
				return a.pid - b.pid
			})
		}
		.memory {
			m.rows.sort_with_compare(fn (a &ActivityRow, b &ActivityRow) int {
				if a.mem_percent != b.mem_percent {
					return if a.mem_percent > b.mem_percent { -1 } else { 1 }
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
const activity_header_height = 62
const activity_footer_height = 26
const activity_padding = 10

// Column widths, measured from the right edge so the process name takes
// whatever is left over and a narrow window still shows the numbers.
const activity_cpu_column = 62
const activity_mem_column = 62
const activity_pid_column = 52

struct ActivityApp {
mut:
	monitor ActivityMonitor
}

fn open_activity(mut desktop Desktop) !HostedApp {
	mut app := &ActivityApp{}
	app.monitor.buffer = []u8{len: activity_buffer_size()}
	app.monitor.sample()
	// A missing device is worth refusing to open for: the window would have
	// nothing in it but the reason it is empty, and the message reads better
	// where the desktop puts the rest of its launch failures.
	if app.monitor.error != '' {
		return error(app.monitor.error)
	}
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
	return a.monitor.sample()
}

fn (mut a ActivityApp) build(size ui2.Rect) !ui2.Element {
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

	mut children := []ui2.Element{}
	children << ui2.label('', 'Activity Monitor', ui2.rect(f64(activity_padding), 10,
		f64(inner), 22), ui2.TextStyle{
		color: body_heading
		size: 16
		bold: true
	})

	// What the list is ordered by. Three buttons rather than clickable column
	// headings: a heading that is also a button has to look like one, and at
	// eleven point there is no room to show that it does.
	mut sort_x := width - activity_padding - 3 * activity_sort_width - 2 * 4
	for option in [ActivitySort.cpu, .memory, .name] {
		children << ui2.button(activity_action_of(option), activity_sort_title(option),
			ui2.rect(f64(sort_x), 12, f64(activity_sort_width), 20), ui2.BoxStyle{
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
	for heading in activity_headings(width) {
		children << heading
	}
	children << ui2.view('', ui2.rect(0, f64(list_top - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if a.monitor.error != '' {
		children << ui2.label('', a.monitor.error, ui2.rect(f64(activity_padding), f64(list_top +
			10), f64(inner), 40), ui2.TextStyle{
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
		children << ui2.view('', ui2.rect(0, f64(y), f64(width), f64(activity_row_height)),
			ui2.BoxStyle{
			bg: activity_row_alt
			transparent: index % 2 == 0
		}, activity_row_cells(entry, width))
		row++
	}

	if a.monitor.rows.len > a.monitor.visible_rows {
		button_size := 18
		right := width - activity_padding - button_size
		children << ui2.button(activity_action_scroll_up, '-', ui2.rect(f64(right - button_size - 4),
			f64(activity_header_height - 22), f64(button_size), 18), ui2.BoxStyle{
			bg: files_up
			radius: 4
		}, ui2.TextStyle{
			color: app_on_accent
			size: 11
			align: .center
		})
		children << ui2.button(activity_action_scroll_down, '+', ui2.rect(f64(right),
			f64(activity_header_height - 22), f64(button_size), 18), ui2.BoxStyle{
			bg: files_up
			radius: 4
		}, ui2.TextStyle{
			color: app_on_accent
			size: 11
			align: .center
		})
	}

	// The footer: what the machine as a whole is doing.
	children << ui2.view('', ui2.rect(0, f64(height - activity_footer_height), f64(width),
		1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << ui2.label('', a.monitor.summary, ui2.rect(f64(activity_padding), f64(height -
		activity_footer_height + 5), f64(inner), 16), ui2.TextStyle{
		color: body_muted
		size: 11
	})

	return ui2.screen(app_surface, children)
}

const activity_sort_width = 52

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
	style := ui2.TextStyle{
		color: body_muted
		size: 10
		bold: true
	}
	right := ui2.TextStyle{
		color: body_muted
		size: 10
		bold: true
		align: .right
	}
	name_width := width - activity_padding * 2 - activity_pid_column - activity_cpu_column -
		activity_mem_column
	return [
		ui2.label('', 'PROCESS', ui2.rect(f64(activity_padding), y, f64(name_width), 14),
			style),
		ui2.label('', 'PID', ui2.rect(f64(activity_padding + name_width), y, f64(activity_pid_column),
			14), right),
		ui2.label('', '% CPU', ui2.rect(f64(activity_padding + name_width + activity_pid_column),
			y, f64(activity_cpu_column), 14), right),
		ui2.label('', '% RAM', ui2.rect(f64(activity_padding + name_width + activity_pid_column +
			activity_cpu_column), y, f64(activity_mem_column), 14), right),
	]
}

// activity_row_cells lays one process across the same four columns the
// headings above use.
fn activity_row_cells(entry ActivityRow, width int) []ui2.Element {
	name_width := width - activity_padding * 2 - activity_pid_column - activity_cpu_column -
		activity_mem_column
	number := ui2.TextStyle{
		color: body_text
		size: 11
		align: .right
	}
	// The busiest processes are the point of the window, so a process using a
	// real share of a CPU is marked rather than left to be found by reading.
	busy := entry.cpu_percent >= activity_busy_percent
	return [
		ui2.label('', entry.name, ui2.rect(f64(activity_padding), 0, f64(name_width),
			f64(activity_row_height)), ui2.TextStyle{
			color: body_heading
			size: 11
			bold: busy
		}),
		ui2.label('', entry.pid_text, ui2.rect(f64(activity_padding + name_width), 0,
			f64(activity_pid_column), f64(activity_row_height)), ui2.TextStyle{
			color: body_muted
			size: 11
			align: .right
		}),
		ui2.label('', entry.cpu_text, ui2.rect(f64(activity_padding + name_width +
			activity_pid_column), 0, f64(activity_cpu_column), f64(activity_row_height)),
			ui2.TextStyle{
			color: if busy { activity_busy } else { body_text }
			size: 11
			bold: busy
			align: .right
		}),
		ui2.label('', entry.mem_text, ui2.rect(f64(activity_padding + name_width +
			activity_pid_column + activity_cpu_column), 0, f64(activity_mem_column),
			f64(activity_row_height)), number),
	]
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
