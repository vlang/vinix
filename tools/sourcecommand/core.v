// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecommand

import os
import strings
import time

#flag -I @DIR
#include "abi.h"
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

@[typedef]
struct C.vinix_source_child_info { si_pid i32 si_code i32 si_status i32 }
@[typedef]
struct C.posix_spawn_file_actions_t {}
@[typedef]
struct C.posix_spawnattr_t {}
@[typedef]
struct C.sigset_t {}
struct C.pollfd { mut: fd i32 events i16 revents i16 }
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawn_file_actions_addchdir_np(voidptr, &char) i32
fn C.posix_spawn_file_actions_addinherit_np(voidptr, i32) i32
fn C.posix_spawnattr_init(voidptr) i32
fn C.posix_spawnattr_destroy(voidptr) i32
fn C.posix_spawnattr_setpgroup(voidptr, i32) i32
fn C.posix_spawnattr_setflags(voidptr, i16) i32
fn C.posix_spawnattr_setsigdefault(voidptr, voidptr) i32
fn C.posix_spawnattr_setbinpref_np(voidptr, usize, &i32, &usize) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.waitid(i32, u32, &C.vinix_source_child_info, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.killpg(i32, i32) i32
fn C.mkdtemp(&char) &char

pub fn temporary(prefix string) !string {
	base := if os.getenv('TMPDIR') != '' { os.getenv('TMPDIR') } else { os.temp_dir() }
	mut name := (base + '/' + prefix + '.XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(name.data)) { return os.error_posix() }
	return name.bytestr().all_before('\x00')
}

pub struct Output { pub: status int stdout string stderr string }

// Only use from a run_owned/capture_owned callback, which reserves the PID
// until this observation and all callback work have finished.
pub fn child_exited(pid int) !bool {
	mut info := C.vinix_source_child_info{}
	for {
		if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	return info.si_pid == pid
}

pub struct ChildExit {
pub:
	exited bool
	return_code int
}

// Observe Python/Popen-style signed return codes without releasing the
// leader identity. The command owner still performs the sole final reap.
pub fn child_exit(pid int) !ChildExit {
	mut info := C.vinix_source_child_info{}
	for {
		if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 { break }
		if C.errno != C.EINTR { return os.error_posix() }
	}
	if info.si_pid != pid { return ChildExit{} }
	return ChildExit{true, if info.si_code == C.CLD_EXITED { int(info.si_status) } else { -int(info.si_status) }}
}

// Keep the child unreaped until its private group is retired. Drain both pipes
// concurrently, cap memory before append, and check cancellation on every poll.
pub fn capture(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool) !Output {
	return capture_observed(argv, env, timeout, limit, cancel, unsafe { nil }, unsafe { nil }, 0)
}

// Byte-comparison fixtures need both complete streams. Ordinary command
// diagnostics retain their existing 64 KiB stderr prefix policy.
pub fn capture_full(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool) !Output {
 if limit < 0 { return error('invalid command output limit') }
 return capture_stream_policy_arch(argv,env,timeout,limit,cancel,unsafe { nil },unsafe { nil },unsafe { nil },0,false,false,'','',false,'','',false,limit,true)
}

// Use one SDK pipe for both child streams when the caller's original command
// used stderr=STDOUT. Preserve their write ordering and one output bound.
pub fn capture_combined(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool) !Output {
	return capture_policy(argv, env, timeout, limit, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, true, false, '', '', false, '')
}

// Preserve a supplied argv[0] for independent executable oracles. The SDK
// still resolves the explicit executable without a shell.
pub fn capture_as(executable string, argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool) !Output {
	if executable == '' || executable.contains('\x00') { return error('invalid executable') }
	return capture_policy(argv, env, timeout, limit, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, false, false, executable, '', false, '')
}

// Prefer the original host architecture for universal Darwin compiler tools.
// Spawn, cancellation, process-group retirement and the sole reap stay owned
// by the same SDK path as ordinary commands.
pub fn capture_preferred(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool, host_arch string) !Output {
	return capture_policy_arch(argv, env, timeout, limit, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, false, false, '', '', false, '', host_arch, false)
}

pub fn capture_stdout_preferred(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool, host_arch string) !Output {
	return capture_policy_arch(argv, env, timeout, limit, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, false, false, '', '', false, '', host_arch, true)
}

pub fn run_preferred(argv []string, env map[string]string, cancel fn () bool, host_arch string) !Output {
	return capture_policy_arch(argv, env, -1, 0, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, false, true, '', '', false, '', host_arch, false)
}

// Native builders choose a working directory through SDK spawn actions while
// retaining the same group owner, cancellation and sole reap as other calls.
pub fn run_in(argv []string, env map[string]string, directory string, cancel fn () bool, host_arch string) !Output {
	return capture_policy_arch(argv, env, -1, 0, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, false, true, '', '', false, directory, host_arch, false)
}

pub fn capture_in(argv []string, env map[string]string, directory string, merge bool, cancel fn () bool, host_arch string) !Output {
 return capture_policy_arch(argv, env, -1, 64 * 1024 * 1024, cancel, unsafe { nil }, unsafe { nil }, unsafe { nil }, 0, merge, false, '', '', false, directory, host_arch, false)
}

// A synchronous owner may inspect a live child through WNOWAIT while the
// child inherits stdout/stderr. Its callback finishes before the sole reap;
// verbose emulators cannot block behind undrained capture pipes.
pub fn run_owned(argv []string, env map[string]string, cancel fn () bool, spawned fn (int, voidptr) !, context voidptr) !Output {
	return capture_policy(argv, env, -1, 0, cancel, unsafe { nil }, spawned, context, 0, false, true, '', '', false, '')
}

// SDK file actions stream both child outputs directly into an owned log.
// A synchronous observer retains the leader identity through group retirement
// and the sole reap; verbose children cannot fill an undrained capture pipe.
pub fn run_logged_owned(argv []string, env map[string]string, cancel fn () bool, log string,
	append bool, directory string, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64) !Output {
	if log == '' || log.contains('\x00') { return error('invalid command log') }
	return capture_policy(argv, env, -1, 0, cancel, unsafe { nil }, spawned, context, shutdown_grace,
		false, true, '', log, append, directory)
}

pub fn capture_observed(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool,
	observe fn (string, voidptr) !, context voidptr, shutdown_grace f64) !Output {
	return capture_owned(argv, env, timeout, limit, cancel, observe, unsafe { nil }, context, shutdown_grace)
}

pub fn capture_owned(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool,
	observe fn (string, voidptr) !, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64) !Output {
	return capture_policy(argv, env, timeout, limit, cancel, observe, spawned, context, shutdown_grace, false, false, '', '', false, '')
}

fn capture_policy(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool,
	observe fn (string, voidptr) !, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64, combined bool, inherited bool, executable string, log string, append bool, directory string) !Output {
	return capture_policy_arch(argv, env, timeout, limit, cancel, observe, spawned, context, shutdown_grace, combined, inherited, executable, log, append, directory, '', false)
}

fn capture_policy_arch(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool,
	observe fn (string, voidptr) !, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64, combined bool, inherited bool, executable string, log string, append bool, directory string, host_arch string, stderr_inherited bool) !Output {
 return capture_stream_policy_arch(argv,env,timeout,limit,cancel,observe,spawned,context,shutdown_grace,combined,inherited,executable,log,append,directory,host_arch,stderr_inherited,64 * 1024,false)
}

fn capture_stream_policy_arch(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool,
 observe fn (string, voidptr) !, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64, combined bool, inherited bool, executable string, log string, append bool, directory string, host_arch string, stderr_inherited bool, stderr_limit int, strict_stderr bool) !Output {
	return capture_stream_input_arch(argv, env, timeout, limit, cancel, observe, spawned, context, shutdown_grace, combined, inherited, executable, log, append, directory, host_arch, stderr_inherited, stderr_limit, strict_stderr, -1)!
}

fn capture_stream_input_arch(argv []string, env map[string]string, timeout f64, limit int, cancel fn () bool,
 observe fn (string, voidptr) !, spawned fn (int, voidptr) !, context voidptr, shutdown_grace f64, combined bool, inherited bool, executable string, log string, append bool, directory string, host_arch string, stderr_inherited bool, stderr_limit int, strict_stderr bool, input i32) !Output {
	if argv.len == 0 || argv.any(it.contains('\x00')) { return error('invalid command') }
	mut pipes := [i32(-1), -1, -1, -1]!
	defer { for fd in pipes { if fd >= 0 { C.close(fd) } } }
	if C.pipe(&pipes[0]) != 0 || C.pipe(&pipes[2]) != 0 { return os.error_posix() }
	for index in 0 .. 4 {
		if pipes[index] < 3 {
			fd := C.fcntl(pipes[index], C.F_DUPFD_CLOEXEC, 3)
			if fd < 0 { return os.error_posix() }
			C.close(pipes[index]); pipes[index] = fd
		}
		if C.fcntl(pipes[index], C.F_SETFD, C.FD_CLOEXEC) != 0 { return os.error_posix() }
	}
	mut log_fd := i32(-1)
	defer { if log_fd >= 0 { C.close(log_fd) } }
	if log != '' {
		log_fd = unsafe { C.open(log.str, C.O_WRONLY | C.O_CREAT | C.O_CLOEXEC | if append { C.O_APPEND } else { C.O_TRUNC }, 0o666) }
		if log_fd < 0 { return os.error_posix() }
		if log_fd < 3 {
			moved := C.fcntl(log_fd, C.F_DUPFD_CLOEXEC, 3)
			if moved < 0 { return os.error_posix() }
			C.close(log_fd)
			log_fd = moved
		}
	}
	mut actions := C.posix_spawn_file_actions_t{}
	if C.posix_spawn_file_actions_init(&actions) != 0 { return error('cannot initialize spawn actions') }
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	if input >= 3 {
		if C.posix_spawn_file_actions_adddup2(&actions, input, 0) != 0 || C.posix_spawn_file_actions_addclose(&actions, input) != 0 { return error('cannot configure command input') }
	}
	if directory != '' {
		if directory.contains('\x00') { return error('invalid command directory') }
		status := C.posix_spawn_file_actions_addchdir_np(&actions, directory.str)
		if status != 0 { return error_with_code('cannot configure command directory', int(status)) }
	}
	if !inherited || log_fd >= 0 {
		mut statuses := [C.posix_spawn_file_actions_adddup2(&actions, if log_fd >= 0 { log_fd } else { pipes[1] }, 1)]
		if !stderr_inherited || log_fd >= 0 { statuses << C.posix_spawn_file_actions_adddup2(&actions, if log_fd >= 0 { log_fd } else if combined { pipes[1] } else { pipes[3] }, 2) }
		for status in statuses {
			if status != 0 { return error_with_code('cannot configure spawn streams', int(status)) }
		}
	}
	if log_fd >= 0 && C.posix_spawn_file_actions_addclose(&actions, log_fd) != 0 { return error('cannot configure command log') }
	for status in [C.posix_spawn_file_actions_addclose(&actions, pipes[0]), C.posix_spawn_file_actions_addclose(&actions, pipes[1]),
		C.posix_spawn_file_actions_addclose(&actions, pipes[2]), C.posix_spawn_file_actions_addclose(&actions, pipes[3])] {
		if status != 0 { return error_with_code('cannot configure spawn actions', int(status)) }
	}
	mut attributes := C.posix_spawnattr_t{}
	if C.posix_spawnattr_init(&attributes) != 0 { return error('cannot initialize spawn attributes') }
	defer { C.posix_spawnattr_destroy(&attributes) }
	mut signals := C.sigset_t{}
	$if macos {
		C.sigemptyset(unsafe { &u32(&signals) })
		for signal in [C.SIGINT, C.SIGTERM, C.SIGPIPE] { C.sigaddset(unsafe { &u32(&signals) }, signal) }
	} $else {
		C.sigemptyset(&signals)
		for signal in [C.SIGINT, C.SIGTERM, C.SIGPIPE] { C.sigaddset(&signals, signal) }
	}
	mut flags := i16(C.POSIX_SPAWN_SETPGROUP | C.POSIX_SPAWN_SETSIGDEF)
	$if macos {
		flags |= i16(C.POSIX_SPAWN_CLOEXEC_DEFAULT)
		if input < 3 && C.fcntl(0, C.F_GETFD) >= 0 && C.posix_spawn_file_actions_addinherit_np(&actions, 0) != 0 { return error('cannot preserve command stdin') }
		if inherited && log_fd < 0 { for fd in [1,2] { if C.fcntl(fd, C.F_GETFD) >= 0 && C.posix_spawn_file_actions_addinherit_np(&actions, fd) != 0 { return error('cannot preserve command output') } } }
		if !inherited && stderr_inherited && log_fd < 0 && C.fcntl(2, C.F_GETFD) >= 0 && C.posix_spawn_file_actions_addinherit_np(&actions, 2) != 0 { return error('cannot preserve command stderr') }
	}
	for status in [C.posix_spawnattr_setpgroup(&attributes, 0), C.posix_spawnattr_setsigdefault(&attributes, &signals),
		C.posix_spawnattr_setflags(&attributes, flags)] {
		if status != 0 { return error_with_code('cannot configure spawn attributes', int(status)) }
	}
	$if macos {
		cpu := match host_arch.to_lower() {
			'arm64', 'aarch64' { i32(C.CPU_TYPE_ARM64) }
			'amd64', 'x86_64' { i32(C.CPU_TYPE_X86_64) }
			else { i32(0) }
		}
		if cpu != 0 {
			preferences := [cpu, i32(C.CPU_TYPE_ANY)]!
			mut selected := usize(0)
			status := C.posix_spawnattr_setbinpref_np(&attributes, 2, &preferences[0], &selected)
			if status != 0 { return error_with_code('cannot configure host architecture preference', int(status)) }
			if selected != 2 { return error('incomplete host architecture preference') }
		}
	}
	mut args := []&char{}
	for value in argv { args << unsafe { &char(value.str) } }
	args << &char(unsafe { nil })
	mut env_text := []string{}
	for name, value in env { if name.contains('\x00') || value.contains('\x00') { return error('invalid command environment') }; env_text << name + '=' + value }
	mut environment := []&char{}
	for value in env_text { environment << unsafe { &char(value.str) } }
	environment << &char(unsafe { nil })
	mut pid := i32(0)
	program := if executable == '' { argv[0] } else { executable }
	spawn_status := C.posix_spawnp(&pid, program.str, &actions, &attributes, args.data, environment.data)
	if spawn_status != 0 { return error_with_code('cannot start ' + argv[0], int(spawn_status)) }
	mut raw := i32(0)
	defer {
		if shutdown_grace > 0 {
			C.killpg(pid, C.SIGTERM)
			deadline := time.sys_mono_now() + u64(shutdown_grace * f64(time.second))
			for time.sys_mono_now() < deadline {
				mut observed := C.vinix_source_child_info{}
				if C.waitid(C.P_PID, u32(pid), &observed, C.WEXITED | C.WNOHANG | C.WNOWAIT) == 0 && observed.si_pid == pid { break }
				time.sleep(10 * time.millisecond)
			}
		}
		C.killpg(pid, C.SIGKILL)
		C.kill(pid, C.SIGKILL)
		for { if C.waitpid(pid, &raw, 0) >= 0 || C.errno != C.EINTR { break } }
	}
	if spawned != unsafe { nil } { spawned(int(pid), context)! }
	C.close(pipes[1]); pipes[1] = -1
	C.close(pipes[3]); pipes[3] = -1
	mut streams := [C.pollfd{fd: pipes[0], events: i16(C.POLLIN)}, C.pollfd{fd: pipes[2], events: i16(C.POLLIN)}]!
	mut stdout := strings.new_builder(8192)
	mut stderr := strings.new_builder(1024)
	started := time.sys_mono_now()
	mut buffer := [8192]u8{}
	for {
		if cancel != unsafe { nil } && cancel() { return error('command interrupted') }
		if timeout >= 0 && f64(time.sys_mono_now() - started) >= timeout * f64(time.second) { return error('command timed out') }
		mut observed := C.vinix_source_child_info{}
		if C.waitid(C.P_PID, u32(pid), &observed, C.WEXITED | C.WNOHANG | C.WNOWAIT) != 0 && C.errno != C.EINTR { return os.error_posix() }
		if streams[0].fd < 0 && streams[1].fd < 0 && observed.si_pid == pid { break }
		if C.poll(&streams[0], 2, 50) < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
		for index in 0 .. 2 {
			if streams[index].fd < 0 || streams[index].revents == 0 { continue }
			count := C.read(streams[index].fd, &buffer[0], buffer.len)
			if count < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
			if count == 0 { C.close(streams[index].fd); pipes[index * 2] = -1; streams[index].fd = -1; continue }
			if index == 0 {
				if stdout.len > limit - int(count) { return error('command output exceeds limit') }
				stdout.write(buffer[..int(count)])!
				if observe != unsafe { nil } { observe(buffer[..int(count)].bytestr(), context)! }
			} else {
    if strict_stderr && stderr.len > stderr_limit - int(count) { return error('command stderr exceeds limit') }
    if stderr.len < stderr_limit { stderr.write(buffer[..int_min(int(count), stderr_limit - stderr.len)])! }
			}
		}
	}
	// Observe the SDK status while still reserving the PID; the defer retires
	// the group and performs the only reap before any caller can reuse it.
	mut info := C.vinix_source_child_info{}
	if C.waitid(C.P_PID, u32(pid), &info, C.WEXITED | C.WNOWAIT) != 0 { return os.error_posix() }
	return Output{child_status(info), stdout.str(), stderr.str()}
}

fn child_status(info C.vinix_source_child_info) int {
	return if info.si_code == C.CLD_EXITED { int(info.si_status) } else { -int(info.si_status) }
}
