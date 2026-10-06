// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Independent Linux/musl console guest; preserve original failure line tags.
@[has_globals]
module guestfixture

#include <console-native-abi.h>
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stdout &C.FILE
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.getpid() i32
fn C.fork() i32
fn C.dup2(i32, i32) i32
fn C.setbuf(&C.FILE, &char)
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C._exit(i32)
fn C.sleep(u32) u32

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'FAIL line %d: %s errno=%d\n', line, expression, *C.__errno_location()) }
	}
	return ok
}

fn reap(child i32) i32 {
	mut status := i32(-1)
	if !check(unsafe { C.waitpid(child, &status, 0) == child }, 23, c'waitpid(child, &status, 0) == child') { return 1 }
	if !check(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 24, c'WIFEXITED(status) && WEXITSTATUS(status) == 0') { return 1 }
	return 0
}

fn run_test() i32 {
	unsafe {
		fd := C.open(c'/dev/console', C.O_RDONLY | C.O_NONBLOCK)
		if !check(fd >= 0, 30, c'fd >= 0') { return 1 }
		mut data := [16]char{}
		if !check(C.read(fd, &data[0], 0) == 0, 32, c'read(fd, data, 0) == 0') { return 1 }
		errno_first := C.__errno_location()
		*errno_first = 0
		if !check(C.read(fd, &data[0], sizeof(data)) == -1 && *C.__errno_location() == C.EAGAIN, 34, c'read(fd, data, sizeof(data)) == -1 && errno == EAGAIN') { return 1 }
		if !check(C.fcntl(fd, C.F_SETFL, C.fcntl(fd, C.F_GETFL) & ~i32(C.O_NONBLOCK)) == 0, 35, c'fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0') { return 1 }
		if !check(C.read(fd, &data[0], 0) == 0, 36, c'read(fd, data, 0) == 0') { return 1 }
		if !check(C.fcntl(fd, C.F_SETFL, C.fcntl(fd, C.F_GETFL) | i32(C.O_NONBLOCK)) == 0, 37, c'fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0') { return 1 }
		errno_second := C.__errno_location()
		*errno_second = 0
		if !check(C.read(fd, &data[0], 1) == -1 && *C.__errno_location() == C.EAGAIN, 39, c'read(fd, data, 1) == -1 && errno == EAGAIN') { return 1 }
		if !check(C.close(fd) == 0, 40, c'close(fd) == 0') { return 1 }
		C.puts(c'TEST console: zero-length and nonblocking reads passed')
		return 0
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		if argc > 1 { return 1 }
		if C.getpid() != 1 { return run_test() }
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial >= 0 { C.dup2(serial, 1); C.dup2(serial, 2); C.close(serial) }
		C.puts(c'TEST START')
		worker := C.fork()
		if worker == 0 { C._exit(run_test()) }
		failed := worker < 0 || reap(worker) != 0
		C.printf(c'TEST RESULT: %s\n', if failed { &char(c'FAIL') } else { &char(c'PASS') })
		for { C.sleep(1) }
		return 0
	}
}
