// Original independent fatal teardown and returning signal-handler workload.
@[translated]
module exceptionfixture

#include <exception-native-abi.h>

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.sigset_t {}

@[typedef]
struct C.siginfo_t {}

@[typedef]
struct C.mcontext_t {
mut:
	gregs [23]i64
}

@[typedef]
struct C.ucontext_t {
mut:
	uc_mcontext C.mcontext_t
}

struct C.sigaction {
mut:
	sa_sigaction fn (i32, &C.siginfo_t, voidptr)
	sa_flags     i32
	sa_mask      C.sigset_t
}

@[typedef]
struct C.FILE {}

@[c_extern]
__global C.stdout &C.FILE

@[c_extern]
__global C.errno i32

__global gate [2]i32
__global handled u32
__global failed i32

fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.open(&char, i32, ...) i32
fn C.unlink(&char) i32
fn C.dup2(i32, i32) i32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C._exit(i32)
fn C.memset(voidptr, i32, usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setbuf(&C.FILE, voidptr)
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.vexc_catch_fault(i32, &C.siginfo_t, voidptr)
fn C.vexc_fault_worker(voidptr) voidptr
fn C.vexc_release_handlers(voidptr) voidptr

@[c: '__atomic_store_n']
fn C.exc_store(&i32, i32, i32)

@[c: '__atomic_load_n']
fn C.exc_load(&i32, i32) i32

@[c: '__atomic_load_n']
fn C.exc_load_handled(&u32, i32) u32

@[c: '__atomic_fetch_add']
fn C.exc_add_handled(&u32, u32, i32) u32

@[export: 'vexc_catch_fault']
pub fn catch_fault(signal i32, info &C.siginfo_t, context voidptr) {
	unsafe {
		mut byte := u8(0)
		if C.read(gate[0], &byte, 1) != 1 { C.exc_store(&failed, 1, 5) }
		if signal == C.SIGILL {
			mut native := &C.ucontext_t(context)
			native.uc_mcontext.gregs[C.REG_RIP] = native.uc_mcontext.gregs[C.REG_RIP] + 2
		}
		C.exc_add_handled(&handled, 1, 5)
	}
}

@[export: 'vexc_fault_worker']
pub fn fault_worker(arg voidptr) voidptr {
	for _ in 0 .. 64 {
		asm volatile amd64 { int3 }
		asm volatile amd64 { ud2 }
	}
	return unsafe { nil }
}

@[export: 'vexc_release_handlers']
pub fn release_handlers(arg voidptr) voidptr {
	unsafe {
		for _ in 0 .. 256 {
			C.usleep(100)
			if C.write(gate[1], c'x', 1) != 1 { C.exc_store(&failed, 1, 5) }
		}
	}
	return unsafe { nil }
}

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'EXCEPTION TEST: FAIL line %d: %s errno=%d\n', line, expression, C.errno) }
	}
	return ok
}

