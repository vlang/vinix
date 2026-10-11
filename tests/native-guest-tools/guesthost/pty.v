// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module guesthost

import os
import time

#flag linux -lutil

$if macos {
	#include <util.h>
} $else {
	#include <pty.h>
}

#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

struct C.sockaddr_un {
mut:
	sun_len    u8
	sun_family u16
	sun_path   [108]char
}

fn C.forkpty(&i32, &char, voidptr, voidptr) i32
fn C.execve(&char, &&char, &&char) i32
fn C.killpg(i32, i32) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.send(i32, voidptr, usize, i32) i32
fn C.recv(i32, voidptr, usize, i32) i32
fn C.signal(i32, voidptr) voidptr
fn C.WIFSIGNALED(i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32

__global (
	interrupted i32
)

fn interrupt(_signal i32) {
	unsafe { C.__atomic_store_n(&interrupted, i32(1), C.__ATOMIC_RELAXED) }
}

fn interruption() ! {
	if unsafe { C.__atomic_load_n(&interrupted, C.__ATOMIC_RELAXED) } != 0 {
		return error('Guest run interrupted')
	}
}

fn posix_error() IError { return error_with_code(os.get_error_msg(int(C.errno)), int(C.errno)) }

fn now() f64 { return f64(time.sys_mono_now()) / 1e9 }

// All allocation, PATH lookup and environment construction happens before fork.
// The child invokes only execve/write/_exit and cannot enter the V runtime.
fn spawn_guest(command []string, env map[string]string) !(i32, i32) {
	if command.len == 0 { return error('Missing guest command') }
	program := if command[0].contains('/') {
		command[0]
	} else {
		os.find_abs_path_of_executable(command[0])!
	}
	mut argv := []&char{}
	for arg in command { argv << &char(arg.str) }
	argv << &char(unsafe { nil })
	mut entries := []string{}
	for key, value in env { entries << key + '=' + value }
	mut envp := []&char{}
	for entry in entries { envp << &char(entry.str) }
	envp << &char(unsafe { nil })
	mut master := i32(-1)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return posix_error() }
	if pid == 0 {
		unsafe { C.execve(program.str, argv.data, envp.data) }
		C.write(2, c'Cannot execute guest runner\n', 28)
		C._exit(127)
	}
	if C.fcntl(master, C.F_SETFL, C.O_NONBLOCK) < 0 {
		cause := posix_error()
		C.kill(pid, C.SIGKILL)
		mut status := i32(0)
		C.waitpid(pid, &status, 0)
		C.close(master)
		return cause
	}
	return pid, master
}

fn ready(fd i32, writing bool, deadline f64) !bool {
	for {
		interruption()!
		left := deadline - now()
		if left <= 0 { return false }
		mut descriptor := C.pollfd{ fd: fd, events: i16(if writing { C.POLLOUT } else { C.POLLIN }) }
		result := C.poll(&descriptor, 1, int(left * 1000) + 1)
		if result >= 0 { return result > 0 }
		if C.errno != C.EINTR { return posix_error() }
	}
	return false
}

fn drain(master i32, mut transcript []u8, inherit bool) ! {
	mut buffer := [65536]u8{}
	for {
		count := C.read(master, &buffer[0], buffer.len)
		if count < 0 {
			if C.errno in [C.EAGAIN, C.EWOULDBLOCK, C.EIO] { return }
			if C.errno == C.EINTR { continue }
			return posix_error()
		}
		if count == 0 { return }
		transcript << buffer[..count]
		if inherit {
			print(replacement_text(buffer[..count]))
			flush_stdout()
		}
	}
}

// Keep raw transcript bytes; the console matches the original per-read UTF-8
// decode(errors='replace'), including incomplete sequences at a read boundary.
pub fn replacement_text(bytes []u8) string {
	mut result := []u8{cap: bytes.len}
	mut index := 0
	for index < bytes.len {
		first := bytes[index]
		if first < 0x80 {
			result << first
			index++
			continue
		}
		width := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			1
		}
		mut consumed := 1
		for consumed < width && index + consumed < bytes.len {
			next := bytes[index + consumed]
			if next < 0x80 || next > 0xbf { break }
			if consumed == 1 && ((first == 0xe0 && next < 0xa0) || (first == 0xed && next > 0x9f)
				|| (first == 0xf0 && next < 0x90) || (first == 0xf4 && next > 0x8f)) {
				break
			}
			consumed++
		}
		if width > 1 && consumed == width {
			result << bytes[index..index + width]
		} else {
			result << [u8(0xef), 0xbf, 0xbd]
		}
		index += consumed
	}
	return result.bytestr()
}

fn monitor_receive(fd i32) ! {
	if !ready(fd, false, now() + 1)! { return error('QMP receive timed out') }
	mut bytes := [4096]u8{}
	if C.recv(fd, &bytes[0], bytes.len, 0) < 0 { return posix_error() }
}

fn monitor_send(fd i32, text string) ! {
	deadline := now() + 1
	mut sent := 0
	for sent < text.len {
		if !ready(fd, true, deadline)! { return error('QMP send timed out') }
		count := unsafe { C.send(fd, text.str + sent, usize(text.len - sent), 0) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return posix_error()
		}
		if count == 0 { return error('QMP closed during send') }
		sent += int(count)
	}
}

