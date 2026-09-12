// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// V implementation of the desktop's POSIX boundary. Only declarations and
// constants come from libc headers; there are no custom C function bodies.
// Import vlib's declarations rather than inventing incompatible duplicates.
module main

#flag -I @VMODROOT

import os as _
import time as _
import term.termios

#include <dirent.h>

#include <errno.h>

#include <fcntl.h>

#include <poll.h>

#include <sys/ioctl.h>

#include <sys/mman.h>

#include <sys/reboot.h>

#include <sys/stat.h>

#include <sys/wait.h>

#include <signal.h>

#include <stdlib.h>

#include <termios.h>

#include <time.h>

#include <unistd.h>

#include "libc_compat.h"

fn C.fstat(fd int, buf &C.stat) int

fn C.lstat(path &char, buf &C.stat) int

fn C.posix_openpt(flags int) int

fn C.grantpt(fd int) int

fn C.unlockpt(fd int) int

fn C.ptsname(fd int) &char

fn C.setsid() int

fn C.mmap(base voidptr, length usize, prot int, flags int, fd int, offset i64) voidptr

fn C.munmap(base voidptr, length usize) int

fn C.lseek(fd int, offset i64, whence int) i64

fn C.unlink(path &char) int

struct C.pollfd {
	fd      int
	events  i16
	revents i16
}

fn C.poll(fds &C.pollfd, count usize, timeout int) int

// Match vlib/net's declaration if a native application also imports it.
fn C.fcntl(fd int, cmd int, arg ...voidptr) int

// reboot(2) takes an int; the three commands it accepts are spelled as
// unsigned values because two of them do not fit a positive int.
fn C.reboot(command u32) int

fn C.sync()

fn desktop_open_rw(path string) int {
	return C.open(&char(path.str), C.O_RDWR)
}

fn desktop_create_truncated(path string) int {
	return C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_TRUNC, 0o644)
}

fn desktop_open_ro_nonblock(path string) int {
	return C.open(&char(path.str), C.O_RDONLY | C.O_NONBLOCK)
}

fn desktop_close(fd int) int {
	return C.close(fd)
}

fn desktop_seek_start(fd int, offset u64) bool {
	if offset > u64(0x7fffffffffffffff) {
		return false
	}
	return C.lseek(fd, i64(offset), C.SEEK_SET) == i64(offset)
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
	if mapping == voidptr(C.MAP_FAILED) {
		return unsafe { nil }
	}
	return mapping
}

fn desktop_mmap_readonly(fd int, length u64) voidptr {
	mapping := C.mmap(unsafe { nil }, usize(length), C.PROT_READ, C.MAP_SHARED, fd, 0)
	if mapping == voidptr(C.MAP_FAILED) {
		return unsafe { nil }
	}
	return mapping
}

fn desktop_munmap(base voidptr, length u64) int {
	return C.munmap(base, usize(length))
}

