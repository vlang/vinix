// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only guard for the supplemental standalone ARM capture controller.
@[has_globals]
module winejitstream

import os
import time

#include <sys/statvfs.h>

struct C.statvfs {
	f_frsize u64
	f_bavail u64
}

fn C.statvfs(&char, &C.statvfs) int
fn C.getpgrp() i32

__global native_interrupted = i32(0)

fn native_note_interrupt(signal os.Signal) { native_interrupted = i32(signal) }

pub fn native_was_interrupted() bool { return native_interrupted != 0 }

pub fn native_interruption_signal() int { return int(native_interrupted) }

pub fn native_watch_interrupts() ! {
	for signal in [os.Signal.int, .term, .hup] {
		os.signal_opt(signal, native_note_interrupt)!
	}
}

pub struct NativeLimits {
pub:
	timeout_ms   int
	file_bytes   u64
	total_bytes  u64
	log_bytes    u64
	serial_bytes u64
	min_free_kib u64
}

pub struct NativeRun {
pub:
	leader_pid     int
	wait_status    int
	duration_ms    u64
	timed_out      bool
	size_limited   bool
	stopped        bool
	reason         string
	observed_bytes u64
	cleanup_scope  string
	owner_group    int
}

// f_frsize is the allocation fragment size. V's macOS disk_usage incorrectly
// uses f_bsize, which overstates this machine's actual availability by 256x.
pub fn native_require_free(directory string, minimum_kib u64) !u64 {
	mut information := C.statvfs{}
	if C.statvfs(directory.str, &information) != 0 || information.f_frsize == 0
		|| information.f_bavail > (~u64(0)) / information.f_frsize {
		return error('invalid actual free-space reading')
	}
	available := information.f_bavail * information.f_frsize / 1024
	if available < minimum_kib { return error('insufficient actual free space') }
	return available
}

struct NativeTree {
mut:
	bytes   u64
	entries int
	limited bool
}

fn native_scan(directory string, relative string, limits NativeLimits, mut tree NativeTree) ! {
	names := os.ls(directory) or {
		// Trusted compilers remove temporary subdirectories between samples.
		// The selected scan root must always remain present.
		if relative != '' && err.code() == C.ENOENT { return }
		return err
	}
	for name in names { native_scan_entry(directory, relative, name, limits, mut tree)! }
}

fn native_scan_entry(directory string, relative string, name string, limits NativeLimits, mut tree NativeTree) ! {
	tree.entries++
	if tree.entries > 512 { return error('capture state exceeds 512 entries') }
	path := directory + '/' + name
	rel := if relative == '' { name } else { relative + '/' + name }
	info := os.lstat(path) or {
		// A name from ls may already have been unlinked by the guarded tool.
		if err.code() == C.ENOENT { return }
		return err
	}
	match info.get_filetype() {
		.directory { native_scan(path, rel, limits, mut tree)! }
		.regular {
			if tree.bytes > (~u64(0)) - info.size {
				tree.bytes = ~u64(0)
			} else {
				tree.bytes += info.size
			}
			if tree.bytes > limits.total_bytes { tree.limited = true }
			mut cap := limits.file_bytes
			if name == 'serial.log' {
				cap = limits.serial_bytes
			} else if name.ends_with('.log') {
				cap = limits.log_bytes
			}
			if info.size >= cap { tree.limited = true }
		}
		.socket {
			if rel != 'boot/qmp.sock' { return error('unexpected state socket') }
		}
		else { return error('capture state contains a link or unsupported type: ' + rel) }
	}
}

pub fn native_state_bytes(directory string) !u64 {
	mut tree := NativeTree{}
	native_scan(directory, '', NativeLimits{
		file_bytes:   ~u64(0)
		total_bytes:  ~u64(0)
		log_bytes:    ~u64(0)
		serial_bytes: ~u64(0)
	}, mut tree)!
	return tree.bytes
}

pub fn native_require_state(directory string, limits NativeLimits) !u64 {
	if os.real_path(directory) != directory || os.lstat(directory)!.get_filetype() != .directory {
		return error('state scan root must be a canonical ordinary directory')
	}
	mut tree := NativeTree{}
	native_scan(directory, '', limits, mut tree)!
	if tree.limited { return error('capture state threshold exceeded') }
	return tree.bytes
}

pub fn native_apply_file_limits(bytes u64) ! {
	if bytes < 1 || bytes > 128 * 1024 * 1024 { return error('invalid inherited file limit') }
	files := C.rlimit{rlim_cur: bytes, rlim_max: bytes}
	cores := C.rlimit{}
	if C.setrlimit(C.RLIMIT_FSIZE, &files) != 0 || C.setrlimit(C.RLIMIT_CORE, &cores) != 0 {
		return error('cannot apply inherited owner file/core limits')
	}
}

// A finite trusted tool group is monitored every 10 ms. Per-log and aggregate
// thresholds can overshoot between polls: the inherited hard per-file limit is
// the final ceiling, including a serial writer. It must accommodate FAT/UEFI
// media; it is deliberately distinct from the smaller admission thresholds.
pub fn native_guard(command []string, directory string, log_name string, limits NativeLimits) !NativeRun {
	return native_guard_run(command, directory, log_name, limits, 0)
}

// The enclosing owner retires the shared group; this guard reaps only its
// direct leader. Trusted tools must keep the inherited group throughout.
pub fn native_guard_inherited(command []string, directory string, log_name string,
	limits NativeLimits, owner_group int) !NativeRun {
	if owner_group <= 1 || owner_group > 2147483647 || int(C.getpgrp()) != owner_group {
		return error('inherited native guard requires its reserved owner process group')
	}
	return native_guard_run(command, directory, log_name, limits, owner_group)
}

