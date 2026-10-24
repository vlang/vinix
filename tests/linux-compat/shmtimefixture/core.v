// SPDX-License-Identifier: GPL-2.0-or-later
module shmtimefixture

#include <errno.h>
#include <stdio.h>
#include <sys/shm.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.ipc_perm { mut: __ipc_perm_key i32 uid u32 gid u32 cuid u32 cgid u32 mode u32 }
struct C.shmid_ds {
mut:
	shm_perm C.ipc_perm
	shm_segsz u64
	shm_atime i64
	shm_dtime i64
	shm_ctime i64
	shm_cpid i32
	shm_lpid i32
	shm_nattch u64
}
struct Totals { mut: checks i32 failures i32 }
struct Stamp { sec i64 nsec i64 }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.getpid() i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SHMTIME FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMTIME MISMATCH: stage=%d\n', stage) }
	}
}
fn clock_seconds(clock isize) i64 {
	mut stamp := Stamp{}
	if C.syscall(isize(C.SYS_clock_gettime), clock, unsafe { &stamp }) != 0 { fatal(1) }
	return stamp.sec
}
fn now() i64 { return clock_seconds(0) }
fn next_second() i64 {
	start := now()
	deadline := clock_seconds(1) + 5
	delay := Stamp{ nsec: 20_000_000 }
	// Linux IPC stamps use coarse realtime; wait for its next whole second.
	for clock_seconds(5) <= start {
		if clock_seconds(1) > deadline { fatal(2) }
		if C.syscall(isize(C.SYS_nanosleep), unsafe { &delay }, voidptr(0)) != 0 { fatal(3) }
	}
	return clock_seconds(5)
}
fn bounded(value i64, lower i64) bool { return value >= lower && value <= now() }
fn ctl(id i32, command i32, buffer voidptr) isize {
	return C.syscall(isize(C.SYS_shmctl), isize(id), isize(command), buffer)
}
fn state(id i32) C.shmid_ds {
	mut info := C.shmid_ds{}
	if ctl(id, C.IPC_STAT, unsafe { &info }) != 0 { fatal(4) }
	return info
}
fn unchanged(a C.shmid_ds, b C.shmid_ds) bool {
	return a.shm_perm.__ipc_perm_key == b.shm_perm.__ipc_perm_key
		&& a.shm_perm.uid == b.shm_perm.uid && a.shm_perm.gid == b.shm_perm.gid
		&& a.shm_perm.cuid == b.shm_perm.cuid && a.shm_perm.cgid == b.shm_perm.cgid
		&& a.shm_perm.mode == b.shm_perm.mode && a.shm_segsz == b.shm_segsz
		&& a.shm_atime == b.shm_atime && a.shm_dtime == b.shm_dtime
		&& a.shm_ctime == b.shm_ctime && a.shm_cpid == b.shm_cpid
		&& a.shm_lpid == b.shm_lpid && a.shm_nattch == b.shm_nattch
}
fn failed_set(mut t Totals, id i32, info C.shmid_ds) {
	unsafe {
		for kind in 0 .. 3 {
			next_second()
			mut input := info
			input.shm_ctime = -123
			if kind == 1 { input.shm_perm.uid = u32(-1) }
			if kind == 2 { input.shm_perm.gid = u32(-1) }
			buffer := if kind == 0 { voidptr(0) } else { voidptr(&input) }
			mut errno_slot := C.__errno_location()
			*errno_slot = 0
			result := ctl(id, C.IPC_SET, buffer)
			code := *C.__errno_location()
			check(mut t, result == -1 && code == if kind == 0 { C.EFAULT } else { C.EINVAL }, 30 + kind)
			check(mut t, unchanged(state(id), info), 33 + kind)
		}
	}
}

