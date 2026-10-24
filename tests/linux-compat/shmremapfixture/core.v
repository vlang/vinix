// SPDX-License-Identifier: GPL-2.0-or-later
module shmremapfixture

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/shm.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.ipc_perm { mut: mode u32 }
struct C.shmid_ds { mut: shm_perm C.ipc_perm shm_nattch u64 shm_segsz u64 }
struct Totals { mut: checks i32 failures i32 }
struct Outcome { value isize code i32 }

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.sysconf(i32) isize
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SHMREMAP FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMREMAP MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id i32, command int, argument voidptr) isize {
	return C.syscall(isize(C.SYS_shmctl), isize(id), isize(command), argument)
}

fn create(page isize) i32 {
	id := i32(C.syscall(isize(C.SYS_shmget), isize(C.IPC_PRIVATE), page, isize(0o700)))
	if id < 0 { fatal(1) }
	return id
}

fn remove(id i32) { if ctl(id, C.IPC_RMID, unsafe { nil }) != 0 { fatal(2) } }

fn state(id i32) C.shmid_ds {
	mut metadata := C.shmid_ds{}
	if ctl(id, C.IPC_STAT, unsafe { &metadata }) != 0 { fatal(3) }
	return metadata
}

fn attach(id i32, address u64, flags int) Outcome {
	mut error_code := C.__errno_location()
	unsafe { *error_code = 0 }
	value := C.syscall(isize(C.SYS_shmat), isize(id), address, isize(flags))
	return Outcome{ value, unsafe { *error_code } }
}

fn detach(address isize) {
	if C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(4) }
}

fn expect_error(mut t Totals, id i32, address u64, flags int, wanted int) {
	actual := attach(id, address, flags)
	check(mut t, actual.value == -1 && actual.code == wanted, 100)
	if actual.value != -1 { detach(actual.value) }
	if actual.code != wanted && t.failures <= 20 {
		C.printf(c'LINUX SHMREMAP DETAIL: id=%d address=%lu flags=%o result=%ld/%d expected=%d\n',
			id, address, flags, actual.value, actual.code, wanted)
	}
}

fn refusals(mut t Totals, id i32, removed i32, page isize) {
	unsafe {
		before := state(id)
		for number in [id, removed, i32(-1)]! {
			for flags in [0, int(C.SHM_RDONLY), int(C.SHM_EXEC), int(C.SHM_RDONLY | C.SHM_EXEC)]! {
				expect_error(mut t, number, 0, flags | C.SHM_REMAP, C.EINVAL)
				for address in [u64(0), 1, u64(page - 1)]! {
					expect_error(mut t, number, address, flags | C.SHM_REMAP | C.SHM_RND, C.EINVAL)
				}
				// Misaligned non-rounded addresses keep their earlier error.
				expect_error(mut t, number, 1, flags | C.SHM_REMAP, C.EINVAL)
			}
		}
		for _ in 0 .. 200 { expect_error(mut t, id, 1, C.SHM_REMAP | C.SHM_RND, C.EINVAL) }
		after := state(id)
		check(mut t, C.memcmp(&before, &after, sizeof(C.shmid_ds)) == 0, 101)
	}
}

fn controls(mut t Totals, id i32, page isize) {
	unsafe {
		first := attach(id, 0, 0)
		if first.value == -1 { fatal(5) }
		mut memory := &u8(first.value)
		memory[0] = 0x5a
		// Ordinary null-address attachments still choose distinct mappings.
		second := attach(id, 0, 0)
		if second.value == -1 { fatal(6) }
		check(mut t, second.value != first.value && (&u8(second.value))[0] == 0x5a, 200)
		detach(second.value)
		// Executable controls use RX; Vinix deliberately refuses RWX mappings.
		for flags in [0, int(C.SHM_RDONLY), int(C.SHM_RDONLY | C.SHM_EXEC)]! {
			mapped := C.syscall(isize(C.SYS_mmap), isize(0), page,
				isize(C.PROT_READ | C.PROT_WRITE), isize(C.MAP_PRIVATE | C.MAP_ANONYMOUS), isize(-1), isize(0))
			if mapped == -1 { fatal(7) }
			(&u8(mapped))[0] = 0x31
			// Both exact and rounded fixed addresses must still replace mappings.
			for offset in [u64(0), 1, u64(page - 1)]! {
				result := attach(id, u64(mapped) + offset, flags | C.SHM_REMAP | C.SHM_RND)
				check(mut t, result.value == mapped && result.code == 0, 201)
				if result.value == -1 { break }
				check(mut t, (&u8(result.value))[0] == 0x5a, 202)
			}
			detach(mapped)
		}
		refusals(mut t, id, i32(-1), page)
		check(mut t, memory[0] == 0x5a && state(id).shm_nattch == 1, 203)
		detach(first.value)
		check(mut t, state(id).shm_nattch == 0, 204)
	}
}

fn suite(mut t Totals) {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		if page != 4096 && page != 16384 { fatal(8) }
		id := create(page)
		removed := create(page)
		remove(removed)
		refusals(mut t, id, removed, page)
		controls(mut t, id, page)
		mut metadata := state(id)
		metadata.shm_perm.mode = 0
		if ctl(id, C.IPC_SET, &metadata) != 0 { fatal(9) }
		// Invalid remaps precede permission checks, even for an inaccessible ID.
		for flags in [0, int(C.SHM_RDONLY), int(C.SHM_EXEC)]! {
			expect_error(mut t, id, 0, flags | C.SHM_REMAP, C.EINVAL)
			expect_error(mut t, id, 1, flags | C.SHM_REMAP | C.SHM_RND, C.EINVAL)
		}
		metadata.shm_perm.mode = 0o700
		if ctl(id, C.IPC_SET, &metadata) != 0 { fatal(10) }
		check(mut t, state(id).shm_nattch == 0, 300)
		remove(id)
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(11) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(12) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(2000) != 0 || C.setuid(1000) != 0 { fatal(13) }
			mut child := Totals{}
			suite(mut child)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(14) }
			C.fflush(nil)
			C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(15) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 400)
		C.close(pipe[0])
		C.printf(c'LINUX SHMREMAP SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SHMREMAP: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0)
		C.printf(c'LINUX SHMREMAP: PASS\n')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
