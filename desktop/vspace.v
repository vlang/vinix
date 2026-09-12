// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// VSpace, a disk inventory, built into the desktop.
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
const vspace_rank_limit = 24

// A tree deeper than this is a loop the identity check missed, or something no
// inventory needs to open. Each level also holds an open directory handle.
const vspace_max_depth = 64

// One slice of the walk. The compositor is waiting on the poll that runs it,
// so this is the longest a scan may delay a frame.
const vspace_slice_ms = u64(20)

// A hard ceiling on one slice, for a filesystem fast enough that the clock
// never advances far enough to stop it.
const vspace_slice_entries = 20000

// Longer than any name the kernel's Dirent can hold.
const vspace_name_max = 256

const vspace_identity_slots = 2048

// ── Identity set ──────────────────────────────────────────────────
// A scan must not descend into the same directory twice and must count a file
// with several names once. Both are the question "have I seen this device and
// inode already", asked once per entry. An open-addressed set of packed keys
// answers it without allocating the string per file that a keyed map would,
// and the desktop has no garbage collector to clean up after one.

struct VSpaceIdentitySet {
mut:
	slots []u64
	used  int
}

fn vspace_identity_key(device u64, inode u64) u64 {
	key := (device << 48) ^ inode
	// Zero marks a free slot, so the one identity that would collide with it
	// is folded onto a neighbour. Two entries sharing a key is only ever a
	// miscount of one file, never a wrong answer about the tree's shape.
	return if key == 0 { u64(1) } else { key }
}

fn (mut s VSpaceIdentitySet) reset() {
	if s.slots.len == 0 {
		s.slots = []u64{len: vspace_identity_slots}
		unsafe { s.slots.flags |= .noslices }
	} else {
		for index in 0 .. s.slots.len {
			s.slots[index] = 0
		}
	}
	s.used = 0
}

