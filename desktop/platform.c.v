// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// V implementation of the desktop's POSIX boundary. Only declarations and
// constants come from libc headers; there are no custom C function bodies.
// Import vlib's declarations rather than inventing incompatible duplicates.
module main

import os as _
import time as _
import term.termios

#include <dirent.h>

#include <errno.h>

#include <fcntl.h>

#include <sys/ioctl.h>

#include <sys/mman.h>

#include <sys/stat.h>

#include <sys/wait.h>

#include <signal.h>

#include <termios.h>

#include <time.h>

#include <unistd.h>

fn C.fstat(fd int, buf &C.stat) int

fn C.mmap(base voidptr, length usize, prot int, flags int, fd int, offset i64) voidptr

fn C.munmap(base voidptr, length usize) int

// Match vlib/net's declaration if a native application also imports it.
fn C.fcntl(fd int, cmd int, arg ...voidptr) int

fn desktop_open_rw(path string) int {
	return C.open(&char(path.str), C.O_RDWR)
}

fn desktop_open_ro_nonblock(path string) int {
	return C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK)
}

fn desktop_close(fd int) int {
	return C.close(fd)
}

fn desktop_read(fd int, buffer voidptr, count u64) i64 {
	// vlib's POSIX read declaration returns int. Our bounded device packets
	// are tiny; refuse a count that could make that result truncate.
	if count > 0x7fffffff {
		return -1
	}
	return i64(C.read(fd, buffer, usize(count)))
}

fn desktop_ioctl(fd int, request u64, argument voidptr) int {
	return termios.ioctl(fd, request, argument)
}

fn desktop_mmap_shared(fd int, length u64) voidptr {
	mapping := C.mmap(unsafe { nil }, usize(length), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	if mapping == C.MAP_FAILED {
		return unsafe { nil }
	}
	return mapping
}

fn desktop_munmap(base voidptr, length u64) int {
	return C.munmap(base, usize(length))
}

struct TerminalState {
mut:
	attributes         termios.Termios
	flags              int = -1
	restore_attributes bool
	restore_flags      bool
}

fn terminal_input_raw(saved termios.Termios) termios.Termios {
	mut raw := saved
	// Cast each flag before combining them. C.ECHO carries the C header's own
	// type, which is not int on every platform, and an uncast three-way `or`
	// leaves the checker with no type for the result at all — which is what
	// stopped these files building on a macOS host, and with them every test
	// that stages them.
	lflags := termios.flag(int(C.ICANON) | int(C.ECHO) | int(C.ISIG))
	raw.c_lflag &= termios.invert(lflags)
	raw.c_cc[C.VMIN] = 0
	raw.c_cc[C.VTIME] = 0
	return raw
}

fn desktop_terminal_raw(fd int) TerminalState {
	mut saved := TerminalState{}
	if termios.tcgetattr(fd, mut saved.attributes) == 0 {
		mut raw := terminal_input_raw(saved.attributes)
		saved.restore_attributes = termios.tcsetattr(fd, C.TCSANOW, mut raw) == 0
	}
	saved.flags = C.fcntl(fd, C.F_GETFL)
	if saved.flags >= 0 {
		// Preserve all existing descriptor flags, and restore them on exit.
		saved.restore_flags = C.fcntl(fd, C.F_SETFL, saved.flags | C.O_NONBLOCK) == 0
	}
	return saved
}

fn desktop_terminal_restore(fd int, mut saved TerminalState) {
	if saved.restore_attributes {
		termios.tcsetattr(fd, C.TCSANOW, mut saved.attributes)
		saved.restore_attributes = false
	}
	if saved.restore_flags {
		C.fcntl(fd, C.F_SETFL, saved.flags)
		saved.restore_flags = false
	}
}

fn desktop_realtime() (i64, i64) {
	mut stamp := C.timespec{}
	if C.clock_gettime(C.CLOCK_REALTIME, &stamp) != 0 {
		return -1, 0
	}
	return stamp.tv_sec, stamp.tv_nsec
}

// UINT64_MAX is an explicit failed-clock sentinel, shared by both clients.
fn desktop_monotonic_ms() u64 {
	mut stamp := C.timespec{}
	if C.clock_gettime(C.CLOCK_MONOTONIC, &stamp) != 0 || stamp.tv_sec < 0
		|| stamp.tv_nsec < 0 || stamp.tv_nsec >= 1_000_000_000
		|| u64(stamp.tv_sec) > (~u64(0) - 999) / 1000 {
		return ~u64(0)
	}
	return u64(stamp.tv_sec) * 1000 + u64(stamp.tv_nsec) / 1_000_000
}

// A positive frame interval must always produce a real sleep, even when the
// render already consumed the budget. On Vinix/ARM64 the blocking scheduler
// path also pumps polled console devices, including the shared Apple
// keyboard/touchpad transport. Returning zero for an over-budget drag can
// therefore starve the input needed to end that same drag.
fn desktop_frame_wait_ms(elapsed i64, interval i64) i64 {
	if interval <= 0 {
		return 0
	}
	remaining := interval - elapsed
	return if remaining > 0 { remaining } else { 1 }
}

fn desktop_sleep_ms(milliseconds i64) {
	if milliseconds <= 0 {
		return
	}
	mut request := C.timespec{ tv_sec: milliseconds / 1000, tv_nsec: (milliseconds % 1000) * 1_000_000 }
	mut remainder := C.timespec{}
	for _ in 0 .. 4 {
		if C.nanosleep(&request, &remainder) == 0 || C.errno != C.EINTR {
			return
		}
		request = remainder
	}
}

// Read a whole file into a caller-supplied buffer, returning the byte count or
// -1. The desktop only ever does this for a wallpaper, whose size it has
// already asked for with desktop_stat().
fn desktop_read_file(path string, buffer voidptr, max u64) i64 {
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return -1
	}
	mut total := u64(0)
	for total < max {
		got := desktop_read(fd, unsafe { voidptr(&u8(buffer) + total) }, max - total)
		if got < 0 {
			C.close(fd)
			return -1
		}
		if got == 0 {
			break
		}
		total += u64(got)
	}
	C.close(fd)
	return i64(total)
}