fn desktop_unlink(path string) int {
	return C.unlink(&char(path.str))
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

// Wait until either input source has something new, or until the compositor's
// next housekeeping deadline. Both descriptors remain nonblocking: readiness
// only parks this thread efficiently instead of changing read semantics.
fn desktop_wait_for_input(pointer_fd int, keyboard_fd int, milliseconds i64) {
	if milliseconds <= 0 {
		return
	}
	mut fds := [2]C.pollfd{}
	mut count := 0
	if pointer_fd >= 0 {
		fds[count] = C.pollfd{
			fd: pointer_fd
			events: i16(C.POLLIN)
		}
		count++
	}
	if keyboard_fd >= 0 {
		fds[count] = C.pollfd{
			fd: keyboard_fd
			events: i16(C.POLLIN)
		}
		count++
	}
	if count == 0 {
		desktop_sleep_ms(milliseconds)
		return
	}
	timeout := if milliseconds > 0x7fffffff { 0x7fffffff } else { int(milliseconds) }
	C.poll(&fds[0], usize(count), timeout)
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

// A child process and its pseudo-terminal master.
struct SpawnedShell {
	pid      int
	terminal int
}

// Linux/Vinix's struct winsize is four unsigned shorts. Keep the ABI shape in
// V because the Vinix C backend does not import tagged C struct declarations.
struct DesktopWinSize {
mut:
	rows    u16
	columns u16
	width   u16
	height  u16
}

// Both architecture images follow Alpine's standard command layout.
const desktop_command_path = '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'

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
		c'SHELL=/bin/zsh', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
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
// The master is retained by the desktop. The child starts a new session,
// claims the slave as its controlling terminal and attaches it to all three
// standard streams. This is what gives the shell normal echo, signals and job
// control instead of requiring a private prompt protocol over pipes.
//
// The master comes back non-blocking, so polling it once per compositor frame
// never stalls.
fn desktop_spawn_shell(path string, rows int, columns int, width int, height int) ?SpawnedShell {
	master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY | C.O_CLOEXEC)
	if master < 0 {
		return none
	}
	if C.grantpt(master) != 0 || C.unlockpt(master) != 0 {
		C.close(master)
		return none
	}
	slave_name := C.ptsname(master)
	if slave_name == unsafe { nil } {
		C.close(master)
		return none
	}
	slave := C.open(slave_name, C.O_RDWR | C.O_NOCTTY | C.O_CLOEXEC)
	if slave < 0 {
		C.close(master)
		return none
	}
	// Set geometry before the shell starts. Starting at 0x0 and resizing after
	// the first prompt makes a real shell handle SIGWINCH by drawing that prompt
	// twice, which is precisely the synthetic-looking behavior PTYs remove.
	if !desktop_terminal_winsize(slave, rows, columns, width, height) {
		C.close(slave)
		C.close(master)
		return none
	}

	// Built before the fork. Between fork and execve the child may call only
	// async-signal-safe functions, which allocating is not.
	argv := [&char(path.str), c'-i', &char(unsafe { nil })]
	path_entry := 'PATH=${desktop_command_path}'
	// A valid terminal type is required by terminal applications such as tmux.
	// `linux` is available in ncurses-terminfo-base, including when tmux is
	// installed through pkg, and the terminal parser accepts its ANSI output.
	envp := [&char(path_entry.str), c'HOME=/root', c'TERM=linux', c'USER=root', c'LOGNAME=root',
		c'SHELL=/bin/zsh', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
		c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri',
		c'SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt', &char(unsafe { nil })]

	pid := C.fork()
	if pid < 0 {
		C.close(slave)
		C.close(master)
		return none
	}
	if pid == 0 {
		C.close(master)
		if C.setsid() < 0 || desktop_ioctl(slave, u64(C.TIOCSCTTY), unsafe { nil }) != 0 {
			C._exit(126)
		}
		C.dup2(slave, 0)
		C.dup2(slave, 1)
		C.dup2(slave, 2)
		if slave > 2 {
			C.close(slave)
		}
		C.execve(&char(path.str), argv.data, envp.data)
		C._exit(127)
	}

	C.close(slave)
	flags := C.fcntl(master, C.F_GETFL)
	if flags < 0 || C.fcntl(master, C.F_SETFL, flags | C.O_NONBLOCK) != 0 {
		C.close(master)
		desktop_terminate_child(pid)
		return none
	}
	return SpawnedShell{
		pid: pid
		terminal: master
	}
}

fn desktop_terminal_winsize(fd int, rows int, columns int, width int, height int) bool {
	if fd < 0 || rows <= 0 || columns <= 0 {
		return false
	}
	mut size := DesktopWinSize{
		rows: u16(rows)
		columns: u16(columns)
		width: u16(width)
		height: u16(height)
	}
	// Darwin's encoded request has its high bit set and its header macro is a
	// signed int. Cast through u32 so conversion to the wrapper's u64 does not
	// sign-extend it; Linux/Vinix requests are preserved by the same cast.
	return desktop_ioctl(fd, u64(u32(C.TIOCSWINSZ)), &size) == 0
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

// What the session should do once it has finished tearing itself down.
enum PowerAction {
	keep_running
	restart
	power_off
	halt
}

// The commands reboot(2) accepts, as <sys/reboot.h> names them.
const reboot_restart = u32(0x01234567)
const reboot_power_off = u32(0x4321fedc)
const reboot_halt = u32(0xcdef0123)

// The signal number a power signal arrived as, written by the handler and read
// by the compositor loop. A handler runs between two instructions of whatever
// the loop was doing, so it may do nothing but this store.
__global desktop_power_signal = int(0)

// The signal number arrives in a C `int`, which V's own `int` is wider than.
fn desktop_power_signal_handler(signal i32) {
	desktop_power_signal = signal
}

// busybox reboot, poweroff and halt do not call reboot(2) themselves unless
// they are given -f: they sync, signal pid 1, and leave the machine to init.
// The desktop image's init execs this compositor, so pid 1 is this process and
// those signals arrive here. Their meanings are the ones busybox init gives
// them, which is what busybox halt sends them for.
fn desktop_install_power_signals() {
	unsafe {
		handler := voidptr(desktop_power_signal_handler)
		C.signal(C.SIGTERM, handler) // reboot
		C.signal(C.SIGUSR2, handler) // poweroff
		C.signal(C.SIGUSR1, handler) // halt
	}
}

// The power action a signal asked for since this was last called, consuming it.
fn desktop_pending_power_action() PowerAction {
	signal := desktop_power_signal
	if signal == 0 {
		return .keep_running
	}
	desktop_power_signal = 0
	if signal == C.SIGUSR1 {
		return .halt
	}
	if signal == C.SIGUSR2 {
		return .power_off
	}
	return .restart
}

// Only the process the kernel started as init may take the machine down. A
// desktop launched from a shell on the full image is an ordinary process, and
// ending its session there means returning to that shell.
fn desktop_is_init() bool {
	return C.getpid() == 1
}

// Hand the machine to the kernel. reboot(2) only returns when it refuses, so
// everything the session wanted to finish must already be done.
fn desktop_power_apply(action PowerAction) {
	mut command := u32(0)
	match action {
		.keep_running { return }
		.restart { command = reboot_restart }
		.power_off { command = reboot_power_off }
		.halt { command = reboot_halt }
	}
	C.sync()
	if C.reboot(command) != 0 {
		eprintln('vinix-desktop: the kernel refused the power request')
	}
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
	// C pipe descriptors are always 32-bit even when V3's `int` is 64-bit.
	mut request := [2]i32{}
	mut response := [2]i32{}
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
		c'SHELL=/bin/zsh', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
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
		to_child: int(request[1])
		from_child: int(response[0])
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

struct SpawnedWineHost {
	pid   int
	input int
}

struct SpawnedNativeSurface {
	pid   int
	input int
}

// Start a native Vinix surface client. The child receives compositor input on
// stdin and publishes XRGB frames at VINIX_SURFACE_PATH. Deliberately omit all
// X11 and Wayland environment variables: this is the native window-system ABI.
fn desktop_spawn_native_surface(path string, first_argument string, second_argument string, surface_path string, width int, height int) ?SpawnedNativeSurface {
	if C.access(&char(path.str), C.X_OK) != 0 || width <= 0 || height <= 0 {
		return none
	}
	mut input := [2]i32{}
	if C.pipe(&input[0]) != 0 {
		return none
	}
	desktop_set_cloexec(input[0], true)
	desktop_set_cloexec(input[1], true)

	argv := [&char(path.str), &char(first_argument.str), &char(second_argument.str),
		&char(unsafe { nil })]
	path_entry := 'PATH=${desktop_command_path}'
	surface_entry := 'VINIX_SURFACE_PATH=${surface_path}'
	width_entry := 'VINIX_SURFACE_WIDTH=${width}'
	height_entry := 'VINIX_SURFACE_HEIGHT=${height}'
	mut envp := [&char(path_entry.str), c'HOME=/root', c'TERM=dumb', c'USER=root', c'LOGNAME=root',
		c'SHELL=/bin/zsh', c'LD_LIBRARY_PATH=/usr/lib', c'LIBGL_DRIVERS_PATH=/usr/lib/dri',
		c'EGL_PLATFORM=surfaceless', c'SSL_CA_CERT_FILE=/etc/ssl/certs/ca-certificates.crt']
	// QEMU exposes only simpledrm, so select the packaged software renderer
	// explicitly. Preserve Mesa's native Asahi selection on Vinix hardware.
	if C.access(c'/dev/dri/renderD128', C.R_OK | C.W_OK) != 0 {
		envp << c'LIBGL_ALWAYS_SOFTWARE=1'
		envp << c'GALLIUM_DRIVER=llvmpipe'
		envp << c'MESA_LOADER_DRIVER_OVERRIDE=swrast'
		envp << c'MESA_SHADER_CACHE_DISABLE=true'
	}
	envp << &char(surface_entry.str)
	envp << &char(width_entry.str)
	envp << &char(height_entry.str)
	envp << &char(unsafe { nil })

	pid := C.fork()
	if pid < 0 {
		C.close(input[0])
		C.close(input[1])
		unsafe {
			path_entry.free()
			surface_entry.free()
			width_entry.free()
			height_entry.free()
			argv.free()
			envp.free()
		}
		return none
	}
	if pid == 0 {
		C.dup2(input[0], C.STDIN_FILENO)
		C.close(input[0])
		C.close(input[1])
		C.execve(&char(path.str), argv.data, envp.data)
		C._exit(127)
	}
	C.close(input[0])
	unsafe {
		path_entry.free()
		surface_entry.free()
		width_entry.free()
		height_entry.free()
		argv.free()
		envp.free()
	}
	return SpawnedNativeSurface{
		pid: pid
		input: int(input[1])
	}
}

// Start the native Xvfb/Wine bridge with a private input pipe. The application
// process retains only the write end; the host receives it as stdin and owns
// every X11 and translated Wine child for the lifetime of the Vinix window.
fn desktop_spawn_wine_host(directory string, width int, height int, command string) ?SpawnedWineHost {
	host := '/usr/bin/vinix-wine-host'
	if C.access(&char(host.str), C.X_OK) != 0 || C.access(&char(command.str), C.X_OK) != 0 {
		return none
	}
	mut input := [2]i32{}
	if C.pipe(&input[0]) != 0 {
		return none
	}
	desktop_set_cloexec(input[0], true)
	desktop_set_cloexec(input[1], true)

	display_name := ':${C.getpid()}'
	geometry := '${width}x${height}x24'
	argv := [&char(host.str), &char(display_name.str), &char(directory.str), &char(geometry.str),
		&char(command.str), &char(unsafe { nil })]
	path_entry := 'PATH=${desktop_command_path}'
	envp := [&char(path_entry.str), c'HOME=/root', c'TERM=dumb', c'USER=root', c'LOGNAME=root',
		c'SHELL=/bin/zsh', c'LD_LIBRARY_PATH=/usr/lib:/usr/lib/xorg/modules',
		c'LIBGL_DRIVERS_PATH=/usr/lib/xorg/modules/dri:/usr/lib/dri', &char(unsafe { nil })]

	pid := C.fork()
	if pid < 0 {
		C.close(input[0])
		C.close(input[1])
		unsafe {
			display_name.free()
			geometry.free()
			path_entry.free()
			argv.free()
			envp.free()
		}
		return none
	}
	if pid == 0 {
		C.dup2(input[0], C.STDIN_FILENO)
		C.close(input[0])
		C.close(input[1])
		C.execve(&char(host.str), argv.data, envp.data)
		C._exit(127)
	}
	C.close(input[0])
	unsafe {
		display_name.free()
		geometry.free()
		path_entry.free()
		argv.free()
		envp.free()
	}
	return SpawnedWineHost{
		pid: pid
		input: int(input[1])
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

// What a disk inventory needs from one directory entry. The identity pair is
// what answers "have I already counted these bytes": a file reached through a
// second hard link, or a directory reached through a second path, has the same
// device and inode as the first time it was seen.
struct DesktopNodeInfo {
	size    u64
	is_dir  bool
	is_file bool
	links   u64
	device  u64
	inode   u64
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

// lstat, so a symbolic link is reported as the link and not as whatever it
// points at. An inventory that followed one would count the target's bytes
// again under a second name, and a link into an ancestor would never finish.
fn desktop_lstat(path string) ?DesktopNodeInfo {
	mut info := C.stat{}
	if unsafe { C.lstat(&char(path.str), &info) } != 0 {
		return none
	}
	kind := u32(info.st_mode) & u32(C.S_IFMT)
	return DesktopNodeInfo{
		size: u64(info.st_size)
		is_dir: kind == u32(C.S_IFDIR)
		is_file: kind == u32(C.S_IFREG)
		links: u64(info.st_nlink)
		device: u64(info.st_dev)
		inode: u64(info.st_ino)
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
