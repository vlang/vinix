// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Disk Usage, a disk inventory, built into the desktop.
//
// The application is the standalone V/ui2 program of the same name: the same
// four metrics, the same two ranked panels with a proportion bar under every
// row, and the same accounting rules — symbolic links are not followed, a file
// with several hard links is counted once, and a directory it cannot open is
// recorded as skipped rather than ending the scan.
//
// What is different here is that the desktop is the window system. The
// standalone program hands the walk to a worker thread, publishes snapshots
// through a mutex and asks its platform window to refresh; a Vinix application
// has neither a window nor an event loop of its own. So the walk is a
// resumable state machine which the compositor advances with the poll it
// already sends, one time-bounded slice per poll. The compositor is blocked
// while a slice runs, which is what the budget is for: a scan of the whole
// disk costs a fraction of each frame instead of a frozen desktop, and the
// rankings fill in while it runs exactly as they do natively.
module main

import ui2

// How many entries each panel ranks. The window shows seven or eight rows;
// the rest is what the ranking falls back on when a scan is restarted deeper
// in the tree, and what makes the floor below worth having.
const disk_usage_rank_limit = 24

// A tree deeper than this is a loop the identity check missed, or something no
// inventory needs to open. Each level also holds an open directory handle.
const disk_usage_max_depth = 64

// One slice of the walk. The compositor is waiting on the poll that runs it,
// so this is the longest a scan may delay a frame.
const disk_usage_slice_ms = u64(20)

// A hard ceiling on one slice, for a filesystem fast enough that the clock
// never advances far enough to stop it.
const disk_usage_slice_entries = 20000

// Longer than any name the kernel's Dirent can hold.
const disk_usage_name_max = 256

const disk_usage_identity_slots = 2048

// ── Identity set ──────────────────────────────────────────────────
// A scan must not descend into the same directory twice and must count a file
// with several names once. Both are the question "have I seen this device and
// inode already", asked once per entry. An open-addressed set of packed keys
// answers it without allocating the string per file that a keyed map would,
// and the desktop has no garbage collector to clean up after one.

struct DiskUsageIdentitySet {
mut:
	slots []u64
	used  int
}

fn disk_usage_identity_key(device u64, inode u64) u64 {
	key := (device << 48) ^ inode
	// Zero marks a free slot, so the one identity that would collide with it
	// is folded onto a neighbour. Two entries sharing a key is only ever a
	// miscount of one file, never a wrong answer about the tree's shape.
	return if key == 0 { u64(1) } else { key }
}

fn (mut s DiskUsageIdentitySet) reset() {
	if s.slots.len == 0 {
		s.slots = []u64{len: disk_usage_identity_slots}
		unsafe { s.slots.flags |= .noslices }
	} else {
		for index in 0 .. s.slots.len {
			s.slots[index] = 0
		}
	}
	s.used = 0
}

// add reports whether the key had not been seen before.
fn (mut s DiskUsageIdentitySet) add(key u64) bool {
	if s.slots.len == 0 {
		s.reset()
	}
	// Keep the table under half full: linear probing degrades quickly past
	// that, and this is on the path of every single file.
	if (s.used + 1) * 2 > s.slots.len {
		s.grow()
	}
	mask := u64(s.slots.len - 1)
	mut index := key & mask
	for s.slots[index] != 0 {
		if s.slots[index] == key {
			return false
		}
		index = (index + 1) & mask
	}
	s.slots[index] = key
	s.used++
	return true
}

fn (mut s DiskUsageIdentitySet) grow() {
	old := s.slots
	mut slots := []u64{len: old.len * 2}
	unsafe { slots.flags |= .noslices }
	mask := u64(slots.len - 1)
	for key in old {
		if key == 0 {
			continue
		}
		mut index := key & mask
		for slots[index] != 0 {
			index = (index + 1) & mask
		}
		slots[index] = key
	}
	s.slots = slots
	unsafe { old.free() }
}

fn (mut s DiskUsageIdentitySet) release() {
	if s.slots.cap > 0 {
		unsafe { s.slots.free() }
	}
	s.slots = []u64{}
	s.used = 0
}

// ── Rankings ──────────────────────────────────────────────────────

struct DiskUsageEntry {
mut:
	name  string
	path  string
	bytes u64
}

// DiskUsageRanking is the largest few of something, kept in order. Below the
// floor nothing can enter, which is what stops a hundred thousand files from
// each costing an insertion.
struct DiskUsageRanking {
mut:
	entries []DiskUsageEntry
	floor   u64
}

// consider always takes ownership of the two strings: it either keeps them in
// the ranking or releases them. A caller that had to know which would have to
// repeat the floor test it is here to avoid.
fn (mut r DiskUsageRanking) consider(name string, path string, bytes u64) {
	if r.entries.len >= disk_usage_rank_limit && bytes <= r.floor {
		unsafe {
			name.free()
			path.free()
		}
		return
	}
	entry := DiskUsageEntry{
		name:  name
		path:  path
		bytes: bytes
	}
	r.entries << entry
	// The array is short and nearly always already in order, so one pass down
	// from the end costs less than sorting the ranking per file.
	mut index := r.entries.len - 1
	for index > 0 && r.entries[index - 1].bytes < bytes {
		r.entries[index] = r.entries[index - 1]
		index--
	}
	r.entries[index] = entry
	if r.entries.len > disk_usage_rank_limit {
		dropped := r.entries.last()
		unsafe {
			dropped.name.free()
			dropped.path.free()
		}
		r.entries.delete_last()
	}
	r.floor = if r.entries.len >= disk_usage_rank_limit {
		r.entries.last().bytes
	} else {
		u64(0)
	}
}

