// SPDX-License-Identifier: GPL-2.0-or-later
module shmflagsfixture

#include <errno.h>
#include <stdio.h>
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
	C.printf(c'LINUX SHMFLAGS FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMFLAGS MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id i32, command int, argument voidptr) isize {
	return C.syscall(isize(C.SYS_shmctl), isize(id), isize(command), argument)
}

fn state(id i32) C.shmid_ds {
	mut metadata := C.shmid_ds{}
	if ctl(id, C.IPC_STAT, unsafe { &metadata }) != 0 { fatal(1) }
	return metadata
}

fn attach(id i32, address u64, flags u64) Outcome {
	mut error_code := C.__errno_location()
	unsafe { *error_code = 0 }
	value := C.syscall(isize(C.SYS_shmat), isize(id), address, flags)
	return Outcome{ value, unsafe { *error_code } }
}

fn detach(address isize) {
	if C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(2) }
}

fn expect_error(mut t Totals, id i32, address u64, flags u64, wanted int) {
	actual := attach(id, address, flags)
	check(mut t, actual.value == -1 && actual.code == wanted, 100)
	if actual.value != -1 { detach(actual.value) }
	if actual.code != wanted && t.failures <= 20 {
		C.printf(c'LINUX SHMFLAGS DETAIL: address=%lu flags=%lx result=%ld/%d expected=%d\n',
			address, flags, actual.value, actual.code, wanted)
	}
}

fn attachment(mut t Totals, id i32, page isize, first isize, flags u64) {
	unsafe {
		actual := attach(id, 0, flags)
		check(mut t, actual.value != -1 && actual.code == 0, 200)
		if actual.value == -1 {
			// Keep the same check total when the original kernel refuses a flag.
			for stage in 201 .. 204 { check(mut t, false, stage) }
		} else {
			mut memory := &u8(actual.value)
			check(mut t, actual.value != first && memory[0] == 0x5a, 201)
			metadata := state(id)
			check(mut t, metadata.shm_nattch == 2 && metadata.shm_segsz == u64(page), 202)
			if flags & u64(C.SHM_RDONLY) != 0 {
				mut error_code := C.__errno_location()
				*error_code = 0
				result := C.syscall(isize(C.SYS_mprotect), actual.value, page, isize(C.PROT_READ | C.PROT_WRITE))
				check(mut t, result == -1 && *C.__errno_location() == C.EACCES, 203)
			} else {
				memory[0] = 0x63
				check(mut t, (&u8(first))[0] == 0x63, 203)
				memory[0] = 0x5a
			}
			detach(actual.value)
		}
		check(mut t, state(id).shm_nattch == 1 && (&u8(first))[0] == 0x5a, 204)
	}
}

fn suite(mut t Totals, unprivileged bool) {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		if page != 4096 && page != 16384 { fatal(3) }
		id := i32(C.syscall(isize(C.SYS_shmget), isize(C.IPC_PRIVATE), page, isize(0o700)))
		if id < 0 { fatal(4) }
		first := attach(id, 0, 0)
		if first.value == -1 { fatal(5) }
		(&u8(first.value))[0] = 0x5a
		known := u64(C.SHM_RDONLY | C.SHM_RND | C.SHM_REMAP | C.SHM_EXEC)
		mut unused := [32]u64{}
		mut index := 0
		for bit in 0 .. 32 {
			value := u64(1) << bit
			if value & known == 0 { unused[index] = value; index++ }
		}
		// All unused low bits, the empty mask, and upper raw syscall words.
		for value in [u64(0xffff_ffff) & ~known, u64(0), u64(0xffff_ffff_0000_0000), u64(1) << 63]! {
			unused[index] = value; index++
		}
		if index != 32 { fatal(14) }
		for flags in unused {
			for active in [u64(0), u64(C.SHM_RND), u64(C.SHM_RDONLY), u64(C.SHM_RDONLY | C.SHM_EXEC)]! {
				attachment(mut t, id, page, first.value, flags | active)
			}
			expect_error(mut t, -1, 0, flags, C.EINVAL)
			expect_error(mut t, id, 1, flags, C.EINVAL)
			expect_error(mut t, id, 0, flags | u64(C.SHM_REMAP), C.EINVAL)
			expect_error(mut t, id, u64(page - 1), flags | u64(C.SHM_REMAP | C.SHM_RND), C.EINVAL)
			check(mut t, state(id).shm_nattch == 1, 300)
			check(mut t, (&u8(first.value))[0] == 0x5a, 301)
		}
		if unprivileged {
			mut metadata := state(id)
			metadata.shm_perm.mode = 0
			if ctl(id, C.IPC_SET, &metadata) != 0 { fatal(6) }
			for flags in unused {
				for active in [u64(0), u64(C.SHM_RDONLY), u64(C.SHM_RDONLY | C.SHM_EXEC)]! {
					expect_error(mut t, id, 0, flags | active, C.EACCES)
				}
			}
			metadata.shm_perm.mode = 0o700
			if ctl(id, C.IPC_SET, &metadata) != 0 { fatal(7) }
		}
		detach(first.value)
		check(mut t, state(id).shm_nattch == 0, 302)
		if ctl(id, C.IPC_RMID, nil) != 0 { fatal(8) }
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t, false)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(9) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(10) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(2000) != 0 || C.setuid(1000) != 0 { fatal(11) }
			mut child := Totals{}
			suite(mut child, true)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(12) }
			C.fflush(nil)
			C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(13) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 400)
		C.close(pipe[0])
		C.printf(c'LINUX SHMFLAGS SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SHMFLAGS: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0)
		C.printf(c'LINUX SHMFLAGS: PASS\n')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