// Fork before attaching: this tests the caller's PID and exit detach without
// conflating them with the separately unqualified inherited-VMA accounting.
fn child_mapping(mut t Totals, id i32, explicit_detach bool) {
	unsafe {
		before := state(id)
		lower := next_second()
		mut ready := [2]i32{}
		mut release := [2]i32{}
		if C.pipe(&ready[0]) != 0 || C.pipe(&release[0]) != 0 { fatal(5) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(6) }
		if pid == 0 {
			C.close(ready[0]); C.close(release[1])
			address := C.syscall(isize(C.SYS_shmat), isize(id), voidptr(0), isize(C.SHM_RDONLY))
			if address == -1 { fatal(7) }
			mut token := u8(1)
			if C.write(ready[1], &token, 1) != 1 || C.read(release[0], &token, 1) != 1 { fatal(8) }
			if explicit_detach && C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(9) }
			C._exit(0)
		}
		C.close(ready[1]); C.close(release[0])
		mut token := u8(0)
		if C.read(ready[0], &token, 1) != 1 { fatal(10) }
		attached := state(id)
		check(mut t, bounded(attached.shm_atime, lower), 40)
		check(mut t, attached.shm_atime > before.shm_atime, 41)
		check(mut t, attached.shm_lpid == pid, 42)
		check(mut t, attached.shm_nattch == 1, 43)
		check(mut t, attached.shm_dtime == before.shm_dtime, 44)
		check(mut t, attached.shm_ctime == before.shm_ctime, 45)
		check(mut t, attached.shm_cpid == before.shm_cpid, 46)
		detach_lower := next_second()
		if C.write(release[1], &token, 1) != 1 { fatal(11) }
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 47)
		detached := state(id)
		check(mut t, bounded(detached.shm_dtime, detach_lower), 48)
		check(mut t, detached.shm_dtime > attached.shm_dtime, 49)
		check(mut t, detached.shm_lpid == pid, 50)
		check(mut t, detached.shm_nattch == 0, 51)
		check(mut t, detached.shm_atime == attached.shm_atime, 52)
		check(mut t, detached.shm_ctime == attached.shm_ctime, 53)
		check(mut t, detached.shm_cpid == before.shm_cpid, 54)
		C.close(ready[0]); C.close(release[1])
	}
}
fn suite(mut t Totals) {
	unsafe {
		created_lower := clock_seconds(5)
		id := i32(C.syscall(isize(C.SYS_shmget), isize(C.IPC_PRIVATE), usize(4096), isize(0o666)))
		if id < 0 { fatal(12) }
		initial := state(id)
		check(mut t, initial.shm_atime == 0, 1)
		check(mut t, initial.shm_dtime == 0, 2)
		check(mut t, bounded(initial.shm_ctime, created_lower) && initial.shm_ctime > 0, 3)
		check(mut t, initial.shm_cpid == C.getpid(), 4)
		check(mut t, initial.shm_lpid == 0, 5)
		check(mut t, initial.shm_nattch == 0, 6)
		check(mut t, initial.shm_segsz == 4096, 7)
		for iteration in 0 .. 2 {
			before := state(id)
			attach_lower := next_second()
			address := C.syscall(isize(C.SYS_shmat), isize(id), voidptr(0), isize(0))
			if address == -1 { fatal(13) }
			(&u8(address))[0] = 0x5a
			attached := state(id)
			check(mut t, bounded(attached.shm_atime, attach_lower), 10)
			check(mut t, attached.shm_atime > before.shm_atime, 11)
			check(mut t, attached.shm_lpid == C.getpid(), 12)
			check(mut t, attached.shm_nattch == 1, 13)
			check(mut t, attached.shm_ctime == before.shm_ctime, 14)
			check(mut t, attached.shm_dtime == before.shm_dtime, 15)
			check(mut t, attached.shm_cpid == initial.shm_cpid, 16)
			set_lower := next_second()
			mut input := attached
			input.shm_atime = -11; input.shm_dtime = -22; input.shm_ctime = -33
			input.shm_cpid = -44; input.shm_lpid = -55; input.shm_nattch = 999
			if ctl(id, C.IPC_SET, &input) != 0 { fatal(14) }
			changed := state(id)
			check(mut t, bounded(changed.shm_ctime, set_lower), 20)
			check(mut t, changed.shm_ctime > attached.shm_ctime, 21)
			mut expected := attached
			expected.shm_ctime = changed.shm_ctime
			check(mut t, unchanged(changed, expected), 22)
			check(mut t, (&u8(address))[0] == 0x5a, 23)
			failed_set(mut t, id, changed)
			detach_lower := next_second()
			if C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(15) }
			detached := state(id)
			check(mut t, bounded(detached.shm_dtime, detach_lower), 60)
			check(mut t, detached.shm_dtime > changed.shm_dtime, 61)
			check(mut t, detached.shm_lpid == C.getpid(), 62)
			check(mut t, detached.shm_nattch == 0, 63)
			check(mut t, detached.shm_atime == changed.shm_atime, 64)
			check(mut t, detached.shm_ctime == changed.shm_ctime, 65)
			child_mapping(mut t, id, iteration == 0)
		}
		address := C.syscall(isize(C.SYS_shmat), isize(id), voidptr(0), isize(0))
		if address == -1 { fatal(16) }
		before_remove := state(id)
		next_second()
		if ctl(id, C.IPC_RMID, nil) != 0 { fatal(17) }
		after_remove := state(id)
		check(mut t, after_remove.shm_atime == before_remove.shm_atime, 70)
		check(mut t, after_remove.shm_dtime == before_remove.shm_dtime, 71)
		check(mut t, after_remove.shm_ctime == before_remove.shm_ctime, 72)
		check(mut t, after_remove.shm_lpid == before_remove.shm_lpid, 73)
		if C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(18) }
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(19) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(20) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(2000) != 0 || C.setuid(1000) != 0 { fatal(21) }
			mut child := Totals{}
			suite(mut child)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(22) }
			C.fflush(nil); C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(23) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 80)
		C.close(pipe[0])
		C.printf(c'LINUX SHMTIME SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SHMTIME: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0); C.printf(c'LINUX SHMTIME: PASS\n'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