fn (mut r DiskUsageRanking) release() {
	for index in 0 .. r.entries.len {
		unsafe {
			r.entries[index].name.free()
			r.entries[index].path.free()
		}
	}
	if r.entries.cap > 0 {
		unsafe { r.entries.free() }
	}
	r.entries = []DiskUsageEntry{}
	r.floor = 0
}

fn (r &DiskUsageRanking) largest() u64 {
	if r.entries.len == 0 {
		return 0
	}
	return r.entries[0].bytes
}

// ── The walk ──────────────────────────────────────────────────────

enum DiskUsagePhase {
	scanning
	complete
	cancelled
	failed
}

// One open directory, and what its subtree has added up to so far. The stack
// of these is the recursion the standalone program does with the C stack; made
// explicit, it can be left in the middle and resumed on the next poll.
struct DiskUsageFrame {
mut:
	path  string
	name  string
	dir   voidptr
	bytes u64
}

struct DiskUsageScanner {
mut:
	root        string         = '/'
	phase       DiskUsagePhase = .complete
	stack       []DiskUsageFrame
	files_rank  DiskUsageRanking
	dirs_rank   DiskUsageRanking
	seen_dirs   DiskUsageIdentitySet
	seen_links  DiskUsageIdentitySet
	total_bytes u64
	capacity    DiskUsageCapacity
	files       u64
	directories u64
	unreadable  u64
	started_ms  u64
	elapsed_ms  u64
	error       string
	// The language the error is worded in.
	error_language DesktopLanguage
	name_buffer    [disk_usage_name_max]u8
}

// begin restarts the walk at `path`. The new root is copied before anything is
// released, so a rescan of the current root and a descent into a ranked folder
// can both hand in a string the reset is about to free.
fn (mut s DiskUsageScanner) begin(path string) {
	next := path.clone()
	s.reset()
	unsafe { s.root.free() }
	s.root = next
	s.capacity = disk_usage_read_capacity(s.root)
	s.seen_dirs.reset()
	s.seen_links.reset()
	s.started_ms = desktop_monotonic_ms()
	dir := desktop_opendir(s.root)
	if dir == unsafe { nil } {
		s.phase = .failed
		s.word_error()
		return
	}
	if info := desktop_lstat(s.root) {
		s.seen_dirs.add(disk_usage_identity_key(info.device, info.inode))
	}
	s.stack << DiskUsageFrame{
		path: s.root.clone()
		name: s.root.clone()
		dir:  dir
	}
	s.directories = 1
	s.phase = .scanning
}

// step advances the walk by one bounded slice and reports whether the window
// has anything new to show.
fn (mut s DiskUsageScanner) step() bool {
	if s.phase != .scanning {
		return false
	}
	started := desktop_monotonic_ms()
	mut worked := 0
	for s.stack.len > 0 && worked < disk_usage_slice_entries {
		s.advance()
		worked++
		// The clock is only read every 64 entries: on a fast filesystem the
		// call itself would otherwise be a measurable share of the walk.
		if worked & 63 == 0 && disk_usage_elapsed(started, desktop_monotonic_ms()) >= disk_usage_slice_ms {
			break
		}
	}
	s.elapsed_ms = disk_usage_elapsed(s.started_ms, desktop_monotonic_ms())
	if s.stack.len == 0 {
		s.phase = .complete
	}
	return true
}

// advance consumes exactly one directory entry, or leaves a directory that has
// none left. Everything the walk does is one of those two things, which is
// what makes it interruptible between any two of them.
fn (mut s DiskUsageScanner) advance() {
	depth := s.stack.len - 1
	mut names := unsafe { (&s.name_buffer[0]).vbytes(disk_usage_name_max) }
	if !desktop_readdir(s.stack[depth].dir, mut names) {
		s.leave()
		return
	}
	name := unsafe { cstring_to_vstring(&char(&s.name_buffer[0])) }
	// `.` says nothing and `..` is where we came from.
	if name == '.' || name == '..' {
		unsafe { name.free() }
		return
	}
	full := join_path(s.stack[depth].path, name)
	info := desktop_lstat(full) or {
		s.unreadable++
		unsafe {
			name.free()
			full.free()
		}
		return
	}
	if info.is_dir {
		s.enter(name, full, info)
		return
	}
	// Anything that is not a directory and not a regular file — a symbolic
	// link, a device node, a socket — occupies no bytes anyone can free, and
	// following a link would count its target a second time.
	if info.is_file
		&& (info.links < 2 || s.seen_links.add(disk_usage_identity_key(info.device, info.inode))) {
		s.files++
		s.total_bytes += info.size
		s.stack[depth].bytes += info.size
		s.files_rank.consider(name, full, info.size)
		return
	}
	unsafe {
		name.free()
		full.free()
	}
}

fn (mut s DiskUsageScanner) enter(name string, path string, info DesktopNodeInfo) {
	if !s.seen_dirs.add(disk_usage_identity_key(info.device, info.inode))
		|| s.stack.len >= disk_usage_max_depth {
		unsafe {
			name.free()
			path.free()
		}
		return
	}
	dir := desktop_opendir(path)
	if dir == unsafe { nil } {
		s.unreadable++
		unsafe {
			name.free()
			path.free()
		}
		return
	}
	s.directories++
	s.stack << DiskUsageFrame{
		path: path
		name: name
		dir:  dir
	}
}

// leave closes a finished directory and gives its subtree total to the parent
// that will be ranked against its own siblings.
fn (mut s DiskUsageScanner) leave() {
	frame := s.stack.last()
	desktop_closedir(frame.dir)
	s.stack.delete_last()
	if s.stack.len == 0 {
		// The root is the whole scan; it is not ranked against its children.
		unsafe {
			frame.path.free()
			frame.name.free()
		}
		return
	}
	s.stack[s.stack.len - 1].bytes += frame.bytes
	s.dirs_rank.consider(frame.name, frame.path, frame.bytes)
}