// Replace a regular file with a caller-supplied buffer. The text editor is
// deliberately built on this small POSIX boundary instead of importing os:
// the desktop already has to control exactly which libc surface is available
// in the static Vinix build, and a whole-file save is all the editor needs.
fn desktop_write_file(path string, buffer voidptr, count u64) bool {
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_TRUNC, 0o644)
	if fd < 0 {
		return false
	}
	mut total := u64(0)
	for total < count {
		wrote := desktop_write(fd, unsafe { voidptr(&u8(buffer) + total) }, count - total)
		if wrote < 0 {
			if C.errno == C.EINTR {
				continue
			}
			C.close(fd)
			return false
		}
		if wrote == 0 {
			C.close(fd)
			return false
		}
		total += u64(wrote)
	}
	return C.close(fd) == 0
}

// A child process and the two pipes the terminal talks to it through.
struct SpawnedShell {
	pid        int
	to_child   int
	from_child int
}

// Keep the built-in terminal on the same command path as the full ARM64
// userland. In particular, the native GCC driver is deliberately installed in
// its toolchain prefix rather than /usr/bin.
const desktop_command_path = '/aarch64-linux-musl-native/bin:/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin'

enum ExternalProgramResult {
	success
	unavailable
	spawn_failed
	wait_failed
	failed
}

// Run a framebuffer application as a child of the desktop and wait until it
// gives the display back. The caller closes the desktop's device descriptors
// first; inheriting the console is intentional, as Xorg uses it for its VT.
fn desktop_run_external(path string) ExternalProgramResult {
	if path == '' || C.access(&char(path.str), C.X_OK) != 0 {
		return .unavailable
	}

	argv := [&char(path.str), &char(unsafe { nil })]
	path_entry := 'PATH=${desktop_command_path}'
	envp := [&char(path_entry.str), c'HOME=/root', c'TERM=linux', c'USER=root', c'LOGNAME=root',
		c'SHELL=/bin/busybox', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
		c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri',
		c'SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt', &char(unsafe { nil })]

	pid := C.fork()
	if pid < 0 {
		return .spawn_failed
	}
	if pid == 0 {
		C.execve(&char(path.str), argv.data, envp.data)
		C._exit(127)
	}

	mut status := 0
	for {
		waited := C.waitpid(pid, &status, 0)
		if waited == pid {
			return if status == 0 { .success } else { .failed }
		}
		if waited < 0 && C.errno == C.EINTR {
			continue
		}
		return .wait_failed
	}
	return .wait_failed
}

