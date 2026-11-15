// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <grp.h>
#include <signal.h>
#include <errno.h>
#include <sys/syscall.h>
#define workload_open open
#define workload_syscall syscall
fn C.workload_syscall(i64, ...voidptr) i64
fn C.workload_open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.read(i32, voidptr, u64) i64
fn C.flock(i32, i32) i32
fn C.fcntl(i32, i32, ...voidptr) i32
fn C.prctl(i32, ...voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.setsid() i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getpid() i32
fn C.execv(&char, &&char) i32
fn C.alarm(u32) u32
fn C._exit(i32)

const attach_op = 0x56490003
const depth_op = 0x56490004

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn depth() i32 { return C.prctl(depth_op, voidptr(0), voidptr(0), voidptr(0), voidptr(0)) }
fn attach(fd i32) i32 { return C.prctl(attach_op, voidptr(i64(fd)), voidptr(0), voidptr(0), voidptr(0)) }
fn ordinary() ! {
	need(C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 'cannot drop identity')!
}
fn wait_code(pid i32, code i32) ! {
	mut status := i32(0)
	need(C.waitpid(pid, &status, 0) == pid && status == code << 8, 'child status differs')!
}
fn wait_file(path string) !string {
	deadline := time.sys_mono_now() + 15 * time.second
	for time.sys_mono_now() < deadline {
		if text := os.read_file(path) { if text != '' { return text } }
		time.sleep(5 * time.millisecond)
	}
	return error('fixture handshake timed out: ' + path)
}
fn pin(path string) !i32 {
	fd := C.workload_open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0 && C.flock(fd, C.LOCK_SH | C.LOCK_NB) == 0, 'cannot open shared lease')!
	if attach(fd) != 0 { C.close(fd); return error('kernel workload attach failed') }
	need(attach(fd) == 0, 'same-inode attachment must be idempotent')!
	need(C.flock(fd, C.LOCK_UN) == 0, 'cannot unlock source descriptor')!
	C.close(fd)
	return fd
}
fn busy(path string, expected bool) ! {
	fd := C.workload_open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0, 'cannot inspect lease')!
	defer { C.close(fd) }
	result := C.flock(fd, C.LOCK_EX | C.LOCK_NB)
	need(if expected { result < 0 && C.errno == C.EWOULDBLOCK } else { result == 0 }, 'independent kernel lock lifetime differs')!
}
fn exec_self(args []string) {
	exe := os.executable()
	mut values := [exe]
	values << args
	mut pointers := []&char{cap: values.len + 1}
	for value in values { pointers << value.str }
	pointers << &char(unsafe { nil })
	C.execv(exe.str, pointers.data)
	C._exit(126)
}
fn survivor(work string, closed_fd i32) ! {
	need(depth() == 1 && C.fcntl(closed_fd, C.F_GETFD) < 0, 'exec lost membership or exposed lease descriptor')!
	pin(work + '/nested')!
	need(depth() == 2, 'nested workload depth differs')!
	// The child is parented to PID1, but must inherit membership from its
	// creator. PID1 itself has no workload and reaps this sibling below.
	child := i32(C.workload_syscall(C.SYS_clone, voidptr(u64(0x8000 | 17)), voidptr(0), voidptr(0), voidptr(0), voidptr(0)))
	need(child >= 0, 'nested fork failed')!
	if child == 0 {
		if depth() != 2 { C._exit(127) }
		os.write_file(work + '/clone-parent', C.getpid().str()) or { C._exit(126) }
		C._exit(0)
	}
	os.write_file(work + '/survivor', C.getpid().str())!
	wait_file(work + '/retire')!
	C._exit(37)
}
fn owner(work string) ! {
	ordinary()!
	fd := pin(work + '/lease')!
	need(depth() == 1, 'initial workload depth differs')!
	child := C.fork()
	need(child >= 0, 'intermediate fork failed')!
	if child == 0 {
		need(C.setsid() > 0, 'setsid failed')!
		grandchild := C.fork()
		need(grandchild >= 0, 'grandchild fork failed')!
		if grandchild == 0 { exec_self(['--survivor', work, fd.str()]) }
		C._exit(0)
	}
	wait_code(child, 0)!
	os.write_file(work + '/owner', 'ready')!
	for { time.sleep(time.second) }
}
fn cycle(work string, count int) ! {
	ordinary()!
	for index in 0 .. count { pin(work + '/nest-' + index.str())! }
	need(depth() == count, 'chain depth differs')!
	if count == 32 {
		fd := C.workload_open((work + '/nest-32').str, C.O_RDONLY | C.O_CLOEXEC)
		need(fd >= 0 && C.flock(fd, C.LOCK_SH | C.LOCK_NB) == 0, 'depth-limit source open failed')!
		need(attach(fd) < 0 && C.errno == C.E2BIG && depth() == 32, 'chain bound did not refuse')!
		C.close(fd)
	}
	C._exit(0)
}
fn one_cycle(work string, count int, paths []string) ! {
	pid := C.fork()
	need(pid >= 0, 'cycle fork failed')!
	if pid == 0 { exec_self(['--cycle', work, count.str()]) }
	wait_code(pid, 0)!
	for index in 0 .. count { busy(paths[index], false)! }
}
fn slab(buffer &u8) !int {
	fd := C.workload_open(c'/proc/slabinfo', C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0, 'cannot open slab snapshot')!
	defer { C.close(fd) }
	mut length := 0
	for length < 8192 {
		got := C.read(fd, unsafe { buffer + length }, u64(8192 - length))
		need(got >= 0, 'cannot read slab snapshot')!
		if got == 0 { return length }
		length += int(got)
	}
	return error('slab snapshot exceeds bound')
}
fn suite() ! {
	need(depth() == 0, 'workload lease query unsupported or observer unexpectedly enrolled')!
	need(C.prctl(depth_op, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) < 0, 'query accepted spare argument')!
	work := '/tmp/workload-lease'
	os.mkdir(work)!; os.chmod(work, 0o777)!
	for name in ['lease', 'nested'] { os.write_file(work + '/' + name, '')!; os.chmod(work + '/' + name, 0o644)! }
	mut paths := []string{cap: 33}
	for index in 0 .. 33 { paths << work + '/nest-' + index.str(); os.write_file(paths.last(), '')! }
	fd := C.workload_open((work + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 0 && attach(fd) < 0 && depth() == 0, 'unlocked file accepted')!
	need(C.flock(fd, C.LOCK_EX | C.LOCK_NB) == 0 && attach(fd) < 0, 'exclusive source lock accepted')!
	C.close(fd)
	pid := C.fork()
	need(pid >= 0, 'owner fork failed')!
	if pid == 0 { owner(work)!; return }
	wait_file(work + '/owner')!
	survivor_pid := wait_file(work + '/survivor')!.i32()
	parented_pid := wait_file(work + '/clone-parent')!.i32()
	wait_code(parented_pid, 0)!
	busy(work + '/lease', true)!; busy(work + '/nested', true)!
	need(C.kill(pid, 9) == 0, 'cannot kill owner')!
	mut status := i32(0)
	need(C.waitpid(pid, &status, 0) == pid && status == 9, 'owner did not die by SIGKILL')!
	need(C.kill(survivor_pid, 0) == 0, 'survivor vanished with holder')!
	busy(work + '/lease', true)!; busy(work + '/nested', true)!
	os.write_file(work + '/retire', 'retire')!
	wait_code(survivor_pid, 37)!
	busy(work + '/lease', false)!; busy(work + '/nested', false)!
	need(depth() == 0, 'adoption enrolled observer into workload')!
	println('WORKLOAD LEASE HOLDER DEATH PASS unlock-close exec double-fork setsid nested original37 release')
	one_cycle(work, 32, paths)!
	println('WORKLOAD LEASE DEPTH PASS 32 independent locks; E2BIG; final release')
	for _ in 0 .. 32 { one_cycle(work, 4, paths)! }
	mut before := [8192]u8{}
	mut after := [8192]u8{}
	// Fault both buffers in before measuring; snapshots create no tmpfs files.
	for index in 0 .. 8192 { before[index] = 1; after[index] = 1 }
	slab(unsafe { &before[0] })!; slab(unsafe { &after[0] })!
	$if workload_sites ? { os.read_file('/proc/allocstart')! }
	// Match the observer's last namespace/read activity on both snapshots.
	slab(unsafe { &after[0] })!
	time.sleep(13 * time.second)
	before_len := slab(unsafe { &before[0] })!
	for _ in 0 .. 32 { one_cycle(work, 4, paths)! }
	slab(unsafe { &after[0] })!
	time.sleep(13 * time.second)
	after_len := slab(unsafe { &after[0] })!
	println('WORKLOAD SLAB BEFORE\n' + unsafe { tos(&before[0], before_len) })
	println('WORKLOAD SLAB AFTER\n' + unsafe { tos(&after[0], after_len) })
	$if workload_sites ? { println('WORKLOAD SITES\n' + os.read_file('/proc/allocsites')!) }
	println('HWTEST PASS workload-lease')
}
fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.workload_open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	C.alarm(180)
	if os.args.len == 4 && os.args[1] == '--survivor' { survivor(os.args[2], os.args[3].i32()) or { eprintln(err); C._exit(125) }; return }
	if os.args.len == 4 && os.args[1] == '--cycle' { cycle(os.args[2], os.args[3].int()) or { eprintln(err); C._exit(125) }; return }
	suite() or { println('HWTEST FAIL workload-lease: ' + err.msg()); return }
}