fn (mut s DiskUsageScanner) cancel() {
	if s.phase != .scanning {
		return
	}
	s.elapsed_ms = disk_usage_elapsed(s.started_ms, desktop_monotonic_ms())
	s.close_stack()
	s.phase = .cancelled
}

fn (mut s DiskUsageScanner) close_stack() {
	for index in 0 .. s.stack.len {
		desktop_closedir(s.stack[index].dir)
		unsafe {
			s.stack[index].path.free()
			s.stack[index].name.free()
		}
	}
	s.stack.clear()
}

fn (mut s DiskUsageScanner) reset() {
	s.close_stack()
	s.files_rank.release()
	s.dirs_rank.release()
	s.total_bytes = 0
	s.capacity = DiskUsageCapacity{}
	s.files = 0
	s.directories = 0
	s.unreadable = 0
	s.elapsed_ms = 0
	s.started_ms = 0
	s.set_error('')
}

fn (mut s DiskUsageScanner) release() {
	s.reset()
	s.seen_dirs.release()
	s.seen_links.release()
	unsafe { s.root.free() }
	s.root = ''
}

// set_error replaces the reason a scan produced nothing, releasing the one
// before it. Assigning over a string built by interpolation would strand it.
fn (mut s DiskUsageScanner) set_error(message string) {
	if s.error == message {
		unsafe { message.free() }
		return
	}
	unsafe { s.error.free() }
	s.error = message
}

// word_error says, in the desktop's language, why the root could not be
// scanned. The window asks again when the language has changed since.
fn (mut s DiskUsageScanner) word_error() {
	s.error_language = desktop_language
	s.set_error(tr_fill('disk_usage.error.cannot_open', s.root))
}

// current_path is what the walk is inside of right now. The string belongs to
// the frame that owns the open directory, and the element tree is encoded and
// thrown away before that frame can be popped.
fn (s &DiskUsageScanner) current_path() string {
	if s.stack.len == 0 {
		return s.root
	}
	return s.stack[s.stack.len - 1].path
}

fn disk_usage_elapsed(from u64, to u64) u64 {
	if from == ~u64(0) || to == ~u64(0) || to < from {
		return 0
	}
	return to - from
}

// ── Formatting ────────────────────────────────────────────────────

// KB, MB, GB, TB and PB.
const disk_usage_size_unit_count = 5

// disk_usage_size_unit is a unit's symbol in the desktop's language.
fn disk_usage_size_unit(unit int) string {
	return match unit {
		0 { tr('disk_usage.unit.kb') }
		1 { tr('disk_usage.unit.mb') }
		2 { tr('disk_usage.unit.gb') }
		3 { tr('disk_usage.unit.tb') }
		else { tr('disk_usage.unit.pb') }
	}
}

// disk_usage_size_text is the standalone program's byte formatter: a compact
// binary unit carrying three significant figures. The arithmetic is integer
// because V's floating-point formatter keeps scratch storage alive under
// -manualfree, and this runs for every row of both panels every frame. The
// decimal point and the units are the language's own.
fn disk_usage_size_text(bytes u64) string {
	if bytes < 1024 {
		count := bytes.str()
		text := tr_fill('disk_usage.size.bytes', count)
		unsafe { count.free() }
		return text
	}
	mut value := bytes
	mut unit := 0
	for value >= 1024 * 1024 && unit + 1 < disk_usage_size_unit_count {
		value /= 1024
		unit++
	}
	// value is now at least one and less than 1024 of the chosen unit, held as
	// the count of the unit below it so the decimals survive the division.
	hundredths := (value * 100 + 512) / 1024
	if hundredths >= 10000 {
		whole := ((hundredths + 50) / 100).str()
		text := tr_fill2('disk_usage.size.whole', whole, disk_usage_size_unit(unit))
		unsafe { whole.free() }
		return text
	}
	if hundredths >= 1000 {
		tenths := (hundredths + 5) / 10
		whole := (tenths / 10).str()
		fraction := (tenths % 10).str()
		text := tr_fill3('disk_usage.size.decimal', whole, fraction, disk_usage_size_unit(unit))
		unsafe {
			whole.free()
			fraction.free()
		}
		return text
	}
	whole := (hundredths / 100).str()
	fraction := pad2(int(hundredths % 100))
	text := tr_fill3('disk_usage.size.decimal', whole, fraction, disk_usage_size_unit(unit))
	unsafe {
		whole.free()
		fraction.free()
	}
	return text
}

// disk_usage_group_separator is what a language writes between groups of three
// digits: French and Russian use spaces, Spanish uses dots, English, Japanese
// and Chinese use commas.
fn disk_usage_group_separator() u8 {
	return match desktop_language {
		.en, .ja, .zh { `,` }
		.ru, .fr { ` ` }
		.es { `.` }
	}
}

// disk_usage_count_text groups an integer into thousands. Six hundred thousand
// files is unreadable as a run of digits and obvious with two commas in it.
fn disk_usage_count_text(value u64) string {
	digits := value.str()
	separator := disk_usage_group_separator()
	mut out := []u8{cap: digits.len + digits.len / 3}
	for index in 0 .. digits.len {
		if index > 0 && (digits.len - index) % 3 == 0 {
			out << separator
		}
		out << digits[index]
	}
	text := out.bytestr()
	unsafe {
		digits.free()
		out.free()
	}
	return text
}

