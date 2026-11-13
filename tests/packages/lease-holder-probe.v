// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.launchhold

#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <sys/prctl.h>
#include <signal.h>
#include <grp.h>
#include <pthread.h>
#include <sys/syscall.h>
#include <sys/resource.h>
fn C.open(&char, i32, ...i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.flock(i32, i32) i32
fn C.fork() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.setsid() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.prctl(i32, ...voidptr) i32
fn C.kill(i32, i32) i32
fn C.raise(i32) i32
fn C.alarm(u32) u32
fn C._exit(i32)
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.dup2(i32, i32) i32
fn C.signal(i32, voidptr) voidptr
fn C.pthread_atfork(voidptr, voidptr, voidptr) i32
fn C.syscall(i64, ...) i64

fn fork_callback() { C._exit(97) }
fn unexpected_signal(_ i32) { C._exit(99) }

struct ProbeLimit { current u64 maximum u64 }
fn limit_read(resource i32) !ProbeLimit {
	mut value := ProbeLimit{}
	if C.syscall(C.SYS_prlimit64, u64(0), resource, voidptr(0), &value) != 0 { return error('cannot read fixture limit') }
	return value
}
fn limit_set(resource i32, value &ProbeLimit) ! {
	if C.syscall(C.SYS_prlimit64, u64(0), resource, value, voidptr(0)) != 0 { return error('cannot set fixture limit') }
}

fn wait_exit(pid i32, code i32) ! {
	mut status := i32(0)
	for {
		result := C.waitpid(pid, &status, 0)
		if result < 0 && C.errno == C.EINTR { continue }
		if result != pid || status != code { return error('process status differs: ' + status.str()) }
		return
	}
}
fn await_file(path string) ! {
	deadline := time.sys_mono_now() + 10 * time.second
	for !os.exists(path) {
		if time.sys_mono_now() > deadline { return error('missing fixture marker: ' + path) }
		time.sleep(time.millisecond)
	}
}
fn no_children() ! {
	mut status := i32(0)
	if C.waitpid(-1, &status, C.WNOHANG) != -1 || C.errno != C.ECHILD { return error('unexpected children remain') }
}
fn lock_busy(path string, wanted bool) ! {
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open independent lease probe') }
	defer { C.close(fd) }
	result := C.flock(fd, C.LOCK_EX | C.LOCK_NB)
	if wanted {
		if result == 0 || C.errno != C.EAGAIN { return error('live workload lease was not busy') }
	} else if result != 0 { return error('retired or unrelated lease remained busy') }
}

fn client() ! {
	root := os.args[2]; mode := os.args[3]; lease := i32(os.args[4].int())
	if C.fcntl(lease, C.F_GETFD) >= 0 { return error('workload inherited holder lease') }
	C.raise(C.SIGUSR2) // The caller deliberately ignored this disposition.
	owner := C.getppid()
	os.write_file(root + '/holder', owner.str())!
	middle := C.fork()
	if middle < 0 { return error('workload middle fork failed') }
	if middle == 0 {
		worker := C.fork()
		if worker < 0 { C._exit(80) }
		if worker > 0 { C._exit(0) }
		C.alarm(15)
		if C.setsid() < 0 { C._exit(81) }
		deadline := time.sys_mono_now() + 5 * time.second
		for C.getppid() != owner {
			if time.sys_mono_now() > deadline { C._exit(82) }
			time.sleep(time.millisecond)
		}
		os.write_file(root + '/ready', C.getpid().str()) or { C._exit(83) }
		for !os.exists(root + '/release') { time.sleep(time.millisecond) }
		C._exit(23)
	}
	wait_exit(middle, 0)!
	os.write_file(root + '/client-gone', 'ready')!
	if mode == 'signal' { C.raise(C.SIGTERM); C._exit(99) }
	C._exit(i32(mode.int()))
}

fn lifetime(root string, mode string, kill_caller bool, cancel_holder bool, high_fd bool, fault bool) ! {
	os.mkdir(root)!
	os.write_file(root + '/lease', '')!; os.write_file(root + '/unrelated', '')!
	mut lease := C.open((root + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	other := C.open((root + '/unrelated').str, C.O_RDONLY | C.O_CLOEXEC)
	if lease < 3 || other < 3 || C.flock(lease, C.LOCK_SH | C.LOCK_NB) != 0 || C.flock(other, C.LOCK_SH | C.LOCK_NB) != 0 { return error('fixture shared locks failed') }
	if high_fd {
		moved := C.fcntl(lease, C.F_DUPFD_CLOEXEC, 128)
		if moved < 128 { return error('high descriptor setup failed') }
		C.close(lease); lease = moved
	}
	caller := C.fork()
	if caller < 0 { return error('fixture caller fork failed') }
	if caller == 0 {
		if C.pthread_atfork(unsafe { nil }, unsafe { nil }, voidptr(fork_callback)) != 0 { C._exit(94) }
		mut unrelated_child := i32(-1)
		if !kill_caller {
			unrelated_child = C.fork()
			if unrelated_child < 0 { C._exit(95) }
			if unrelated_child == 0 { C._exit(96) } // Callback must exit 97 first.
		}
		C.signal(C.SIGUSR2, C.SIG_IGN)
		mut before_mask := u64(0)
		if C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, voidptr(0), &before_mask, u64(8)) != 0 { C._exit(93) }
		mut reaper := i32(-1)
		if C.prctl(37, &reaper, voidptr(0), voidptr(0), voidptr(0)) != 0 || reaper != 0 { C._exit(84) }
		code := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp', arguments: ['client', root, mode, lease.str()]}, lease) or { eprintln(err); C._exit(85); return }
		mut after_mask := u64(0)
		if C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, voidptr(0), &after_mask, u64(8)) != 0 || before_mask != after_mask { C._exit(92) }
		if unrelated_child > 0 { wait_exit(unrelated_child, 97 << 8) or { C._exit(91) } }
		if C.fcntl(lease, C.F_GETFD) < 0 || C.prctl(37, &reaper, voidptr(0), voidptr(0), voidptr(0)) != 0 || reaper != 0 { C._exit(86) }
		C.close(lease); C.close(other)
		C._exit(i32(code))
	}
	C.close(lease); C.close(other)
	await_file(root + '/ready')!; await_file(root + '/client-gone')!; await_file(root + '/holder')!
	holder := i32(os.read_file(root + '/holder')!.int())
	mut status := i32(0)
	if C.waitpid(caller, &status, C.WNOHANG) != 0 { return error('holder returned before descendant retirement') }
	lock_busy(root + '/lease', true)!
	if cancel_holder {
		if C.kill(holder, C.SIGTERM) != 0 { return error('cannot signal holder') }
		time.sleep(30 * time.millisecond)
		lock_busy(root + '/lease', true)!
	}
	if kill_caller {
		if C.kill(caller, C.SIGTERM) != 0 { return error('cannot signal caller') }
		wait_exit(caller, C.SIGTERM)!
		lock_busy(root + '/lease', true)!
		lock_busy(root + '/unrelated', false)!
	}
	os.write_file(root + '/release', 'release')!
	if fault {
		time.sleep(100 * time.millisecond)
		lock_busy(root + '/lease', true)!
		// SIGKILL is an explicit limitation of the primitive, not cancellation.
		if C.kill(holder, C.SIGKILL) != 0 { return error('cannot retire fault-control holder') }
		wait_exit(holder, C.SIGKILL)!
		// The forced wait error prevented reaping the worker; this subreaper
		// must adopt it after the intentionally killed control holder.
		worker := i32(os.read_file(root + '/ready')!.int())
		wait_exit(worker, 23 << 8)!
	} else if kill_caller {
		wanted := if mode == 'signal' { i32(143) } else { i32(mode.int()) }
		wait_exit(holder, wanted << 8)!
	} else {
		wanted := if mode == 'signal' { i32(143) } else { i32(mode.int()) }
		wait_exit(caller, wanted << 8)!
	}
	lock_busy(root + '/lease', false)!
	no_children()!
}

fn concurrent_holders(kill_first bool) ! {
	base := if kill_first { '/tmp/concurrent-orphan-' } else { '/tmp/concurrent-holder-' }
	mut callers := [i32(0), i32(0)]!
	for index in 0 .. 2 {
		root := base + index.str()
		os.mkdir(root)!
		os.write_file(root + '/lease', '')!
		lease := C.open((root + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
		if lease < 3 || C.flock(lease, C.LOCK_SH | C.LOCK_NB) != 0 { return error('concurrent lease setup failed') }
		caller := C.fork()
		if caller < 0 { return error('concurrent caller fork failed') }
		if caller == 0 {
			C.signal(C.SIGUSR2, C.SIG_IGN)
			code := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp',
				arguments: ['client', root, if index == 0 { '37' } else { '126' }, lease.str()]}, lease) or { C._exit(85); return }
			C.close(lease)
			C._exit(i32(code))
		}
		C.close(lease)
		callers[index] = caller
	}
	outsider := C.fork()
	if outsider < 0 { return error('unrelated child fork failed') }
	if outsider == 0 { C._exit(97) }
	for index in 0 .. 2 {
		root := base + index.str()
		await_file(root + '/ready')!
		await_file(root + '/client-gone')!
		lock_busy(root + '/lease', true)!
		mut status := i32(0)
		if C.waitpid(callers[index], &status, C.WNOHANG) != 0 { return error('concurrent holder retired early') }
	}
	mut first_owner := callers[0]
	if kill_first {
		await_file(base + '0/holder')!
		first_owner = i32(os.read_file(base + '0/holder')!.int())
		if first_owner <= 1 || first_owner == callers[0] { return error('invalid concurrent holder identity') }
		if C.kill(callers[0], C.SIGKILL) != 0 { return error('cannot kill concurrent caller') }
		wait_exit(callers[0], C.SIGKILL)!
		lock_busy(base + '0/lease', true)!
		lock_busy(base + '1/lease', true)!
	}
	// Retire in reverse order, requiring the other holder's lock to survive.
	os.write_file(base + '1/release', '')!
	wait_exit(callers[1], 126 << 8)!
	lock_busy(base + '1/lease', false)!
	lock_busy(base + '0/lease', true)!
	wait_exit(outsider, 97 << 8)!
	os.write_file(base + '0/release', '')!
	wait_exit(first_owner, 37 << 8)!
	lock_busy(base + '0/lease', false)!
	no_children()!
	if kill_first {
		println('LEASE HOLDER CONCURRENT DEATH PASS caller SIGKILL; adopted holder37; independent caller126; unrelated child97')
	} else {
		println('LEASE HOLDER CONCURRENT PASS independent leases and statuses; unrelated child waitable')
	}
}

fn refusals() ! {
	os.write_file('/tmp/refusal-lease', '')!
	lease := C.open(c'/tmp/refusal-lease', C.O_RDONLY | C.O_CLOEXEC)
	if lease < 3 || C.flock(lease, C.LOCK_SH | C.LOCK_NB) != 0 { return error('refusal lease failed') }
	defer { C.close(lease) }
	for command in [launchhold.Command{program: '/sbin/init', directory: '/missing-holder-directory'},
		launchhold.Command{program: '/missing-holder-executable', directory: '/tmp'}] {
		if _ := launchhold.run(command, lease) { return error('setup failure accepted') }
		else { if !err.msg().contains('setup stage ') { return error('wrong setup failure') }; unsafe { err.free() } }
		no_children()!
		if C.fcntl(lease, C.F_GETFD) < 0 { return error('refusal closed borrowed lease') }
	}
	for fd in [i32(-1), 0, 1000000]! {
		if _ := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp'}, fd) { return error('invalid lease accepted') }
		else { unsafe { err.free() } }
		no_children()!
	}
	if C.fcntl(lease, C.F_SETFD, 0) != 0 { return error('cannot remove fixture CLOEXEC') }
	if _ := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp'}, lease) { return error('inheritable lease accepted') }
	else { unsafe { err.free() } }
	if C.fcntl(lease, C.F_SETFD, C.FD_CLOEXEC) != 0 { return error('cannot restore fixture CLOEXEC') }
	for resource in [i32(C.RLIMIT_NPROC), C.RLIMIT_NOFILE]! {
		original := limit_read(resource)!
		limited := ProbeLimit{current: if resource == C.RLIMIT_NPROC { u64(0) } else { u64(3) }, maximum: original.maximum}
		mut before_mask := u64(0)
		if C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, voidptr(0), &before_mask, u64(8)) != 0 { return error('cannot read pre-refusal mask') }
		limit_set(resource, &limited)!
		mut refused := false
		if _ := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp'}, lease) {}
		else { refused = err.msg().contains(if resource == C.RLIMIT_NPROC { 'cannot fork generation lease holder' } else { 'cannot create holder status pipe' }); unsafe { err.free() } }
		limit_set(resource, &original)!
		if !refused { return error('resource exhaustion did not refuse before workload start') }
		mut after_mask := u64(0)
		if C.syscall(C.SYS_rt_sigprocmask, C.SIG_SETMASK, voidptr(0), &after_mask, u64(8)) != 0 || before_mask != after_mask { return error('resource refusal changed caller signal mask') }
		no_children()!
	}
	C.signal(C.SIGCHLD, C.SIG_IGN)
	if _ := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp'}, lease) {
		C.signal(C.SIGCHLD, C.SIG_DFL); return error('unwaitable caller accepted')
	} else { unsafe { err.free() } }
	C.signal(C.SIGCHLD, C.SIG_DFL)
	no_children()!
	no_wait := [u64(0), u64(C.SA_NOCLDWAIT), 0, 0]!
	mut previous_action := [4]u64{}
	if C.syscall(C.SYS_rt_sigaction, C.SIGCHLD, &no_wait[0], &previous_action[0], u64(8)) != 0 { return error('cannot set fixture no-child-wait policy') }
	mut no_wait_refused := false
	if _ := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp'}, lease) {}
	else { no_wait_refused = err.msg().contains('default SIGCHLD'); unsafe { err.free() } }
	if C.syscall(C.SYS_rt_sigaction, C.SIGCHLD, &previous_action[0], voidptr(0), u64(8)) != 0 { return error('cannot restore fixture child policy') }
	if !no_wait_refused { return error('no-child-wait caller accepted') }
	no_children()!
}
fn suite() ! {
	C.alarm(60)
	if C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) != 0 { return error('fixture subreaper setup failed') }
	$if lease_holder_signal_window ? {
		os.write_file('/tmp/signal-window-lease', '')!
		lease := C.open(c'/tmp/signal-window-lease', C.O_RDONLY | C.O_CLOEXEC)
		if lease < 3 || C.flock(lease, C.LOCK_SH | C.LOCK_NB) != 0 { return error('signal-window lease setup failed') }
		C.signal(C.SIGUSR1, voidptr(unexpected_signal))
		result := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp', arguments: ['unreachable']}, lease)!
		C.signal(C.SIGUSR1, C.SIG_DFL)
		C.close(lease)
		if result == 99 { return error('inherited handler ran before exec') }
		if result != 128 + C.SIGUSR1 { return error('signal window status differs') }
		no_children()!
		println('LEASE HOLDER SIGNAL PASS caught handler reset before unmask; pending signal preserves default status')
		return
	}
	$if lease_holder_wait_fault ? {
		lifetime('/tmp/holder-fault', '37', true, false, false, true)!
		println('LEASE HOLDER FAULT PASS retained lease after wait error and caller death; SIGKILL limitation explicit')
		return
	}
	for mode in ['37', '126', '127', 'signal']! { lifetime('/tmp/holder-' + mode, mode, false, false, false, false)! }
	lifetime('/tmp/holder-caller-death', '37', true, false, false, false)!
	lifetime('/tmp/holder-cancellation', '37', false, true, true, false)!
	refusals()!
	concurrent_holders(false)!
	concurrent_holders(true)!
	println('LEASE HOLDER PASS statuses 37/126/127/143; double-fork setsid; caller death; cancellation; descriptor isolation; setup refusals')
}
fn main() {
	if os.args.len > 1 && os.args[1] == 'client' { client() or { eprintln(err); exit(98) }; return }
	if C.getpid() != 1 { eprintln('requires fixture PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		suite() or { eprintln('HWTEST FAIL lease-holder: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	if pid < 0 { eprintln('HWTEST FAIL lease-holder: fork'); for { time.sleep(time.second) } }
	wait_exit(pid, 0) or { eprintln('HWTEST FAIL lease-holder: ' + err.msg()); for { time.sleep(time.second) } }
	println('HWTEST PASS lease-holder fixture')
	for { time.sleep(time.second) }
}
