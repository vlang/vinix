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

interface DeviceIO {
mut:
	open(path string, writable bool) (int, DeviceError)
	read(fd int, mut buffer []u8) (int, DeviceError)
	write(fd int, buffer []u8) (int, DeviceError)
	ioctl(fd int, request u64, mut buffer []u8) DeviceError
	close(fd int) DeviceError
	is_character(fd int) (bool, DeviceError)
}
