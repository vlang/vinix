// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn C.getuid() u32

const activity_default_columns = u32(15)
const activity_search_limit = 128
const activity_action_search = 'activity.search'
const activity_action_search_done = 'activity.search.done'
const activity_action_filter = 'activity.filter'
const activity_action_tree = 'activity.tree'
const activity_action_columns = 'activity.columns'
const activity_action_pause = 'activity.pause'
const activity_action_interval = 'activity.interval'
const activity_action_inspect = 'activity.inspect'
const activity_action_scrollbar = 'activity.scrollbar'

enum ActivityFilter {
	all
	applications
	user
	active
	system
	inactive
	other_users
	selected
}

struct ActivityVisible {
	index   int
	depth   int
	context bool
}


// Reused tree scratch belongs to the monitor. Passing local fixed arrays by
// reference makes V heap-lift them under -manualfree, even on the flat path.
struct ActivityBrowseWorkspace {
mut:
	included [activity_max_records]bool
	matched [activity_max_records]bool
	visited [activity_max_records]bool
}

// Search compares UTF-8 bytes without allocating lowercase copies. ASCII
// letters fold, while non-ASCII text matches exactly as typed.
fn activity_contains_fold(text string, query []u8) bool {
	if query.len == 0 {
		return true
	}
	if query.len > text.len {
		return false
	}
	for start := 0; start <= text.len - query.len; start++ {
		mut found := true
		for index, byte in query {
			left := text[start + index]
			folded_left := if left >= `A` && left <= `Z` { left + 32 } else { left }
			folded_right := if byte >= `A` && byte <= `Z` { byte + 32 } else { byte }
			if folded_left != folded_right {
				found = false
				break
			}
		}
		if found {
			return true
		}
	}
	return false
}

fn activity_is_application(row &ActivityRow) bool {
	mut start := 0
	for index, byte in row.executable {
		if byte == `/` {
			start = index + 1
		}
	}
	for app in available_apps {
		if app.process_name.len == row.executable.len - start {
			mut matches := true
			for index, byte in app.process_name {
				if row.executable[start + index] != byte {
					matches = false
					break
				}
			}
			if matches {
				return true
			}
		}
	}
	return false
}

fn (m &ActivityMonitor) matches_row(row &ActivityRow) bool {
	if !activity_contains_fold(activity_display_name(row.name), m.query)
		&& !activity_contains_fold(row.executable, m.query)
		&& !activity_contains_fold(row.pid_text, m.query) {
		return false
	}
	return match m.filter {
		.all { true }
		.applications { activity_is_application(row) }
		.user { row.uid_known && row.uid == m.viewer_uid }
		.active { row.cpu_percent > 0.0 }
		.system { row.uid_known && row.uid == 0 }
		.inactive { row.cpu_percent == 0.0 }
		.other_users { row.uid_known && row.uid != m.viewer_uid }
		.selected { m.selected_pid > 0 && row.pid == m.selected_pid }
	}
}

// Ancestors remain in filtered trees as dimmed context, so a search result
// keeps its real parent relationship. Fixed working arrays also bound malformed
// or recycled PPID cycles, and the output array is reused at each sample.
fn (mut m ActivityMonitor) rebuild_visible() {
	m.visible.clear()
	unsafe { m.visible.flags |= .noslices }
	m.workspace = ActivityBrowseWorkspace{}
	count := if m.rows.len < activity_max_records { m.rows.len } else { activity_max_records }
	for index := 0; index < count; index++ {
		m.workspace.matched[index] = m.matches_row(&m.rows[index])
		m.workspace.included[index] = m.workspace.matched[index]
	}
	if !m.hierarchy {
		for index := 0; index < count; index++ {
			if m.workspace.included[index] {
				m.visible << ActivityVisible{ index: index }
			}
		}
		m.clamp_scroll()
		return
	}
	for index := 0; index < count; index++ {
		if !m.workspace.matched[index] {
			continue
		}
		mut parent := m.rows[index].ppid
		for _ in 0 .. count {
			parent_index := m.process_row_index(parent)
			if parent_index < 0 || parent_index >= count || m.workspace.included[parent_index] {
				break
			}
			m.workspace.included[parent_index] = true
			parent = m.rows[parent_index].ppid
		}
	}
	// Visit roots in the chosen sort order. Their children follow that same
	// order; sorting never breaks the adjacency of a parent and its children.
	for index := 0; index < count; index++ {
		parent := m.process_row_index(m.rows[index].ppid)
		if m.workspace.included[index] && (parent < 0 || parent == index || !m.workspace.included[parent]) {
			m.append_tree(index, 0)
		}
	}
	// Every process must remain reachable even if its PPID forms a cycle.
	for index := 0; index < count; index++ {
		if m.workspace.included[index] && !m.workspace.visited[index] {
			m.append_tree(index, 0)
		}
	}
	m.clamp_scroll()
}