// add reports whether the key had not been seen before.
fn (mut s VSpaceIdentitySet) add(key u64) bool {
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

fn (mut s VSpaceIdentitySet) grow() {
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

fn (mut s VSpaceIdentitySet) release() {
	if s.slots.cap > 0 {
		unsafe { s.slots.free() }
	}
	s.slots = []u64{}
	s.used = 0
}

// ── Rankings ──────────────────────────────────────────────────────

struct VSpaceEntry {
mut:
	name  string
	path  string
	bytes u64
}

// VSpaceRanking is the largest few of something, kept in order. Below the
// floor nothing can enter, which is what stops a hundred thousand files from
// each costing an insertion.
struct VSpaceRanking {
mut:
	entries []VSpaceEntry
	floor   u64
}

// consider always takes ownership of the two strings: it either keeps them in
// the ranking or releases them. A caller that had to know which would have to
// repeat the floor test it is here to avoid.
fn (mut r VSpaceRanking) consider(name string, path string, bytes u64) {
	if r.entries.len >= vspace_rank_limit && bytes <= r.floor {
		unsafe {
			name.free()
			path.free()
		}
		return
	}
	entry := VSpaceEntry{
		name: name
		path: path
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
	if r.entries.len > vspace_rank_limit {
		dropped := r.entries.last()
		unsafe {
			dropped.name.free()
			dropped.path.free()
		}
		r.entries.delete_last()
	}
	r.floor = if r.entries.len >= vspace_rank_limit {
		r.entries.last().bytes
	} else {
		u64(0)
	}
}

fn (mut r VSpaceRanking) release() {
	for index in 0 .. r.entries.len {
		unsafe {
			r.entries[index].name.free()
			r.entries[index].path.free()
		}
	}
	if r.entries.cap > 0 {
		unsafe { r.entries.free() }
	}
	r.entries = []VSpaceEntry{}
	r.floor = 0
}

fn (r &VSpaceRanking) largest() u64 {
	if r.entries.len == 0 {
		return 0
	}
	return r.entries[0].bytes
}

// ── The walk ──────────────────────────────────────────────────────

enum VSpacePhase {
	scanning
	complete
	cancelled
	failed
}

// One open directory, and what its subtree has added up to so far. The stack
// of these is the recursion the standalone program does with the C stack; made
// explicit, it can be left in the middle and resumed on the next poll.
struct VSpaceFrame {
mut:
	path  string
	name  string
	dir   voidptr
	bytes u64
}

struct VSpaceScanner {
mut:
	root        string = '/'
	phase       VSpacePhase = .complete
	stack       []VSpaceFrame
	files_rank  VSpaceRanking
	dirs_rank   VSpaceRanking
	seen_dirs   VSpaceIdentitySet
	seen_links  VSpaceIdentitySet
	total_bytes u64
	files       u64
	directories u64
	unreadable  u64
	started_ms  u64
	elapsed_ms  u64
	error       string
	name_buffer [vspace_name_max]u8
}

// begin restarts the walk at `path`. The new root is copied before anything is
// released, so a rescan of the current root and a descent into a ranked folder
// can both hand in a string the reset is about to free.
fn (mut s VSpaceScanner) begin(path string) {
	next := path.clone()
	s.reset()
	unsafe { s.root.free() }
	s.root = next
	s.seen_dirs.reset()
	s.seen_links.reset()
	s.started_ms = desktop_monotonic_ms()
	dir := desktop_opendir(s.root)
	if dir == unsafe { nil } {
		s.phase = .failed
		s.set_error('cannot open ${s.root}')
		return
	}
	if info := desktop_lstat(s.root) {
		s.seen_dirs.add(vspace_identity_key(info.device, info.inode))
	}
	s.stack << VSpaceFrame{
		path: s.root.clone()
		name: s.root.clone()
		dir: dir
	}
	s.directories = 1
	s.phase = .scanning
}

// step advances the walk by one bounded slice and reports whether the window
// has anything new to show.
fn (mut s VSpaceScanner) step() bool {
	if s.phase != .scanning {
		return false
	}
	started := desktop_monotonic_ms()
	mut worked := 0
	for s.stack.len > 0 && worked < vspace_slice_entries {
		s.advance()
		worked++
		// The clock is only read every 64 entries: on a fast filesystem the
		// call itself would otherwise be a measurable share of the walk.
		if worked & 63 == 0 && vspace_elapsed(started, desktop_monotonic_ms()) >= vspace_slice_ms {
			break
		}
	}
	s.elapsed_ms = vspace_elapsed(s.started_ms, desktop_monotonic_ms())
	if s.stack.len == 0 {
		s.phase = .complete
	}
	return true
}

// advance consumes exactly one directory entry, or leaves a directory that has
// none left. Everything the walk does is one of those two things, which is
// what makes it interruptible between any two of them.
fn (mut s VSpaceScanner) advance() {
	depth := s.stack.len - 1
	mut names := unsafe { (&s.name_buffer[0]).vbytes(vspace_name_max) }
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
		&& (info.links < 2 || s.seen_links.add(vspace_identity_key(info.device, info.inode))) {
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

fn (mut s VSpaceScanner) enter(name string, path string, info DesktopNodeInfo) {
	if !s.seen_dirs.add(vspace_identity_key(info.device, info.inode))
		|| s.stack.len >= vspace_max_depth {
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
	s.stack << VSpaceFrame{
		path: path
		name: name
		dir: dir
	}
}

// leave closes a finished directory and gives its subtree total to the parent
// that will be ranked against its own siblings.
fn (mut s VSpaceScanner) leave() {
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

fn (mut s VSpaceScanner) cancel() {
	if s.phase != .scanning {
		return
	}
	s.elapsed_ms = vspace_elapsed(s.started_ms, desktop_monotonic_ms())
	s.close_stack()
	s.phase = .cancelled
}

fn (mut s VSpaceScanner) close_stack() {
	for index in 0 .. s.stack.len {
		desktop_closedir(s.stack[index].dir)
		unsafe {
			s.stack[index].path.free()
			s.stack[index].name.free()
		}
	}
	s.stack.clear()
}

fn (mut s VSpaceScanner) reset() {
	s.close_stack()
	s.files_rank.release()
	s.dirs_rank.release()
	s.total_bytes = 0
	s.files = 0
	s.directories = 0
	s.unreadable = 0
	s.elapsed_ms = 0
	s.started_ms = 0
	s.set_error('')
}

fn (mut s VSpaceScanner) release() {
	s.reset()
	s.seen_dirs.release()
	s.seen_links.release()
	unsafe { s.root.free() }
	s.root = ''
}

// set_error replaces the reason a scan produced nothing, releasing the one
// before it. Assigning over a string built by interpolation would strand it.
fn (mut s VSpaceScanner) set_error(message string) {
	if s.error == message {
		unsafe { message.free() }
		return
	}
	unsafe { s.error.free() }
	s.error = message
}

// current_path is what the walk is inside of right now. The string belongs to
// the frame that owns the open directory, and the element tree is encoded and
// thrown away before that frame can be popped.
fn (s &VSpaceScanner) current_path() string {
	if s.stack.len == 0 {
		return s.root
	}
	return s.stack[s.stack.len - 1].path
}

fn vspace_elapsed(from u64, to u64) u64 {
	if from == ~u64(0) || to == ~u64(0) || to < from {
		return 0
	}
	return to - from
}

// ── Formatting ────────────────────────────────────────────────────

const vspace_size_units = ['KB', 'MB', 'GB', 'TB', 'PB']

// vspace_size_text is the standalone program's byte formatter: a compact
// binary unit carrying three significant figures. The arithmetic is integer
// because V's floating-point formatter keeps scratch storage alive under
// -manualfree, and this runs for every row of both panels every frame.
fn vspace_size_text(bytes u64) string {
	if bytes < 1024 {
		count := bytes.str()
		text := '${count} B'
		unsafe { count.free() }
		return text
	}
	mut value := bytes
	mut unit := 0
	for value >= 1024 * 1024 && unit + 1 < vspace_size_units.len {
		value /= 1024
		unit++
	}
	// value is now at least one and less than 1024 of the chosen unit, held as
	// the count of the unit below it so the decimals survive the division.
	hundredths := (value * 100 + 512) / 1024
	if hundredths >= 10000 {
		whole := ((hundredths + 50) / 100).str()
		text := '${whole} ${vspace_size_units[unit]}'
		unsafe { whole.free() }
		return text
	}
	if hundredths >= 1000 {
		tenths := (hundredths + 5) / 10
		whole := (tenths / 10).str()
		fraction := (tenths % 10).str()
		text := '${whole}.${fraction} ${vspace_size_units[unit]}'
		unsafe {
			whole.free()
			fraction.free()
		}
		return text
	}
	whole := (hundredths / 100).str()
	fraction := pad2(int(hundredths % 100))
	text := '${whole}.${fraction} ${vspace_size_units[unit]}'
	unsafe {
		whole.free()
		fraction.free()
	}
	return text
}

// vspace_count_text groups an integer into thousands. Six hundred thousand
// files is unreadable as a run of digits and obvious with two commas in it.
fn vspace_count_text(value u64) string {
	digits := value.str()
	mut out := []u8{cap: digits.len + digits.len / 3}
	for index in 0 .. digits.len {
		if index > 0 && (digits.len - index) % 3 == 0 {
			out << `,`
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

fn vspace_duration_text(milliseconds u64) string {
	if milliseconds < 1000 {
		count := milliseconds.str()
		text := '${count} ms'
		unsafe { count.free() }
		return text
	}
	seconds := milliseconds / 1000
	if seconds < 60 {
		whole := seconds.str()
		tenth := (milliseconds % 1000 / 100).str()
		text := '${whole}.${tenth} sec'
		unsafe {
			whole.free()
			tenth.free()
		}
		return text
	}
	minutes := (seconds / 60).str()
	remaining := (seconds % 60).str()
	text := '${minutes} min ${remaining} sec'
	unsafe {
		minutes.free()
		remaining.free()
	}
	return text
}

// ── The native application ────────────────────────────────────────

const vspace_action_rescan = 'vspace.rescan'
const vspace_action_stop = 'vspace.stop'
const vspace_action_up = 'vspace.up'
const vspace_action_dirs_back = 'vspace.dirs.back'
const vspace_action_dirs_next = 'vspace.dirs.next'
const vspace_action_files_back = 'vspace.files.back'
const vspace_action_files_next = 'vspace.files.next'

// The scopes the standalone program's Whole disk and Home buttons stand for,
// plus the one directory on a Vinix image that is worth a button of its own.
const vspace_scope_titles = ['Whole disk', 'Home', 'System']
const vspace_scope_paths = ['/', '/root', '/usr']
const vspace_scope_actions = ['vspace.scope.0', 'vspace.scope.1', 'vspace.scope.2']

// Row actions are literals because the tree is rebuilt on every frame and this
// target has no garbage collector. They name a row of the window, not an entry
// of the ranking: the page offset is what turns one into the other.
const vspace_dir_actions = ['vspace.dir.0', 'vspace.dir.1', 'vspace.dir.2', 'vspace.dir.3',
	'vspace.dir.4', 'vspace.dir.5', 'vspace.dir.6', 'vspace.dir.7', 'vspace.dir.8', 'vspace.dir.9',
	'vspace.dir.10', 'vspace.dir.11']

const vspace_pad = 12
const vspace_row_height = 48
const vspace_metric_height = 62
const vspace_panel_header = 34

struct VSpaceApp {
mut:
	scanner   VSpaceScanner
	dir_page  int
	file_page int
	dir_rows  int = 1
	file_rows int = 1
}

fn open_vspace(mut _ Desktop) !NativeApp {
	mut app := &VSpaceApp{}
	// A disk inventory that opened on an empty window and waited to be told
	// what to look at would be asking a question with one sensible answer.
	app.scanner.begin('/')
	return app
}

fn (mut a VSpaceApp) poll() bool {
	return a.scanner.step()
}

fn (mut a VSpaceApp) close_app() {
	a.scanner.release()
}

fn (mut a VSpaceApp) scan(path string) {
	a.scanner.begin(path)
	a.dir_page = 0
	a.file_page = 0
}

fn (mut a VSpaceApp) handle(event_id string) ! {
	match event_id {
		vspace_action_rescan {
			a.scan(a.scanner.root)
			return
		}
		vspace_action_stop {
			a.scanner.cancel()
			return
		}
		vspace_action_up {
			if a.scanner.root != '/' {
				a.scan(parent_path(a.scanner.root))
			}
			return
		}
		vspace_action_dirs_back {
			a.dir_page = vspace_page_back(a.dir_page, a.dir_rows)
			return
		}
		vspace_action_dirs_next {
			a.dir_page = vspace_page_next(a.dir_page, a.dir_rows, a.scanner.dirs_rank.entries.len)
			return
		}
		vspace_action_files_back {
			a.file_page = vspace_page_back(a.file_page, a.file_rows)
			return
		}
		vspace_action_files_next {
			a.file_page = vspace_page_next(a.file_page, a.file_rows, a.scanner.files_rank.entries.len)
			return
		}
		else {}
	}
	for index, action in vspace_scope_actions {
		if event_id == action {
			a.scan(vspace_scope_paths[index])
			return
		}
	}
	// Descending into a ranked folder rescans it, which is the only way to
	// learn what is inside a folder the ranking only gives a total for.
	for row, action in vspace_dir_actions {
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

fn vspace_page_back(page int, rows int) int {
	next := page - rows
	return if next < 0 { 0 } else { next }
}

fn vspace_page_next(page int, rows int, total int) int {
	next := page + rows
	return if next >= total { page } else { next }
}

fn (a &VSpaceApp) phase_color() u32 {
	return match a.scanner.phase {
		.scanning { vspace_phase_scanning }
		.complete { vspace_phase_complete }
		.cancelled { vspace_phase_stopped }
		.failed { files_error }
	}
}

fn (a &VSpaceApp) phase_title() string {
	return match a.scanner.phase {
		.scanning { 'SCANNING' }
		.complete { 'COMPLETE' }
		.cancelled { 'STOPPED' }
		.failed { 'UNREADABLE' }
	}
}

// status_text is the sentence along the bottom of the window. It is built for
// this frame and released with the tree, like every other formatted string
// here; only the paths inside it belong to the scanner.
fn (a &VSpaceApp) status_text() string {
	match a.scanner.phase {
		.scanning {
			return 'Walking ${a.scanner.current_path()}'
		}
		.failed {
			return a.scanner.error.clone()
		}
		.cancelled {
			return 'Stopped. The rankings below hold what had been counted.'
		}
		.complete {
			duration := vspace_duration_text(a.scanner.elapsed_ms)
			if a.scanner.unreadable == 0 {
				text := 'Scanned ${a.scanner.root} in ${duration}.'
				unsafe { duration.free() }
				return text
			}
			skipped := vspace_count_text(a.scanner.unreadable)
			text := 'Scanned ${a.scanner.root} in ${duration}. ${skipped} protected or unreadable items were skipped.'
			unsafe {
				duration.free()
				skipped.free()
			}
			return text
		}
	}
}

fn vspace_owned_label(text string, frame ui2.Rect, style ui2.TextStyle) ui2.Element {
	return ui2.label(frame_owned_text_id, text, frame, style)
}

fn vspace_button(action string, title string, x int, y int, width int, enabled bool) ui2.Element {
	return ui2.button(action, title, ui2.rect(f64(x), f64(y), f64(width), 24), ui2.BoxStyle{
		bg: if enabled { files_up } else { files_up_disabled }
		radius: 6
	}, ui2.TextStyle{
		color: if enabled { app_on_accent } else { body_muted }
		size: 13
		align: .center
	})
}

fn vspace_metric(title string, value string, x int, y int, width int, accent u32) ui2.Element {
	mut children := frame_elements(3)
	children << ui2.view('', ui2.rect(0, 0, 4, f64(vspace_metric_height)), ui2.BoxStyle{
		bg: accent
		radius: 2
	}, [])
	children << ui2.label('', title, ui2.rect(16, 11, f64(width - 26), 14), ui2.TextStyle{
		color: body_muted
		size: 11
		bold: true
	})
	children << vspace_owned_label(value, ui2.rect(16, 29, f64(width - 26), 24), ui2.TextStyle{
		color: body_heading
		size: 17
		bold: true
	})
	return ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(vspace_metric_height)), ui2.BoxStyle{
		bg: 0xffffff
		radius: 10
		border_color: body_rule
		border_left: 1
		border_top: 1
		border_right: 1
		border_bottom: 1
	}, children)
}

// vspace_row is one ranked entry: where it is, how much it holds, and a bar
// proportional to the largest entry in the same panel. The bar is what turns
// a column of numbers into a picture of the disk.
fn vspace_row(action string, rank int, entry &VSpaceEntry, y int, width int, largest u64, accent u32, clickable bool) ui2.Element {
	number := rank.str()
	size_text := vspace_size_text(entry.bytes)
	track := width - 50
	mut bar := 0
	if largest > 0 && entry.bytes > 0 && track > 0 {
		bar = int(u64(track) * entry.bytes / largest)
		if bar < 2 {
			bar = 2
		}
	}
	mut children := frame_elements(5)
	children << vspace_owned_label(number, ui2.rect(10, 5, 22, 16), ui2.TextStyle{
		color: body_muted
		size: 11
		bold: true
		align: .right
	})
	children << ui2.label('', entry.name, ui2.rect(40, 3, f64(width - 132), 18), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
	})
	children << vspace_owned_label(size_text, ui2.rect(f64(width - 90), 3, 80, 18), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
		align: .right
	})
	children << ui2.label('', entry.path, ui2.rect(40, 22, f64(width - 50), 14), ui2.TextStyle{
		color: body_muted
		size: 11
	})
	// Clear of the path by enough that the bar reads as a bar and not as an
	// underline of the text above it.
	children << ui2.view('', ui2.rect(40, 41, f64(bar), 3), ui2.BoxStyle{
		bg: accent
		radius: 1
	}, [])
	frame := ui2.rect(0, f64(y), f64(width), f64(vspace_row_height - 2))
	box := ui2.BoxStyle{
		bg: if rank % 2 == 1 { u32(0xffffff) } else { activity_row_alt }
		radius: 6
	}
	if !clickable {
		return ui2.view('', frame, box, children)
	}
	return ui2.clickable_view(action, frame, box, children)
}

fn (a &VSpaceApp) panel(title string, ranking &VSpaceRanking, page int, rows int, actions []string, back string, next string, x int, y int, width int, height int, accent u32, clickable bool) ui2.Element {
	// The two page buttons live in the header rather than under the rows: the
	// list is sized to fill the panel, so anything below it would sit on the
	// last row.
	paging := ranking.entries.len > rows
	summary_right := if paging { 60 } else { 14 }
	mut children := frame_elements(rows + 6)
	children << ui2.label('', title, ui2.rect(14, 9, f64(width - 200), 18), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
	})
	summary_frame := ui2.rect(f64(width - 186), 12, f64(186 - summary_right), 14)
	summary_style := ui2.TextStyle{
		color: body_muted
		size: 11
		align: .right
	}
	if ranking.entries.len == 0 {
		children << ui2.label('', 'nothing yet', summary_frame, summary_style)
	} else {
		count := vspace_count_text(u64(ranking.entries.len))
		children << vspace_owned_label('${count} ranked', summary_frame, summary_style)
		unsafe { count.free() }
	}
	children << ui2.view('', ui2.rect(0, f64(vspace_panel_header - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if paging {
		children << ui2.button(back, '-', ui2.rect(f64(width - 54), 8, 22, 18), ui2.BoxStyle{
			bg: files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size: 11
			align: .center
		})
		children << ui2.button(next, '+', ui2.rect(f64(width - 28), 8, 22, 18), ui2.BoxStyle{
			bg: files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size: 11
			align: .center
		})
	}

	if ranking.entries.len == 0 {
		children << ui2.label('', 'Results appear here while the disk is walked.', ui2.rect(14,
			f64(vspace_panel_header + 10), f64(width - 28), 18), ui2.TextStyle{
			color: body_muted
			size: 11
		})
	}
	largest := ranking.largest()
	mut row := 0
	for index := page; index < ranking.entries.len && row < rows; index++ {
		// Only the folder panel's rows can be descended into, and only then do
		// they need an action to be recognised by.
		action := if clickable && row < actions.len { actions[row] } else { '' }
		children << vspace_row(action, index + 1, &ranking.entries[index], vspace_panel_header +
			row * vspace_row_height, width, largest, accent, action.len > 0)
		row++
	}

	return ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: 0xffffff
		radius: 12
		border_color: body_rule
		border_left: 1
		border_top: 1
		border_right: 1
		border_bottom: 1
	}, children)
}

fn (mut a VSpaceApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	inner := width - vspace_pad * 2
	scanning := a.scanner.phase == .scanning

	panel_y := 178
	panel_height := height - panel_y - 34
	rows := if panel_height > vspace_panel_header + vspace_row_height {
		(panel_height - vspace_panel_header - 8) / vspace_row_height
	} else {
		1
	}
	a.dir_rows = rows
	a.file_rows = rows
	a.dir_page = vspace_clamp_page(a.dir_page, rows, a.scanner.dirs_rank.entries.len)
	a.file_page = vspace_clamp_page(a.file_page, rows, a.scanner.files_rank.entries.len)

	mut children := frame_elements(16)

	children << ui2.label('', 'VSpace', ui2.rect(f64(vspace_pad), 5, 84, 24), ui2.TextStyle{
		color: body_heading
		size: 18
		bold: true
	})
	children << ui2.label('', 'Disk inventory', ui2.rect(f64(vspace_pad + 78), 12, 160, 16),
		ui2.TextStyle{
		color: body_muted
		size: 11
	})

	mut badge := frame_elements(1)
	badge << ui2.label('', a.phase_title(), ui2.rect(6, 4, 92, 14), ui2.TextStyle{
		color: a.phase_color()
		size: 11
		bold: true
		align: .center
	})
	children << ui2.view('', ui2.rect(f64(width - vspace_pad - 104), 7, 104, 22), ui2.BoxStyle{
		bg: 0xffffff
		radius: 11
		border_color: a.phase_color()
		border_left: 1
		border_top: 1
		border_right: 1
		border_bottom: 1
	}, badge)

	// Scope: the presets, the way back out of a folder that was descended
	// into, and the two controls that start and stop a walk.
	mut scope_x := vspace_pad
	for index, title in vspace_scope_titles {
		button_width := if index == 0 { 92 } else { 72 }
		children << vspace_button(vspace_scope_actions[index], title, scope_x, 40, button_width,
			true)
		scope_x += button_width + 6
	}
	children << vspace_button(vspace_action_up, 'Up', scope_x, 40, 48, a.scanner.root != '/')
	children << vspace_button(vspace_action_stop, 'Stop', width - vspace_pad - 68, 40, 68,
		scanning)
	children << vspace_button(vspace_action_rescan, 'Rescan', width - vspace_pad - 144, 40,
		72, !scanning)

	children << ui2.label('', a.scanner.root, ui2.rect(f64(vspace_pad), 72, f64(inner), 16),
		ui2.TextStyle{
		color: body_text
		size: 11
		bold: true
	})

	// The hairline under the controls is the whole progress display: a walk
	// cannot know how much is left, so it says only that it is moving.
	mut bar := frame_elements(1)
	if scanning {
		travel := inner + 160
		offset := int(a.scanner.elapsed_ms / 4 % u64(travel)) - 160
		bar << ui2.view('', ui2.rect(f64(offset), 0, 160, 3), ui2.BoxStyle{
			bg: app_accent
			radius: 1
		}, [])
	} else if a.scanner.phase == .complete {
		bar << ui2.view('', ui2.rect(0, 0, f64(inner), 3), ui2.BoxStyle{
			bg: vspace_phase_complete
			radius: 1
		}, [])
	}
	children << ui2.view('', ui2.rect(f64(vspace_pad), 94, f64(inner), 3), ui2.BoxStyle{
		bg: body_rule
		radius: 1
	}, bar)

	gap := 10
	metric_width := (inner - gap * 3) / 4
	children << vspace_metric('INDEXED SIZE', vspace_size_text(a.scanner.total_bytes), vspace_pad,
		106, metric_width, app_accent)
	children << vspace_metric('FILES', vspace_count_text(a.scanner.files), vspace_pad + metric_width +
		gap, 106, metric_width, vspace_files_accent)
	children << vspace_metric('FOLDERS', vspace_count_text(a.scanner.directories), vspace_pad +
		(metric_width + gap) * 2, 106, metric_width, vspace_folders_accent)
	children << vspace_metric('SKIPPED', vspace_count_text(a.scanner.unreadable), vspace_pad +
		(metric_width + gap) * 3, 106, metric_width, files_error)

	panel_width := (inner - gap) / 2
	children << a.panel('Largest folders', &a.scanner.dirs_rank, a.dir_page, rows, vspace_dir_actions,
		vspace_action_dirs_back, vspace_action_dirs_next, vspace_pad, panel_y, panel_width,
		panel_height, vspace_folders_accent, !scanning)
	children << a.panel('Largest files', &a.scanner.files_rank, a.file_page, rows, vspace_dir_actions,
		vspace_action_files_back, vspace_action_files_next, vspace_pad + panel_width + gap,
		panel_y, panel_width, panel_height, vspace_files_accent, false)

	mut status := frame_elements(1)
	status << vspace_owned_label(a.status_text(), ui2.rect(10, 5, f64(inner - 20), 14), ui2.TextStyle{
		color: body_text
		size: 11
	})
	children << ui2.view('', ui2.rect(f64(vspace_pad), f64(height - 28), f64(inner), 22),
		ui2.BoxStyle{
		bg: body_panel
		radius: 6
	}, status)

	return ui2.screen(app_surface, children)
}

fn vspace_clamp_page(page int, rows int, total int) int {
	if page + rows > total {
		last := total - rows
		return if last < 0 { 0 } else { last }
	}
	return if page < 0 { 0 } else { page }
}
