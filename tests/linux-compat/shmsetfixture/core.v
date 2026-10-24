// SPDX-License-Identifier: GPL-2.0-or-later
module shmsetfixture

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
struct Outcome { value isize code i32 }

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
fn C.sysconf(i32) isize
fn C.getuid() u32
fn C.getgid() u32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SHMSET FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMSET MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id i32, command i32, buffer voidptr) Outcome {
	mut error_code := C.__errno_location()
	unsafe { *error_code = 0 }
	value := C.syscall(isize(C.SYS_shmctl), isize(id), isize(command), buffer)
	return Outcome{ value, unsafe { *C.__errno_location() } }
}

fn state(id i32) C.shmid_ds {
	mut info := C.shmid_ds{}
	if ctl(id, C.IPC_STAT, unsafe { &info }).value != 0 { fatal(1) }
	return info
}

fn error_is(outcome Outcome, wanted int) bool { return outcome.value == -1 && outcome.code == wanted }

fn fixed_fields(a C.shmid_ds, b C.shmid_ds) bool {
	return a.shm_perm.__ipc_perm_key == b.shm_perm.__ipc_perm_key && a.shm_perm.cuid == b.shm_perm.cuid
		&& a.shm_perm.cgid == b.shm_perm.cgid && a.shm_segsz == b.shm_segsz
		&& a.shm_cpid == b.shm_cpid && a.shm_lpid == b.shm_lpid && a.shm_nattch == b.shm_nattch
		&& a.shm_atime == b.shm_atime && a.shm_dtime == b.shm_dtime
}

fn unchanged(a C.shmid_ds, b C.shmid_ds) bool {
	return fixed_fields(a, b) && a.shm_perm.uid == b.shm_perm.uid && a.shm_perm.gid == b.shm_perm.gid
		&& a.shm_perm.mode == b.shm_perm.mode && a.shm_ctime == b.shm_ctime
}

// The non-owner has a valid buffer: ownership rejection precedes ID validation.
fn denied(mut t Totals, id i32) {
	unsafe {
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(2) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(3) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(4000) != 0 || C.setuid(3000) != 0 { fatal(4) }
			mut child := Totals{}
			before := state(id)
			for ids in [[u32(1234), u32(5678)]!, [u32(-1), u32(5678)]!, [u32(1234), u32(-1)]!, [u32(-1), u32(-1)]!]! {
				mut input := before
				input.shm_perm.uid = ids[0]; input.shm_perm.gid = ids[1]; input.shm_perm.mode = 0o644
				check(mut child, error_is(ctl(id, C.IPC_SET, &input), C.EPERM), 200)
				check(mut child, unchanged(state(id), before), 201)
			}
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(5) }
			C.fflush(nil); C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(6) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 202)
		C.close(pipe[0])
	}
}

fn suite(mut t Totals, owner_is_root bool) {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		if page != 4096 && page != 16384 { fatal(7) }
		id := i32(C.syscall(isize(C.SYS_shmget), isize(C.IPC_PRIVATE), page, isize(0o666)))
		if id < 0 { fatal(8) }
		address := C.syscall(isize(C.SYS_shmat), isize(id), isize(0), isize(0))
		if address == -1 { fatal(9) }
		(&u8(address))[0] = 0x5a
		initial := state(id)
		for ids in [[C.getuid(), C.getgid()]!, [u32(65534), u32(65533)]!,
			[u32(0xffff_fffe), u32(0xffff_fffd)]!, [u32(0x8000_0000), u32(0x8000_0001)]!,
			[initial.shm_perm.uid, initial.shm_perm.gid]!]! {
			mut input := initial
			input.shm_perm.uid = ids[0]; input.shm_perm.gid = ids[1]; input.shm_perm.mode = 0o7666
			// Fields outside uid/gid/mode are ignored by IPC_SET.
			input.shm_perm.cuid = u32(-1); input.shm_perm.cgid = u32(-1)
			input.shm_segsz = 0; input.shm_nattch = u64(-1); input.shm_cpid = -1
			actual := ctl(id, C.IPC_SET, &input)
			check(mut t, actual.value == 0 && actual.code == 0, 100)
			before := state(id)
			check(mut t, before.shm_perm.uid == ids[0] && before.shm_perm.gid == ids[1]
				&& before.shm_perm.mode & 0o7777 == 0o666, 101)
			check(mut t, fixed_fields(before, initial), 102)
			for invalid in [[u32(-1), ids[1]]!, [ids[0], u32(-1)]!, [u32(-1), u32(-1)]!,
				[u32(-1), u32(5678)]!, [u32(1234), u32(-1)]!]! {
				input = before
				input.shm_perm.uid = invalid[0]; input.shm_perm.gid = invalid[1]; input.shm_perm.mode = 0o644
				check(mut t, error_is(ctl(id, C.IPC_SET, &input), C.EINVAL), 110)
				after := state(id)
				check(mut t, after.shm_perm.uid == before.shm_perm.uid, 111)
				check(mut t, after.shm_perm.gid == before.shm_perm.gid, 112)
				check(mut t, after.shm_perm.mode == before.shm_perm.mode, 113)
				check(mut t, fixed_fields(after, before) && after.shm_ctime == before.shm_ctime, 114)
				check(mut t, (&u8(address))[0] == 0x5a && after.shm_nattch == 1, 115)
				input = before
				if ctl(id, C.IPC_SET, &input).value != 0 { fatal(10) }
				check(mut t, fixed_fields(state(id), before), 116)
			}
		}
		before := state(id)
		check(mut t, error_is(ctl(id, C.IPC_SET, nil), C.EFAULT), 120)
		check(mut t, unchanged(state(id), before), 121)
		mut input := before
		check(mut t, error_is(ctl(-1, C.IPC_SET, &input), C.EINVAL), 122)
		check(mut t, error_is(ctl(id, -1, &input), C.EINVAL), 123)
		if owner_is_root {
			denied(mut t, id)
		}
		if C.syscall(isize(C.SYS_shmdt), address) != 0 || ctl(id, C.IPC_RMID, nil).value != 0 { fatal(11) }
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t, true)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(12) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(13) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(2000) != 0 || C.setuid(1000) != 0 { fatal(14) }
			mut child := Totals{}
			suite(mut child, false)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(15) }
			C.fflush(nil); C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(16) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 124)
		C.close(pipe[0])
		C.printf(c'LINUX SHMSET SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SHMSET: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0); C.printf(c'LINUX SHMSET: PASS\n'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
