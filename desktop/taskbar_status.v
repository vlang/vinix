// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Taskbar progress bars, badges and attention, in the manner of Windows 7's
// ITaskbarList3.
//
// Every application process the compositor starts gets its own status file in
// VINIX_TASKBAR_STATUS. Anything running under that process -- the app itself,
// or a shell and whatever it runs inside Terminal -- can write it:
//
//     progress 42            percent complete, 0..100
//     state paused           normal, paused, error, indeterminate or none
//     badge 3                up to three printable characters, or nothing
//     attention 7            a serial; each new value flashes the button
//
// Missing lines keep their default (no progress, no badge). The compositor
// reads the file a couple of times a second and draws the result over the
// window's taskbar button. Terminal translates the OSC 9;4 progress sequence
// and the bell into this file, so ordinary command-line tools can drive it.
module main

import ui2

const taskbar_status_directory = '/run/vinix-taskbar'
const taskbar_status_env = 'VINIX_TASKBAR_STATUS'
const taskbar_status_file_limit = 256
// Reported progress is read on the desktop's ordinary one-second idle wake.
const taskbar_status_poll_ms = i64(1000)
const taskbar_badge_max = 3
// Windows 7's indeterminate bar is a highlight sweeping across the button.
const taskbar_marquee_period_ms = i64(1600)
// Each step recomposes the frame, so the sweep moves in coarse steps.
const taskbar_marquee_frame_ms = i64(150)

const taskbar_progress_overlay_id = 'taskbar.progress'
const taskbar_progress_normal = u32(0x3fb24f)
const taskbar_progress_paused = u32(0xd9b52b)
const taskbar_progress_error = u32(0xd24a3c)
const taskbar_progress_alpha = u32(96)
const taskbar_badge_bg = u32(0xd83b2d)
const taskbar_attention_bg = u32(0xd97a2b)

enum TaskProgress {
	none_
	normal
	paused
	error
	indeterminate
}

struct TaskStatus {
mut:
	progress_state TaskProgress
	progress       int
	badge          string
	// Each attention request carries a new serial. The button is flagged
	// while the serial is newer than the last one its window saw focused.
	attention_serial int
	attention        bool
}

fn (s &TaskStatus) same(other &TaskStatus) bool {
	return s.progress_state == other.progress_state && s.progress == other.progress
		&& s.badge == other.badge && s.attention_serial == other.attention_serial
		&& s.attention == other.attention
}

fn (s &TaskStatus) visible() bool {
	return s.progress_state != .none_ || s.badge.len > 0 || s.attention
}

// merge_task_status folds one window into a button's combined status: the
// first progress and the first badge win, and attention is any window's that
// is not the focused one.
fn merge_task_status(current TaskStatus, next TaskStatus, focused bool) TaskStatus {
	mut merged := current
	if merged.progress_state == .none_ && next.progress_state != .none_ {
		merged.progress_state = next.progress_state
		merged.progress = next.progress
	}
	if merged.badge.len == 0 && next.badge.len > 0 {
		merged.badge = next.badge
	}
	if next.attention && !focused {
		merged.attention = true
	}
	return merged
}

fn task_status_word(word string) ?TaskProgress {
	return match word {
		'none' { TaskProgress.none_ }
		'normal' { TaskProgress.normal }
		'paused' { TaskProgress.paused }
		'error' { TaskProgress.error }
		'indeterminate' { TaskProgress.indeterminate }
		else { none }
	}
}

// parse_task_status reads the line format documented above. The badge is
// the only allocation and belongs to the returned status.
fn parse_task_status(text []u8) TaskStatus {
	mut status := TaskStatus{}
	mut saw_state := false
	mut saw_progress := false
	mut start := 0
	for offset := 0; offset <= text.len; offset++ {
		if offset < text.len && text[offset] != `\n` {
			continue
		}
		mut end := offset
		if end > start && text[end - 1] == `\r` {
			end--
		}
		if end <= start {
			start = offset + 1
			continue
		}
		mut space := -1
		for at in start .. end {
			if text[at] == ` ` {
				space = at
				break
			}
		}
		key_end := if space >= 0 { space } else { end }
		key := unsafe { tos(&u8(text.data) + start, key_end - start) }
		value := if space >= 0 && end > space + 1 {
			unsafe { tos(&u8(text.data) + space + 1, end - space - 1) }
		} else {
			''
		}
		match key {
			'progress' {
				mut percent := 0
				mut valid := value.len > 0 && value.len <= 3
				for ch in value {
					if ch < `0` || ch > `9` {
						valid = false
						break
					}
					percent = percent * 10 + int(ch - `0`)
				}
				if valid {
					status.progress = if percent > 100 { 100 } else { percent }
					saw_progress = true
				}
			}
			'state' {
				if state := task_status_word(value) {
					status.progress_state = state
					saw_state = true
				}
			}
			'badge' {
				mut printable := value.len <= taskbar_badge_max
				for ch in value {
					if ch < 0x21 || ch > 0x7e {
						printable = false
					}
				}
				if printable && value.len > 0 && status.badge.len == 0 {
					status.badge = value.clone()
				}
			}
			'attention' {
				status.attention_serial = value.int()
			}
			else {}
		}
		start = offset + 1
	}
	// A bare percentage means ordinary progress, which is what nearly every
	// writer wants to say.
	if saw_progress && !saw_state {
		status.progress_state = .normal
	}
	return status
}

