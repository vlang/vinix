// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/ioctl.h>
#include <sys/syscall.h>

fn C.posix_openpt(i32) i32
fn C.grantpt(i32) i32
fn C.unlockpt(i32) i32
fn C.ptsname(i32) &char
fn C.ioctl(i32, u32, ...voidptr) i32
fn C.syscall(isize, ...voidptr) isize

fn terminal_services() bool {
	unsafe {
		for _ in 0 .. 8 {
			master := C.posix_openpt(C.O_RDWR | C.O_CLOEXEC)
			if master < 0 || C.grantpt(master) != 0 || C.unlockpt(master) != 0 { return false }
			name := C.ptsname(master)
			if name == nil || C.strcmp(name, c'/dev/pts/0') != 0 { return false }
			slave := C.open(name, C.O_RDWR | C.O_CLOEXEC)
			mut size := [u16(24), 80, 640, 480]!
			mut read_size := [4]u16{}
			if slave < 0 || C.ioctl(slave, u32(C.TIOCSWINSZ), &size[0]) != 0
				|| C.ioctl(master, u32(C.TIOCGWINSZ), &read_size[0]) != 0 { return false }
			for i in 0 .. 4 { if size[i] != read_size[i] { return false } }
			pid := C.fork()
			if pid < 0 { return false }
			if pid == 0 {
				C.close(master)
				if C.dup2(slave, 0) != 0 || C.dup2(slave, 1) != 1 || C.dup2(slave, 2) != 2 { C._exit(80) }
				C.close(slave)
				mut byte := u8(0)
				if C.read(0, &byte, 1) != 1 || byte != `k` || C.write(1, c'pty-ok\n', 7) != 7 { C._exit(81) }
				C._exit(0)
			}
			C.close(slave)
			mut response := [8]u8{}
			if C.write(master, c'k', 1) != 1 || C.read(master, &response[0], 8) != 8 { return false }
			for i in 0 .. 8 { if response[i] != u8(c'pty-ok\r\n'[i]) { return false } }
			mut status := i32(0)
			if C.waitpid(pid, &status, 0) != pid || status != 0
				|| C.read(master, &response[0], 1) != -1 || *C.__errno_location() != 5 || C.close(master) != 0 { return false }
		}
		return true
	}
}

fn sandbox_services() bool {
	unsafe {
		mut request := [2]i32{}
		mut response := [2]i32{}
		if C.pipe(&request[0]) != 0 || C.pipe(&response[0]) != 0 { return false }
		file := C.open(c'/etc/motd', C.O_RDONLY)
		if file < 0 { return false }
		pid := C.fork()
		if pid < 0 { return false }
		if pid == 0 {
			if C.syscall(0x7f10, request[0], response[1]) != 0 { C._exit(70) }
			mut byte := u8(0)
			if C.read(file, &byte, 1) != -1 || *C.__errno_location() != 9
				|| C.open(c'/etc/motd', C.O_RDONLY) != -1 || *C.__errno_location() != 1
				|| C.fork() != -1 || *C.__errno_location() != 1 || C.getuid() != 65534
				|| C.syscall(0x7f10, request[0], response[1]) != -1 || *C.__errno_location() != 1 { C._exit(71) }
			if C.read(request[0], &byte, 1) != 1 || byte != `s` || C.write(response[1], &byte, 1) != 1 { C._exit(72) }
			C._exit(0)
		}
		C.close(request[0]); C.close(response[1]); C.close(file)
		mut byte := u8(0)
		mut status := i32(0)
		ok := C.write(request[1], c's', 1) == 1 && C.read(response[0], &byte, 1) == 1
			&& byte == `s` && C.waitpid(pid, &status, 0) == pid && status == 0
		C.close(request[1]); C.close(response[0])
		return ok
	}
}
