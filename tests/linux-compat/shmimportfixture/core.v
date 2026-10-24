// SPDX-License-Identifier: GPL-2.0-or-later
module shmimportfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
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
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.sysconf(i32) isize
fn C._exit(i32)
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.munmap(voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr

fn fatal(stage int) {
	C.printf(c'LINUX SHMIMPORT FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMIMPORT MISMATCH: stage=%d\n', stage) }
	}
}
fn ctl(id i32, command i32, buffer voidptr) isize {
	error_pointer := C.__errno_location()
	unsafe { *error_pointer = 0 }
	return C.syscall(isize(C.SYS_shmctl), isize(id), isize(command), buffer)
}
fn error_is(mut t Totals, id i32, command i32, buffer voidptr, code i32, stage int) {
	result := ctl(id, command, buffer)
	check(mut t, result == -1 && unsafe { *C.__errno_location() } == code, stage)
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
fn create() i32 {
	id := i32(C.syscall(isize(C.SYS_shmget), isize(0), usize(4097), isize(C.IPC_CREAT | 0o666)))
	if id < 0 { fatal(2) }
	return id
}

// Run without inherited SHM mappings. Fork/VMA attachment accounting is a
// separate qualification from input copying and error precedence.
fn suite(mut t Totals) {
	unsafe {
		check(mut t, sizeof(C.shmid_ds) == 112, 1)
		id := create()
		stale := create()
		if ctl(stale, C.IPC_RMID, nil) != 0 { fatal(3) }
		initial := state(id)
		mut input := initial
		input.shm_perm.mode = 0o640
		pages := usize(C.sysconf(C._SC_PAGESIZE))
		if pages < 4096 || pages > 65536 { fatal(25) }
		memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		gone := C.mmap(nil, pages, C.PROT_READ, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if memory == voidptr(usize(-1)) || gone == voidptr(usize(-1)) { fatal(4) }
		if C.munmap(gone, pages) != 0 { fatal(5) }
		edge := voidptr(usize(memory) + pages - sizeof(C.shmid_ds))
		C.memcpy(edge, &input, sizeof(C.shmid_ds))
		if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 { fatal(6) }
		// The full native ABI record must be readable, even its ignored tail.
		for pointer in [voidptr(0), voidptr(1), voidptr(usize(-1)), gone,
			voidptr(usize(memory) + pages), voidptr(usize(edge) + 1), voidptr(usize(edge) + 64)]! {
			error_is(mut t, id, C.IPC_SET, pointer, C.EFAULT, 10)
			check(mut t, unchanged(state(id), initial), 11)
			for missing in [stale, i32(2147483647)]! {
				error_is(mut t, missing, C.IPC_SET, pointer, C.EFAULT, 12)
				error_is(mut t, missing, C.IPC_STAT, pointer, C.EINVAL, 13)
				error_is(mut t, missing, C.IPC_RMID, pointer, C.EINVAL, 14)
			}
			for negative in [i32(-1), i32(-2), i32(-2147483647 - 1)]! {
				error_is(mut t, negative, C.IPC_SET, pointer, C.EINVAL, 15)
			}
			error_is(mut t, id, -1, pointer, C.EINVAL, 16)
			error_is(mut t, id, 0x7fff, pointer, C.EINVAL, 17)
		}
		for missing in [stale, i32(2147483647), i32(-1)]! {
			error_is(mut t, missing, C.IPC_SET, &input, C.EINVAL, 20)
		}
		for field in 0 .. 2 {
			mut bad := input
			if field == 0 { bad.shm_perm.uid = u32(-1) } else { bad.shm_perm.gid = u32(-1) }
			error_is(mut t, id, C.IPC_SET, &bad, C.EINVAL, 21)
			check(mut t, unchanged(state(id), initial), 22)
		}
		// Read-only input exactly ending at a page boundary is sufficient.
		if C.mprotect(memory, pages, C.PROT_READ) != 0 { fatal(7) }
		check(mut t, ctl(id, C.IPC_SET, edge) == 0, 30)
		updated := state(id)
		mut expected := initial
		expected.shm_perm.mode = 0o640
		expected.shm_ctime = updated.shm_ctime
		check(mut t, unchanged(updated, expected) && updated.shm_ctime >= initial.shm_ctime, 31)
		if C.munmap(memory, pages * 2) != 0 { fatal(8) }
		if ctl(id, C.IPC_RMID, voidptr(usize(-1))) != 0 { fatal(9) }
	}
}

fn nonowner(mut t Totals) {
	unsafe {
		id := create()
		before := state(id)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(10) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(11) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(4000) != 0 || C.setuid(3000) != 0 { fatal(12) }
			mut child := Totals{}
			pages := usize(C.sysconf(C._SC_PAGESIZE))
			if pages < 4096 || pages > 65536 { fatal(26) }
			memory := C.mmap(nil, pages * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if memory == voidptr(usize(-1)) { fatal(13) }
			C.memcpy(voidptr(usize(memory) + pages - 112), &before, 112)
			if C.mprotect(voidptr(usize(memory) + pages), pages, C.PROT_NONE) != 0 { fatal(14) }
			for pointer in [voidptr(0), voidptr(1), voidptr(usize(-1)), voidptr(usize(memory) + pages),
				voidptr(usize(memory) + pages - 111)]! {
				error_is(mut child, id, C.IPC_SET, pointer, C.EFAULT, 40)
				check(mut child, unchanged(state(id), before), 41)
			}
			mut input := before
			error_is(mut child, id, C.IPC_SET, &input, C.EPERM, 42)
			input.shm_perm.uid = u32(-1)
			error_is(mut child, id, C.IPC_SET, &input, C.EPERM, 43)
			error_is(mut child, id, C.IPC_RMID, nil, C.EPERM, 44)
			check(mut child, unchanged(state(id), before), 45)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(15) }
			C.fflush(nil); C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(16) }
		mut status := i32(0)
		if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(17) }
		C.close(pipe[0])
		t.checks += child.checks; t.failures += child.failures
		check(mut t, unchanged(state(id), before), 46)
		if ctl(id, C.IPC_RMID, nil) != 0 { fatal(18) }
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t)
		nonowner(mut t)
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
		mut status := i32(0)
		if C.waitpid(pid, &status, 0) != pid || status != 0 { fatal(24) }
		C.close(pipe[0])
		t.checks += child.checks; t.failures += child.failures
		check(mut t, true, 50)
		C.printf(c'LINUX SHMIMPORT SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures == 0 {
			C.printf(c'LINUX SHMIMPORT: PASS\n')
		} else {
			C.printf(c'LINUX SHMIMPORT: FAIL\n')
		}
		C.fflush(nil)
		C.alarm(0)
		for { C.pause() }
	}
	return 0
}