fn disk_usage_duration_text(milliseconds u64) string {
	if milliseconds < 1000 {
		count := milliseconds.str()
		text := tr_fill('disk_usage.duration.milliseconds', count)
		unsafe { count.free() }
		return text
	}
	seconds := milliseconds / 1000
	if seconds < 60 {
		whole := seconds.str()
		tenth := (milliseconds % 1000 / 100).str()
		text := tr_fill2('disk_usage.duration.seconds', whole, tenth)
		unsafe {
			whole.free()
			tenth.free()
		}
		return text
	}
	minutes := (seconds / 60).str()
	remaining := (seconds % 60).str()
	text := tr_fill2('disk_usage.duration.minutes', minutes, remaining)
	unsafe {
		minutes.free()
		remaining.free()
	}
	return text
}

// ── The native application ────────────────────────────────────────

const disk_usage_action_root = 'disk_usage.root'
const disk_usage_action_scan_path = 'disk_usage.scan_path'
const disk_usage_action_report_path = 'disk_usage.report_path'
const disk_usage_action_export = 'disk_usage.export'
const disk_usage_report_filename = 'disk-usage.csv'
const disk_usage_path_limit = 512

enum DiskUsageFocus {
	none_
	root
	report
}

const disk_usage_action_rescan = 'disk_usage.rescan'
const disk_usage_action_stop = 'disk_usage.stop'
const disk_usage_action_up = 'disk_usage.up'
const disk_usage_action_dirs_back = 'disk_usage.dirs.back'
const disk_usage_action_dirs_next = 'disk_usage.dirs.next'
const disk_usage_action_files_back = 'disk_usage.files.back'
const disk_usage_action_files_next = 'disk_usage.files.next'
const disk_usage_action_inventory = 'disk_usage.view.inventory'
const disk_usage_action_capacity = 'disk_usage.view.capacity'

// The scopes the standalone program's Whole disk and Home buttons stand for,
// plus the one directory on a Vinix image that is worth a button of its own.
const disk_usage_scope_count = 3
const disk_usage_scope_paths = ['/', '/root', '/usr']
const disk_usage_scope_actions = ['disk_usage.scope.0', 'disk_usage.scope.1', 'disk_usage.scope.2']

fn disk_usage_scope_title(index int) string {
	return match index {
		0 { tr('disk_usage.scope.whole_disk') }
		1 { tr('disk_usage.scope.home') }
		else { tr('disk_usage.scope.system') }
	}
}

// Row actions are literals because the tree is rebuilt on every frame and this
// target has no garbage collector. They name a row of the window, not an entry
// of the ranking: the page offset is what turns one into the other.
const disk_usage_dir_actions = ['disk_usage.dir.0', 'disk_usage.dir.1', 'disk_usage.dir.2',
	'disk_usage.dir.3', 'disk_usage.dir.4', 'disk_usage.dir.5', 'disk_usage.dir.6', 'disk_usage.dir.7',
	'disk_usage.dir.8', 'disk_usage.dir.9', 'disk_usage.dir.10', 'disk_usage.dir.11']

const disk_usage_pad = 12
const disk_usage_row_height = 48
const disk_usage_metric_height = 62
const disk_usage_panel_header = 34

struct DiskUsageApp {
mut:
	scanner         DiskUsageScanner
	dir_page        int
	file_page       int
	dir_rows        int = 1
	file_rows       int = 1
	root_input      []u8
	report_path     []u8
	focus           DiskUsageFocus
	path_select_all bool
	report_status   string
	capacity_view   bool
}

fn open_disk_usage(mut _ Desktop) !NativeApp {
	mut app := &DiskUsageApp{}
	// A disk inventory that opened on an empty window and waited to be told
	// what to look at would be asking a question with one sensible answer.
	app.scan('/')
	unsafe { app.report_path.flags |= .noslices }
	path := disk_usage_default_report_path()
	disk_usage_append(mut app.report_path, path)
	unsafe { path.free() }
	return app
}

fn (mut a DiskUsageApp) poll() bool {
	changed := a.scanner.step()
	// A walk has no known end, so its button shows indeterminate progress,
	// and an error bar if the walk failed.
	publish_taskbar_status(TaskStatus{
		progress_state: match a.scanner.phase {
			.scanning { TaskProgress.indeterminate }
			.failed { TaskProgress.error }
			else { TaskProgress.none_ }
		}
		progress:       if a.scanner.phase == .failed { 100 } else { 0 }
	})
	return changed
}

fn (mut a DiskUsageApp) close_app() {
	a.scanner.release()
	unsafe {
		a.root_input.free()
		a.report_path.free()
	}
	a.root_input = []u8{}
	a.report_path = []u8{}
}

fn (mut a DiskUsageApp) scan(path string) {
	a.scanner.begin(path)
	a.dir_page = 0
	a.file_page = 0
	unsafe { a.root_input.flags |= .noslices }
	a.root_input.clear()
	disk_usage_append(mut a.root_input, a.scanner.root)
	a.report_status = ''
	a.path_select_all = false
}