fn run_test() i32 {
	unsafe {
		mut payload := [4096]u8{}
		C.memset(&payload[0], 0x5a, sizeof(payload))
		for round in 0 .. 24 {
			mut children := [2]i32{}
			mut pairs := [2][2]i32{}
			for worker in 0 .. 2 {
				if !check(C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &pairs[worker][0]) == 0, 48, c'socketpair(AF_UNIX, SOCK_STREAM, 0, pairs[worker]) == 0') {
					return 1
				}
				children[worker] = C.fork()
				if !check(children[worker] >= 0, 49, c'children[worker] >= 0') { return 1 }
				if children[worker] == 0 {
					C.close(pairs[worker][0])
					for old in 0 .. worker { C.close(pairs[old][0]) }
					mut pipefds := [2]i32{}
					if C.pipe(&pipefds[0]) != 0 { C._exit(99) }
					mut path := [80]u8{}
					C.snprintf(&char(&path[0]), sizeof(path), c'/tmp/fault-%d-%d', i32(round), i32(worker))
					fd := C.open(&char(&path[0]), C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600))
					if fd < 0 { C._exit(100) }
					for _ in 0 .. 32 {
						if C.write(fd, &payload[0], sizeof(payload)) != isize(sizeof(payload)) {
							C._exit(101)
						}
					}
					if C.write(pairs[worker][1], c'z', 1) != 1 { C._exit(103) }
					asm volatile amd64 { ud2 }
					C._exit(102)
				}
				C.close(pairs[worker][1])
			}
			for worker in 0 .. 2 {
				mut status := i32(0)
				if !check(C.waitpid(children[worker], &status, 0) == children[worker], 66, c'waitpid(children[worker], &status, 0) == children[worker]') {
					return 1
				}
				if !check(C.WIFSIGNALED(status) && C.WTERMSIG(status) == C.SIGILL, 67, c'WIFSIGNALED(status) && WTERMSIG(status) == SIGILL') {
					return 1
				}
				mut byte := u8(0)
				if !check(C.read(pairs[worker][0], &byte, 1) == 1 && byte == `z`, 68, c"read(pairs[worker][0], &byte, 1)==1 && byte=='z'") {
					return 1
				}
				if !check(C.read(pairs[worker][0], &byte, 1) == 0, 69, c'read(pairs[worker][0], &byte, 1)==0') {
					return 1
				}
				C.close(pairs[worker][0])
				mut path := [80]u8{}
				C.snprintf(&char(&path[0]), sizeof(path), c'/tmp/fault-%d-%d', i32(round), i32(worker))
				if !check(C.unlink(&char(&path[0])) == 0, 71, c'unlink(path) == 0') { return 1 }
			}
		}
		C.puts(c'EXCEPTION TEST: file, pipe and socket fatal teardown passed (48 children)')
		if !check(C.pipe(&gate[0]) == 0, 75, c'pipe(gate) == 0') { return 1 }
		mut action := C.sigaction{ sa_sigaction: C.vexc_catch_fault, sa_flags: C.SA_SIGINFO }
		C.sigemptyset(&action.sa_mask)
		if !check(C.sigaction(C.SIGILL, &action, nil) == 0, 78, c'sigaction(SIGILL, &action, NULL) == 0') {
			return 1
		}
		if !check(C.sigaction(C.SIGTRAP, &action, nil) == 0, 79, c'sigaction(SIGTRAP, &action, NULL) == 0') {
			return 1
		}
		mut threads := [3]C.pthread_t{}
		if !check(C.pthread_create(&threads[0], nil, C.vexc_fault_worker, nil) == 0, 81, c'pthread_create(&threads[0], NULL, fault_worker, NULL) == 0') {
			return 1
		}
		if !check(C.pthread_create(&threads[1], nil, C.vexc_fault_worker, nil) == 0, 82, c'pthread_create(&threads[1], NULL, fault_worker, NULL) == 0') {
			return 1
		}
		if !check(C.pthread_create(&threads[2], nil, C.vexc_release_handlers, nil) == 0, 83, c'pthread_create(&threads[2], NULL, release_handlers, NULL) == 0') {
			return 1
		}
		for i in 0 .. 3 {
			if !check(C.pthread_join(threads[i], nil) == 0, 84, c'pthread_join(threads[i], NULL) == 0') {
				return 1
			}
		}
		if !check(C.exc_load_handled(&handled, 5) == 256 && C.exc_load(&failed, 5) == 0, 85, c'atomic_load(&handled) == 256 && !atomic_load(&failed)') {
			return 1
		}
		C.close(gate[0])
		C.close(gate[1])
		C.puts(c'EXCEPTION TEST: returning handlers and blocked peers passed (256 faults)')
		return 0
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setbuf(C.stdout, nil)
		serial := C.open(c'/dev/com1', C.O_WRONLY)
		if serial >= 0 {
			C.dup2(serial, 1)
			C.dup2(serial, 2)
			C.close(serial)
		}
		result := run_test()
		C.printf(c'EXCEPTION TEST: %s\n', if result != 0 { &char(c'FAIL') } else { &char(c'PASS') })
		for { C.pause() }
	}
}
