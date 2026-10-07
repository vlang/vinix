// Independent dumpability/secure-loader and same-UID inspection regression.
@[translated; has_globals]
module dumpfixture

#include <dump-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.vdu_native_long {}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout &C.FILE
__global failures i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.strcmp(&char, &char) i32
fn C.prctl(i32, ...) i32
fn C.getauxval(usize) usize
fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setreuid(u32, u32) i32
fn C.setregid(u32, u32) i32
fn C.setuid(u32) i32
fn C.setgid(u32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.pipe(&i32) i32
fn C.getpid() i32
fn C.pause() i32
fn C.memcpy(voidptr, voidptr, usize) voidptr

fn native_long(bits i64) C.vdu_native_long {
	unsafe {
		mut value := C.vdu_native_long{}
		C.memcpy(&value, &bits, sizeof(C.vdu_native_long))
		return value
	}
}

fn check(valid bool, name &char) {
	unsafe {
		C.printf(c'DUMPABILITY %s: %s\n', if valid { &char(c'PASS') } else { &char(c'FAIL') }, name)
		failures += i32(!valid)
	}
}

fn layout(pid i32) bool {
	unsafe {
		mut path := [80]char{}
		mut byte := char(0)
		C.snprintf(&path[0], sizeof(path), c'/proc/%d/maps', pid)
		fd := C.open(&path[0], C.O_RDONLY)
		if fd < 0 { return false }
		valid := C.read(fd, &byte, 1) == 1
		C.close(fd)
		return valid
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 2 && C.strcmp(argv[1], c'--exec') == 0 {
			return if C.prctl(C.PR_GET_DUMPABLE) == 1 && C.getauxval(C.AT_SECURE) == 0 { 0 } else { 1 }
		}
		if argc == 2 && C.strcmp(argv[1], c'--secure') == 0 {
			return if C.prctl(C.PR_GET_DUMPABLE) == 0 && C.getauxval(C.AT_SECURE) == 1 &&
				C.getauxval(C.AT_UID) == C.getuid() && C.getauxval(C.AT_EUID) == C.geteuid() &&
				C.getauxval(C.AT_GID) == C.getgid() && C.getauxval(C.AT_EGID) == C.getegid() { 0 } else { 1 }
		}
		console := C.open(c'/dev/com1', C.O_WRONLY)
		if console >= 0 { C.dup2(console, 1); C.dup2(console, 2); C.close(console) }
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		check(C.prctl(C.PR_GET_DUMPABLE) == 1, c'initial state')
		check(C.prctl(C.PR_SET_DUMPABLE, native_long(0)) == 0 && C.prctl(C.PR_GET_DUMPABLE) == 0, c'state is retained')
		C.errno = 0
		check(C.prctl(C.PR_SET_DUMPABLE, native_long(2)) == -1 && C.errno == C.EINVAL && C.prctl(C.PR_GET_DUMPABLE) == 0, c'invalid setting rejected')
		mut child := C.fork()
		if child == 0 { C._exit(if C.prctl(C.PR_GET_DUMPABLE) == 0 { 0 } else { 1 }) }
		mut status := i32(0)
		check(child > 0 && C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, c'fork inherits state')
		child = C.fork()
		if child == 0 {
			mut args := [3]&char{}
			args[0] = argv[0]
			args[1] = c'--exec'
			C.execv(argv[0], &args[0])
			C._exit(2)
		}
		check(child > 0 && C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, c'ordinary exec resets state')
		for group := i32(0); group < 2; group++ {
			child = C.fork()
			if child == 0 {
				changed := if group != 0 { C.setregid(1000, 0) } else { C.setreuid(1000, 0) }
				if changed != 0 { C._exit(2) }
				mut args := [3]&char{}
				args[0] = argv[0]
				args[1] = c'--secure'
				C.execv(argv[0], &args[0])
				C._exit(3)
			}
			check(child > 0 && C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0,
				if group != 0 { &char(c'mixed gids select secure loader and dump protection') } else { &char(c'mixed uids select secure loader and dump protection') })
		}
		C.prctl(C.PR_SET_DUMPABLE, native_long(1))
		check(C.setgid(1000) == 0 && C.prctl(C.PR_GET_DUMPABLE) == 0, c'effective gid change protects process')
		C.prctl(C.PR_SET_DUMPABLE, native_long(1))
		check(C.setuid(1000) == 0 && C.prctl(C.PR_GET_DUMPABLE) == 0, c'effective uid change protects process')
		check(C.prctl(C.PR_SET_DUMPABLE, native_long(1)) == 0, c'unprivileged program can enable inspection')
		mut to_child := [2]i32{}
		mut from_child := [2]i32{}
		check(C.pipe(&to_child[0]) == 0 && C.pipe(&from_child[0]) == 0, c'control pipes')
		child = C.fork()
		if child == 0 {
			C.close(to_child[1])
			C.close(from_child[0])
			mut state := char(0)
			for C.read(to_child[0], &state, 1) == 1 {
				if C.prctl(C.PR_SET_DUMPABLE, native_long(i64(state == `1`))) != 0 { C._exit(3) }
				if C.write(from_child[1], &state, 1) != 1 { C._exit(4) }
			}
			C._exit(0)
		}
		C.close(to_child[0])
		C.close(from_child[1])
		mut state := char(`0`)
		mut response := char(0)
		C.write(to_child[1], &state, 1)
		check(C.read(from_child[0], &response, 1) == 1 && !layout(child), c'same uid cannot inspect nondumpable peer')
		check(layout(C.getpid()), c'program can inspect itself')
		state = `1`
		C.write(to_child[1], &state, 1)
		check(C.read(from_child[0], &response, 1) == 1 && layout(child), c'same uid can inspect enabled peer')
		C.close(to_child[1])
		C.close(from_child[0])
		check(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, c'peer exits normally')
		C.puts(if failures != 0 { &char(c'DUMPABILITY GUEST: FAIL') } else { &char(c'DUMPABILITY GUEST: PASS') })
		for { C.pause() }
		return 0
	}
}