fn (mut m ActivityMonitor) append_tree(index int, depth int) {
	if m.workspace.visited[index] {
		return
	}
	m.workspace.visited[index] = true
	m.visible << ActivityVisible{ index: index, depth: depth, context: !m.workspace.matched[index] }
	pid := m.rows[index].pid
	for child := 0; child < m.rows.len && child < activity_max_records; child++ {
		if m.workspace.included[child] && !m.workspace.visited[child] && m.rows[child].ppid == pid {
			m.append_tree(child, depth + 1)
		}
	}
}

fn activity_executable_of(record &ActivitySample) string {
	mut length := 0
	for length < activity_name_len && record.name[length] != 0 {
		length++
	}
	for length > 0 && record.name[length - 1] == `]` {
		mut bracket := length - 2
		for bracket >= 0 && record.name[bracket] >= `0` && record.name[bracket] <= `9` {
			bracket--
		}
		if bracket < 0 || bracket >= length - 2 || record.name[bracket] != `[` {
			break
		}
		length = bracket
	}
	return if length > 0 { unsafe { tos(&record.name[0], length).clone() } } else { '' }
}

fn activity_cpu_time_text(nanoseconds u64) string {
	milliseconds := nanoseconds / 1_000_000
	seconds := (milliseconds / 1000).str()
	fraction := ((milliseconds % 1000) / 10).str()
	text := if milliseconds % 1000 < 100 {
		'${seconds}.0${fraction}'
	} else {
		'${seconds}.${fraction}'
	}
	unsafe {
		seconds.free()
		fraction.free()
	}
	return text
}

// Parse /proc without string splitting: sampling every process is a repeated
// path under -manualfree, and the buffer can live on the stack.
fn activity_parse_identity(mut row ActivityRow, buffer &u8, length int) {
	row.uid_known = false
	row.state = 0
	mut start := 0
	for start < length {
		mut end := start
		for end < length && unsafe { buffer[end] } != `\n` {
			end++
		}
		if end - start >= 4 && unsafe {
			buffer[start] == `U` && buffer[start + 1] == `i`
				&& buffer[start + 2] == `d` && buffer[start + 3] == `:`
		} {
			mut index := start + 4
			for index < end && unsafe { buffer[index] == ` ` || buffer[index] == `\t` } {
				index++
			}
			mut uid := 0
			for index < end && unsafe { buffer[index] >= `0` && buffer[index] <= `9` } {
				row.uid_known = true
				uid = uid * 10 + int(unsafe { buffer[index] }) - int(`0`)
				index++
			}
			row.uid = uid
		} else if end - start >= 6 && unsafe {
			buffer[start] == `S` && buffer[start + 1] == `t`
				&& buffer[start + 2] == `a` && buffer[start + 3] == `t` && buffer[start + 4] == `e`
				&& buffer[start + 5] == `:`
		} {
			mut index := start + 6
			for index < end && unsafe { buffer[index] == ` ` || buffer[index] == `\t` } {
				index++
			}
			if index < end {
				row.state = unsafe { buffer[index] }
			}
		}
		start = end + 1
	}
	row.user_text = replace_activity_text(row.user_text, if row.uid_known {
		row.uid.str()
	} else {
		'—'
	})
	row.state_text = replace_activity_text(row.state_text, activity_state_text(row.state).clone())
}

fn activity_read_identity(mut row ActivityRow) {
	path := '/proc/${row.pid_text}/status'
	defer { unsafe { path.free() } }
	fd := desktop_open_ro_nonblock(path)
	mut buffer := [2048]u8{}
	mut got := i64(0)
	if fd >= 0 {
		got = desktop_read(fd, &buffer[0], u64(buffer.len))
		desktop_close(fd)
	}
	activity_parse_identity(mut row, &buffer[0], if got > 0 { int(got) } else { 0 })
}

