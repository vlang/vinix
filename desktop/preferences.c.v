// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Persist a complete desktop settings snapshot in the writable home.
module main

import os
import io.util

#include <errno.h>

#include <unistd.h>

// os.File.flush() flushes stdio, not the device. Keep only the durability
// primitive here; opening, reading, writing, renaming and cleanup use vlib.
fn C.fsync(fd int) int

enum PreferenceFileState {
	loaded
	missing
	invalid
}

fn desktop_preferences_path(home string) string {
	return '${home}/${desktop_preferences_name}'
}

// Check ordinary configuration mistakes before the whole-file read. These
// path checks are not a race-free sandbox: the desktop owns its home, and the
// file must not be replaced or grown concurrently with startup.
fn desktop_read_preference_record(path string) (string, PreferenceFileState) {
	info := os.lstat(path) or {
		return '', if err.code() == C.ENOENT { PreferenceFileState.missing } else { PreferenceFileState.invalid }
	}
	if info.get_filetype() != .regular || info.size == 0
		|| info.size > u64(desktop_preferences_max_bytes) {
		return '', .invalid
	}
	record := os.read_file(path) or { return '', .invalid }
	if record.len == 0 || record.len > desktop_preferences_max_bytes {
		unsafe { record.free() }
		return '', .invalid
	}
	return record, .loaded
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
	mut directory := os.open(home) or { return false }
	defer { directory.close() }
	if desktop_preferences_fsync(directory.fd) {
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

// vlib owns file creation and whole-string writes. Publish a complete synced
// sibling rather than truncating the last good snapshot in place.
fn desktop_save_preferences(home string, p DesktopPreferences) bool {
	if home == '' || !os.is_dir(home) {
		return false
	}
	data := desktop_encode_preferences(p) or { return false }
	defer { unsafe { data.free() } }
	path := desktop_preferences_path(home)
	defer { unsafe { path.free() } }
	mut file, temporary := util.temp_file(path: home, pattern: '${desktop_preferences_name}.*') or {
		return false
	}
	mut published := false
	defer {
		file.close()
		if !published {
			os.rm(temporary) or {}
		}
		unsafe { temporary.free() }
	}
	// Unbuffered writes report their errors here, not in File.close(), whose
	// API has no result. write_string handles short/interrupted writes in vlib.
	file.set_unbuffered()
	file.write_string(data) or { return false }
	if !desktop_preferences_fsync(file.fd) {
		return false
	}
	// Use the exact-destination API: os.rename() would move the file INSIDE
	// an existing directory at `path`, instead of rejecting that destination.
	os.rename_dir(temporary, path) or { return false }
	published = true
	if !desktop_preferences_sync_directory(home, file.fd) {
		return false
	}
	// Do not delete a directory accidentally placed at the legacy path.
	legacy := '${home}/${desktop_legacy_scale_name}'
	defer { unsafe { legacy.free() } }
	info := os.lstat(legacy) or { return err.code() == C.ENOENT }
	if info.get_filetype() == .directory {
		return false
	}
	os.rm(legacy) or { return false }
	return desktop_preferences_sync_directory(home, file.fd)
}