// Start a shell for the terminal.
//
// Vinix has no pseudo-terminals, so the child is given plain pipes. It sees
// them as its stdin, stdout and stderr, and because they are not a terminal it
// neither echoes what is typed nor prints a prompt — the terminal does both
// itself.
//
// from_child comes back non-blocking, so a compositor polling it once a frame
// never stalls.
fn desktop_spawn_shell(path string, arg string) ?SpawnedShell {
	mut in_pipe := [2]int{}
	mut out_pipe := [2]int{}
	if C.pipe(&in_pipe[0]) != 0 {
		return none
	}
	if C.pipe(&out_pipe[0]) != 0 {
		C.close(in_pipe[0])
		C.close(in_pipe[1])
		return none
	}

	// Built before the fork. Between fork and execve the child may call only
	// async-signal-safe functions, which allocating is not.
	argv := [&char(path.str), &char(arg.str), &char(unsafe { nil })]
	path_entry := 'PATH=${desktop_command_path}'
	envp := [&char(path_entry.str), c'HOME=/root', c'TERM=dumb', c'USER=root', c'LOGNAME=root',
		c'SHELL=/bin/busybox', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
		c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri',
		c'SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt', &char(unsafe { nil })]

	pid := C.fork()
	if pid < 0 {
		C.close(in_pipe[0])
		C.close(in_pipe[1])
		C.close(out_pipe[0])
		C.close(out_pipe[1])
		return none
	}
	if pid == 0 {
		C.dup2(in_pipe[0], 0)
		C.dup2(out_pipe[1], 1)
		C.dup2(out_pipe[1], 2)
		C.close(in_pipe[0])
		C.close(in_pipe[1])
		C.close(out_pipe[0])
		C.close(out_pipe[1])
		C.execve(&char(path.str), argv.data, envp.data)
		C._exit(127)
	}

	C.close(in_pipe[0])
	C.close(out_pipe[1])
	C.fcntl(out_pipe[0], C.F_SETFL, C.O_NONBLOCK)
	return SpawnedShell{
		pid: pid
		to_child: in_pipe[1]
		from_child: out_pipe[0]
	}
}

fn desktop_write(fd int, buffer voidptr, count u64) i64 {
	// vlib's POSIX write declaration returns int, as read's does. A terminal
	// only ever sends a typed line; refuse a count that could truncate.
	if count > 0x7fffffff {
		return -1
	}
	return i64(C.write(fd, buffer, usize(count)))
}

// Exact pipe I/O for compositor/application messages. Unlike device reads,
// pipes may legally return a short count; a protocol frame is complete only
// after every byte has crossed.
fn desktop_read_all(fd int, buffer voidptr, count u64) bool {
	mut done := u64(0)
	for done < count {
		got := desktop_read(fd, unsafe { voidptr(&u8(buffer) + done) }, count - done)
		if got > 0 {
			done += u64(got)
			continue
		}
		if got < 0 && C.errno == C.EINTR {
			continue
		}
		return false
	}
	return true
}

fn desktop_write_all(fd int, buffer voidptr, count u64) bool {
	mut done := u64(0)
	for done < count {
		wrote := desktop_write(fd, unsafe { voidptr(&u8(buffer) + done) }, count - done)
		if wrote > 0 {
			done += u64(wrote)
			continue
		}
		if wrote < 0 && C.errno == C.EINTR {
			continue
		}
		return false
	}
	return true
}

fn desktop_set_cloexec(fd int, enabled bool) bool {
	flags := C.fcntl(fd, C.F_GETFD)
	if flags < 0 {
		return false
	}
	next := if enabled { flags | C.FD_CLOEXEC } else { flags & ~C.FD_CLOEXEC }
	return C.fcntl(fd, C.F_SETFD, next) == 0
}

fn desktop_ignore_broken_pipe() {
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
}

// A native application is another invocation of the desktop executable via a
// per-app symlink. Vinix records the exec path as the process name, so these
// are distinct `vinix-files`, `vinix-terminal`, ... processes even though the
// immutable program image is shared on disk.
struct SpawnedAppProcess {
	pid        int
	to_child   int
	from_child int
}

fn desktop_spawn_app(path string, app_name string, tz_offset i64) ?SpawnedAppProcess {
	if C.access(&char(path.str), C.X_OK) != 0 {
		return none
	}
	mut request := [2]int{}
	mut response := [2]int{}
	if C.pipe(&request[0]) != 0 {
		return none
	}
	if C.pipe(&response[0]) != 0 {
		C.close(request[0])
		C.close(request[1])
		return none
	}
	desktop_set_cloexec(request[0], true)
	desktop_set_cloexec(request[1], true)
	desktop_set_cloexec(response[0], true)
	desktop_set_cloexec(response[1], true)

	mode_arg := '--vinix-app=${app_name}'
	request_arg := '--request-fd=${request[0]}'
	response_arg := '--response-fd=${response[1]}'
	tz_arg := '--app-tz=${tz_offset}'
	argv := [&char(path.str), &char(mode_arg.str), &char(request_arg.str), &char(response_arg.str),
		&char(tz_arg.str), &char(unsafe { nil })]
	path_entry := 'PATH=${desktop_command_path}'
	envp := [&char(path_entry.str), c'HOME=/root', c'TERM=dumb', c'USER=root', c'LOGNAME=root',
		c'SHELL=/bin/busybox', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
		c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri',
		c'SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt', &char(unsafe { nil })]

	pid := C.fork()
	if pid < 0 {
		C.close(request[0])
		C.close(request[1])
		C.close(response[0])
		C.close(response[1])
		unsafe {
			mode_arg.free()
			request_arg.free()
			response_arg.free()
			tz_arg.free()
			path_entry.free()
			argv.free()
			envp.free()
		}
		return none
	}
	if pid == 0 {
		// Do not lend the app the compositor's framebuffer, pointer, or any
		// existing app channels. The two protocol ends are the only descriptors
		// above stderr that survive exec.
		for fd := 3; fd < 4096; fd++ {
			if fd != request[0] && fd != response[1] {
				C.close(fd)
			}
		}
		desktop_set_cloexec(request[0], false)
		desktop_set_cloexec(response[1], false)
		C.execve(&char(path.str), argv.data, envp.data)
		C._exit(127)
	}

	C.close(request[0])
	C.close(response[1])
	unsafe {
		mode_arg.free()
		request_arg.free()
		response_arg.free()
		tz_arg.free()
		path_entry.free()
		argv.free()
		envp.free()
	}
	return SpawnedAppProcess{
		pid: pid
		to_child: request[1]
		from_child: response[0]
	}
}

