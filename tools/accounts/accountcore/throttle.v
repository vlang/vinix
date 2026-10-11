// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What slows a guesser down besides the cost of one check: after a few
// wrong passwords for an account, further tries have to wait, twice as long
// each time, up to a ceiling. An account is never locked for good by wrong
// guesses -- that would let anyone at the keyboard lock its owner out.
//
// The count is kept per account in a directory only root can read. The
// record is the wall-clock time of the last failure and the number of
// failures in a row; a time that lies in the future (the clock was set back)
// counts as now.
module accountcore

import os

pub const throttle_directory = '/run/vinix/auth/failures'

// Wrong passwords before any wait at all.
pub const free_attempts = 3
// The first wait, and the longest one.
pub const first_wait_seconds = i64(2)
pub const longest_wait_seconds = i64(300)
// After this long without a failure the count starts again.
pub const forget_seconds = i64(3600)

pub struct Failures {
pub:
	count int
	last  i64 // seconds since 1970
}

pub struct Throttle {
pub:
	directory string = throttle_directory
}

// How long a caller must still wait before the next try is looked at.
pub fn wait_for(failures Failures, now i64) i64 {
	if failures.count < free_attempts {
		return 0
	}
	last := if failures.last > now { now } else { failures.last }
	if now - last >= forget_seconds {
		return 0
	}
	mut wait := first_wait_seconds
	mut step := failures.count - free_attempts
	for step > 0 && wait < longest_wait_seconds {
		wait *= 2
		step--
	}
	if wait > longest_wait_seconds {
		wait = longest_wait_seconds
	}
	remaining := last + wait - now
	return if remaining > 0 { remaining } else { 0 }
}

fn (t Throttle) path(name string) !string {
	// The name comes from whoever is trying to log in. It becomes a file
	// name only if it could be an account's.
	if !valid_name(name) {
		return error('invalid name')
	}
	return os.join_path(t.directory, name)
}

pub fn (t Throttle) read(name string, now i64) Failures {
	path := t.path(name) or { return Failures{} }
	text := os.read_file(path) or { return Failures{} }
	fields := text.trim_space().split(' ')
	if fields.len != 2 {
		return Failures{}
	}
	count := fields[0].int()
	last := fields[1].i64()
	if count <= 0 || count > 1_000_000 || last <= 0 {
		return Failures{}
	}
	if now - last >= forget_seconds {
		return Failures{}
	}
	return Failures{
		count: count
		last:  if last > now { now } else { last }
	}
}

pub fn (t Throttle) record_failure(name string, now i64) {
	path := t.path(name) or { return }
	previous := t.read(name, now)
	os.mkdir_all(t.directory, mode: 0o700) or {}
	os.chmod(t.directory, 0o700) or {}
	temporary := '${path}.new'
	os.write_file(temporary, '${previous.count + 1} ${now}\n') or { return }
	os.chmod(temporary, 0o600) or {}
	os.rename(temporary, path) or { os.rm(temporary) or {} }
}

pub fn (t Throttle) record_success(name string) {
	path := t.path(name) or { return }
	os.rm(path) or {}
}
