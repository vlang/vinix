// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import term.termios

// Only system declarations; the implementation under test is platform.c.v.
#include <stdlib.h>

fn C.posix_openpt(flags int) int

fn C.grantpt(fd int) int

fn C.unlockpt(fd int) int

fn C.ptsname(fd int) &char

fn test_platform_file_stat_directory_read_and_shared_mapping() {
	root := os.join_path(os.temp_dir(), 'vinix-v-platform-${os.getpid()}')
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'sample')
	os.write_file(path, 'hello')!
	info := desktop_stat(path)?
	assert info.size == 5 && !info.is_dir
	assert desktop_stat(root)?.is_dir
	assert desktop_stat(os.join_path(root, 'absent')) == none
	fd := desktop_open_rw(path)
	assert fd >= 0
	mut data := [5]u8{}
	assert desktop_read(fd, &data[0], 5) == 5
	assert data == [u8(`h`), `e`, `l`, `l`, `o`]!
	mapping := desktop_mmap_shared(fd, 5)
	assert mapping != unsafe { nil }
	unsafe { (&u8(mapping))[0] = `H` }
	assert desktop_munmap(mapping, 5) == 0
	assert desktop_close(fd) == 0
	assert os.read_file(path)! == 'Hello'
	assert desktop_mmap_shared(-1, 0) == unsafe { nil }
	dir := desktop_opendir(root)
	assert dir != unsafe { nil }
	mut names := [256]u8{}
	mut buffer := unsafe { (&names[0]).vbytes(names.len) }
	mut seen := false
	for desktop_readdir(dir, mut buffer) {
		// Verify writes reached the original fixed array, not a slice copy.
		name := unsafe { cstring_to_vstring(&char(&names[0])) }
		if name == 'sample' {
			seen = true
		}
	}
	desktop_closedir(dir)
	assert seen
}

fn test_platform_character_device_flags_and_io() {
	mut io := PosixDeviceIO{}
	fd, result := io.open('/dev/null', true)
	assert fd >= 0 && result == .none
	flags := C.fcntl(fd, C.F_GETFL)
	assert flags & C.O_NONBLOCK != 0
	assert flags & C.O_ACCMODE == C.O_RDWR
	assert C.fcntl(fd, C.F_GETFD) & C.FD_CLOEXEC != 0
	character, stat_result := io.is_character(fd)
	assert character && stat_result == .none
	written, write_result := io.write(fd, 'test'.bytes())
	assert written == 4 && write_result == .none
	mut data := []u8{len: 4}
	read, read_result := io.read(fd, mut data)
	assert read == 0 && read_result == .none
	assert io.close(fd) == .none
	assert device_errno(C.ENOENT) == .unavailable
	assert device_errno(C.ENODEV) == .unavailable
	assert device_errno(C.ENXIO) == .unavailable
	assert device_errno(C.EACCES) == .permission
	assert device_errno(C.EPERM) == .permission
	assert device_errno(C.EROFS) == .permission
	assert device_errno(C.EINTR) == .interrupted
	assert device_errno(C.EIO) == .io
}

fn test_platform_terminal_raw_mode_and_restoration() {
	master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
	assert master >= 0
	defer { desktop_close(master) }
	assert C.grantpt(master) == 0 && C.unlockpt(master) == 0
	name := C.ptsname(master)
	assert name != unsafe { nil }
	fd := C.open(name, C.O_RDWR | C.O_NOCTTY)
	assert fd >= 0
	defer { desktop_close(fd) }
	mut original := termios.Termios{}
	assert termios.tcgetattr(fd, mut original) == 0
	flags := C.fcntl(fd, C.F_GETFL)
	mut saved := desktop_terminal_raw(fd)
	defer { desktop_terminal_restore(fd, mut saved) }
	assert saved.restore_attributes && saved.restore_flags
	mut raw := termios.Termios{}
	assert termios.tcgetattr(fd, mut raw) == 0
	// Cast before combining, as terminal_input_raw does: the flags do not all
	// carry the same C type on every host.
	assert raw.c_lflag & termios.flag(int(C.ICANON) | int(C.ECHO) | int(C.ISIG)) == 0
	assert raw.c_cc[C.VMIN] == 0 && raw.c_cc[C.VTIME] == 0
	assert C.fcntl(fd, C.F_GETFL) == flags | C.O_NONBLOCK
	desktop_terminal_restore(fd, mut saved)
	mut restored := termios.Termios{}
	assert termios.tcgetattr(fd, mut restored) == 0
	// PENDIN is the tty driver's own bookkeeping, not a setting: macOS raises
	// it whenever canonical mode is switched back on, however faithfully the
	// saved flags are written back. Compare the settings, not that.
	settings := termios.invert(termios.flag(int(C.PENDIN)))
	assert restored.c_lflag & settings == original.c_lflag & settings
	assert restored.c_cc[C.VMIN] == original.c_cc[C.VMIN]
	assert restored.c_cc[C.VTIME] == original.c_cc[C.VTIME]
	assert C.fcntl(fd, C.F_GETFL) == flags
	assert !saved.restore_attributes && !saved.restore_flags
}

fn test_platform_clocks_and_sleep() {
	seconds, nanoseconds := desktop_realtime()
	assert seconds > 0 && nanoseconds >= 0 && nanoseconds < 1_000_000_000
	start := desktop_monotonic_ms()
	assert start != ~u64(0)
	desktop_sleep_ms(2)
	end := desktop_monotonic_ms()
	assert end != ~u64(0) && end >= start
	desktop_sleep_ms(0)
	desktop_sleep_ms(-1)
}