fn desktop_wait_child(pid int) {
	if pid <= 0 {
		return
	}
	mut status := 0
	for {
		waited := C.waitpid(pid, &status, 0)
		if waited == pid || (waited < 0 && C.errno != C.EINTR) {
			return
		}
	}
}

fn desktop_terminate_child(pid int) {
	if pid <= 0 {
		return
	}
	C.kill(pid, C.SIGTERM)
	desktop_wait_child(pid)
}

// True once the child has exited, so the terminal can say so.
fn desktop_child_exited(pid int) bool {
	mut status := 0
	return C.waitpid(pid, &status, C.WNOHANG) == pid
}

fn desktop_opendir(path string) voidptr {
	return C.opendir(&char(path.str))
}

// Keep the file browser's bounded iteration without requiring a copied
// dirent layout. vlib declares d_name; file type is obtained by stat below.
fn desktop_readdir(dir voidptr, mut name []u8) bool {
	if name.len == 0 {
		return false
	}
	entry := C.readdir(dir)
	if entry == unsafe { nil } {
		return false
	}
	mut i := 0
	for i + 1 < name.len && i < 255 && entry.d_name[i] != 0 {
		name[i] = u8(entry.d_name[i])
		i++
	}
	name[i] = 0
	return true
}

fn desktop_closedir(dir voidptr) {
	if dir != unsafe { nil } { C.closedir(dir) }
}

struct DesktopFileInfo {
	size   u64
	is_dir bool
}

fn desktop_stat(path string) ?DesktopFileInfo {
	mut info := C.stat{}
	if unsafe { C.stat(&char(path.str), &info) } != 0 {
		return none
	}
	return DesktopFileInfo{
		size: u64(info.st_size)
		is_dir: (u32(info.st_mode) & u32(C.S_IFMT)) == u32(C.S_IFDIR)
	}
}

struct PosixDeviceIO {}

fn device_errno(value int) DeviceError {
	return match value {
		C.ENOENT, C.ENODEV, C.ENXIO { .unavailable }
		C.EACCES, C.EPERM, C.EROFS { .permission }
		C.EINTR { .interrupted }
		else { .io }
	}
}

fn (mut io PosixDeviceIO) open(path string, writable bool) (int, DeviceError) {
	mode := if writable { C.O_RDWR } else { C.O_RDONLY }
	fd := C.open(&char(path.str), mode | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 {
		return fd, device_errno(C.errno)
	}
	return fd, DeviceError.none
}

fn (mut io PosixDeviceIO) read(fd int, mut buffer []u8) (int, DeviceError) {
	count := C.read(fd, buffer.data, usize(buffer.len))
	if count < 0 {
		return count, device_errno(C.errno)
	}
	return count, DeviceError.none
}

fn (mut io PosixDeviceIO) write(fd int, buffer []u8) (int, DeviceError) {
	count := C.write(fd, buffer.data, usize(buffer.len))
	if count < 0 {
		return count, device_errno(C.errno)
	}
	return count, DeviceError.none
}

fn (mut io PosixDeviceIO) ioctl(fd int, request u64, mut buffer []u8) DeviceError {
	result := if buffer.len > 0 {
		desktop_ioctl(fd, request, buffer.data)
	} else {
		desktop_ioctl(fd, request, unsafe { nil })
	}
	if result < 0 {
		return device_errno(C.errno)
	}
	return .none
}

fn (mut io PosixDeviceIO) close(fd int) DeviceError {
	if C.close(fd) < 0 {
		return device_errno(C.errno)
	}
	return .none
}

fn (mut io PosixDeviceIO) is_character(fd int) (bool, DeviceError) {
	mut info := C.stat{}
	if C.fstat(fd, &info) < 0 {
		return false, device_errno(C.errno)
	}
	return (u32(info.st_mode) & u32(C.S_IFMT)) == u32(C.S_IFCHR), DeviceError.none
}
