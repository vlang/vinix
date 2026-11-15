// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import tools.packages.launchhold

#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <grp.h>
#include <signal.h>
#include <errno.h>
#define workload_holder_open open
fn C.workload_holder_open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.fcntl(i32, i32, ...i32) i32
fn C.flock(i32, i32) i32
fn C.prctl(i32, ...voidptr) i32
fn C.fork() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.setsid() i32
fn C.setgroups(u64, voidptr) i32
fn C.setuid(u32) i32
fn C.setgid(u32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.execv(&char, &&char) i32
fn C.alarm(u32) u32
fn C._exit(i32)

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn depth() i32 { return C.prctl(0x56490004, voidptr(0), voidptr(0), voidptr(0), voidptr(0)) }
fn wait_status(pid i32, expected i32) ! {
	mut status := i32(0)
	need(C.waitpid(pid, &status, 0) == pid && status == expected, 'unexpected wait status')!
}
fn await_file(path string) !string {
	deadline := time.sys_mono_now() + 10 * time.second
	for time.sys_mono_now() < deadline {
		if value := os.read_file(path) { if value != '' { return value } }
		time.sleep(time.millisecond)
	}
	return error('handshake missing: ' + path)
}
fn busy(path string, wanted bool) ! {
	fd := C.workload_holder_open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0, 'cannot inspect lease')!
	defer { C.close(fd) }
	result := C.flock(fd, C.LOCK_EX | C.LOCK_NB)
	need(if wanted { result < 0 && C.errno == C.EWOULDBLOCK } else { result == 0 }, 'kernel lease lifetime differs')!
}
fn survivor(work string) ! {
	need(depth() == 1, 'exec lost holder membership')!
	os.write_file(work + '/survivor', C.getpid().str())!
	await_file(work + '/retire')!
	C._exit(37)
}
fn client(work string, mode string, lease i32) ! {
	need(depth() == 1 && C.fcntl(lease, C.F_GETFD) < 0, 'client membership or descriptor boundary differs')!
	if mode == 'cycle' { C._exit(37) }
	os.write_file(work + '/holder', C.getppid().str())!
	middle := C.fork()
	need(middle >= 0, 'middle fork failed')!
	if middle == 0 {
		child := C.fork()
		need(child >= 0, 'survivor fork failed')!
		if child == 0 {
			need(C.setsid() > 0, 'setsid failed')!
			args := [c'/sbin/init', c'--survivor', work.str, &char(unsafe { nil })]!
			C.execv(c'/sbin/init', unsafe { &&char(&args[0]) })
			C._exit(126)
		}
		C._exit(0)
	}
	wait_status(middle, 0)!
	C._exit(37)
}
fn run_owner(work string, mode string) ! {
	need(C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 'identity drop failed')!
	fd := C.workload_holder_open((work + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 3 && C.flock(fd, C.LOCK_SH | C.LOCK_NB) == 0, 'source lock failed')!
	code := launchhold.run(launchhold.Command{program: '/sbin/init', directory: work,
		arguments: ['--client', work, mode, fd.str()], kernel_lease: true}, fd)!
	need(depth() == 0 && C.fcntl(fd, C.F_GETFD) >= 0, 'caller enrolled or borrowed lease closed')!
	C.close(fd)
	C._exit(i32(code))
}
fn cycle(work string, lease_path string) ! {
	pid := C.fork()
	need(pid >= 0, 'owner fork failed')!
	if pid == 0 { run_owner(work, 'cycle')!; return }
	wait_status(pid, 37 << 8)!
	busy(lease_path, false)!
}
fn refusal(work string, baseline bool) ! {
	fd := C.workload_holder_open((work + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 3, 'refusal source open failed')!
	defer { C.close(fd) }
	if baseline { need(C.flock(fd, C.LOCK_SH | C.LOCK_NB) == 0, 'baseline source lock failed')! }
	mut refused := false
	// This client writes its holder identity if exec occurs. No fallback may run.
	launchhold.run(launchhold.Command{program: '/sbin/init', directory: work,
		arguments: ['--client', work, 'life', fd.str()], kernel_lease: true}, fd) or {
		refused = err.msg().contains('setup stage 9 failed')
	}
	need(refused && !os.exists(work + '/holder') && C.fcntl(fd, C.F_GETFD) >= 0, 'attachment failure did not refuse before exec')!
	mut status := i32(0)
	need(C.waitpid(-1, &status, C.WNOHANG) < 0 && C.errno == C.ECHILD, 'refusal left children')!
}
fn slab(buffer &u8) !int {
	fd := C.workload_holder_open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0, 'slab open failed')!
	defer { C.close(fd) }
	mut length := 0
	for length < 8192 {
		got := C.read(fd, unsafe { buffer + length }, u64(8192 - length))
		need(got >= 0, 'slab read failed')!
		if got == 0 { return length }
		length += int(got)
	}
	return error('slab snapshot exceeds bound')
}
fn suite() ! {
	work := '/tmp/workload-holder'
	lease_path := work + '/lease'
	os.mkdir(work)!; os.chmod(work, 0o777)!
	os.write_file(work + '/lease', '')!; os.chmod(work + '/lease', 0o644)!
	$if workload_holder_baseline ? {
		refusal(work, true)!
		println('WORKLOAD HOLDER UNSUPPORTED PASS stage9 no exec no fallback borrowed FD intact no children')
		return
	}
	need(depth() == 0, 'observer membership differs')!
	refusal(work, false)!
	println('WORKLOAD HOLDER REFUSAL PASS unlocked source stage9 no exec no fallback')
	caller := C.fork()
	need(caller >= 0, 'caller fork failed')!
	if caller == 0 { run_owner(work, 'life')!; return }
	holder := await_file(work + '/holder')!.i32()
	worker := await_file(work + '/survivor')!.i32()
	busy(work + '/lease', true)!
	need(C.kill(holder, C.SIGKILL) == 0, 'holder kill failed')!
	wait_status(caller, 137 << 8)!
	need(C.kill(worker, 0) == 0 && depth() == 0, 'survivor gone or observer enrolled')!
	busy(work + '/lease', true)!
	os.write_file(work + '/retire', 'retire')!
	wait_status(worker, 37 << 8)!
	busy(work + '/lease', false)!
	println('WORKLOAD HOLDER DEATH PASS UID1000 holder137 caller outside worker37 double-fork setsid exec final release')
	for _ in 0 .. 32 { cycle(work, lease_path)! }
	mut before := [8192]u8{}
	mut after := [8192]u8{}
	for index in 0 .. 8192 { before[index] = 1; after[index] = 1 }
	slab(unsafe { &before[0] })!; slab(unsafe { &after[0] })!
	$if workload_sites ? { os.read_file('/proc/allocstart')! }
	slab(unsafe { &after[0] })!; time.sleep(13 * time.second)
	before_len := slab(unsafe { &before[0] })!
	for _ in 0 .. 32 { cycle(work, lease_path)! }
	slab(unsafe { &after[0] })!; time.sleep(13 * time.second)
	after_len := slab(unsafe { &after[0] })!
	println('WORKLOAD SLAB BEFORE\n' + unsafe { tos(&before[0], before_len) })
	println('WORKLOAD SLAB AFTER\n' + unsafe { tos(&after[0], after_len) })
	$if workload_sites ? { println('WORKLOAD SITES\n' + os.read_file('/proc/allocsites')!) }
}
fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.workload_holder_open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	C.alarm(180)
	if os.args.len == 3 && os.args[1] == '--survivor' { survivor(os.args[2]) or { eprintln(err); C._exit(125) }; return }
	if os.args.len == 5 && os.args[1] == '--client' { client(os.args[2], os.args[3], os.args[4].i32()) or { eprintln(err); C._exit(125) }; return }
	suite() or { println('HWTEST FAIL workload-holder: ' + err.msg()); return }
	println('HWTEST PASS workload-holder')
}
