// SPDX-License-Identifier: GPL-2.0-or-later
// Persist the native desktop's scale in its writable home, not the initramfs.
// Keep POSIX I/O separate from scale.v's requested/applied state and policy.
module main

#include <stdio.h>

fn C.mkstemp(template &char) int

fn C.rename(old_path &char, new_path &char) int

fn C.fsync(fd int) int

const desktop_scale_preference_name = '.vinix-desktop-scale'

fn desktop_scale_preference_path(home string) string {
	return '${home}/${desktop_scale_preference_name}'
}

// Loading is an override, not a new request to persist. In particular, a first
// boot must not save the geometry default and pin it for a different display.
fn desktop_configure_saved_scale(width int, height int, home string) int {
	fallback := desktop_configure_scale(width, height)
	scale := desktop_load_scale_preference(home) or { return fallback }
	desktop_request_scale(scale)
	desktop_commit_scale(scale)
	return scale
}

// Called only by the compositor, after apply_requested_scale(). Settings can
// run in a child process: persisting the request there would save a value that
// the compositor has not yet accepted. No-op and rejected requests do no I/O.
fn desktop_save_scale_change(previous_scale int, home string) bool {
	scale := desktop_current_scale()
	if scale == previous_scale {
		return true
	}
	return desktop_save_scale_preference(home, scale)
}

// The entire record is "1" or "2", optionally followed by a newline. Read one
// extra byte to reject trailing garbage rather than accepting a valid prefix.
// Nonblocking open plus fstat keeps a damaged path (including a FIFO) from
// hanging desktop startup. The record never requires an unbounded allocation.
fn desktop_load_scale_preference(home string) ?int {
	if home == '' {
		return none
	}
	path := desktop_scale_preference_path(home)
	defer { unsafe { path.free() } }
	fd := C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 {
		return none
	}
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0
		|| (u32(info.st_mode) & u32(C.S_IFMT)) != u32(C.S_IFREG) {
		return none
	}
	mut data := [3]u8{}
	mut total := 0
	mut interruptions := 0
	for total < data.len {
		got := desktop_read(fd, &data[total], u64(data.len - total))
		if got < 0 {
			if C.errno == C.EINTR && interruptions < 4 {
				interruptions++
				continue
			}
			return none
		}
		if got == 0 {
			break
		}
		total += int(got)
	}
	if (total != 1 && total != 2) || (total == 2 && data[1] != `\n`) {
		return none
	}
	if data[0] == `1` {
		return desktop_scale_100
	}
	if data[0] == `2` {
		return desktop_scale_200
	}
	return none
}

fn desktop_scale_fsync(fd int) bool {
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

fn desktop_scale_sync_directory(home string, file_fd int) bool {
	fd := C.open(&char(home.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if fd < 0 {
		return false
	}
	defer { C.close(fd) }
	if desktop_scale_fsync(fd) {
		return true
	}
	// Vinix can reject fsync on a directory. Its ARM64 file fsync also drains
	// the block-device caches, so syncing the still-open file after rename
	// flushes the new directory entry there. Do not hide other I/O failures.
	if C.errno == C.EINVAL {
		return desktop_scale_fsync(file_fd)
	}
	return false
}

// Write and sync a private sibling before publishing it. Failed writes must
// not truncate the last good preference. mkstemp creates mode 0600 with O_EXCL
// and avoids following a pre-existing temporary-file symlink. All allocations,
// descriptors and unpublished temporary files have a single cleanup path.
fn desktop_save_scale_preference(home string, scale int) bool {
	if home == '' || !desktop_scale_valid(scale) {
		return false
	}
	path := desktop_scale_preference_path(home)
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
	mut data := [2]u8{}
	data[0] = if scale == desktop_scale_100 { `1` } else { `2` }
	data[1] = `\n`
	mut total := 0
	mut interruptions := 0
	for total < data.len {
		wrote := desktop_write(fd, &data[total], u64(data.len - total))
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
	if !desktop_scale_fsync(fd) || C.rename(&char(temporary.str), &char(path.str)) != 0 {
		return false
	}
	published = true
	if !desktop_scale_sync_directory(home, fd) {
		return false
	}
	closed := C.close(fd)
	fd = -1
	return closed == 0
}
