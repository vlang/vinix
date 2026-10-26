// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import os
import time

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <grp.h>

struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.fork() int
fn C.setpgid(int, int) int
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(int, int) int
fn C.dup2(int, int) int
fn C.execv(&char, &&char) int
fn C._exit(int)
fn C.setrlimit(int, &C.rlimit) int
fn C.unsetenv(&char) int
fn C.setgroups(usize, voidptr) int
fn C.setresuid(u32, u32, u32) int
fn C.setresgid(u32, u32, u32) int
fn C.getresuid(&u32, &u32, &u32) int
fn C.getresgid(&u32, &u32, &u32) int
fn C.getgroups(int, voidptr) int

// POSIX wait status is a C int even when this compiler's V int is wider.
// Both supervisors use this exact raw path; widen only for public receipts.
fn raw_waitpid(pid int, status &i32, options int) i32 {
	return C.waitpid(i32(pid), status, i32(options))
}

pub struct Run {
pub:
	leader_pid   int
	wait_status  int
	timed_out    bool
	size_limited bool
	stopped      bool
	duration_ms  u64
	startup      string
	parent       string
	child        string
}

fn ordinary_identity() bool {
	$if linux {
		mut real := u32(0)
		mut effective := u32(0)
		mut saved := u32(0)
		if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0
			|| C.setresuid(1000, 1000, 1000) != 0 {
			return false
		}
		if C.getresuid(&real, &effective, &saved) != 0 || real != 1000 || effective != 1000 || saved != 1000 {
			return false
		}
		if C.getresgid(&real, &effective, &saved) != 0 || real != 1000 || effective != 1000 || saved != 1000 {
			return false
		}
		return C.getgroups(0, unsafe { nil }) == 0
	} $else {
		return false
	}
}

fn log_size(path string) !u64 {
	if !os.exists(path) && !os.is_link(path) { return 0 }
	info := os.lstat(path)!
	if info.get_filetype() != .regular { return error('log is not an ordinary file: ' + path) }
	return info.size
}

fn read_log(path string) !string {
	if !os.exists(path) && !os.is_link(path) { return '' }
	if log_size(path)! > u64(log_limit) { return error('log exceeds byte limit') }
	return os.read_file(path)
}

// Both the original leader and its process group are bounded. The child also
// inherits a hard per-file RLIMIT_FSIZE. Logs are admitted only after the group
// disappears. ordinary=true is reserved for the native Linux guest supervisor.
pub fn capture(command []string, directory string, ordinary bool, timeout_ms int) !Run {
	if command.len == 0 || timeout_ms < 1 || timeout_ms > 10000 {
		return error('invalid command or runtime bound')
	}
	if (os.lstat(directory)!).get_filetype() != .directory || os.real_path(directory) != directory {
		return error('capture directory must be a canonical ordinary directory')
	}
	paths := [directory + '/startup.log', directory + '/parent.log', directory + '/child.log']
	for path in paths {
		if os.exists(path) || os.is_link(path) { return error('capture log already exists') }
	}
	mut exec_arguments := []&char{len: command.len + 1, init: unsafe { nil }}
	for index, argument in command { exec_arguments[index] = &char(argument.str) }
	started := time.sys_mono_now()
	pid := C.fork()
	if pid < 0 { return error('supervisor fork failed') }
	if pid == 0 {
		if C.setpgid(0, 0) != 0 { C._exit(120) }
		limits := C.rlimit{ rlim_cur: u64(log_limit), rlim_max: u64(log_limit) }
		if C.setrlimit(C.RLIMIT_FSIZE, &limits) != 0 { C._exit(121) }
		fd := C.open(paths[0].str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
		if fd < 0 || C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 { C._exit(122) }
		if fd > 2 { C.close(fd) }
		for name in ['VINIX_ALLOW_WX', 'QEMU_LOG_FILENAME', 'QEMU_LOG', 'QEMU_STRACE'] {
			if C.unsetenv(name.str) != 0 || C.getenv(name.str) != unsafe { nil } { C._exit(123) }
		}
		if ordinary && !ordinary_identity() { C._exit(124) }
		if ordinary {
			text := 'JITSTREAM ORDINARY uid/gid=1000 groups=0 no-WX PASS\n'
			if C.write(1, text.str, usize(text.len)) != text.len { C._exit(126) }
		}
		C.execv(command[0].str, &exec_arguments[0])
		C._exit(125)
	}
	mut reaped := false
	mut status := i32(-1)
	mut timed_out := false
	mut size_limited := false
	mut monitor_error := ''
	for {
		for path in paths {
			size := log_size(path) or {
				monitor_error = err.msg()
				break
			}
			if size >= u64(log_limit) { size_limited = true }
		}
		waited := raw_waitpid(pid, &status, C.WNOHANG)
		if waited == pid {
			reaped = true
			break
		}
		if waited < 0 && C.errno != C.EINTR {
			monitor_error = 'leader wait failed'
			break
		}
		if (time.sys_mono_now() - started) / 1000000 >= u64(timeout_ms) { timed_out = true }
		if timed_out || size_limited || monitor_error != '' { break }
		time.sleep(10 * time.millisecond)
	}
	// Stop descendants even when their translator leader failed first.
	C.kill(-pid, C.SIGKILL)
	if !reaped { C.kill(pid, C.SIGKILL) }
	mut stopped := false
	for _ in 0 .. 200 {
		if !reaped {
			waited := raw_waitpid(pid, &status, C.WNOHANG)
			if waited == pid { reaped = true }
		}
		// PID 1 can reap adopted members; a host may have no such children.
		if reaped {
			mut descendant_status := i32(0)
			for raw_waitpid(-pid, &descendant_status, C.WNOHANG) > 0 {
			}
		}
		if C.kill(-pid, 0) < 0 && C.errno == C.ESRCH && reaped {
			stopped = true
			break
		}
		time.sleep(10 * time.millisecond)
	}
	if !stopped { return error('process group cleanup was not confirmed; logs not admitted') }
	if monitor_error != '' { return error(monitor_error) }
	for path in paths { if log_size(path)! >= u64(log_limit) { size_limited = true } }
	return Run{
		leader_pid:   pid
		wait_status:  int(status)
		timed_out:    timed_out
		size_limited: size_limited
		stopped:      stopped
		duration_ms:  (time.sys_mono_now() - started) / 1000000
		startup:      read_log(paths[0])!
		parent:       read_log(paths[1])!
		child:        read_log(paths[2])!
	}
}