fn activity_state_text(state u8) string {
	return match state {
		`R` { tr('activity.state.running') }
		`S`, `D`, `I` { tr('activity.state.sleeping') }
		`T`, `t` { tr('activity.state.stopped') }
		`Z` { tr('activity.state.zombie') }
		`X` { tr('activity.state.exited') }
		else { '—' }
	}
}

fn activity_filter_text(filter ActivityFilter) string {
	return match filter {
		.all { tr('activity.filter.all') }
		.applications { tr('activity.filter.applications') }
		.user { tr('activity.filter.user') }
		.active { tr('activity.filter.active') }
		.system { tr('activity.filter.system') }
		.inactive { tr('activity.filter.inactive') }
		.other_users { tr('activity.filter.other_users') }
		.selected { tr('activity.filter.selected') }
	}
}

fn activity_interval_text(interval i64) string {
	return match interval {
		500 { tr('activity.interval.fast') }
		2000 { tr('activity.interval.slow') }
		5000 { tr('activity.interval.slowest') }
		else { tr('activity.interval.normal') }
	}
}

fn activity_toolbar_button(action string, label string, x int, y int, width int, selected bool) ui2.Element {
	return ui2.Element{
		...ui2.button(action, label, ui2.rect(f64(x), f64(y), f64(width), 26), ui2.BoxStyle{
			bg:     if selected { files_sidebar_selected } else { app_surface }
			radius: 4
		}, ui2.TextStyle{ color: body_text, size: 11, align: .center })
		tooltip:             label
		accessibility_label: label
	}
}

fn activity_toolbar_icon(action string, label string, image string, x int, y int, width int, selected bool) ui2.Element {
	return ui2.Element{
		...ui2.button_with_image(action, '', image, ui2.rect(f64(x), f64(y), f64(width), 26),
			ui2.BoxStyle{ bg: if selected { files_sidebar_selected } else { app_surface }, radius: 4 },
			ui2.TextStyle{ color: body_text })
		tooltip: label
		accessibility_label: label
	}
}

fn (a &ActivityApp) build_search_field(mut children []ui2.Element, x int, y int, width int) {
	children << ui2.Element{
		...ui2.text_field(activity_action_search, tr('activity.search'), rename_buffer_text(a.monitor.query),
			ui2.rect(f64(x), f64(y), f64(width), 26), ui2.BoxStyle{ bg: app_surface, radius: 4 },
			ui2.TextStyle{ color: body_text }, 0)
		image_path: 'builtin:finder_search'
		focused: a.search_focused
		text_selection: ui2.TextSelection{ anchor: files_rune_count(a.monitor.query), caret: files_rune_count(a.monitor.query) }
		accessibility_label: tr('activity.search')
	}
}

