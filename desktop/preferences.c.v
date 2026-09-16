// SPDX-License-Identifier: GPL-2.0-or-later
// Persist a complete desktop settings snapshot in the writable home.
module main

#include <stdio.h>

fn C.mkstemp(template &char) int

fn C.rename(old_path &char, new_path &char) int

fn C.fsync(fd int) int

enum PreferenceFileState {
	loaded
	missing
	invalid
}

fn desktop_preferences_path(home string) string {
	return '${home}/${desktop_preferences_name}'
}

// Nonblocking open plus fstat prevents a FIFO/device at this path from hanging
// startup. The extra byte rejects oversized records instead of valid prefixes.
fn desktop_read_preference_record(path string) (string, PreferenceFileState) {
	fd := C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 {
		return '', if C.errno == C.ENOENT { PreferenceFileState.missing } else { PreferenceFileState.invalid }
	}
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0
		|| (u32(info.st_mode) & u32(C.S_IFMT)) != u32(C.S_IFREG) {
		return '', .invalid
	}
	mut data := [4097]u8{}
	mut total := 0
	mut interruptions := 0
	for total < data.len {
		got := desktop_read(fd, &data[total], u64(data.len - total))
		if got < 0 {
			if C.errno == C.EINTR && interruptions < 4 {
				interruptions++
				continue
			}
			return '', .invalid
		}
		if got == 0 { break }
		total += int(got)
	}
	if total == 0 || total > desktop_preferences_max_bytes {
		return '', .invalid
	}
	return unsafe { (&data[0]).vbytes(total).bytestr() }, .loaded
}

fn desktop_load_preferences(home string) DesktopPreferences {
	if home == '' { return DesktopPreferences{} }
	path := desktop_preferences_path(home)
	defer { unsafe { path.free() } }
	record, state := desktop_read_preference_record(path)
	if state == .loaded {
		defer { unsafe { record.free() } }
		return desktop_parse_preferences(record) or { DesktopPreferences{} }
	}
	// An existing but damaged unified file must not resurrect a stale scale
	// preference. Only a genuinely missing new file permits legacy migration.
	if state != .missing { return DesktopPreferences{} }
	legacy := '${home}/${desktop_legacy_scale_name}'
	defer { unsafe { legacy.free() } }
	old, old_state := desktop_read_preference_record(legacy)
	if old_state != .loaded { return DesktopPreferences{} }
	defer { unsafe { old.free() } }
	scale := match old {
		'1', '1\n' { desktop_scale_100 }
		'2', '2\n' { desktop_scale_200 }
		else { return DesktopPreferences{} }
	}
	p := DesktopPreferences{ scale: scale }
	// Publish the entire new record before removing the legacy file. On a
	// failed migration its original value still applies for this session.
	if !desktop_save_preferences(home, p) {
		eprintln('vinix-desktop: could not migrate desktop settings')
	}
	return p
}

// Only the parent compositor calls this, after applying scale and accepting
// Settings' IPC response. Every write includes ALL preferences. Merely opening
// Settings, clock/device refreshes and rejected scale requests do no I/O.
fn (mut p DesktopPreferences) save_changes(settings Settings, previous_scale int, home string) bool {
	applied := desktop_current_scale()
	next := DesktopPreferences{
		settings: settings
		scale: if applied != previous_scale && desktop_scale_valid(applied) { applied } else { p.scale }
	}
	if next.settings == p.settings && next.scale == p.scale { return true }
	// Remember the live snapshot even after failure, to avoid writes/logging
	// every frame on a read-only home. The next change retries the full state.
	p = next
	return desktop_save_preferences(home, p)
}

fn desktop_preferences_fsync(fd int) bool {
	for _ in 0 .. 4 {
		if C.fsync(fd) == 0 {
			return true
		}
		if C.errno != C.EINTR {
			return false
		}
	}
	return false
}

fn desktop_preferences_sync_directory(home string, file_fd int) bool {
	fd := C.open(&char(home.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if fd < 0 {
		return false
	}
	defer { C.close(fd) }
	if desktop_preferences_fsync(fd) {
		return true
	}
	// Vinix can reject fsync on a directory. Its ARM64 file fsync also drains
	// the block-device caches, so syncing the still-open file after rename
	// flushes the new directory entry there. Do not hide other I/O failures.
	if C.errno == C.EINVAL {
		return desktop_preferences_fsync(file_fd)
	}
	return false
}

// Write and sync a private sibling before publishing it. Failed writes must
// not truncate the last good preference. mkstemp creates mode 0600 with O_EXCL
// and avoids following a pre-existing temporary-file symlink. All allocations,
// descriptors and unpublished temporary files have a single cleanup path.
fn desktop_save_preferences(home string, p DesktopPreferences) bool {
	if home == '' {
		return false
	}
	data := desktop_encode_preferences(p) or { return false }
	defer { unsafe { data.free() } }
	path := desktop_preferences_path(home)
	temporary := '${path}.XXXXXX'
	defer {
		unsafe {
			temporary.free()
			path.free()
		}
	}
	// Interpolation owns this writable buffer; mkstemp replaces its final Xs.
	mut fd := C.mkstemp(&char(temporary.str))
	if fd < 0 {
		return false
	}
	mut published := false
	defer {
		if fd >= 0 {
			C.close(fd)
		}
		if !published {
			C.unlink(&char(temporary.str))
		}
	}
	if C.fcntl(fd, C.F_SETFD, C.FD_CLOEXEC) != 0 {
		return false
	}
	mut total := 0
	mut interruptions := 0
	for total < data.len {
		wrote := desktop_write(fd, unsafe { voidptr(data.str + total) }, u64(data.len - total))
		if wrote < 0 {
			if C.errno == C.EINTR && interruptions < 4 {
				interruptions++
				continue
			}
			return false
		}
		if wrote == 0 {
			return false
		}
		total += int(wrote)
	}
	if !desktop_preferences_fsync(fd) || C.rename(&char(temporary.str), &char(path.str)) != 0 {
		return false
	}
	published = true
	if !desktop_preferences_sync_directory(home, fd) {
		return false
	}
	// A successful unified save is also the end of legacy migration. Never
	// remove the old preference before the new snapshot is durable.
	legacy := '${home}/${desktop_legacy_scale_name}'
	defer { unsafe { legacy.free() } }
	if C.unlink(&char(legacy.str)) == 0 {
		if !desktop_preferences_sync_directory(home, fd) { return false }
	} else if C.errno != C.ENOENT {
		return false
	}
	closed := C.close(fd)
	fd = -1
	return closed == 0
}
