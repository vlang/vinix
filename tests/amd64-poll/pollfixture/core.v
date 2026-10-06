// Independent Vinix poll fixture; original predicates and logical lines retained.
@[translated]
module pollfixture

#include <poll-native-abi.h>

@[typedef]
struct C.FILE {}

struct C.timespec {
mut:
	tv_sec  i64
	tv_nsec i64
}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

@[c_extern]
__global C.stdout &C.FILE

@[c_extern]
__global C.errno i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setbuf(&C.FILE, &char)
fn C.clock_gettime(i32, &C.timespec) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.syscall(isize, ...) isize
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.usleep(u32) i32
fn C._exit(i32)
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.getpid() i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.sleep(u32) u32

fn check(ok bool, line i32, expression &char) bool {
	if !ok { unsafe { C.printf(c'FAIL line %d: %s errno=%d\n', line, expression, C.errno) } }
	return ok
}

fn reap(child i32) i32 {
	unsafe {
		mut status := i32(-1)
		if !check(C.waitpid(child, &status, 0) == child, 19, c'waitpid(child, &status, 0) == child') {
			return 1
		}
		if !check(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 20, c'WIFEXITED(status) && WEXITSTATUS(status) == 0') {
			return 1
		}
		return 0
	}
}

fn elapsed_ms(a C.timespec, b C.timespec) i64 {
	return (b.tv_sec - a.tv_sec) * 1000 + (b.tv_nsec - a.tv_nsec) / 1000000
}

