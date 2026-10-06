// SPDX-License-Identifier: GPL-2.0-or-later
// Versioned view settings contain no process identity or sampled counters.
module main

import ui2

const activity_preferences_filename = '.vinix-activity-settings'
const activity_preferences_limit = 1024

struct ActivityViewPreferences {
mut:
	sort ActivitySort = .cpu
	descending bool = true
	filter ActivityFilter
	hierarchy bool
	columns u32 = activity_default_columns
	interval_ms i64 = activity_interval_ms
	view ActivityView
	resource_tab ActivityResourceTab
}

struct ActivityPreferenceStore {
mut:
	initialized bool
	home_fd int = -1
	expected ActivityViewPreferences
	expected_state PreferenceFileState = .missing
	attempted ActivityViewPreferences
	sequence u64
	read_failed bool
	status string
}

fn activity_preferences_valid(p ActivityViewPreferences) bool {
	return int(p.sort) >= 0 && int(p.sort) <= int(ActivitySort.state)
		&& int(p.filter) >= 0 && int(p.filter) < int(ActivityFilter.selected)
		&& int(p.view) >= 0 && int(p.view) <= int(ActivityView.startup)
		&& int(p.resource_tab) >= 0 && int(p.resource_tab) <= int(ActivityResourceTab.network)
		&& p.columns & 1 != 0 && p.columns & ~u32(511) == 0
		&& p.interval_ms in [i64(500), 1000, 2000, 5000]!
}

fn activity_preference_borrow(text string, start int, end int) string {
	return if end > start { unsafe { tos(text.str + start, end - start) } } else { '' }
}

fn activity_preference_number(text string) ?int {
	if text.len == 0 || text.len > 4 { return none }
	mut value := 0
	for byte in text {
		if byte < `0` || byte > `9` { return none }
		value = value * 10 + int(byte - `0`)
	}
	return value
}

fn activity_sort_code(sort ActivitySort) string {
	return match sort {
		.cpu { 'cpu' } .memory { 'memory' } .name { 'name' } .pid { 'pid' }
		.ppid { 'ppid' } .threads { 'threads' } .cpu_time { 'cpu_time' }
		.user { 'user' } .state { 'state' }
	}
}

fn activity_filter_code(filter ActivityFilter) string {
	return match filter {
		.applications { 'applications' } .user { 'user' } .active { 'active' }
		.system { 'system' } .inactive { 'inactive' } .other_users { 'other_users' }
		else { 'all' }
	}
}

fn activity_view_code(view ActivityView) string {
	return match view {
		.processes { 'processes' } .resources { 'resources' } .gpu { 'gpu' }
		.energy { 'energy' } .startup { 'startup' }
	}
}

fn activity_resource_tab_code(tab ActivityResourceTab) string {
	return match tab { .cpu { 'cpu' } .memory { 'memory' } .disk { 'disk' } .network { 'network' } }
}

// A complete schema is required: partial/truncated records must never silently
// apply a mixture of saved values and defaults. All parsing spans are borrowed.
fn activity_parse_view_preferences(record string) ?ActivityViewPreferences {
	if record.len == 0 || record.len > activity_preferences_limit || record.index_u8(0) >= 0 { return none }
	mut p := ActivityViewPreferences{}
	mut seen := u32(0)
	mut start := 0
	for start < record.len {
		mut end := start
		for end < record.len && record[end] != `\n` { end++ }
		mut line_end := end
		if line_end > start && record[line_end - 1] == `\r` { line_end-- }
		line := activity_preference_borrow(record, start, line_end)
		start = end + 1
		if line.len == 0 || line[0] == `#` { continue }
		equals := line.index_u8(`=`)
		if equals <= 0 { return none }
		key := activity_preference_borrow(line, 0, equals)
		value := activity_preference_borrow(line, equals + 1, line.len)
		bit := match key {
			'version' { u32(1) } 'sort' { u32(2) } 'descending' { u32(4) }
			'filter' { u32(8) } 'tree' { u32(16) } 'columns' { u32(32) }
			'interval_ms' { u32(64) } 'view' { u32(128) } 'resource_tab' { u32(256) }
			else { return none }
		}
		if seen & bit != 0 { return none }
		seen |= bit
		match key {
			'version' { if value != '1' { return none } }
			'sort' {
				p.sort = match value {
					'cpu' { ActivitySort.cpu } 'memory' { ActivitySort.memory } 'name' { ActivitySort.name }
					'pid' { ActivitySort.pid } 'ppid' { ActivitySort.ppid } 'threads' { ActivitySort.threads }
					'cpu_time' { ActivitySort.cpu_time } 'user' { ActivitySort.user } 'state' { ActivitySort.state }
					else { return none }
				}
			}
			'descending' { p.descending = match value { '1' { true } '0' { false } else { return none } } }
			'filter' {
				p.filter = match value {
					'all' { ActivityFilter.all } 'applications' { ActivityFilter.applications } 'user' { ActivityFilter.user }
					'active' { ActivityFilter.active } 'system' { ActivityFilter.system } 'inactive' { ActivityFilter.inactive }
					'other_users' { ActivityFilter.other_users } else { return none }
				}
			}
			'tree' { p.hierarchy = match value { '1' { true } '0' { false } else { return none } } }
			'columns' { p.columns = u32(activity_preference_number(value)?) }
			'interval_ms' { p.interval_ms = i64(activity_preference_number(value)?) }
			'view' {
				p.view = match value {
					'processes' { ActivityView.processes } 'resources' { ActivityView.resources }
					'gpu' { ActivityView.gpu } 'energy' { ActivityView.energy } 'startup' { ActivityView.startup }
					else { return none }
				}
			}
			'resource_tab' {
				p.resource_tab = match value {
					'cpu' { ActivityResourceTab.cpu } 'memory' { ActivityResourceTab.memory }
					'disk' { ActivityResourceTab.disk } 'network' { ActivityResourceTab.network } else { return none }
				}
			}
			else { return none }
		}
	}
	if seen != 511 || !activity_preferences_valid(p) { return none }
	return p
}

