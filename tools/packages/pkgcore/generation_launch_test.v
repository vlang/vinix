// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

#include <unistd.h>
#include <grp.h>
#include <sys/wait.h>
#define generation_test_wait waitpid
fn C.generation_test_wait(i32, &i32, i32) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.setsid() i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.alarm(u32) u32

fn generation_need(ok bool, message string) ! { if !ok { return error(message) } }
fn generation_lock(path string, busy bool) ! {
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	generation_need(fd >= 3, 'cannot open independent generation lock')!
	defer { C.close(fd) }
	result := C.flock(fd, C.LOCK_EX | C.LOCK_NB)
	generation_need(if busy { result != 0 && C.errno == C.EAGAIN } else { result == 0 }, 'generation lock lifetime differs')!
}

fn generation_fixture(low bool) ! {
	C.alarm(30)
	root := if low { '/tmp/pkg-generation-launch-low' } else { '/tmp/pkg-generation-launch' }
	os.mkdir(root)!
	os.write_file(root + '/lease', '')!
	lease := C.open((root + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	generation_need(lease >= 3 && C.flock(lease, C.LOCK_SH | C.LOCK_NB) == 0, 'cannot acquire fixture generation lease')!
	caller := C.fork()
	if caller == 0 {
		mut borrowed := lease
		if low {
			C.close(0)
			borrowed = C.fcntl(lease, C.F_DUPFD_CLOEXEC, 0)
			if borrowed != 0 { C._exit(87) }
			C.close(lease)
		}
		launch := Launch{program: '/sbin/init', directory: '/tmp', arguments: ['--generation-client', root]}
		if low {
			if C.fcntl(borrowed, C.F_SETFD, 0) != 0 { C._exit(91) }
			mut refused := false
			run_generation_launch(launch, true, borrowed) or { refused = err.msg().contains('must be close-on-exec'); unsafe { err.free() } }
			if !refused || C.fcntl(borrowed, C.F_GETFD) != 0 || C.fcntl(borrowed, C.F_SETFD, C.FD_CLOEXEC) != 0 { C._exit(92) }
		}
		code := run_generation_launch(launch, true, borrowed) or { eprintln('HWTEST FAIL generation dispatch: ' + err.msg()); C._exit(81); return }
		flags := C.fcntl(borrowed, C.F_GETFD)
		if flags < 0 || flags & C.FD_CLOEXEC == 0 { C._exit(88) }
		generation_lock(root + '/lease', true) or { C._exit(89) }
		C.close(borrowed); C._exit(code)
	}
	C.close(lease)
	generation_need(caller > 0, 'cannot fork generation caller')!
	deadline := time.sys_mono_now() + 10 * time.second
	for !os.exists(root + '/ready') {
		generation_need(time.sys_mono_now() < deadline, 'generation worker readiness timed out')!
		time.sleep(time.millisecond)
	}
	mut status := i32(0)
	generation_need(C.generation_test_wait(caller, &status, C.WNOHANG) == 0, 'generation caller returned before descendant')!
	generation_lock(root + '/lease', true)!
	os.write_file(root + '/release', 'release')!
	generation_need(C.generation_test_wait(caller, &status, 0) == caller && status == 37 << 8, 'generation initial client status lost')!
	generation_lock(root + '/lease', false)!
	// Refuse a missing lease before creating a Windows workload.
	mut refused := false
	run_generation_launch(Launch{program: '/sbin/init', directory: '/tmp'}, true, -1) or {
		refused = err.msg().contains('live close-on-exec lease'); unsafe { err.free() }
	}
	generation_need(refused, 'Windows launch accepted missing generation lease')!
	// A non-Windows launch keeps its old cwd/exec diagnostics without a lease.
	mut old_path := false
	run_generation_launch(Launch{program: '/missing', directory: '/tmp'}, false, -1) or {
		old_path = err.msg().contains('cannot execute application program'); unsafe { err.free() }
	}
	generation_need(old_path, 'non-Windows dispatch changed launch path')!
}

fn testsuite_begin() {
	$if generation_launch_fixture ? {
		if os.args.len == 3 && os.args[1] == '--generation-client' {
			root := os.args[2]
			if root.ends_with('-low') && C.fcntl(0, C.F_GETFD) >= 0 { C._exit(90) }
			owner := C.getppid()
			middle := C.fork()
			if middle == 0 {
				worker := C.fork()
				if worker > 0 { C._exit(0) }
				if worker < 0 || C.setsid() < 0 { C._exit(82) }
				for C.getppid() != owner { time.sleep(time.millisecond) }
				os.write_file(root + '/ready', 'ready') or { C._exit(83) }
				for !os.exists(root + '/release') { time.sleep(time.millisecond) }
				C._exit(23)
			}
			mut status := i32(0)
			if middle <= 0 || C.generation_test_wait(middle, &status, 0) != middle || status != 0 { C._exit(84) }
			C._exit(37)
		}
	}
}

fn test_generation_launch_dispatch() {
	$if generation_launch_fixture ? {
		if C.getpid() != 1 { panic('generation fixture requires PID1') }
		fd := C.open(c'/dev/com1', C.O_WRONLY)
		if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
		os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
		pid := C.fork()
		if pid == 0 {
			if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(85) }
			generation_fixture(false) or { eprintln('HWTEST FAIL generation launch: ' + err.msg()); C._exit(86) }
			generation_fixture(true) or { eprintln('HWTEST FAIL generation launch: ' + err.msg()); C._exit(86) }
			C._exit(0)
		}
		mut status := i32(0)
		if pid <= 0 || C.generation_test_wait(pid, &status, 0) != pid || status != 0 {
			eprintln('HWTEST FAIL generation launch fixture'); for { time.sleep(time.second) }
		}
		println('HWTEST PASS generation launch: holder adoption; lease lifetime; status37; missing lease; non-Windows dispatch; low descriptor isolation')
		for { time.sleep(time.second) }
	}
}