fn format_task_status(status TaskStatus) string {
	state := match status.progress_state {
		.none_ { 'none' }
		.normal { 'normal' }
		.paused { 'paused' }
		.error { 'error' }
		.indeterminate { 'indeterminate' }
	}
	return 'state ${state}\nprogress ${status.progress}\nbadge ${status.badge}\nattention ${status.attention_serial}\n'
}

// ── Application side ──────────────────────────────────────────────

struct TaskbarStatusWriter {
mut:
	resolved bool
	path     string
	last     TaskStatus
	written  bool
}

__global taskbar_status_writer = TaskbarStatusWriter{}

fn (mut w TaskbarStatusWriter) resolve() {
	if w.resolved {
		return
	}
	w.resolved = true
	value := C.getenv(c'VINIX_TASKBAR_STATUS')
	if value != unsafe { nil } {
		w.path = unsafe { cstring_to_vstring(value) }
	}
}

// publish_taskbar_status is how an application process reports progress. It
// is a no-op outside the desktop, and rewrites the file only on change. The
// temporary name keeps the compositor from ever reading a half-written file.
fn publish_taskbar_status(status TaskStatus) {
	taskbar_status_writer.resolve()
	if taskbar_status_writer.path.len == 0 {
		return
	}
	if taskbar_status_writer.written && taskbar_status_writer.last.same(status) {
		return
	}
	text := format_task_status(status)
	temporary := '${taskbar_status_writer.path}.tmp'
	if desktop_write_file(temporary, text.str, u64(text.len)) {
		C.rename(&char(temporary.str), &char(taskbar_status_writer.path.str))
	}
	unsafe {
		text.free()
		temporary.free()
		if taskbar_status_writer.last.badge.len > 0 {
			taskbar_status_writer.last.badge.free()
		}
	}
	taskbar_status_writer.last = TaskStatus{
		...status
		badge: status.badge.clone()
	}
	taskbar_status_writer.written = true
}

// ── Compositor side ───────────────────────────────────────────────

// next_taskbar_status_path names the file for the application about to be
// started. The directory lives on /run, so stale files do not survive a boot.
fn (mut d Desktop) next_taskbar_status_path() string {
	ensure_directory(taskbar_status_directory) or { return '' }
	d.next_status_token++
	path := '${taskbar_status_directory}/${d.next_status_token}'
	// /run outlives a desktop reload, so the name may still hold what an
	// earlier session's window last reported.
	desktop_unlink(path)
	return path
}

fn (mut d Desktop) release_taskbar_status(index int) {
	if d.windows[index].status_path.len > 0 {
		desktop_unlink(d.windows[index].status_path)
		unsafe { d.windows[index].status_path.free() }
		d.windows[index].status_path = ''
	}
	if d.windows[index].status.badge.len > 0 {
		unsafe { d.windows[index].status.badge.free() }
	}
	d.windows[index].status = TaskStatus{}
}

// poll_taskbar_status reads every window's status file on a slow cadence and
// only invalidates the frame when something a button shows has changed.
fn (mut d Desktop) poll_taskbar_status() {
	now := monotonic_millis()
	if d.taskbar_status_polled_ms != 0 && now >= d.taskbar_status_polled_ms
		&& now - d.taskbar_status_polled_ms < taskbar_status_poll_ms {
		return
	}
	d.taskbar_status_polled_ms = now
	for index in 0 .. d.windows.len {
		d.refresh_window_status(index)
	}
}