fn (mut a DiskUsageApp) handle(event_id string) ! {
	match event_id {
		disk_usage_action_inventory {
			a.capacity_view = false
			a.focus = .none_
			return
		}
		disk_usage_action_capacity {
			a.capacity_view = true
			a.focus = .none_
			return
		}
		disk_usage_action_root {
			a.focus = .root
			a.path_select_all = true
			return
		}
		disk_usage_action_report_path {
			a.focus = .report
			a.path_select_all = true
			return
		}
		disk_usage_action_scan_path {
			a.scan_typed_path()
			return
		}
		disk_usage_action_export {
			a.export_report()
			return
		}
		disk_usage_action_rescan {
			a.scan(a.scanner.root)
			return
		}
		disk_usage_action_stop {
			a.scanner.cancel()
			return
		}
		disk_usage_action_up {
			if a.scanner.root != '/' {
				a.scan(parent_path(a.scanner.root))
			}
			return
		}
		disk_usage_action_dirs_back {
			a.dir_page = disk_usage_page_back(a.dir_page, a.dir_rows)
			return
		}
		disk_usage_action_dirs_next {
			a.dir_page = disk_usage_page_next(a.dir_page, a.dir_rows, a.scanner.dirs_rank.entries.len)
			return
		}
		disk_usage_action_files_back {
			a.file_page = disk_usage_page_back(a.file_page, a.file_rows)
			return
		}
		disk_usage_action_files_next {
			a.file_page = disk_usage_page_next(a.file_page, a.file_rows, a.scanner.files_rank.entries.len)
			return
		}
		else {}
	}
	for index, action in disk_usage_scope_actions {
		if event_id == action {
			a.scan(disk_usage_scope_paths[index])
			return
		}
	}
	// Descending into a ranked folder rescans it, which is the only way to
	// learn what is inside a folder the ranking only gives a total for.
	for row, action in disk_usage_dir_actions {
		if event_id != action {
			continue
		}
		entry_index := a.dir_page + row
		if entry_index < a.scanner.dirs_rank.entries.len {
			a.scan(a.scanner.dirs_rank.entries[entry_index].path)
		}
		return
	}
}

fn disk_usage_page_back(page int, rows int) int {
	next := page - rows
	return if next < 0 { 0 } else { next }
}

fn disk_usage_page_next(page int, rows int, total int) int {
	next := page + rows
	return if next >= total { page } else { next }
}

fn (a &DiskUsageApp) phase_color() u32 {
	return match a.scanner.phase {
		.scanning { disk_usage_phase_scanning }
		.complete { disk_usage_phase_complete }
		.cancelled { disk_usage_phase_stopped }
		.failed { files_error }
	}
}

fn (a &DiskUsageApp) phase_title() string {
	return match a.scanner.phase {
		.scanning { tr('disk_usage.phase.scanning') }
		.complete { tr('disk_usage.phase.complete') }
		.cancelled { tr('disk_usage.phase.stopped') }
		.failed { tr('disk_usage.phase.unreadable') }
	}
}

// status_text is the sentence along the bottom of the window. It is built for
// this frame and released with the tree, like every other formatted string
// here; only the paths inside it belong to the scanner.
fn (a &DiskUsageApp) status_text() string {
	if a.report_status.len > 0 {
		return tr_fill(a.report_status, disk_usage_buffer_text(a.report_path))
	}
	match a.scanner.phase {
		.scanning {
			return tr_fill('disk_usage.status.walking', a.scanner.current_path())
		}
		.failed {
			return a.scanner.error.clone()
		}
		.cancelled {
			// The label owns and frees its text; the table's is not its to free.
			return tr('disk_usage.status.stopped').clone()
		}
		.complete {
			duration := disk_usage_duration_text(a.scanner.elapsed_ms)
			if a.scanner.unreadable == 0 {
				text := tr_fill2('disk_usage.status.scanned', a.scanner.root, duration)
				unsafe { duration.free() }
				return text
			}
			// The count is grouped into thousands, so the form is chosen for
			// it and then filled rather than left to tr_count.
			skipped := disk_usage_count_text(a.scanner.unreadable)
			text := tr_substitute(tr_plural_form('disk_usage.status.scanned_skipped', i64(a.scanner.unreadable)),
				skipped, a.scanner.root, duration)
			unsafe {
				duration.free()
				skipped.free()
			}
			return text
		}
	}
}

fn disk_usage_owned_label(text string, frame ui2.Rect, style ui2.TextStyle) ui2.Element {
	return ui2.label(frame_owned_text_id, text, frame, style)
}

fn disk_usage_button(action string, title string, x int, y int, width int, enabled bool) ui2.Element {
	return ui2.button(action, title, ui2.rect(f64(x), f64(y), f64(width), 24), ui2.BoxStyle{
		bg:     if enabled { files_up } else { files_up_disabled }
		radius: 6
	}, ui2.TextStyle{
		color: if enabled { app_on_accent } else { body_muted }
		size:  13
		align: .center
	})
}

fn disk_usage_metric(title string, value string, x int, y int, width int, accent u32) ui2.Element {
	mut children := frame_elements(3)
	children << ui2.view('', ui2.rect(0, 0, 4, f64(disk_usage_metric_height)), ui2.BoxStyle{
		bg:     accent
		radius: 2
	}, [])
	children << ui2.label('', title, ui2.rect(16, 11, f64(width - 26), 14), ui2.TextStyle{
		color: body_muted
		size:  11
		bold:  true
	})
	children << disk_usage_owned_label(value, ui2.rect(16, 29, f64(width - 26), 24), ui2.TextStyle{
		color: body_heading
		size:  17
		bold:  true
	})
	return ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(disk_usage_metric_height)), ui2.BoxStyle{
		bg:            0xffffff
		radius:        10
		border_color:  body_rule
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, children)
}