fn quit_monitor(path string) ! {
	mut address := C.sockaddr_un{}
	if path.len >= int(sizeof(address.sun_path)) { return error('QMP socket path too long') }
	address.sun_family = C.AF_UNIX
	$if macos {
		address.sun_len = u8(sizeof(C.sockaddr_un))
	}
	unsafe { C.memcpy(&address.sun_path[0], path.str, usize(path.len)) }
	fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	if fd < 0 { return posix_error() }
	defer { C.close(fd) }
	if C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) < 0 { return posix_error() }
	if C.connect(fd, &address, u32(sizeof(C.sockaddr_un))) < 0 {
		if C.errno !in [C.EINPROGRESS, C.EAGAIN] { return posix_error() }
		if !ready(fd, true, now() + 1)! { return error('QMP connect timed out') }
		mut failure := i32(0)
		mut size := u32(sizeof(i32))
		if C.getsockopt(fd, C.SOL_SOCKET, C.SO_ERROR, &failure, &size) < 0 { return posix_error() }
		if failure != 0 { return error_with_code('QMP connect failed', int(failure)) }
	}
	monitor_receive(fd)!
	monitor_send(fd, '{"execute":"qmp_capabilities"}\n')!
	monitor_receive(fd)!
	monitor_send(fd, '{"execute":"quit"}\n')!
}

fn wait(pid i32, nonblocking bool) !(bool, int) {
	mut status := i32(0)
	for {
		result := C.waitpid(pid, &status, if nonblocking { C.WNOHANG } else { 0 })
		if result == 0 { return false, 0 }
		if result == pid {
			return true, if C.WIFSIGNALED(status) != 0 {
				-int(C.WTERMSIG(status))
			} else {
				int(C.WEXITSTATUS(status))
			}
		}
		if C.errno == C.EINTR { continue }
		if C.errno == C.ECHILD { return true, 0 }
		return posix_error()
	}
	return false, 0
}

fn stop(pid i32, master i32, state string, mut transcript []u8, inherit bool) ! {
	// Never signal an already reaped PID. QMP and Ctrl-A x precede signals.
	reaped, _ := wait(pid, true)!
	if reaped { return }
	quit_monitor(state + '/qmp.sock') or {}
	C.write(master, c'\x01x', 2)
	for phase in 0 .. 3 {
		if phase > 0 {
			signal := if phase == 1 { C.SIGTERM } else { C.SIGKILL }
			if C.killpg(pid, signal) < 0 && C.errno == C.EPERM { C.kill(pid, signal) }
		}
		deadline := now() + 3
		for now() < deadline {
			drain(master, mut transcript, inherit)!
			done, _ := wait(pid, true)!
			if done { return }
			time.sleep(50 * time.millisecond)
		}
	}
	return error('Guest runner did not stop')
}

pub fn verdict_policy(expected []string, failures []string, panic_mode bool) ([]string, []string) {
	return if panic_mode {
		['KERNEL PANIC', ...expected], ['FATAL EXCEPTION', 'FAIL:', ...failures, 'USERSPACE ENTERED',
			'INIT ENTERED', 'Entering userspace']
	} else {
		expected.clone(), ['KERNEL PANIC', 'FATAL EXCEPTION', 'FAIL:', ...failures]
	}
}

pub fn boot(command []string, env map[string]string, state string, expected []string, failures []string, timeout int, inherit bool) !int {
	if timeout <= 0 { return error('Guest timeout must be positive') }
	unsafe { C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED) }
	previous := unsafe { C.signal(C.SIGINT, voidptr(interrupt)) }
	defer { unsafe { C.signal(C.SIGINT, previous) } }
	previous_pipe := unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	defer { unsafe { C.signal(C.SIGPIPE, previous_pipe) } }
	pid, master := spawn_guest(command, env)!
	mut transcript := []u8{}
	mut reaped := false
	mut closed := false
	defer {
		if !reaped {
			C.killpg(pid, C.SIGKILL)
			C.kill(pid, C.SIGKILL)
			wait(pid, false) or {}
		}
		if !closed { C.close(master) }
	}
	deadline := now() + timeout
	mut settled := f64(-1)
	mut timed_out := false
	mut status := 0
	mut cause := ''
	for {
		if now() >= deadline {
			timed_out = true
			break
		}
		ready(master, false, now() + 0.2) or {
			cause = err.msg()
			break
		}
		drain(master, mut transcript, inherit) or {
			cause = err.msg()
			break
		}
		done, code := wait(pid, true) or {
			cause = err.msg()
			break
		}
		if done {
			reaped = true
			status = code
			break
		}
		text := transcript.bytestr()
		if failures.any(text.contains(it)) { break }
		if expected.all(text.contains(it)) {
			if settled < 0 {
				settled = now()
			} else if now() - settled >= 2 {
				break
			}
		}
	}
	unsafe {
		C.__atomic_store_n(&interrupted, i32(0), C.__ATOMIC_RELAXED)
		C.signal(C.SIGINT, C.SIG_IGN)
	}
	if !reaped {
		stop(pid, master, state, mut transcript, inherit) or { cause = err.msg() }
		// A failed stop still has an emergency owner in the defer above.
		done, _ := wait(pid, true) or { false, 0 }
		reaped = done
	}
	drain(master, mut transcript, inherit) or { cause = err.msg() }
	if C.close(master) < 0 {
		closed = true
		return posix_error()
	}
	closed = true
	os.write_file_array(state + '/serial.log', transcript)!
	if cause != '' { return error(cause) }
	text := transcript.bytestr()
	missing := expected.filter(!text.contains(it))
	mut observed := failures.filter(text.contains(it))
	if status != 0 { observed << 'QEMU runner exited ' + status.str() }
	if timed_out { observed << 'QEMU runner timed out' }
	if missing.len > 0 || observed.len > 0 {
		if inherit {
			println('Missing verdicts: ' + missing.str() + '; failures: ' + observed.str())
		}
		return 1
	}
	if inherit { println('All requested guest verdicts passed.') }
	return 0
}
