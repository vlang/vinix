// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

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

struct ProgressInput {
	format     int    @[required]
	phase      string @[required]
	package    string @[required]
	repository string @[required]
	path       string @[required]
	current    u64    @[required]
	total      u64    @[required]
}

pub fn (event &Progress) validate() ! {
	if event.format != 1 || event.phase !in ['resolve', 'metadata', 'download', 'verify', 'copy', 'stage', 'activate', 'complete']
		|| (event.package != '' && !identifier(event.package)) || (event.repository != '' && !identifier(event.repository))
		|| !printable(event.path, 1024) || (event.path != '' && (event.path.starts_with('/')
		|| event.path.contains('\\') || event.path.split('/').any(it in ['', '.', '..'])))
		|| (event.total != 0 && event.current > event.total) {
		return error('invalid package progress event')
	}
	if (event.phase in ['download', 'copy'] && (event.package == '' || event.path == ''
		|| event.total > u64(4) * 1024 * 1024 * 1024 || event.current > u64(4) * 1024 * 1024 * 1024))
		|| (event.phase == 'metadata' && (event.repository == '' || event.current > 8 * 1024 * 1024 || event.total != 0))
		|| (event.phase == 'stage' && (event.total > 4096 || event.current > 4096))
		|| (event.phase in ['resolve', 'verify', 'activate'] && (event.current != 0 || event.total != 0))
		|| (event.phase == 'complete' && (event.current != 1 || event.total != 1)) {
		return error('invalid package progress counters')
	}
}

pub fn decode_progress(text string) !Progress {
	if text.len > progress_limit { return error('package progress exceeds its size limit') }
	input := json2.decode[ProgressInput](text, strict: true)!
	mut event := Progress{ format: input.format, phase: input.phase, package: input.package,
		repository: input.repository, path: input.path, current: input.current, total: input.total }
	event.validate() or { event.close(); return err }
	return event
}

pub fn (mut event Progress) close() {
	unsafe {
		event.phase.free()
		event.package.free()
		event.repository.free()
		event.path.free()
	}
	event = Progress{}
}
