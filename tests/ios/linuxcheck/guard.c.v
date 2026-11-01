// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module linuxcheck

import os
import time

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>

$if linux {
	#include <sys/prctl.h>
	fn C.prctl(int, u64, u64, u64, u64) int
}

@[typedef]
struct C.siginfo_t {
	si_pid    int
	si_code   int
	si_status int
}

fn C.waitid(int, u32, &C.siginfo_t, int) int
fn C.waitpid(int, &int, int) int
fn C.fstat(int, &C.stat) int
fn C.pread(int, voidptr, usize, i64) i64
fn C.setsid() int
fn C.signal(int, voidptr) voidptr
fn C.__atomic_load_n(&int, int) int
fn C.__atomic_store_n(&int, int, int)

__global linux_guard_signal int

const guard_output_limit = u64(16 * 1024 * 1024)

fn guard_interrupted(signum int) {
	unsafe { C.__atomic_store_n(&linux_guard_signal, signum, C.__ATOMIC_RELAXED) }
}

fn guard_subreaper() !int {
	$if linux {
		mut previous := 0
		if C.prctl(C.PR_GET_CHILD_SUBREAPER, u64(unsafe { &previous }), 0, 0, 0) != 0 {
			return os.error_posix()
		}
		if C.prctl(C.PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0 { return os.error_posix() }
		return previous
	} $else {
		return error('the Linux command guard requires Linux child-subreaper support')
	}
}

fn guard_restore_subreaper(previous int) {
	$if linux {
		C.prctl(C.PR_SET_CHILD_SUBREAPER, u64(previous), 0, 0, 0)
	}
}

fn guard_observe(pid int) !(bool, int) {
	mut info := C.siginfo_t{}
	for {
		if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	code := if info.si_code == C.CLD_EXITED { info.si_status } else { 128 + info.si_status }
	return info.si_pid == pid, code
}

fn guard_log_size(fd int) !u64 {
	mut metadata := C.stat{}
	if C.fstat(fd, &metadata) != 0 { return os.error_posix() }
	if metadata.st_size < 0 { return error('negative command log size') }
	return u64(metadata.st_size)
}

// Keep capture descriptors above stdin/stdout/stderr, even when the caller
// started with a standard descriptor closed. This also makes dup2 clear
// close-on-exec on every standard descriptor in the child.
fn guard_owned_descriptor(fd int) !int {
	if fd < 0 { return os.error_posix() }
	if fd > 2 { return fd }
	moved := C.fcntl(fd, C.F_DUPFD_CLOEXEC, 3)
	if moved < 0 {
		failure := os.error_posix()
		C.close(fd)
		return failure
	}
	C.close(fd)
	return moved
}

fn guard_read_log(fd int) !string {
	size := guard_log_size(fd)!
	// A failing command can overshoot between samples. Preserve its file but
	// never allocate an unbounded output string while reporting the failure.
	count := int(if size > guard_output_limit { guard_output_limit } else { size })
	mut bytes := []u8{len: count}
	mut position := 0
	for position < count {
		n := C.pread(fd, unsafe { &bytes[position] }, usize(count - position), i64(position))
		if n < 0 {
			if C.errno == C.EINTR { continue }
			return os.error_posix()
		}
		if n == 0 { return error('command log changed while reading') }
		position += int(n)
	}
	return bytes.bytestr()
}

// Only async-signal-safe operations occur between fork and exec. Keep setup
// errno visible without allocating a V string in the forked child.
fn guard_child_fail(prefix &char, length usize, number int, status int) {
	C.write(2, prefix, length)
	mut digits := [16]u8{}
	mut index := 14
	mut value := if number < 0 { 0 } else { number }
	digits[15] = `\n`
	for {
		digits[index] = u8(value % 10) + `0`
		value /= 10
		if value == 0 { break }
		index--
	}
	C.write(2, unsafe { &digits[index] }, usize(16 - index))
	C._exit(status)
}

struct GuardRetirement {
mut:
	status      int = -1
	descendants int
	reaped      bool
	complete    bool
	failure     string
}

fn guard_signal_target(target int, signum int) ! {
	if C.kill(target, signum) != 0 && C.errno != C.ESRCH { return os.error_posix() }
}

// Hold the leader's zombie until the group has been signalled. The subreaper
// adopts orphaned controls, allowing their retirement and detection without
// procfs and without reaping an unrelated command's children.
fn guard_retire(pid int) GuardRetirement {
	mut result := GuardRetirement{}
	deadline := time.sys_mono_now() + 5 * u64(time.second)
	mut signal_errors := []string{}
	guard_signal_target(-pid, C.SIGTERM) or { signal_errors << err.msg() }
	guard_signal_target(pid, C.SIGTERM) or { signal_errors << err.msg() }
	time.sleep(100 * time.millisecond)
	guard_signal_target(-pid, C.SIGKILL) or { signal_errors << err.msg() }
	guard_signal_target(pid, C.SIGKILL) or { signal_errors << err.msg() }
	mut status := 0
	for {
		child := C.waitpid(pid, &status, C.WNOHANG)
		if child == pid { break }
		if child < 0 && C.errno != C.EINTR {
			result.failure = 'cannot reap direct child: ' + os.error_posix().msg()
			return result
		}
		if time.sys_mono_now() >= deadline {
			result.failure = 'child did not reap within five seconds after SIGKILL'
			return result
		}
		time.sleep(10 * time.millisecond)
	}
	result.reaped = true
	result.status = if status & 0x7f == 0 { (status >> 8) & 0xff } else { 128 + (status & 0x7f) }
	for {
		if time.sys_mono_now() >= deadline {
			result.failure = 'descendants did not reap within five seconds after SIGKILL'
			return result
		}
		mut child_status := 0
		child := C.waitpid(-pid, &child_status, C.WNOHANG)
		if child > 0 {
			result.descendants++
			continue
		}
		if child == 0 {
			// An owned child still reserves this process-group identity. It is
			// safe to finish a fork racing the first group signal before reap.
			guard_signal_target(-pid, C.SIGKILL) or { signal_errors << err.msg() }
			if time.sys_mono_now() >= deadline {
				result.failure = 'descendants did not reap within five seconds after SIGKILL'
				return result
			}
			time.sleep(10 * time.millisecond)
			continue
		}
		if C.errno == C.EINTR { continue }
		if C.errno != C.ECHILD {
			result.failure = 'cannot reap descendants: ' + os.error_posix().msg()
			return result
		}
		break
	}
	result.complete = true
	result.failure = signal_errors.join('; ')
	return result
}

// Capture to an exclusive regular file: a grandchild cannot hold a capture
// pipe open after its parent exits. The guard is a single-command owner.
fn guarded_command(out string, label string, args []string, cwd string, env map[string]string, seconds int) !(int, string) {
	if seconds <= 0 || seconds > 3600 || args.len == 0 || args.any(it.contains('\x00'))
		|| !os.is_dir(cwd) || cwd.contains('\x00') {
		return error('invalid guarded command or deadline')
	}
	if label == '' || label in ['.', '..'] || label.bytes().any(!((it >= `a` && it <= `z`)
		|| (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it in [u8(`-`), `_`, `.`])) {
		return error('invalid command receipt label')
	}
	executable_path := os.find_abs_path_of_executable(args[0])!
	mut command := args.clone()
	command[0] = executable_path
	mut argv := []&char{}
	for value in command { argv << unsafe { &char(value.str) } }
	argv << &char(unsafe { nil })
	mut values := []string{}
	for key, value in env {
		if key == '' || key.contains_any('=\x00') || value.contains('\x00') {
			return error('invalid command environment')
		}
		values << key + '=' + value
	}
	mut envp := []&char{}
	for value in values { envp << unsafe { &char(value.str) } }
	envp << &char(unsafe { nil })
	base := out + '/' + label
	log_path := base + '.log'
	fd := guard_owned_descriptor(unsafe { C.open(log_path.str, C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600) })!
	defer { C.close(fd) }
	input := guard_owned_descriptor(unsafe { C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC) })!
	defer { C.close(input) }
	os.write_file(base + '.command.txt', command.map(os.quoted_path(it)).join(' ') + '\n')!
	previous_subreaper := guard_subreaper()!
	defer { guard_restore_subreaper(previous_subreaper) }
	unsafe { C.__atomic_store_n(&linux_guard_signal, 0, C.__ATOMIC_RELAXED) }
	old_interrupt := unsafe { C.signal(C.SIGINT, voidptr(guard_interrupted)) }
	if old_interrupt == C.SIG_ERR { return os.error_posix() }
	defer { unsafe { C.signal(C.SIGINT, old_interrupt) } }
	old_terminate := unsafe { C.signal(C.SIGTERM, voidptr(guard_interrupted)) }
	if old_terminate == C.SIG_ERR { return os.error_posix() }
	defer { unsafe { C.signal(C.SIGTERM, old_terminate) } }
	start := time.sys_mono_now()
	pid := C.fork()
	if pid < 0 { return os.error_posix() }
	if pid == 0 {
		unsafe {
			C.signal(C.SIGINT, C.SIG_DFL)
			C.signal(C.SIGTERM, C.SIG_DFL)
			C.signal(C.SIGPIPE, C.SIG_DFL)
		}
		if C.setsid() < 0 { guard_child_fail(c'guard setsid errno=', 19, C.errno, 126) }
		if C.dup2(input, 0) < 0 || C.dup2(fd, 1) < 0 || C.dup2(fd, 2) < 0 {
			guard_child_fail(c'guard dup2 errno=', 17, C.errno, 126)
		}
		if fd > 2 { C.close(fd) }
		if input > 2 { C.close(input) }
		if C.chdir(cwd.str) != 0 { guard_child_fail(c'guard chdir errno=', 18, C.errno, 126) }
		unsafe { C.execve(command[0].str, argv.data, envp.data) }
		guard_child_fail(c'guard execve errno=', 19, C.errno, 127)
	}
	mut retirement_started := false
	defer { if !retirement_started { guard_retire(pid) } }
	deadline := start + u64(seconds) * u64(time.second)
	mut failure := ''
	mut error_code := 1
	for {
		signum := unsafe { C.__atomic_load_n(&linux_guard_signal, C.__ATOMIC_RELAXED) }
		if signum != 0 {
			failure = 'interrupted by signal ${signum}'
			error_code = 128 + signum
			break
		}
		log_size := guard_log_size(fd) or {
			failure = 'cannot inspect command log: ' + err.msg()
			break
		}
		if log_size > guard_output_limit {
			failure = 'command output exceeded 16 MiB'
			break
		}
		exited, _ := guard_observe(pid) or {
			failure = 'cannot observe direct child: ' + err.msg()
			break
		}
		if exited { break }
		if time.sys_mono_now() >= deadline {
			failure = 'command deadline exceeded'
			error_code = 124
			break
		}
		time.sleep(10 * time.millisecond)
	}
	retirement_started = true
	retirement := guard_retire(pid)
	last_signal := unsafe { C.__atomic_load_n(&linux_guard_signal, C.__ATOMIC_RELAXED) }
	if last_signal != 0 && failure == '' {
		failure = 'interrupted by signal ${last_signal}'
		error_code = 128 + last_signal
	}
	if retirement.failure != '' { failure += '; cleanup: ' + retirement.failure }
	if retirement.descendants > 0 && failure == '' {
		failure = 'command left ${retirement.descendants} process-group descendants'
	}
	final_size := guard_log_size(fd) or {
		failure += '; cannot inspect command log: ' + err.msg()
		u64(0)
	}
	if final_size > guard_output_limit && failure == '' {
		failure = 'command output exceeded 16 MiB'
	}
	output := guard_read_log(fd) or {
		failure += '; cannot read command log: ' + err.msg()
		''
	}
	os.write_file(base + '.status.txt', '${retirement.status}\n')!
	os.write_file(base + '.elapsed-ns.txt', '${time.sys_mono_now() - start}\n')!
	os.write_file(base + '.guard.txt', 'child=${pid}\nreaped=${retirement.reaped}\ncleanup_complete=${retirement.complete}\n' +
		'residual_descendants=${retirement.descendants}\n' +
		'output_limit=${guard_output_limit}\nresult=' + if failure == '' {
		'clean\n'
	} else {
		failure + '\n'
	})!
	if failure != '' { return error_with_code('${label}: ${failure}; see ${log_path}', error_code) }
	return retirement.status, output
}
