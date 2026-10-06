// Independent Linux ABI smoke fixture; expectations match the frozen C test.
@[has_globals]
module smokefixture

#include <stdio.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
@[typedef]
struct C.FILE {}
@[c_extern]
__global C.stdout &C.FILE
struct C.timespec { tv_sec isize tv_nsec isize }
fn C.setbuf(&C.FILE, &char)
fn C.puts(&char) i32
fn C.getpid() i32
fn C.clock_gettime(i32, &C.timespec) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr, usize, i32, i32, i32, isize) voidptr
fn C.munmap(voidptr, usize) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.pause() i32

fn check(condition bool) {
	if !condition {
		C.puts(c'FAIL: kernel guest runner smoke')
		for { C.pause() }
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		check(C.getpid() == 1)
		mut now := C.timespec{}
		check(C.clock_gettime(C.CLOCK_MONOTONIC, &now) == 0)
		page := usize(C.sysconf(C._SC_PAGESIZE))
		memory := &u8(C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		check(voidptr(memory) != voidptr(C.MAP_FAILED))
		memory[0] = 42
		child := C.fork()
		check(child >= 0)
		if child == 0 { memory[0] = 7; C._exit(if memory[0] == 7 { 0 } else { 1 }) }
		mut status := i32(0)
		check(C.waitpid(child, &status, 0) == child)
		check(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0 && memory[0] == 42)
		check(C.munmap(memory, page) == 0)
		C.puts(c'KERNEL GUEST RUNNER: PASS')
		for { C.pause() }
		return 0
	}
}
