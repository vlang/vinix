// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

pub const progress_prefix = 'VINIX-PACKAGE-PROGRESS '
pub const progress_limit = 8192

// Counters describe the current phase, not completion of the whole operation.
// A zero total is indeterminate. Download/copy use bytes; stage uses packages.
pub struct Progress {
pub:
	format     int = 1
	phase      string
	package    string
	repository string
	path       string
	current    u64
	total      u64
}

fn progress_path(path string) bool {
	if path == '' { return true }
	if path.contains('\\') { return false }
	mut start := 0
	for at in 0 .. path.len + 1 {
		if at != path.len && path[at] != `/` { continue }
		length := at - start
		if length == 0 || (length == 1 && path[start] == `.`)
			|| (length == 2 && path[start] == `.` && path[start + 1] == `.`) { return false }
		start = at + 1
	}
	return true
}

pub fn (event &Progress) validate() ! {
	if event.format != 1 || event.phase !in ['resolve', 'metadata', 'download', 'verify', 'copy', 'stage', 'activate', 'complete']!
		|| (event.package != '' && !identifier(event.package)) || (event.repository != '' && !identifier(event.repository))
		|| !printable(event.path, 1024) || !progress_path(event.path)
		|| (event.total != 0 && event.current > event.total) {
		return error('invalid package progress event')
	}
	if (event.phase in ['download', 'copy']! && (event.package == '' || event.path == ''
		|| event.total > u64(4) * 1024 * 1024 * 1024 || event.current > u64(4) * 1024 * 1024 * 1024))
		|| (event.phase == 'metadata' && (event.repository == '' || event.current > 8 * 1024 * 1024 || event.total != 0))
		|| (event.phase == 'stage' && (event.total > 4096 || event.current > 4096))
		|| (event.phase in ['resolve', 'verify', 'activate']! && (event.current != 0 || event.total != 0))
		|| (event.phase == 'complete' && (event.current != 1 || event.total != 1)) {
		return error('invalid package progress counters')
	}
}

pub fn decode_progress(text string) !Progress {
	if text.len > progress_limit { return error('package progress exceeds its size limit') }
	mut r := &MetadataReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut event := Progress{}
	mut accepted := false
	defer { if !accepted { event.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(progress_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { r.expect(`1`)! }
			1 { event = Progress{ ...event, phase: r.quoted(16)! } }
			2 { event = Progress{ ...event, package: r.quoted(128)! } }
			3 { event = Progress{ ...event, repository: r.quoted(128)! } }
			4 { event = Progress{ ...event, path: r.quoted(1024)! } }
			5 { event = Progress{ ...event, current: r.unsigned(~u64(0))! } }
			6 { event = Progress{ ...event, total: r.unsigned(~u64(0))! } }
			else {}
		}
	}
	r.spaces()
	if seen != 127 || r.position != text.len { return error('incomplete or trailing package progress event') }
	event.validate()!
	accepted = true
	return event
}

const progress_keys = ['format', 'phase', 'package', 'repository', 'path', 'current', 'total']

pub fn (mut event Progress) close() {
	unsafe {
		event.phase.free()
		event.package.free()
		event.repository.free()
		event.path.free()
	}
	event = Progress{}
}
