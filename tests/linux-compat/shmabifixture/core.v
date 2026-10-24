// SPDX-License-Identifier: GPL-2.0-or-later
module shmabifixture

#include <errno.h>
#include <stdio.h>
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
fn C.getpid() i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C._exit(i32)

fn fatal(stage int) {
	C.printf(c'LINUX SHMABI FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil })
	C._exit(90)
}

fn check(mut t Totals, good bool, stage int) {
	t.checks++
	if !good {
		t.failures++
		if t.failures <= 20 { C.printf(c'LINUX SHMABI MISMATCH: stage=%d\n', stage) }
	}
}

fn ctl(id u64, command u64, buffer u64) Outcome {
	mut error_code := C.__errno_location()
	unsafe { *error_code = 0 }
	value := C.syscall(isize(C.SYS_shmctl), id, command, buffer)
	return Outcome{ value, unsafe { *C.__errno_location() } }
}

fn state(id u64) C.shmid_ds {
	mut metadata := C.shmid_ds{}
	if ctl(id, u64(C.IPC_STAT), u64(unsafe { &metadata })).value != 0 { fatal(1) }
	return metadata
}

fn attach(id u64, address u64, flags u64) Outcome {
	mut error_code := C.__errno_location()
	unsafe { *error_code = 0 }
	value := C.syscall(isize(C.SYS_shmat), id, address, flags)
	return Outcome{ value, unsafe { *C.__errno_location() } }
}

fn detach(address isize) {
	if C.syscall(isize(C.SYS_shmdt), address) != 0 { fatal(2) }
}

fn error_is(outcome Outcome, wanted int) bool {
	return outcome.value == -1 && outcome.code == wanted
}

fn suite(mut t Totals, unprivileged bool) {
	unsafe {
		page := C.sysconf(C._SC_PAGESIZE)
		if page != 4096 && page != 16384 { fatal(3) }
		key := u64(u32(0x4e00_0000 | (C.getpid() & 0xffff)))
		id := C.syscall(isize(C.SYS_shmget), key, page, isize(C.IPC_CREAT | C.IPC_EXCL | 0o600))
		if id < 0 { fatal(4) }
		first := attach(u64(id), 0, 0)
		if first.value == -1 { fatal(5) }
		(&u8(first.value))[0] = 0x5a
		for upper in [u64(0), u64(1) << 32, u64(0x7fff_ffff_0000_0000), u64(1) << 63, u64(0xffff_ffff_0000_0000)]! {
			decorated := u64(id) | upper
			mut info := C.shmid_ds{}
			buffer := u64(&info)
			for words in [[decorated, u64(C.IPC_STAT)]!, [u64(id), u64(C.IPC_STAT) | upper]!, [decorated, u64(C.IPC_STAT) | upper]!]! {
				actual := ctl(words[0], words[1], buffer)
				check(mut t, actual.value == 0 && actual.code == 0, 100)
				check(mut t, actual.value == 0 && info.shm_segsz == u64(page) && info.shm_nattch == 1, 101)
			}
			check(mut t, error_is(ctl(decorated, u64(C.IPC_STAT) | upper, 0), C.EFAULT), 102)
			info = state(u64(id))
			info.shm_perm.mode = 0o640
			changed := ctl(decorated, u64(C.IPC_SET) | upper, buffer)
			check(mut t, changed.value == 0 && changed.code == 0, 103)
			check(mut t, state(u64(id)).shm_perm.mode & 0o777 == 0o640, 104)
			info.shm_perm.mode = 0o600
			if ctl(u64(id), u64(C.IPC_SET), buffer).value != 0 { fatal(6) }
			mapped := attach(decorated, 0, upper)
			check(mut t, mapped.value != -1 && mapped.code == 0, 105)
			if mapped.value == -1 {
				check(mut t, false, 106)
			} else {
				check(mut t, (&u8(mapped.value))[0] == 0x5a && state(u64(id)).shm_nattch == 2, 106)
				detach(mapped.value)
			}
			check(mut t, state(u64(id)).shm_nattch == 1 && (&u8(first.value))[0] == 0x5a, 107)
			for invalid in [u64(0xffff_ffff), u64(0x8000_0000)]! {
				check(mut t, error_is(ctl(invalid | upper, u64(C.IPC_STAT) | upper, buffer), C.EINVAL), 108)
				check(mut t, error_is(attach(invalid | upper, 0, upper), C.EINVAL), 109)
			}
			check(mut t, error_is(ctl(decorated, u64(0xffff_ffff) | upper, buffer), C.EINVAL), 110)
			check(mut t, error_is(attach(decorated, 0, u64(C.SHM_REMAP) | upper), C.EINVAL), 111)
			// Pointer and size arguments retain all 64 bits.
			check(mut t, error_is(ctl(u64(id), u64(C.IPC_STAT), buffer | (u64(1) << 63)), C.EFAULT), 112)
			check(mut t, C.syscall(isize(C.SYS_shmget), key | upper, page, upper | 0o600) == id, 113)
			mut error_code := C.__errno_location()
			*error_code = 0
			oversize := C.syscall(isize(C.SYS_shmget), key | upper, u64(page) | (u64(1) << 32), upper | 0o600)
			check(mut t, oversize == -1 && *C.__errno_location() == C.EINVAL, 114)
			fresh := C.syscall(isize(C.SYS_shmget), upper, page, upper | 0o600)
			if fresh < 0 { fatal(7) }
			removed := ctl(u64(fresh) | upper, u64(C.IPC_RMID) | upper, 0)
			check(mut t, removed.value == 0 && removed.code == 0, 115)
			if removed.value != 0 && ctl(u64(fresh), u64(C.IPC_RMID), 0).value != 0 { fatal(8) }
			check(mut t, error_is(ctl(u64(fresh), u64(C.IPC_STAT), buffer), C.EINVAL), 116)
			if unprivileged {
				info = state(u64(id)); info.shm_perm.mode = 0
				if ctl(u64(id), u64(C.IPC_SET), buffer).value != 0 { fatal(9) }
				check(mut t, error_is(attach(decorated, 0, upper), C.EACCES), 117)
				check(mut t, error_is(ctl(decorated, u64(C.IPC_STAT) | upper, buffer), C.EACCES), 118)
				info.shm_perm.mode = 0o600
				if ctl(u64(id), u64(C.IPC_SET), buffer).value != 0 { fatal(10) }
			}
		}
		detach(first.value)
		check(mut t, state(u64(id)).shm_nattch == 0, 119)
		if ctl(u64(id), u64(C.IPC_RMID), 0).value != 0 { fatal(11) }
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.alarm(120)
		mut t := Totals{}
		suite(mut t, false)
		mut pipe := [2]i32{}
		if C.pipe(&pipe[0]) != 0 { fatal(12) }
		C.fflush(nil)
		pid := C.fork()
		if pid < 0 { fatal(13) }
		if pid == 0 {
			C.close(pipe[0])
			if C.setgid(2000) != 0 || C.setuid(1000) != 0 { fatal(14) }
			mut child := Totals{}
			suite(mut child, true)
			if C.write(pipe[1], &child, sizeof(Totals)) != sizeof(Totals) { fatal(15) }
			C.fflush(nil); C._exit(0)
		}
		C.close(pipe[1])
		mut child := Totals{}
		if C.read(pipe[0], &child, sizeof(Totals)) != sizeof(Totals) { fatal(16) }
		t.checks += child.checks; t.failures += child.failures
		mut status := i32(0)
		check(mut t, C.waitpid(pid, &status, 0) == pid && status == 0, 120)
		C.close(pipe[0])
		C.printf(c'LINUX SHMABI SUMMARY: checks=%d failures=%d\n', t.checks, t.failures)
		if t.failures != 0 { C.printf(c'LINUX SHMABI: FAIL\n'); C.fflush(nil); return 1 }
		C.alarm(0); C.printf(c'LINUX SHMABI: PASS\n'); C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
