// SPDX-License-Identifier: GPL-2.0-or-later
module shmremovefixture

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

const dest = u32(0o1000)

fn fatal(stage int) {
	C.printf(c'LINUX SHMREMOVE FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMREMOVE MISMATCH: stage=%d\n', stage) }
	}
}
fn ctl(id i32, command i32, buffer voidptr) isize {
	return C.syscall(isize(C.SYS_shmctl), isize(id), isize(command), buffer)
}
fn state(id i32) C.shmid_ds {
	mut info := C.shmid_ds{}
	if ctl(id, C.IPC_STAT, unsafe { &info }) != 0 { fatal(1) }
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
fn error_is(mut t Totals, result isize, code i32, stage int) {
	check(mut t, result == -1 && unsafe { *C.__errno_location() } == code, stage)
}

// Each cohort finishes all mappings before fork. Inherited/split VMA accounting
// is deliberately outside this deletion-status qualification.
fn suite(mut t Totals) {
	unsafe {
		for kind in 0 .. 4 {
			key := if kind == 0 { i32(0) } else if kind == 3 { -i32(0x52300000 + C.getpid() * 8 + kind) }
				else { i32(0x52300000 + C.getpid() * 8 + kind) }
			mode := if kind % 2 == 0 { u32(0o600) } else { u32(0o660) }
			id := i32(C.syscall(isize(C.SYS_shmget), isize(key), usize(4097), isize(C.IPC_CREAT | C.IPC_EXCL | int(mode) | int(dest))))
			if id < 0 { fatal(2) }
			initial := state(id)
			check(mut t, initial.shm_perm.__ipc_perm_key == key, 1)
			check(mut t, initial.shm_perm.mode == mode, 2)
			check(mut t, initial.shm_segsz == 4097 && initial.shm_nattch == 0, 3)
			mut input := initial
			input.shm_perm.__ipc_perm_key = -991
			input.shm_perm.mode = mode | dest
			if ctl(id, C.IPC_SET, &input) != 0 { fatal(3) }
			before_attach := state(id)
			check(mut t, before_attach.shm_perm.mode == mode, 4)
			check(mut t, before_attach.shm_perm.__ipc_perm_key == key, 5)
			address := C.syscall(isize(C.SYS_shmat), isize(id), voidptr(0), isize(0))
			if address == -1 { fatal(4) }
			(&u8(address))[0] = 0x5a
			(&u8(address))[4096] = 0xa5
			before_remove := state(id)
			check(mut t, before_remove.shm_nattch == 1, 6)
			// IPC_RMID ignores its pointer argument.
			if ctl(id, C.IPC_RMID, voidptr(usize(-1))) != 0 { fatal(5) }
			removed := state(id)
			check(mut t, removed.shm_perm.__ipc_perm_key == 0, 10)
			check(mut t, removed.shm_perm.mode == mode | dest, 11)
			mut expected := before_remove
			expected.shm_perm.__ipc_perm_key = 0
			expected.shm_perm.mode |= dest
			check(mut t, unchanged(removed, expected), 12)
			check(mut t, (&u8(address))[0] == 0x5a && (&u8(address))[4096] == 0xa5, 13)
			check(mut t, ctl(id, C.IPC_RMID, nil) == 0, 14)
			check(mut t, unchanged(state(id), removed), 15)
			if key != 0 {
				error_is(mut t, C.syscall(isize(C.SYS_shmget), isize(key), usize(0), isize(0)), C.ENOENT, 16)
			}
			new_id := i32(C.syscall(isize(C.SYS_shmget), isize(key), usize(4097), isize(C.IPC_CREAT | C.IPC_EXCL | 0o600)))
			if new_id < 0 { fatal(6) }
			check(mut t, new_id != id, 20)
			new_initial := state(new_id)
			check(mut t, new_initial.shm_perm.__ipc_perm_key == key && new_initial.shm_perm.mode == 0o600, 21)
			if key != 0 {
				check(mut t, C.syscall(isize(C.SYS_shmget), isize(key), usize(0), isize(0)) == new_id, 22)
			}
			new_address := C.syscall(isize(C.SYS_shmat), isize(new_id), voidptr(0), isize(0))
			if new_address == -1 { fatal(7) }
			check(mut t, (&u8(new_address))[0] == 0 && (&u8(new_address))[4096] == 0, 23)
			(&u8(new_address))[0] = 0x33
			new_attached := state(new_id)
			check(mut t, unchanged(state(id), removed), 24)
			check(mut t, (&u8(address))[0] == 0x5a, 25)
			mut failed_input := removed
			failed_input.shm_perm.uid = u32(-1)
			error_is(mut t, ctl(id, C.IPC_SET, &failed_input), C.EINVAL, 26)
			check(mut t, unchanged(state(id), removed), 27)
			error_is(mut t, ctl(id, C.IPC_SET, nil), C.EFAULT, 28)
			check(mut t, unchanged(state(id), removed), 29)
			input = removed
			input.shm_perm.mode = 0o640 // User cannot clear SHM_DEST.
			input.shm_perm.__ipc_perm_key = key
			if ctl(id, C.IPC_SET, &input) != 0 { fatal(8) }
			updated := state(id)
			check(mut t, updated.shm_perm.mode == 0o640 | dest, 30)
			check(mut t, updated.shm_perm.__ipc_perm_key == 0, 31)
			expected = removed
			expected.shm_perm.mode = 0o640 | dest
			expected.shm_ctime = updated.shm_ctime
			check(mut t, unchanged(updated, expected), 32)
			check(mut t, unchanged(state(new_id), new_attached), 33)
			second := C.syscall(isize(C.SYS_shmat), isize(id), voidptr(0), isize(C.SHM_RDONLY))
			if second == -1 { fatal(9) }
			second_state := state(id)
			check(mut t, second_state.shm_nattch == 2, 40)
			check(mut t, second_state.shm_perm.mode == 0o640 | dest && second_state.shm_perm.__ipc_perm_key == 0, 41)
			check(mut t, (&u8(second))[0] == 0x5a && (&u8(second))[4096] == 0xa5, 42)
			if C.syscall(isize(C.SYS_shmdt), second) != 0 { fatal(10) }
			last := state(id)
			check(mut t, last.shm_nattch == 1, 43)
			check(mut t, last.shm_perm.mode == 0o640 | dest && last.shm_perm.__ipc_perm_key == 0, 44)
			if C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(11) }
			mut output := C.shmid_ds{}
			error_is(mut t, ctl(id, C.IPC_STAT, &output), C.EINVAL, 50)
			error_is(mut t, ctl(id, C.IPC_RMID, nil), C.EINVAL, 51)
			error_is(mut t, C.syscall(isize(C.SYS_shmat), isize(id), voidptr(0), isize(0)), C.EINVAL, 52)
			check(mut t, unchanged(state(new_id), new_attached), 53)
			check(mut t, (&u8(new_address))[0] == 0x33, 54)
			if C.syscall(isize(C.SYS_shmdt), new_address) != 0 || ctl(new_id, C.IPC_RMID, nil) != 0 { fatal(12) }
			error_is(mut t, ctl(new_id, C.IPC_STAT, &output), C.EINVAL, 55)
		}
	}
}
@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(13) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(14) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(2000) != 0 || C.setuid(1000) != 0 { fatal(15) }
			mut child := Totals{}
			suite(mut child)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(16) }
			C.fflush(nil); C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(17) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 60)
		C.close(pipe[0])
		C.printf(c'LINUX SHMREMOVE SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SHMREMOVE: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0); C.printf(c'LINUX SHMREMOVE: PASS\n'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
