// SPDX-License-Identifier: GPL-2.0-or-later
module nativecache

import os

#include <unistd.h>
fn C.access(&char, int) int

// The pinned standalone ART selects a present XDG_CACHE_HOME before HOME,
// including an empty value. Reject unusable settings rather than preparing a
// different cache from the one ART will use.
fn directory() !string {
	if cache := os.getenv_opt('XDG_CACHE_HOME') {
		return selected_directory(cache, 'XDG_CACHE_HOME', '/art/arm64')
	}
	if home := os.getenv_opt('HOME') {
		return selected_directory(home, 'HOME', '/.cache/art/arm64')
	}
	return error('ART cache requires XDG_CACHE_HOME or HOME')
}

fn selected_directory(base string, name string, suffix string) !string {
	if base == '' || !os.is_abs_path(base) || base.contains('\x00') {
		return error('ART cache requires a nonempty absolute ${name}')
	}
	return base + suffix
}

// Use POSIX separators, as ART does. os.mkdir_all also treats backslashes as
// separators, although they are legal characters in a Unix cache path.
fn ensure_directory(path string) ! {
	if os.is_dir(path) { return }
	if os.exists(path) { return error('ART cache path is not a directory: ${path}') }
	position := path.last_index('/') or { return error('ART cache path must be absolute') }
	parent := if position == 0 { '/' } else { path[..position] }
	ensure_directory(parent)!
	os.mkdir(path, mode: 0o700) or {
		if !os.is_dir(path) { return error('cannot create ART cache directory ${path}: ${err}') }
	}
}

// Call after selecting the application's Unix credentials and environment.
// ART's cache creation is not recursive and its oat-file path assumes this
// hierarchy exists. Never repair ownership or permissions on existing paths.
pub fn prepare() ! {
	path := directory()!
	ensure_directory(path)!
	if C.access(&char(path.str), 7) != 0 {
		return error('ART cache directory is not readable, writable and searchable: ${path}')
	}
}