fn (mut d Desktop) refresh_window_status(index int) {
	mut next := TaskStatus{}
	if d.windows[index].status_path.len > 0 {
		text := read_small_file(d.windows[index].status_path, taskbar_status_file_limit)
		next = parse_task_status(text)
		if text.cap > 0 {
			unsafe { text.free() }
		}
	}
	// The compositor records the Capture window's own recording, as it owns
	// the video stream rather than the Capture process.
	if d.windows[index].title == capture_app_title && d.capture.report.phase == .recording {
		if next.badge.len > 0 {
			unsafe { next.badge.free() }
		}
		next.badge = 'REC'.clone()
	}
	if d.windows[index].id == d.focus && !d.windows[index].minimized {
		d.windows[index].attention_seen = next.attention_serial
	}
	next.attention = next.attention_serial > d.windows[index].attention_seen
	if d.windows[index].status.same(next) {
		if next.badge.len > 0 {
			unsafe { next.badge.free() }
		}
		return
	}
	if d.windows[index].status.badge.len > 0 {
		unsafe { d.windows[index].status.badge.free() }
	}
	d.windows[index].status = next
	d.dirty = true
}

// A button stops asking for attention as soon as its window is brought up.
fn (mut d Desktop) acknowledge_attention(id int) {
	index := d.window_index(id) or { return }
	d.windows[index].attention_seen = d.windows[index].status.attention_serial
	if d.windows[index].status.attention {
		d.windows[index].status.attention = false
		d.dirty = true
	}
}

fn (d &Desktop) taskbar_has_indeterminate_progress() bool {
	for window in d.windows {
		if window.status.progress_state == .indeterminate {
			return true
		}
	}
	return false
}

// An indeterminate bar is the only part of the taskbar that animates, so a
// desktop without one keeps its one-second idle wake.
fn (d &Desktop) taskbar_status_idle_interval(maximum i64) i64 {
	if d.taskbar_has_indeterminate_progress() && taskbar_marquee_frame_ms < maximum {
		return taskbar_marquee_frame_ms
	}
	return maximum
}

fn (mut d Desktop) tick_taskbar_marquee() {
	if !d.taskbar_has_indeterminate_progress() {
		return
	}
	now := monotonic_millis()
	if now - d.taskbar_marquee_ms >= taskbar_marquee_frame_ms {
		d.taskbar_marquee_ms = now
		d.dirty = true
	}
}

fn task_progress_color(state TaskProgress) u32 {
	return match state {
		.paused { taskbar_progress_paused }
		.error { taskbar_progress_error }
		else { taskbar_progress_normal }
	}
}

// taskbar_status_elements tints the part of the button that is done, draws a
// solid bar along its bottom edge and puts the badge in its top-right corner.
fn (d &Desktop) taskbar_status_elements(mut children []ui2.Element, status TaskStatus, x int, y int,
	width int, height int, radius int) {
	if status.progress_state != .none_ {
		color := task_progress_color(status.progress_state)
		mut fill_x := x
		mut fill_width := width * status.progress / 100
		if status.progress_state == .indeterminate {
			segment := width / 3
			phase := monotonic_millis() % taskbar_marquee_period_ms
			fill_x = x - segment + int(i64(width + segment) * phase / taskbar_marquee_period_ms)
			fill_width = segment
			if fill_x < x {
				fill_width -= x - fill_x
				fill_x = x
			}
			if fill_x + fill_width > x + width {
				fill_width = x + width - fill_x
			}
		}
		if fill_width > 0 {
			children << ui2.view(taskbar_progress_overlay_id, ui2.rect(f64(fill_x), f64(y),
				f64(fill_width), f64(height)), ui2.BoxStyle{
				bg:     color
				radius: radius
			}, [])
			bar_left := if fill_x < x + 3 { x + 3 } else { fill_x }
			bar_right := if fill_x + fill_width > x + width - 3 {
				x + width - 3
			} else {
				fill_x + fill_width
			}
			if bar_right > bar_left {
				children << ui2.view('', ui2.rect(f64(bar_left), f64(y + height - 3),
					f64(bar_right - bar_left), 2), ui2.BoxStyle{
					bg:     color
					radius: 1
				}, [])
			}
		}
	}
	if status.badge.len > 0 {
		badge_width := if status.badge.len == 1 { 15 } else { 9 + 6 * status.badge.len }
		children << ui2.view('', ui2.rect(f64(x + width - badge_width - 1), f64(y + 1),
			f64(badge_width), 15), ui2.BoxStyle{
			bg:     taskbar_badge_bg
			radius: 7
		}, frame_child(ui2.label('', status.badge, ui2.rect(0, 0, f64(badge_width), 15),
			ui2.TextStyle{
			color: 0xffffff
			size:  9
			bold:  true
			align: .center
		})))
	}
}
