module main
import os
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.dup2(i32, i32) i32
fn C.usleep(u32) i32
fn C.reboot(i32) i32
fn C.shutdown(i32, i32) i32
fn C.poll(voidptr, u64, i32) i32
struct Poll { mut: fd i32 events i16 revents i16 }
fn halfclose() {
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
	mut byte := u8(42)
	assert C.write(pair[1], unsafe { &byte }, 1) == 1
	assert C.shutdown(pair[1], C.SHUT_WR) == 0
	assert C.read(pair[0], unsafe { &byte }, 1) == 1
	mut polling := Poll{ fd: pair[0], events: 1 }
	result := C.poll(unsafe { &polling }, 1, 250)
	println('SOCKET HALF CLOSE poll ' + result.str() + ' events ' + polling.revents.str())
	println('SOCKET HALF CLOSE read ' + C.read(pair[0], unsafe { &byte }, 1).str())
	C.close(pair[0]); C.close(pair[1])
}
fn snapshot(label string) {
	println('SOCKET SNAPSHOT ' + label)
	for path in ['/proc/meminfo', '/proc/slabinfo', '/proc/kernel-resources'] {
		text := os.read_file(path) or { eprintln(err); continue }
		println(path + '\n' + text)
	}
}
fn pairs(count int) int {
	for i in 0 .. count {
		mut pair := [2]i32{}
		if C.socketpair(C.AF_UNIX, C.SOCK_STREAM | C.SOCK_CLOEXEC, 0, unsafe { &pair[0] }) != 0 {
			println('SOCKET EXHAUSTED after ' + i.str() + ' errno ' + C.errno.str())
			return i
		}
		C.close(pair[0]); C.close(pair[1])
	}
	println('SOCKET PAIRS ' + count.str() + ' PASS')
	return count
}
fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(i32(fd), 1); C.dup2(i32(fd), 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START package-socket-probe')
	halfclose()
	pairs(200)
	C.usleep(13_000_000)
	snapshot('warm')
	start := os.read_file('/proc/allocstart') or { err.msg() }
	println(start)
	pairs(20000)
	snapshot('burst')
	C.usleep(13_000_000)
	snapshot('settled')
	println(os.read_file('/proc/allocsites') or { err.msg() })
	pairs(200)
	println('HWTEST PASS package-socket-probe')
	C.reboot(0x4321fedc)
	for { C.usleep(1_000_000) }
}
