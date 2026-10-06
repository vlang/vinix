// SPDX-License-Identifier: GPL-2.0-or-later
// Independent shared-stream fixture; original checks and workloads retained.
@[translated; has_globals]
module streamfixture

#include <stream-native-abi.h>

@[typedef] struct C.FILE {}
struct C.termios { mut: c_lflag u32 c_cc [32]u8 }
@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout &C.FILE
__global stream_failures i32
const children_count = 8
const write_bytes = 512 * 1024

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.write(i32, voidptr, usize) isize
fn C._exit(i32)
fn C.memset(voidptr, i32, usize) voidptr
fn C.open(&char, i32, ...) i32
fn C.lseek(i32, i64, i32) i64
fn C.unlink(&char) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.posix_openpt(i32) i32
fn C.ioctl(i32, usize, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.dup2(i32, i32) i32
fn C.pause() i32

fn check(ok bool, name &char) {
	unsafe {
		C.printf(c'SHARED STREAMS %s: %s errno=%d\n', if ok { &char(c'OK') } else { &char(c'FAIL') }, name, C.errno)
		if !ok { stream_failures++ }
	}
}

fn reap(child i32) bool {
	unsafe {
		mut status := i32(0)
		mut result := i32(0)
		for {
			result = C.waitpid(child, &status, 0)
			if result >= 0 || C.errno != C.EINTR { break }
		}
		return result == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0
	}
}

fn readers(input i32, output i32, name &char) {
	unsafe {
		mut ready := [2]i32{}
		check(C.pipe(&ready[0]) == 0, c'reader readiness pipe')
		mut children := [8]i32{}
		for i := i32(0); i < children_count; i++ {
			children[i] = C.fork()
			if children[i] == 0 {
				C.close(ready[0])
				mut byte := char(`r`)
				if C.write(ready[1], &byte, 1) != 1 { C._exit(1) }
				C._exit(if C.read(input, &byte, 1) == 1 && byte == `x` { 0 } else { 2 })
			}
			check(children[i] > 0, c'fork reader')
		}
		C.close(ready[1])
		for i := i32(0); i < children_count; i++ {
			mut byte := char(0)
			check(C.read(ready[0], &byte, 1) == 1, c'reader reached shared description')
		}
		C.close(ready[0])
		check(C.write(output, c'xxxxxxxx', usize(children_count)) == children_count, c'producer remains schedulable')
		for i := i32(0); i < children_count; i++ { check(reap(children[i]), c'shared reader completed') }
		mut byte := char(0)
		C.errno = 0
		check(C.pread(input, &byte, 1, 0) == -1 && C.errno == C.ESPIPE, c'stream pread fails ESPIPE')
		C.printf(c'SHARED STREAMS PASS: %s\n', name)
	}
}

fn writers() {
	unsafe {
		mut data := [2]i32{}
		mut ready := [2]i32{}
		check(C.pipe(&data[0]) == 0 && C.pipe(&ready[0]) == 0, c'writer pipes')
		mut children := [8]i32{}
		for i := i32(0); i < children_count; i++ {
			children[i] = C.fork()
			if children[i] == 0 {
				C.close(data[0])
				C.close(ready[0])
				mut chunk := [4096]char{}
				C.memset(&chunk[0], `w`, sizeof(chunk))
				if C.write(ready[1], c'r', 1) != 1 { C._exit(1) }
				mut done := i32(0)
				for done < write_bytes {
					amount := C.write(data[1], &chunk[0], sizeof(chunk))
					if amount <= 0 { C._exit(2) }
					done += i32(amount)
				}
				C._exit(0)
			}
			check(children[i] > 0, c'fork writer')
		}
		C.close(ready[1])
		for i := i32(0); i < children_count; i++ {
			mut byte := char(0)
			check(C.read(ready[0], &byte, 1) == 1, c'writer reached shared description')
		}
		C.close(ready[0])
		C.close(data[1])
		mut total := usize(0)
		mut chunk := [8192]char{}
		for {
			amount := C.read(data[0], &chunk[0], sizeof(chunk))
			if amount <= 0 { break }
			total += usize(amount)
		}
		check(total == usize(children_count) * usize(write_bytes), c'shared writers drain without starvation')
		for i := i32(0); i < children_count; i++ { check(reap(children[i]), c'shared writer completed') }
		C.close(data[0])
	}
}

fn offsets() {
	unsafe {
		fd := C.open(c'/root/offsets', C.O_RDWR | C.O_CREAT | C.O_TRUNC, i32(0o600))
		mut answers := [2]i32{}
		check(fd >= 0 && C.pipe(&answers[0]) == 0, c'seekable fixture')
		check(C.write(fd, c'01234567', usize(children_count)) == children_count && C.lseek(fd, 0, C.SEEK_SET) == 0,
			c'seekable initial bytes')
		mut children := [8]i32{}
		for i := i32(0); i < children_count; i++ {
			children[i] = C.fork()
			if children[i] == 0 {
				C.close(answers[0])
				mut byte := char(0)
				C._exit(if C.read(fd, &byte, 1) == 1 && C.write(answers[1], &byte, 1) == 1 { 0 } else { 1 })
			}
		}
		C.close(answers[1])
		mut seen := u32(0)
		for i := i32(0); i < children_count; i++ {
			mut byte := char(0)
			check(C.read(answers[0], &byte, 1) == 1 && byte >= `0` && byte <= `7`, c'file result')
			if byte >= `0` && byte <= `7` { seen |= u32(1) << (byte - `0`) }
		}
		for i := i32(0); i < children_count; i++ { check(reap(children[i]), c'file reader completed') }
		check(seen == 255 && C.lseek(fd, 0, C.SEEK_CUR) == children_count, c'shared file offset stays atomic')
		C.close(answers[0])
		C.close(fd)
		C.unlink(c'/root/offsets')
		C.puts(c'SHARED STREAMS PASS: offsets')
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		console := C.open(c'/dev/com1', C.O_WRONLY)
		if console >= 0 { C.dup2(console, 1); C.dup2(console, 2); C.close(console) }
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		mut pipefd := [2]i32{}
		check(C.pipe(&pipefd[0]) == 0, c'shared pipe')
		readers(pipefd[0], pipefd[1], c'pipe')
		C.close(pipefd[0])
		C.close(pipefd[1])
		mut sockets := [2]i32{}
		check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0, c'shared socket')
		readers(sockets[0], sockets[1], c'socket')
		C.close(sockets[0])
		C.close(sockets[1])
		master := C.posix_openpt(C.O_RDWR | C.O_NOCTTY)
		mut unlock := i32(0)
		mut id := u32(0)
		check(master >= 0 && C.ioctl(master, usize(C.TIOCSPTLCK), &unlock) == 0 && C.ioctl(master, usize(C.TIOCGPTN), &id) == 0, c'PTY master')
		mut path := [64]char{}
		C.snprintf(&path[0], sizeof(path), c'/dev/pts/%u', id)
		slave := C.open(&path[0], C.O_RDWR | C.O_NOCTTY)
		mut settings := C.termios{}
		check(slave >= 0 && C.tcgetattr(slave, &settings) == 0, c'PTY slave')
		settings.c_lflag &= ~u32(C.ICANON | C.ECHO)
		settings.c_cc[C.VMIN] = 1
		settings.c_cc[C.VTIME] = 0
		check(C.tcsetattr(slave, C.TCSANOW, &settings) == 0, c'PTY raw input')
		readers(slave, master, c'terminal')
		C.close(slave)
		C.close(master)
		writers()
		offsets()
		C.puts(if stream_failures != 0 { &char(c'SHARED STREAMS GUEST: FAIL') } else { &char(c'SHARED STREAMS GUEST: PASS') })
		for { C.pause() }
		return 0
	}
}