// disk_usage_row is one ranked entry: where it is, how much it holds, and a bar
// proportional to the largest entry in the same panel. The bar is what turns
// a column of numbers into a picture of the disk.
fn disk_usage_row(action string, rank int, entry &DiskUsageEntry, y int, width int, largest u64, accent u32, clickable bool) ui2.Element {
	number := rank.str()
	size_text := disk_usage_size_text(entry.bytes)
	track := width - 50
	mut bar := 0
	if largest > 0 && entry.bytes > 0 && track > 0 {
		bar = int(u64(track) * entry.bytes / largest)
		if bar < 2 {
			bar = 2
		}
	}
	mut children := frame_elements(5)
	children << disk_usage_owned_label(number, ui2.rect(10, 5, 22, 16), ui2.TextStyle{
		color: body_muted
		size:  11
		bold:  true
		align: .right
	})
	children << ui2.label('', entry.name, ui2.rect(40, 3, f64(width - 132), 18), ui2.TextStyle{
		color: body_heading
		size:  13
		bold:  true
	})
	children << disk_usage_owned_label(size_text, ui2.rect(f64(width - 90), 3, 80, 18), ui2.TextStyle{
		color: body_heading
		size:  13
		bold:  true
		align: .right
	})
	children << ui2.label('', entry.path, ui2.rect(40, 22, f64(width - 50), 14), ui2.TextStyle{
		color: body_muted
		size:  11
	})
	// Clear of the path by enough that the bar reads as a bar and not as an
	// underline of the text above it.
	children << ui2.view('', ui2.rect(40, 41, f64(bar), 3), ui2.BoxStyle{
		bg:     accent
		radius: 1
	}, [])
	frame := ui2.rect(0, f64(y), f64(width), f64(disk_usage_row_height - 2))
	box := ui2.BoxStyle{
		bg:     if rank % 2 == 1 { u32(0xffffff) } else { activity_row_alt }
		radius: 6
	}
	if !clickable {
		return ui2.view('', frame, box, children)
	}
	return ui2.clickable_view(action, frame, box, children)
}