fn run_test() i32 {
	unsafe {
		if !check(C.poll(nil, 0, 0) == 0, 28, c'poll(NULL, 0, 0) == 0') { return 1 }
		mut a := C.timespec{}
		mut b := C.timespec{}
		if !check(C.clock_gettime(C.CLOCK_MONOTONIC, &a) == 0, 30, c'clock_gettime(CLOCK_MONOTONIC, &a) == 0') {
			return 1
		}
		if !check(C.poll(nil, 0, 40) == 0, 31, c'poll(NULL, 0, 40) == 0') { return 1 }
		if !check(C.clock_gettime(C.CLOCK_MONOTONIC, &b) == 0, 32, c'clock_gettime(CLOCK_MONOTONIC, &b) == 0') {
			return 1
		}
		if !check(elapsed_ms(a, b) >= 30, 33, c'elapsed_ms(a,b) >= 30') { return 1 }
		mut f := C.pollfd{ fd: -1, events: C.POLLIN, revents: 123 }
		if !check(C.poll(&f, 1, 0) == 0 && f.revents == 0, 35, c'poll(&f, 1, 0) == 0 && f.revents == 0') {
			return 1
		}
		f.fd = C.INT_MAX
		if !check(C.poll(&f, 1, 0) == 1 && (f.revents & C.POLLNVAL) != 0, 37, c'poll(&f, 1, 0) == 1 && (f.revents & POLLNVAL)') {
			return 1
		}
		C.errno = 0
		if !check(C.syscall(C.SYS_poll, voidptr(1), 1, 0) == -1 && C.errno == C.EFAULT, 39, c'syscall(SYS_poll, (void *)1, 1, 0) == -1 && errno == EFAULT') {
			return 1
		}
		C.errno = 0
		if !check(C.syscall(C.SYS_poll, voidptr(0), 4097, 0) == -1 && C.errno == C.EINVAL, 41, c'syscall(SYS_poll, NULL, 4097, 0) == -1 && errno == EINVAL') {
			return 1
		}
		mut p := [2]i32{}
		if !check(C.pipe(&p[0]) == 0, 42, c'pipe(p) == 0') { return 1 }
		mut pair := [C.pollfd{ fd: p[0], events: C.POLLIN }, C.pollfd{ fd: p[0], events: C.POLLIN }]!
		if !check(C.poll(&pair[0], 2, 0) == 0, 44, c'poll(pair, 2, 0) == 0') { return 1 }
		if !check(C.poll(&pair[0], 2, 10) == 0, 45, c'poll(pair, 2, 10) == 0') { return 1 }
		mut child := C.fork()
		if !check(child >= 0, 46, c'child>=0') { return 1 }
		if child == 0 {
			C.usleep(50000)
			C._exit(if C.write(p[1], c'x', 1) == 1 { i32(0) } else { i32(1) })
		}
		if !check(C.poll(&pair[0], 2, -1) == 2, 48, c'poll(pair, 2, -1) == 2') { return 1 }
		if !check((pair[0].revents & C.POLLIN) != 0 && (pair[1].revents & C.POLLIN) != 0, 49, c'(pair[0].revents & POLLIN) && (pair[1].revents & POLLIN)') {
			return 1
		}
		if !check(reap(child) == 0, 50, c'reap(child) == 0') { return 1 }
		mut c := u8(0)
		if !check(C.read(p[0], &c, 1) == 1 && c == u8(`x`), 51, c"read(p[0], &c, 1) == 1 && c == 'x'") {
			return 1
		}
		C.close(p[1])
		f.fd = p[0]
		f.events = 0
		if !check(C.poll(&f, 1, 0) == 1 && (f.revents & C.POLLHUP) != 0, 53, c'poll(&f, 1, 0) == 1 && (f.revents & POLLHUP)') {
			return 1
		}
		C.close(p[0])
		mut first := [2]i32{}
		mut second := [2]i32{}
		if !check(C.pipe(&first[0]) == 0 && C.pipe(&second[0]) == 0, 55, c'pipe(first)==0 && pipe(second)==0') {
			return 1
		}
		mut distinct := [C.pollfd{ fd: first[0], events: C.POLLIN },
			C.pollfd{ fd: second[0], events: C.POLLIN }]!
		child = C.fork()
		if !check(child >= 0, 57, c'child>=0') { return 1 }
		if child == 0 {
			C.usleep(50000)
			C._exit(if C.write(second[1], c'y', 1) == 1 { i32(0) } else { i32(1) })
		}
		if !check(C.poll(&distinct[0], 2, 1000) == 1, 59, c'poll(distinct,2,1000)==1') { return 1 }
		if !check(distinct[0].revents == 0 && (distinct[1].revents & C.POLLIN) != 0, 60, c'distinct[0].revents==0 && (distinct[1].revents&POLLIN)') {
			return 1
		}
		if !check(reap(child) == 0, 61, c'reap(child)==0') { return 1 }
		C.close(first[0])
		C.close(first[1])
		C.close(second[0])
		C.close(second[1])
		mut pipes := [33][2]i32{}
		mut many := [33]C.pollfd{}
		for i in 0 .. 33 {
			if !check(C.pipe(&pipes[i][0]) == 0, 64, c'pipe(pipes[i])==0') { return 1 }
			many[i] = C.pollfd{ fd: pipes[i][0], events: C.POLLIN }
		}
		if !check(C.poll(&many[0], 33, 0) == 0, 65, c'poll(many,33,0)==0') { return 1 }
		C.errno = 0
		if !check(C.poll(&many[0], 33, 1) == -1 && C.errno == C.EINVAL, 66, c'poll(many,33,1)==-1 && errno==EINVAL') {
			return 1
		}
		C.errno = 0
		if !check(C.poll(&many[0], 32, 1) == -1 && C.errno == C.EINVAL, 67, c'poll(many,32,1)==-1 && errno==EINVAL') {
			return 1
		}
		for i in 0 .. 33 {
			C.close(pipes[i][0])
			C.close(pipes[i][1])
		}
		C.puts(c'TEST poll: timeouts, readiness, duplicate FDs, HUP and invalid inputs passed')
		return 0
	}
}

@[export: 'main']
pub fn main_entry(argc i32, _argv &&char) i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		if argc > 1 { return 1 }
		if C.getpid() != 1 { return run_test() }
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial >= 0 {
			C.dup2(serial, 1)
			C.dup2(serial, 2)
			C.close(serial)
		}
		C.puts(c'TEST START')
		worker := C.fork()
		if worker == 0 { C._exit(run_test()) }
		failed := worker < 0 || reap(worker) != 0
		mut verdict := &char(c'PASS')
		if failed { verdict = &char(c'FAIL') }
		C.printf(c'TEST RESULT: %s\n', verdict)
		for { C.sleep(1) }
	}
	return 0
}
