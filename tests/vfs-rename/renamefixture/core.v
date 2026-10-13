// SPDX-License-Identifier: GPL-2.0-or-later
module renamefixture

#include <native-abi.h>
struct C.timespec {
	tv_sec  i64
	tv_nsec i64
}

struct C.stat {
	st_uid   u32
	st_mode  u32
	st_nlink u64
}

struct C.dirent {
	d_name [256]char
}

fn C.clock_gettime(int, &C.timespec) int
fn C.open(&char, int, ...) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.close(int) int
fn C.fsync(int) int
fn C.fstat(int, &C.stat) int
fn C.rename(&char, &char) int
fn C.mkdir(&char, u32) int
fn C.chown(&char, u32, u32) int
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.getuid() u32
fn C.geteuid() u32
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C.WIFEXITED(int) int
fn C.WEXITSTATUS(int) int
fn C.__errno_location() &i32
fn C.memcmp(voidptr, voidptr, usize) int
fn C.strcmp(&char, &char) int
fn C.opendir(&char) voidptr
fn C.readdir(voidptr) &C.dirent
fn C.closedir(voidptr) int
fn C.snprintf(voidptr, usize, &char, ...) int
fn C.printf(&char, ...) int
fn C.fflush(voidptr) int
fn C.puts(&char) int
fn C.usleep(u32) int
fn C._exit(int)
fn C.pause() int

fn check(ok bool, site int) {
	if !ok {
		unsafe { C.printf(c'FAIL: rename replacement site=%d errno=%d\n', site, *C.__errno_location()) }
		C.fflush(unsafe { nil })
		C._exit(1)
	}
}

fn clock() u64 {
	mut now := C.timespec{}
	check(C.clock_gettime(C.CLOCK_MONOTONIC, unsafe { &now }) == 0, 1)
	return u64(now.tv_sec) * 1000000000 + u64(now.tv_nsec)
}

fn publish(value &char) {
	fd := C.open(c'/tmp/rename-state/new', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0 && C.write(fd, value, 8) == 8 && C.fsync(fd) == 0 && C.close(fd) == 0, 2)
	check(C.rename(c'/tmp/rename-state/new', c'/tmp/rename-state/current') == 0, 3)
}

fn listing() {
	unsafe {
		dir := C.opendir(c'/tmp/rename-state')
		check(dir != nil, 19)
		errno_value := C.__errno_location()
		mut current := 0
		mut entries := 0
		for {
			*errno_value = 0
			entry := C.readdir(dir)
			if entry == nil {
				check(*C.__errno_location() == 0, 20)
				break
			}
			entries++
			check(entries < 32, 21)
			if C.strcmp(&entry.d_name[0], c'current') == 0 { current++ }
		}
		check(current == 1 && C.closedir(dir) == 0, 22)
	}
}

fn exercise(crowded bool) {
	unsafe {
		if crowded {
			// Dot entries, current and nine fillers leave the initial directory
			// map at its growth threshold when the writer creates its source.
			for index in 0 .. 9 {
				mut name := [128]char{}
				check(C.snprintf(&name[0], 128, c'/tmp/rename-state/filler-%d', index) > 0, 17)
				fd := C.open(&name[0], C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
				check(fd >= 0 && C.close(fd) == 0, 18)
			}
		}
		publish(c'AAAAAAAA')
		held := C.open(c'/tmp/rename-state/current', C.O_RDONLY)
		check(held >= 0, 7)
		writer := C.fork()
		check(writer > -1, 8)
		if writer == 0 {
			check(C.close(held) == 0, 9)
			C.usleep(10000)
			for iteration in 0 .. 4000 {
				publish(if iteration % 2 == 0 { c'BBBBBBBB' } else { c'AAAAAAAA' })
			}
			C._exit(0)
		}
		deadline := clock() + 30000000000
		mut reads := 0
		mut missing := 0
		mut open_errors := 0
		mut read_errors := 0
		mut first_open_error := 0
		mut status := 0
		for {
			check(clock() < deadline && reads < 2000000, 10)
			fd := C.open(c'/tmp/rename-state/current', C.O_RDONLY)
			if fd < 0 {
				code := *C.__errno_location()
				if first_open_error == 0 { first_open_error = code }
				if code == C.ENOENT { missing++ } else { open_errors++ }
			} else {
				mut data := [8]char{}
				count := C.read(fd, &data[0], 8)
				if count != 8 || (C.memcmp(&data[0], c'AAAAAAAA', 8) != 0 && C.memcmp(&data[0], c'BBBBBBBB', 8) != 0) {
					read_errors++
				}
				check(C.close(fd) == 0, 11)
			}
			reads++
			if reads % 32 == 0 {
				listing()
				done := C.waitpid(writer, &status, C.WNOHANG)
				check(done >= 0, 12)
				if done == writer { break }
			}
		}
		check(C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0, 13)
		// The replaced inode must also survive the kernel's five-second
		// retirement grace period while this descriptor still owns it.
		check(C.usleep(6500000) == 0, 16)
		mut old := [8]char{}
		mut st := C.stat{}
		check(C.read(held, &old[0], 8) == 8 && C.memcmp(&old[0], c'AAAAAAAA', 8) == 0
			&& C.fstat(held, &st) == 0 && st.st_nlink == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o600
			&& C.close(held) == 0, 14)
		C.printf(c'RENAME REPLACE: crowded=%d uid=1000 replacements=4000 reads=%d missing=%d open_errors=%d read_errors=%d first_open_errno=%d\n',
			int(crowded), reads, missing, open_errors, read_errors, first_open_error)
		C.fflush(nil)
		check(missing == 0 && open_errors == 0 && read_errors == 0, 15)
	}
}

@[export: 'main']
pub fn run() int {
	unsafe {
		check(C.mkdir(c'/tmp/rename-state', 0o700) == 0 && C.chown(c'/tmp/rename-state', 1000, 1000) == 0, 4)
		check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 5)
		check(C.getuid() == 1000 && C.geteuid() == 1000, 6)
		exercise(false)
		exercise(true)
		C.puts(c'RENAME REPLACE: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