// Top row reserves x=10..38 for force-kill; x=44..164 is intentionally
// available for additional icon controls. Search follows the right edge.
fn (a &ActivityApp) build_browse_toolbar(mut children []ui2.Element, width int) {
	children << ui2.Element{
		...activity_toolbar_button(activity_action_inspect, 'i', 44, 4, 28, a.inspector_open)
		enabled:             a.monitor.selected_pid > 0
		tooltip:             tr('activity.inspect')
		accessibility_label: tr('activity.inspect')
	}
	if width < 480 {
		pause_label := if a.monitor.paused { tr('activity.resume_refresh') } else { tr('activity.pause_refresh') }
		children << ui2.Element{
			...activity_toolbar_button(activity_action_pause, if a.monitor.paused { '>' } else { '||' }, 78, 4, 28, a.monitor.paused)
			tooltip: pause_label
			accessibility_label: pause_label
		}
		children << activity_toolbar_button(activity_action_interval, activity_interval_text(a.monitor.interval_ms), 112, 4, 28, false)
		children << activity_toolbar_icon(activity_action_search, tr('activity.search'), 'builtin:finder_search', 146, 4, 24,
			a.search_focused || a.monitor.query.len > 0)
		if width >= 246 {
			children << activity_toolbar_icon(activity_action_export_list, tr('activity.list.export'), 'builtin:finder_list', 180, 4, 28, false)
			children << activity_toolbar_icon(activity_action_clear_history, tr('activity.history.clear'), 'builtin:close', 214, 4, 28, false)
		}
		if a.search_focused {
			a.build_search_field(mut children, activity_padding, 36, width - 54)
			children << activity_toolbar_icon(activity_action_search_done, tr('activity.search.done'), 'builtin:close', width - 34, 36, 24, false)
		} else {
			children << activity_toolbar_icon(activity_action_filter, activity_filter_text(a.monitor.filter), 'builtin:finder_list', 10, 36, 28, a.monitor.filter != .all)
			children << ui2.Element{
				...activity_toolbar_button(activity_action_tree, '↳', 44, 36, 28, a.monitor.hierarchy)
				tooltip: tr('activity.tree')
				accessibility_label: tr('activity.tree')
			}
			children << activity_toolbar_icon(activity_action_columns, tr('activity.columns'), 'builtin:column_view', 78, 36, 28, a.columns_open)
		}
		return
	}
	children << activity_toolbar_icon(activity_action_export_list, tr('activity.list.export'), 'builtin:finder_list', 78, 4, 28, false)
	children << activity_toolbar_icon(activity_action_clear_history, tr('activity.history.clear'), 'builtin:close', 112, 4, 28, false)
	children << activity_toolbar_button(activity_action_pause, if a.monitor.paused {
		tr('activity.resume_refresh')
	} else {
		tr('activity.pause_refresh')
	}, 170, 4, 72, a.monitor.paused)
	children << activity_toolbar_button(activity_action_interval, activity_interval_text(a.monitor.interval_ms),
		246, 4, 64, false)
	search_left := if width > 630 { width - 300 } else { 318 }
	a.build_search_field(mut children, search_left, 4, width - search_left - activity_padding)
	children << activity_toolbar_button(activity_action_filter, activity_filter_text(a.monitor.filter),
		activity_padding, 36, if width >= 640 { 138 } else { 96 }, a.monitor.filter != .all)
	children << activity_toolbar_button(activity_action_tree, tr('activity.tree'), if width >= 640 { 154 } else { 112 }, 36, if width >= 640 { 96 } else { 80 }, a.monitor.hierarchy)
	children << activity_toolbar_button(activity_action_columns, tr('activity.columns'), if width >= 640 { 256 } else { 198 }, 36, if width >= 640 { 96 } else { 70 }, a.columns_open)
}

fn activity_column_bit(column ActivitySort) u32 {
	return match column {
		.name { u32(1) }
		.pid { u32(2) }
		.cpu { u32(4) }
		.memory { u32(8) }
		.ppid { u32(16) }
		.threads { u32(32) }
		.cpu_time { u32(64) }
		.user { u32(128) }
		.state { u32(256) }
	}
}

fn activity_column_toggle(column ActivitySort) string {
	return match column {
		.name { '' }
		.pid { 'activity.column.toggle.pid' }
		.cpu { 'activity.column.toggle.cpu' }
		.memory { 'activity.column.toggle.memory' }
		.ppid { 'activity.column.toggle.ppid' }
		.threads { 'activity.column.toggle.threads' }
		.cpu_time { 'activity.column.toggle.cpu_time' }
		.user { 'activity.column.toggle.user' }
		.state { 'activity.column.toggle.state' }
	}
}

fn activity_column_width(column ActivitySort) int {
	return match column {
		.name { 0 }
		.pid, .ppid { 52 }
		.cpu, .memory, .user, .threads { 62 }
		.cpu_time { 80 }
		.state { 84 }
	}
}

const activity_columns_order = [ActivitySort.name, .pid, .cpu, .memory, .ppid, .threads, .cpu_time,
	.user, .state]!

fn activity_column_layout(width int, columns u32) (int, int) {
	mut numeric_width := 0
	mut count := 0
	for column in activity_columns_order {
		if column != .name && columns & activity_column_bit(column) != 0 {
			numeric_width += activity_column_width(column)
			count++
		}
	}
	available := width - activity_padding * 2 - 10
	if available - numeric_width >= 120 || count == 0 {
		return available - numeric_width, 0
	}
	return 120, if available > 120 { (available - 120) / count } else { 1 }
}