fn native_guard_run(command []string, directory string, log_name string, limits NativeLimits,
	owner_group int) !NativeRun {
	if command.len == 0 || !command[0].starts_with('/') || limits.timeout_ms < 1
		|| limits.timeout_ms > 300000 || limits.file_bytes < 1 || limits.file_bytes > 128 * 1024 * 1024
		|| limits.total_bytes < limits.file_bytes || limits.total_bytes > 256 * 1024 * 1024
		|| limits.log_bytes < 1 || limits.log_bytes > limits.file_bytes
		|| limits.serial_bytes < 1 || limits.serial_bytes > limits.file_bytes
		|| log_name == '' || log_name.contains('/') || !log_name.ends_with('.log') {
		return error('invalid native guard bounds or command')
	}
	if (os.lstat(directory)!).get_filetype() != .directory || os.real_path(directory) != directory {
		return error('guard state must be a canonical ordinary directory')
	}
	native_watch_interrupts()!
	log := directory + '/' + log_name
	if os.exists(log) || os.is_link(log) { return error('guard log already exists') }
	native_require_free(directory, limits.min_free_kib)!
	mut before := NativeTree{}
	native_scan(directory, '', limits, mut before)!
	if before.limited { return error('state already exceeds guard admission limits') }
	mut exec_arguments := []&char{len: command.len + 1, init: unsafe { nil }}
	for index, argument in command { exec_arguments[index] = &char(argument.str) }
	started := time.sys_mono_now()
	pid := C.fork()
	if pid < 0 { return error('native guard fork failed') }
	if pid == 0 {
		if owner_group == 0 {
			if C.setpgid(0, 0) != 0 { C._exit(120) }
		} else if int(C.getpgrp()) != owner_group { C._exit(120) }
		file_limit := C.rlimit{ rlim_cur: limits.file_bytes, rlim_max: limits.file_bytes }
		core_limit := C.rlimit{}
		if C.setrlimit(C.RLIMIT_FSIZE, &file_limit) != 0
			|| C.setrlimit(C.RLIMIT_CORE, &core_limit) != 0 {
			C._exit(121)
		}
		fd := C.open(log.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
		if fd < 0 || C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 { C._exit(122) }
		if fd > 2 { C.close(fd) }
		C.execv(command[0].str, &exec_arguments[0])
		C._exit(125)
	}
	// Standalone children set their group before exec; the parent call narrows
	// immediate-cancellation races. Inherited children never change groups.
	if owner_group == 0 { C.setpgid(pid, pid) }
	mut reaped := false
	mut identity_reserved := true
	mut status := i32(-1)
	mut timed_out := false
	mut limited := false
	mut reason := ''
	mut observed := u64(0)
	mut next_free_check := u64(0)
	for {
		mut current := NativeTree{}
		native_scan(directory, '', limits, mut current) or { reason = err.msg() }
		observed = current.bytes
		limited = current.limited
		elapsed := (time.sys_mono_now() - started) / 1000000
		if elapsed >= next_free_check {
			native_require_free(directory, limits.min_free_kib) or { reason = err.msg() }
			next_free_check = elapsed + 1000
		}
		if native_interrupted != 0 { reason = 'native guard interrupted' }
		waited := raw_waitpid(pid, &status, C.WNOHANG)
		if waited == pid {
			reaped = true
			break
		}
		if waited < 0 && C.errno != C.EINTR {
			reason = 'native leader wait failed'
			identity_reserved = false
			break
		}
		if (time.sys_mono_now() - started) / 1000000 >= u64(limits.timeout_ms) { timed_out = true }
		if timed_out || limited || reason != '' { break }
		time.sleep(10 * time.millisecond)
	}
	mut stopped := false
	if owner_group > 0 {
		// Never signal the shared group or a released numeric identity.
		for _ in 0 .. 200 {
			if reaped { stopped = true; break }
			if !identity_reserved { break }
			C.kill(pid, C.SIGKILL)
			waited := raw_waitpid(pid, &status, C.WNOHANG)
			if waited == pid { reaped = true }
			if waited < 0 && C.errno != C.EINTR { identity_reserved = false }
			time.sleep(10 * time.millisecond)
		}
		stopped = reaped
	} else {
		// Even a successful/failed leader may have left a tool or VM descendant.
		C.kill(-pid, C.SIGKILL)
		if !reaped { C.kill(pid, C.SIGKILL) }
		for _ in 0 .. 200 {
			// A cancellation can precede the child's setpgid. Retry group kill
			// while it settles, and keep the leader stopped until it is reaped.
			C.kill(-pid, C.SIGKILL)
			if !reaped { C.kill(pid, C.SIGKILL) }
			if !reaped && raw_waitpid(pid, &status, C.WNOHANG) == pid { reaped = true }
			if reaped {
				mut descendant_status := i32(0)
				for raw_waitpid(-pid, &descendant_status, C.WNOHANG) > 0 {
				}
			}
			if reaped && C.kill(-pid, 0) < 0 && C.errno == C.ESRCH {
				stopped = true
				break
			}
			time.sleep(10 * time.millisecond)
		}
	}
	mut after := NativeTree{}
	native_scan(directory, '', limits, mut after) or { reason = err.msg() }
	limited = limited || after.limited
	observed = after.bytes
	return NativeRun{
		leader_pid:     pid
		wait_status:    int(status)
		duration_ms:    (time.sys_mono_now() - started) / 1000000
		timed_out:      timed_out
		size_limited:   limited
		stopped:        stopped
		reason:         reason
		observed_bytes: observed
		cleanup_scope:  if owner_group > 0 { 'direct-leader; outer-group-owned' } else { 'leader-and-private-group' }
		owner_group:    owner_group
	}
}
