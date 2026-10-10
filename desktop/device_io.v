// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Native V seam for bounded device transactions. Tests implement this
// interface directly; production's POSIX implementation lives in .c.v.
module main

enum DeviceError {
	none
	unavailable
	permission
	interrupted
	io
}

// What one directory lists: names only, in fixed storage. /sys shows a
// machine's power supplies as a directory, and a poll that repeats for as
// long as the desktop runs must not allocate to read it.
const device_names_capacity = 8
const device_name_capacity = 32

struct DeviceNames {
mut:
	names [device_names_capacity][device_name_capacity]u8
	lens  [device_names_capacity]int
	count int
}

// add keeps a name with its terminating NUL. Hidden entries, a name too long
// to be kept whole and entries past the capacity are left out rather than cut
// down into some other name.
fn (mut names DeviceNames) add(name []u8) bool {
	if names.count >= device_names_capacity || name.len == 0
		|| name.len >= device_name_capacity || name[0] == `.` {
		return false
	}
	for i, byte in name {
		if byte == 0 || byte == `/` {
			return false
		}
		names.names[names.count][i] = byte
	}
	names.names[names.count][name.len] = 0
	names.lens[names.count] = name.len
	names.count++
	return true
}

interface DeviceIO {
mut:
	open(path string, writable bool) (int, DeviceError)
	read(fd int, mut buffer []u8) (int, DeviceError)
	write(fd int, buffer []u8) (int, DeviceError)
	ioctl(fd int, request u64, mut buffer []u8) DeviceError
	close(fd int) DeviceError
	is_character(fd int) (bool, DeviceError)
	// Whether the file's mode lets anyone write it. /sys gives a file nobody
	// can write a read-only mode, which says so without a write being tried.
	is_writable(fd int) (bool, DeviceError)
	list(path string, mut names DeviceNames) DeviceError
}