fn activity_encode_view_preferences(p ActivityViewPreferences) ?string {
	if !activity_preferences_valid(p) { return none }
	columns := p.columns.str()
	interval := p.interval_ms.str()
	sort := activity_sort_code(p.sort)
	filter := activity_filter_code(p.filter)
	view := activity_view_code(p.view)
	tab := activity_resource_tab_code(p.resource_tab)
	descending := if p.descending { '1' } else { '0' }
	tree := if p.hierarchy { '1' } else { '0' }
	data := 'version=1\nsort=${sort}\ndescending=${descending}\nfilter=${filter}\ntree=${tree}\ncolumns=${columns}\ninterval_ms=${interval}\nview=${view}\nresource_tab=${tab}\n'
	unsafe { columns.free() interval.free() }
	return data
}

fn (a &ActivityApp) view_preferences() ActivityViewPreferences {
	return ActivityViewPreferences{
		sort: a.monitor.sort descending: a.monitor.descending
		// A persisted PID selection could identify an unrelated future process.
		filter: if a.monitor.filter == .selected { ActivityFilter.all } else { a.monitor.filter }
		hierarchy: a.monitor.hierarchy columns: a.monitor.columns interval_ms: a.monitor.interval_ms
		view: a.view resource_tab: a.resources.tab
	}
}

fn (mut a ActivityApp) apply_view_preferences(p ActivityViewPreferences) {
	a.monitor.sort = p.sort
	a.monitor.descending = p.descending
	a.monitor.filter = p.filter
	a.monitor.hierarchy = p.hierarchy
	a.monitor.columns = p.columns
	a.monitor.interval_ms = p.interval_ms
	a.view = p.view
	a.resources.tab = p.resource_tab
	a.monitor.sort_rows()
	a.monitor.rebuild_visible()
}

fn (mut a ActivityApp) save_view_preferences() {
	if !a.preferences.initialized || a.preferences.read_failed { return }
	next := a.view_preferences()
	if next == a.preferences.attempted { return }
	// Retry only when a preference changes, never once per draw or sample.
	a.preferences.attempted = next
	a.preferences.status = a.preferences.publish(next)
}

fn (a &ActivityApp) view_preferences_warning() string {
	return if a.preferences.status.len > 0 { tr(a.preferences.status) } else { '' }
}

fn (a &ActivityApp) build_preferences_warning(mut children []ui2.Element, width int, height int) {
	warning := a.view_preferences_warning()
	if warning.len == 0 { return }
	children << ui2.view('activity.preferences.warning', ui2.rect(0, f64(height - activity_footer_height), f64(width), f64(activity_footer_height)), ui2.BoxStyle{ bg: body_panel }, [])
	children << ui2.Element{
		...ui2.label('', warning, ui2.rect(10, f64(height - 21), f64(width - 20), 16), ui2.TextStyle{ size: 11, color: files_error })
		tooltip: warning
	}
}
