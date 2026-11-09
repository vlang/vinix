// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/wait.h>

fn C.fork() i32
fn C.pipe(&i32) i32
fn C.write(i32, voidptr, usize) i32
fn C.dup2(i32, i32) i32
fn C.fcntl(i32, i32, ...voidptr) i32
fn C.execve(&char, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)

fn exec_child() i32 {
	unsafe {
		value := C.getenv(c'PPC_EXEC')
		mut byte := u8(0)
		if value == nil || C.strcmp(value, c'yes') != 0 || C.getpid() <= 1
			|| C.read(5, &byte, 1) != -1 || *C.__errno_location() != 9
			|| C.getauxval(6) != 4096 || C.write(9, c'exec-ok', 7) != 7 { return 99 }
		return 7
	}
}

fn process_services() bool {
	unsafe {
		mut before := C.sysinfo{}
		C.sysinfo(&before)
		for round in 0 .. 8 {
			mut pipe := [2]i32{}
			if C.pipe(&pipe[0]) != 0 || pipe[0] != 3 || pipe[1] != 4 { return false }
			file := C.open(c'/etc/motd', C.O_RDONLY | C.O_CLOEXEC)
			if file != 5 { return false }
			mut buffer := [4096]u8{}
			if C.fcntl(pipe[0], C.F_SETFL, C.O_NONBLOCK) != 0
				|| C.read(pipe[0], &buffer[0], 1) != -1 || *C.__errno_location() != 11
				|| C.fcntl(pipe[0], C.F_SETFL, 0) != 0 { return false }
			mut private := u32(12345)
			pid := C.fork()
			if pid < 0 { return false }
			if pid == 0 {
				private = 54321
				C.close(pipe[0])
				// A regular file duplicated onto stdin must keep its file semantics.
				if C.dup2(file, 0) != 0 || C.read(0, &buffer[0], 1) != 1 || buffer[0] != `V`
					|| C.close(0) != 0 || C.fcntl(0, C.F_GETFD) != -1 || *C.__errno_location() != 9 { C._exit(90) }
				for i in 0 .. 4096 { buffer[i] = u8(i) }
				for _ in 0 .. 24 { if C.write(pipe[1], &buffer[0], 4096) != 4096 { C._exit(91) } }
				if C.dup2(pipe[1], 9) != 9 { C._exit(92) }
				C.close(pipe[1])
				mut args := [&char(c'/bin/init'), &char(c'--exec-child'), &char(nil)]!
				mut env := [&char(c'PPC_EXEC=yes'), &char(nil)]!
				C.close(0)
				if C.execve(c'/missing', &args[0], &env[0]) != -1 || *C.__errno_location() != 2 { C._exit(93) }
				C.execve(c'/bin/init', &args[0], &env[0])
				C._exit(94)
			}
			C.close(pipe[1])
			mut received := 0
			mut expected := C.sin(f64(round) + 0.25)
			for received < 24 * 4096 {
				n := C.read(pipe[0], &buffer[0], usize(4096))
				if n <= 0 { return false }
				for i in 0 .. n { if buffer[i] != u8(received + i) { return false } }
				received += n
				if expected != C.sin(f64(round) + 0.25) { return false }
				expected += 0.0
			}
			if C.read(pipe[0], &buffer[0], 7) != 7 { return false }
			for i in 0 .. 7 { if buffer[i] != u8(c'exec-ok'[i]) { return false } }
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 7 << 8
				|| C.read(pipe[0], &buffer[0], 1) != 0 || private != 12345
				|| C.read(file, &buffer[0], 1) != 1 || buffer[0] != `i` { return false }
			C.close(pipe[0]); C.close(file)
			mut after := C.sysinfo{}
			if C.sysinfo(&after) != 0 || after.freeram != before.freeram { return false }
		}
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 { *(&u32(0x02000000)) = 0; C._exit(95) }
		mut status := i32(0)
		return C.waitpid(pid, &status, 0) == pid && status == 11
	}
}