fn activity_browse_header(mut children []ui2.Element, width int, monitor &ActivityMonitor) {
	children << ui2.view('', ui2.rect(0, f64(activity_toolbar_height), f64(width), f64(activity_header_height)),
		ui2.BoxStyle{ bg: body_panel }, [])
	name_width, compressed := activity_column_layout(width, monitor.columns)
	mut x := activity_padding
	for column in activity_columns_order {
		if monitor.columns & activity_column_bit(column) == 0 {
			continue
		}
		column_width := if column == .name {
			name_width
		} else if compressed > 0 {
			compressed
		} else {
			activity_column_width(column)
		}
		activity_heading(mut children, column, x, column_width, if column == .name {
			0
		} else {
			x + activity_rule_gap
		},
			x + column_width + activity_rule_gap, monitor.sort, monitor.descending)
		x += column_width
	}
}

fn activity_column_value(row &ActivityRow, column ActivitySort) string {
	return match column {
		.name { activity_display_name(row.name) }
		.pid { row.pid_text }
		.cpu { row.cpu_text }
		.memory { row.mem_text }
		.ppid { row.ppid_text }
		.threads { row.threads_text }
		.cpu_time { row.cpu_time_text }
		.user { row.user_text }
		.state { row.state_text }
	}
}

fn activity_browse_row_cells(row &ActivityRow, width int, columns u32, depth int, context bool) []ui2.Element {
	name_width, compressed := activity_column_layout(width, columns)
	mut cells := frame_elements(10)
	mut x := activity_padding
	busy := row.cpu_percent >= activity_busy_percent
	for column in activity_columns_order {
		if columns & activity_column_bit(column) == 0 {
			continue
		}
		column_width := if column == .name {
			name_width
		} else if compressed > 0 {
			compressed
		} else {
			activity_column_width(column)
		}
		indent := if column == .name {
			if depth * 14 < name_width - 40 { depth * 14 } else { name_width - 40 }
		} else {
			0
		}
		if column == .name && depth > 0 {
			cells << ui2.label('', '↳', ui2.rect(f64(x + indent - 12), 0, 12, f64(activity_row_height)),
				ui2.TextStyle{ color: body_muted, size: 11 })
		}
		cells << ui2.label('', activity_column_value(row, column),
			ui2.rect(f64(x + indent), 0, f64(column_width - indent), f64(activity_row_height)), ui2.TextStyle{
				color: if context {
					body_muted
				} else if column == .cpu && busy {
					activity_busy
				} else if column == .name {
					body_heading
				} else {
					body_text
				}
				size:  11
				bold:  busy && column in [.name, .cpu]
				align: if column in [.name, .state] { ui2.Align.left } else { ui2.Align.right }
			})
		x += column_width
	}
	return cells
}

fn activity_columns_geometry(width int, height int) (int, int, int, int) {
	menu_width := if width >= 210 { 190 } else { width - 2 * activity_padding }
	left := if width > 446 { 256 } else { width - menu_width - activity_padding }
	fit := (height - 64 - 6) / 25
	visible := if fit >= 8 { 8 } else if fit > 0 { fit } else { 1 }
	return left, menu_width, visible * 25 + 6, visible
}

fn (mut a ActivityApp) clamp_columns_scroll() {
	maximum := 8 - a.columns_visible
	if a.columns_scroll > maximum { a.columns_scroll = maximum }
	if a.columns_scroll < 0 { a.columns_scroll = 0 }
}

fn (mut a ActivityApp) build_columns_menu(mut children []ui2.Element, width int, height int) {
	left, menu_width, menu_height, visible := activity_columns_geometry(width, height)
	a.columns_visible = visible
	a.clamp_columns_scroll()
	mut menu := frame_elements(20)
	mut y := 3
	for index := a.columns_scroll; index < 8 && index < a.columns_scroll + visible; index++ {
		column := activity_columns_order[index + 1]
		selected := a.monitor.columns & activity_column_bit(column) != 0
		mut item := frame_elements(2)
		item << ui2.label('', if selected { '✓' } else { '' }, ui2.rect(8, 0, 20, 25), ui2.TextStyle{ color: body_text, size: 12 })
		item << ui2.label('', activity_column_title(column), ui2.rect(30, 0, f64(menu_width - 60), 25), ui2.TextStyle{ color: body_text, size: 12 })
		menu << ui2.clickable_view(activity_column_toggle(column), ui2.rect(0, f64(y), f64(menu_width - 24), 25),
			ui2.BoxStyle{ transparent: true }, item)
		y += 25
	}
	if visible < 8 {
		arrow_height := if menu_height >= 46 { 20 } else { (menu_height - 6) / 2 }
		for index in 0 .. 2 {
			label := if index == 0 { tr('activity.scroll_up') } else { tr('activity.scroll_down') }
			menu << ui2.Element{
				...ui2.button_with_image(if index == 0 { 'activity.columns.up' } else { 'activity.columns.down' }, '',
					if index == 0 { 'builtin:arrow_up' } else { 'builtin:arrow_down' },
					ui2.rect(f64(menu_width - 21), f64(if index == 0 { 3 } else { menu_height - 3 - arrow_height }), 18, f64(arrow_height)),
					ui2.BoxStyle{ bg: app_surface, radius: 3 }, ui2.TextStyle{ color: body_text })
				enabled: if index == 0 { a.columns_scroll > 0 } else { a.columns_scroll < 8 - visible }
				tooltip: label
				accessibility_label: label
			}
		}
	}
	children << ui2.view('activity.columns.menu', ui2.rect(f64(left), 64, f64(menu_width), f64(menu_height)), ui2.BoxStyle{
		bg:            body_panel
		border_color:  body_rule
		border_left:   1
		border_right:  1
		border_top:    1
		border_bottom: 1
		radius:        4
	}, menu)
}