fn (a &DiskUsageApp) panel(title string, ranking &DiskUsageRanking, page int, rows int, actions []string, back string, next string, x int, y int, width int, height int, accent u32, clickable bool) ui2.Element {
	// The two page buttons live in the header rather than under the rows: the
	// list is sized to fill the panel, so anything below it would sit on the
	// last row.
	paging := ranking.entries.len > rows
	summary_right := if paging { 60 } else { 14 }
	mut children := frame_elements(rows + 6)
	children << ui2.label('', title, ui2.rect(14, 9, f64(width - 200), 18), ui2.TextStyle{
		color: body_heading
		size:  13
		bold:  true
	})
	summary_frame := ui2.rect(f64(width - 186), 12, f64(186 - summary_right), 14)
	summary_style := ui2.TextStyle{
		color: body_muted
		size:  11
		align: .right
	}
	if ranking.entries.len == 0 {
		children << ui2.label('', tr('disk_usage.panel.nothing_yet'), summary_frame, summary_style)
	} else {
		// A ranking holds at most disk_usage_rank_limit entries, too few to group.
		children << disk_usage_owned_label(tr_count('disk_usage.panel.ranked', ranking.entries.len),
			summary_frame, summary_style)
	}
	children << ui2.view('', ui2.rect(0, f64(disk_usage_panel_header - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if paging {
		children << ui2.button(back, '-', ui2.rect(f64(width - 54), 8, 22, 18), ui2.BoxStyle{
			bg:     files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size:  11
			align: .center
		})
		children << ui2.button(next, '+', ui2.rect(f64(width - 28), 8, 22, 18), ui2.BoxStyle{
			bg:     files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size:  11
			align: .center
		})
	}

	if ranking.entries.len == 0 {
		children << ui2.label('', tr('disk_usage.panel.empty'), ui2.rect(14,
			f64(disk_usage_panel_header + 10), f64(width - 28), 18), ui2.TextStyle{
			color: body_muted
			size:  11
		})
	}
	largest := ranking.largest()
	mut row := 0
	for index := page; index < ranking.entries.len && row < rows; index++ {
		// Only the folder panel's rows can be descended into, and only then do
		// they need an action to be recognised by.
		action := if clickable && row < actions.len { actions[row] } else { '' }
		children << disk_usage_row(action, index + 1, &ranking.entries[index], disk_usage_panel_header +
			row * disk_usage_row_height, width, largest, accent, action.len > 0)
		row++
	}

	return ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg:            0xffffff
		radius:        12
		border_color:  body_rule
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, children)
}

fn (mut a DiskUsageApp) build(size ui2.Rect) !ui2.Element {
	if a.capacity_view { return a.build_capacity(size) }
	if a.scanner.phase == .failed && a.scanner.error_language != desktop_language {
		a.scanner.word_error()
	}
	width := int(size.width)
	height := int(size.height)
	inner := width - disk_usage_pad * 2
	scanning := a.scanner.phase == .scanning

	panel_y := 234
	panel_height := height - panel_y - 34
	rows := if panel_height > disk_usage_panel_header + disk_usage_row_height {
		(panel_height - disk_usage_panel_header - 8) / disk_usage_row_height
	} else {
		1
	}
	a.dir_rows = rows
	a.file_rows = rows
	a.dir_page = disk_usage_clamp_page(a.dir_page, rows, a.scanner.dirs_rank.entries.len)
	a.file_page = disk_usage_clamp_page(a.file_page, rows, a.scanner.files_rank.entries.len)

	mut children := frame_elements(16)

	children << ui2.label('', 'Disk Usage', ui2.rect(f64(disk_usage_pad), 5, 116, 24), ui2.TextStyle{
		color: body_heading
		size:  18
		bold:  true
	})
	children << ui2.label('', tr('disk_usage.subtitle'), ui2.rect(f64(disk_usage_pad + 110), 12, 160, 16),
		ui2.TextStyle{
			color: body_muted
			size:  11
		})

	mut badge := frame_elements(1)
	badge << ui2.label('', a.phase_title(), ui2.rect(6, 4, 92, 14), ui2.TextStyle{
		color: a.phase_color()
		size:  11
		bold:  true
		align: .center
	})
	children << ui2.view('', ui2.rect(f64(width - disk_usage_pad - 104), 7, 104, 22), ui2.BoxStyle{
		bg:            0xffffff
		radius:        11
		border_color:  a.phase_color()
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, badge)

	// Scope: the presets, the way back out of a folder that was descended
	// into, and the two controls that start and stop a walk.
	mut scope_x := disk_usage_pad
	for index in 0 .. disk_usage_scope_count {
		button_width := if index == 0 { 92 } else { 72 }
		children << disk_usage_button(disk_usage_scope_actions[index], disk_usage_scope_title(index), scope_x,
			40, button_width, true)
		scope_x += button_width + 6
	}
	children << disk_usage_button(disk_usage_action_up, tr('disk_usage.button.up'), scope_x, 40, 48,
		a.scanner.root != '/')
	children << disk_usage_button(disk_usage_action_stop, tr('disk_usage.button.stop'), width - disk_usage_pad - 68,
		40, 68, scanning)
	children << disk_usage_button(disk_usage_action_rescan, tr('disk_usage.button.rescan'), width - disk_usage_pad -
		144, 40, 72, !scanning)

	children << ui2.label('', tr('disk_usage.path.root'), ui2.rect(f64(disk_usage_pad), 76, 58, 18),
		ui2.TextStyle{ color: body_muted, size: 11 })
	children << disk_usage_path_field(disk_usage_action_root, disk_usage_buffer_text(a.root_input),
		disk_usage_pad + 62, 72, inner - 148, a.focus == .root)
	children << disk_usage_button(disk_usage_action_scan_path, tr('disk_usage.button.scan'),
		width - disk_usage_pad - 78, 72, 78, true)
	children << ui2.label('', tr('disk_usage.path.report'), ui2.rect(f64(disk_usage_pad), 108, 58, 18),
		ui2.TextStyle{ color: body_muted, size: 11 })
	children << disk_usage_path_field(disk_usage_action_report_path, disk_usage_buffer_text(a.report_path),
		disk_usage_pad + 62, 104, inner - 148, a.focus == .report)
	children << disk_usage_button(disk_usage_action_export, tr('disk_usage.button.export'),
		width - disk_usage_pad - 78, 104, 78, !scanning && a.scanner.phase != .failed)
	a.view_buttons(mut children, 130)

	// The hairline under the controls is the whole progress display: a walk
	// cannot know how much is left, so it says only that it is moving.
	mut bar := frame_elements(1)
	if scanning {
		travel := inner + 160
		offset := int(a.scanner.elapsed_ms / 4 % u64(travel)) - 160
		bar << ui2.view('', ui2.rect(f64(offset), 0, 160, 3), ui2.BoxStyle{
			bg:     app_accent
			radius: 1
		}, [])
	} else if a.scanner.phase == .complete {
		bar << ui2.view('', ui2.rect(0, 0, f64(inner), 3), ui2.BoxStyle{
			bg:     disk_usage_phase_complete
			radius: 1
		}, [])
	}
	children << ui2.view('', ui2.rect(f64(disk_usage_pad), 150, f64(inner), 3), ui2.BoxStyle{
		bg:     body_rule
		radius: 1
	}, bar)

	gap := 10
	metric_width := (inner - gap * 3) / 4
	children << disk_usage_metric(tr('disk_usage.metric.size'), disk_usage_size_text(a.scanner.total_bytes),
		disk_usage_pad, 162, metric_width, app_accent)
	children << disk_usage_metric(tr('disk_usage.metric.files'), disk_usage_count_text(a.scanner.files),
		disk_usage_pad + metric_width + gap, 162, metric_width, disk_usage_files_accent)
	children << disk_usage_metric(tr('disk_usage.metric.folders'), disk_usage_count_text(a.scanner.directories),
		disk_usage_pad + (metric_width + gap) * 2, 162, metric_width, disk_usage_folders_accent)
	children << disk_usage_metric(tr('disk_usage.metric.skipped'), disk_usage_count_text(a.scanner.unreadable),
		disk_usage_pad + (metric_width + gap) * 3, 162, metric_width, files_error)

	panel_width := (inner - gap) / 2
	children << a.panel(tr('disk_usage.panel.folders'), &a.scanner.dirs_rank, a.dir_page, rows,
		disk_usage_dir_actions, disk_usage_action_dirs_back, disk_usage_action_dirs_next, disk_usage_pad, panel_y,
		panel_width, panel_height, disk_usage_folders_accent, !scanning)
	children << a.panel(tr('disk_usage.panel.files'), &a.scanner.files_rank, a.file_page, rows,
		disk_usage_dir_actions, disk_usage_action_files_back, disk_usage_action_files_next, disk_usage_pad +
			panel_width + gap, panel_y, panel_width, panel_height, disk_usage_files_accent, false)

	mut status := frame_elements(1)
	status << disk_usage_owned_label(a.status_text(), ui2.rect(10, 5, f64(inner - 20), 14), ui2.TextStyle{
		color: body_text
		size:  11
	})
	children << ui2.view('', ui2.rect(f64(disk_usage_pad), f64(height - 28), f64(inner), 22),
		ui2.BoxStyle{
			bg:     body_panel
			radius: 6
		}, status)

	return ui2.screen(app_surface, children)
}

fn disk_usage_clamp_page(page int, rows int, total int) int {
	if page + rows > total {
		last := total - rows
		return if last < 0 { 0 } else { last }
	}
	return if page < 0 { 0 } else { page }
}

fn disk_usage_buffer_text(bytes []u8) string {
	if bytes.len == 0 { return '' }
	return unsafe { tos(bytes.data, bytes.len) }
}

fn disk_usage_path_field(action string, text string, x int, y int, width int, focused bool) ui2.Element {
	return ui2.button(action, text, ui2.rect(f64(x), f64(y), f64(width), 24), ui2.BoxStyle{
		bg:            0xffffff
		radius:        5
		border_color:  if focused { app_accent } else { body_rule }
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, ui2.TextStyle{ color: body_text, size: 11 })
}

fn (mut a DiskUsageApp) scan_typed_path() {
	path := disk_usage_buffer_text(a.root_input)
	if path.len == 0 || path[0] != `/` { return }
	a.scan(path)
	a.focus = .none_
}

fn (mut a DiskUsageApp) edit_path(ch u8) {
	mut bytes := if a.focus == .root { &a.root_input } else { &a.report_path }
	unsafe { bytes.flags |= .noslices }
	if a.path_select_all && (ch >= 32 || ch == 8) {
		bytes.clear()
		a.path_select_all = false
		if ch == 8 || ch == 127 { return }
	}
	if ch == 8 || ch == 127 {
		// Delete the entire UTF-8 character, not its last continuation byte.
		mut from := bytes.len - 1
		for from > 0 && unsafe { (*bytes)[from] } & 0xc0 == 0x80 { from-- }
		if from >= 0 { bytes.trim(from) }
	} else if ch >= 32 && ch != 127 && bytes.len < disk_usage_path_limit {
		bytes << ch
	}
	a.report_status = ''
}

fn (mut a DiskUsageApp) key_input(text string) {
	mut at := 0
	for at < text.len {
		ch := text[at]
		if ch == 0x1b && at + 1 < text.len && text[at + 1] == `[` {
			at += 2
			for at < text.len {
				final := text[at] >= 0x40 && text[at] <= 0x7e
				at++
				if final { break }
			}
			continue
		}
		match ch {
			0x0c {
				a.focus = .root
				a.path_select_all = true
			}
			0x15 {
				if a.focus != .none_ {
					a.path_select_all = true
					a.edit_path(8)
				}
			}
			0x1b { a.focus = .none_ }
			`\n`, `\r` {
				if a.focus == .root {
					a.scan_typed_path()
				} else if a.focus == .report {
					a.export_report()
				}
			}
			else {
				if a.focus != .none_ { a.edit_path(ch) }
			}
		}
		at++
	}
}

fn (mut a DiskUsageApp) paste_input(text string) {
	if a.focus == .none_ { return }
	for ch in text {
		if ch >= 32 && ch != 127 { a.edit_path(ch) }
	}
}

// Quote all paths, including embedded quotes/newlines. Column names and raw
// byte totals remain stable across desktop languages for spreadsheet imports.
fn disk_usage_csv_row(mut out []u8, kind string, path string, bytes u64) {
	disk_usage_append(mut out, kind)
	disk_usage_append(mut out, ',"')
	for ch in path {
		if ch == `"` { out << `"` }
		out << ch
	}
	disk_usage_append(mut out, '",')
	count := bytes.str()
	disk_usage_append(mut out, count)
	unsafe { count.free() }
	out << `\n`
}

fn (s &DiskUsageScanner) report_csv() []u8 {
	mut out := []u8{cap: 4096}
	unsafe { out.flags |= .noslices }
	disk_usage_append(mut out, 'kind,path,bytes\n')
	disk_usage_csv_row(mut out, 'root', s.root, s.total_bytes)
	disk_usage_csv_row(mut out, 'phase', match s.phase {
		.scanning { 'scanning' }
		.complete { 'complete' }
		.cancelled { 'cancelled' }
		.failed { 'failed' }
	}, 0)
	disk_usage_csv_row(mut out, 'file_count', '', s.files)
	disk_usage_csv_row(mut out, 'directory_count', '', s.directories)
	disk_usage_csv_row(mut out, 'skipped_count', '', s.unreadable)
	if s.capacity.valid {
		disk_usage_csv_row(mut out, 'filesystem_total', s.root, s.capacity.total)
		disk_usage_csv_row(mut out, 'filesystem_used', s.root, s.capacity.used)
		disk_usage_csv_row(mut out, 'filesystem_free', s.root, s.capacity.free)
		disk_usage_csv_row(mut out, 'filesystem_available', s.root, s.capacity.available)
	} else {
		disk_usage_csv_row(mut out, 'filesystem_capacity_unavailable', s.root, 0)
	}
	for entry in s.dirs_rank.entries {
		disk_usage_csv_row(mut out, 'directory', entry.path, entry.bytes)
	}
	for entry in s.files_rank.entries {
		disk_usage_csv_row(mut out, 'file', entry.path, entry.bytes)
	}
	return out
}

fn (mut a DiskUsageApp) export_report() {
	if a.scanner.phase == .scanning || a.scanner.phase == .failed { return }
	path := disk_usage_buffer_text(a.report_path).clone()
	defer { unsafe { path.free() } }
	if path.len == 0 || path[0] != `/` { return }
	// An inventory report must never overwrite one of the scanned files.
	if desktop_lstat(path) != none {
		a.report_status = 'disk_usage.report.exists'
		return
	}
	data := a.scanner.report_csv()
	success := disk_usage_write_report(path, data)
	unsafe { data.free() }
	a.report_status = if success { 'disk_usage.report.saved' } else { 'disk_usage.report.failed' }
}

fn disk_usage_write_report(path string, data []u8) bool {
	// O_EXCL enforces the same no-overwrite policy even if a file appears
	// between the existence check and opening the report.
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o644)
	if fd < 0 { return false }
	written := desktop_write_all(fd, data.data, u64(data.len))
	closed := C.close(fd) == 0
	if !written || !closed {
		C.unlink(&char(path.str))
		return false
	}
	return true
}

fn disk_usage_append(mut out []u8, text string) {
	for ch in text { out << ch }
}

fn disk_usage_default_report_path() string {
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	return join_path(home, disk_usage_report_filename)
}