fn (mut a ActivityApp) columns_key_input(input string) bool {
	if !a.columns_open { return false }
	match input {
		'\x1b[A' { a.columns_scroll-- }
		'\x1b[B' { a.columns_scroll++ }
		'\x1b[5~' { a.columns_scroll -= a.columns_visible }
		'\x1b[6~' { a.columns_scroll += a.columns_visible }
		'\x1b[H', '\x1b[1~' { a.columns_scroll = 0 }
		'\x1b[F', '\x1b[4~' { a.columns_scroll = 8 }
		else { return false }
	}
	a.clamp_columns_scroll()
	return true
}

fn activity_scroll_thumb(height int, visible int, total int, scroll int) (int, int) {
	if total <= visible || total <= 0 || height <= 0 {
		return 0, height
	}
	mut thumb := height * visible / total
	if thumb < 20 {
		thumb = 20
	}
	if thumb > height {
		thumb = height
	}
	return (height - thumb) * scroll / (total - visible), thumb
}

fn activity_vertical_scrollbar(x int, y int, height int, monitor &ActivityMonitor) ui2.Element {
	position, thumb := activity_scroll_thumb(height, monitor.visible_rows, monitor.visible.len, monitor.scroll)
	mut children := frame_elements(1)
	children << ui2.view('', ui2.rect(1, f64(position), 6, f64(thumb)), ui2.BoxStyle{ bg: body_muted, radius: 3 }, [])
	return ui2.clickable_view(activity_action_scrollbar, ui2.rect(f64(x), f64(y), 8, f64(height)),
		ui2.BoxStyle{ bg: body_rule, radius: 4 }, children)
}

fn (mut a ActivityApp) handle_browse(action string) bool {
	if a.handle_utility(action) { return true }
	if action in [activity_action_search, activity_action_filter, activity_action_tree, activity_action_columns] {
		a.view = .processes
		a.inspector_open = false
		a.panel_scroll = 0
	}
	match action {
		activity_action_search {
			a.search_focused = true
			a.columns_open = false
		}
		activity_action_search_done { a.search_focused = false }
		activity_action_filter {
			a.monitor.filter = match a.monitor.filter {
				.all { ActivityFilter.applications }
				.applications { ActivityFilter.user }
				.user { ActivityFilter.active }
				.active { ActivityFilter.system }
				.system { ActivityFilter.inactive }
				.inactive { ActivityFilter.other_users }
				.other_users { ActivityFilter.selected }
				.selected { ActivityFilter.all }
			}
			a.monitor.scroll = 0
			a.monitor.rebuild_visible()
		}
		activity_action_tree {
			a.monitor.hierarchy = !a.monitor.hierarchy
			a.monitor.scroll = 0
			a.monitor.rebuild_visible()
		}
		activity_action_columns {
			a.columns_open = !a.columns_open
			if a.columns_open { a.columns_scroll = 0 }
		}
		'activity.columns.up' { a.columns_scroll--; a.clamp_columns_scroll() }
		'activity.columns.down' { a.columns_scroll++; a.clamp_columns_scroll() }
		activity_action_pause {
			a.monitor.paused = !a.monitor.paused
			if !a.monitor.paused {
				a.monitor.last_poll_ms = monotonic_millis() - a.monitor.interval_ms
			}
		}
		activity_action_interval {
			a.monitor.interval_ms = match a.monitor.interval_ms {
				500 { i64(1000) }
				1000 { i64(2000) }
				2000 { i64(5000) }
				else { i64(500) }
			}
		}
		activity_action_inspect {
			if a.monitor.selected_pid > 0 {
				a.inspector_open = !a.inspector_open
				a.panel_scroll = 0
			}
		}
		activity_action_scrollbar {}
		else {
			for column in activity_columns_order {
				if column != .name && action == activity_column_toggle(column) {
					a.monitor.columns ^= activity_column_bit(column)
					return true
				}
				if action == activity_action_of(column) && column !in [.name, .pid, .cpu, .memory] {
					a.set_sort(column)
					return true
				}
			}
			return false
		}
	}
	return true
}

fn (mut a ActivityApp) select_relative(delta int) {
	if a.monitor.visible.len == 0 {
		return
	}
	mut selected := -1
	for index, visible in a.monitor.visible {
		if a.monitor.rows[visible.index].pid == a.monitor.selected_pid {
			selected = index
			break
		}
	}
	mut next := if selected < 0 {
		if delta < 0 { a.monitor.visible.len - 1 } else { 0 }
	} else {
		selected + delta
	}
	if next < 0 { next = 0 }
	if next >= a.monitor.visible.len { next = a.monitor.visible.len - 1 }
	a.monitor.selected_pid = a.monitor.rows[a.monitor.visible[next].index].pid
	if a.monitor.filter == .selected { a.monitor.rebuild_visible() }
	a.kill_failed = false
	if next < a.monitor.scroll { a.monitor.scroll = next }
	if next >= a.monitor.scroll + a.monitor.visible_rows {
		a.monitor.scroll = next - a.monitor.visible_rows + 1
	}
	a.monitor.clamp_scroll()
}

fn (mut a ActivityApp) search_key_input(input string) {
	if a.monitor.query.cap == 0 {
		a.monitor.query = []u8{cap: activity_search_limit}
		unsafe { a.monitor.query.flags |= .noslices }
	}
	mut changed := false
	mut index := 0
	for index < input.len {
		byte := input[index]
		if byte == 0x1b {
			if index + 1 < input.len && input[index + 1] in [`[`, `O`] {
				index += 2
				for index < input.len && (input[index] < 0x40 || input[index] > 0x7e) { index++ }
				index++
				continue
			}
			a.monitor.query.clear()
			a.search_focused = false
			changed = true
		} else if byte in [`\r`, `\n`, `\t`] {
			a.search_focused = false
		} else if byte == 8 || byte == 127 {
			for a.monitor.query.len > 0 {
				last := a.monitor.query[a.monitor.query.len - 1]
				a.monitor.query.delete_last()
				changed = true
				if last & 0xc0 != 0x80 { break }
			}
		} else if byte >= 0x20 && a.monitor.query.len < activity_search_limit {
			a.monitor.query << byte
			changed = true
		}
		index++
	}
	if changed {
		a.monitor.scroll = 0
		a.monitor.rebuild_visible()
	}
}

fn (mut a ActivityApp) key_input(input string) {
	if !a.search_focused && input == '\x05' { a.handle_utility(activity_action_export_list); return }
	if !a.search_focused && input == '\x0c' { a.clear_histories(); return }
	if a.columns_key_input(input) { return }
	if a.panel_key_input(input) { return }
	if a.inspector_open {
		if input == '\x1b' { a.inspector_open = false } else { a.inspector.key_input(input) }
		return
	}
	if a.view != .processes {
		if a.view == .startup {
			match input {
				'\x1b[A' { if a.startup.scroll > 0 { a.startup.scroll-- } }
				'\x1b[B' { a.startup.scroll++ }
				'\x1b[5~' { a.startup.scroll -= 10; if a.startup.scroll < 0 { a.startup.scroll = 0 } }
				'\x1b[6~' { a.startup.scroll += 10 }
				else {}
			}
		}
		return
	}
	if a.search_focused {
		a.search_key_input(input)
		return
	}
	if input == '\x06' || input == '/' {
		a.search_focused = true
		return
	}
	if input in ['\r', '\n'] {
		if a.monitor.selected_pid > 0 {
			a.inspector_open = true
			a.view = .processes
			a.inspector.sample(a.monitor.selected_pid)
		}
		return
	}
	if input == '\x1b' {
		a.columns_open = false
		a.inspector_open = false
		return
	}
	match input {
		'\x1b[A' { a.select_relative(-1) }
		'\x1b[B' { a.select_relative(1) }
		'\x1b[5~' { a.select_relative(-a.monitor.visible_rows) }
		'\x1b[6~' { a.select_relative(a.monitor.visible_rows) }
		'\x1b[H', '\x1b[1~' { a.select_relative(-a.monitor.visible.len) }
		'\x1b[F', '\x1b[4~' { a.select_relative(a.monitor.visible.len) }
		else {}
	}
}

fn (a &ActivityApp) pointer_input_enabled() bool { return true }

fn (a &ActivityApp) pointer_moves_matter() bool { return a.scroll_drag || a.inspector.dragging || a.panel_dragging }

fn (mut a ActivityApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int,
	x int, y int, width int, height int) {
	if a.columns_open && phase == .scroll {
		left, menu_width, menu_height, _ := activity_columns_geometry(width, height)
		if x >= left && x < left + menu_width && y >= 64 && y < 64 + menu_height {
			a.columns_scroll -= scroll
			a.clamp_columns_scroll()
			return
		}
	}
	if a.panel_pointer_event(phase, button, scroll, x, y, width) { return }
	if a.inspector_open {
		a.inspector.pointer_event(phase, button, scroll, x, y - activity_toolbar_height + a.panel_scroll,
			if a.panel_content_height > a.panel_height { width - 12 } else { width }, a.panel_content_height - 70)
		return
	}
	if a.view != .processes {
		if a.view == .startup && phase == .scroll && y >= activity_toolbar_height {
			a.startup.scroll -= scroll * 3
			if a.startup.scroll < 0 { a.startup.scroll = 0 }
		}
		return
	}
	if phase == .scroll {
		if y >= a.rows_top && y < a.rows_top + a.rows_height {
			a.monitor.scroll -= scroll * 3
			a.monitor.clamp_scroll()
		}
		return
	}
	if phase == .up {
		a.scroll_drag = false
		return
	}
	if phase == .move && a.scroll_drag {
		_, thumb := activity_scroll_thumb(a.rows_height, a.monitor.visible_rows, a.monitor.visible.len, a.scroll_drag_start)
		travel := a.rows_height - thumb
		maximum := a.monitor.visible.len - a.monitor.visible_rows
		if travel > 0 && maximum > 0 {
			a.monitor.scroll = a.scroll_drag_start + (y - a.scroll_drag_y) * maximum / travel
			a.monitor.clamp_scroll()
		}
		return
	}
	if phase != .down || button != .left { return }
	a.search_focused = false
	if x < width - 12 || y < a.rows_top || y >= a.rows_top + a.rows_height
		|| a.monitor.visible.len <= a.monitor.visible_rows {
		return
	}
	position, thumb := activity_scroll_thumb(a.rows_height, a.monitor.visible_rows, a.monitor.visible.len, a.monitor.scroll)
	offset := y - a.rows_top
	if offset < position || offset >= position + thumb {
		a.monitor.scroll += if offset < position {
			-a.monitor.visible_rows
		} else {
			a.monitor.visible_rows
		}
		a.monitor.clamp_scroll()
	}
	a.scroll_drag = true
	a.scroll_drag_y = y
	a.scroll_drag_start = a.monitor.scroll
}

fn (a &ActivityApp) next_poll_ms() u64 {
	if a.monitor.paused { return 5000 }
	elapsed := monotonic_millis() - a.monitor.last_poll_ms
	return if elapsed >= a.monitor.interval_ms {
		u64(1)
	} else {
		u64(a.monitor.interval_ms - elapsed)
	}
}

fn (mut a ActivityApp) close_app() {
	if a.utility_status.len > 0 { unsafe { a.utility_status.free() } }
	a.inspector.close()
	a.resources.free()
	a.controls.free()
	a.startup.free()
	a.gpu.free()
	a.energy.free()
	a.monitor.free_rows()
	unsafe {
		a.monitor.previous.free()
		a.monitor.error.free()
		a.monitor.buffer.free()
		a.monitor.query.free()
	}
}
