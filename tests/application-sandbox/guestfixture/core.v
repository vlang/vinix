// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module guestfixture

#include <native-abi.h>

struct C.sb_cap_data {
mut:
	effective u32
	permitted u32
	inheritable u32
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stderr voidptr
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.strcmp(&char, &char) i32
fn C.getenv(&char) &char
fn C.setenv(&char, &char, i32) i32
fn C.vksb_getids(&u32, &u32) i32
fn C.vksb_prctl(i32, u64) i32
fn C.vksb_groups(i32) i32
fn C.vksb_capget(voidptr) i32
fn C.vksb_unveil(&char, &char) i32
fn C.vksb_pledge(&char, &char) i32
fn C.vinix_sandbox_main(i32, &&char) i32
fn C.__builtin_alloca(usize) voidptr
fn C.fcntl(i32, i32, ...voidptr) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.chmod(&char, u32) i32
fn C.socket(i32, i32, i32) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.dup2(i32, i32) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

fn require(condition bool, line i32, expression &char) bool {
	if !condition {
		unsafe { C.fprintf(C.stderr, c'APPLICATION SANDBOX FAIL: line %d: %s (errno %d)\n', line, expression, C.errno) }
	}
	return condition
}

fn target(mode &char) i32 {
	unsafe {
		// These native output records were uninitialized automatic arrays in
		// the C control. Successful getters initialize them before each read.
		uid := &u32(C.__builtin_alloca(3 * sizeof(u32)))
		gid := &u32(C.__builtin_alloca(3 * sizeof(u32)))
		caps := &C.sb_cap_data(C.__builtin_alloca(2 * sizeof(C.sb_cap_data)))
		if !require(C.vksb_getids(uid, gid) == 0, 41, c'sb_getids(uid, gid) == 0') { return 1 }
		for i := i32(0); i < 3; i++ {
			if !require(uid[i] == 1000 && gid[i] == 1000, 42, c'uid[i] == 1000 && gid[i] == 1000') { return 1 }
		}
		if !require(C.vksb_prctl(C.SB_PR_GET_NO_NEW_PRIVS, 0) == 1, 43, c'sb_prctl(SB_PR_GET_NO_NEW_PRIVS, 0) == 1') { return 1 }
		if !require(C.vksb_groups(0) == 0, 44, c'sb_groups(0) == 0') { return 1 }
		if !require(C.vksb_capget(caps) == 0, 45, c'sb_capget(caps) == 0') { return 1 }
		for i := i32(0); i < 2; i++ {
			if !require(caps[i].effective == 0 && caps[i].permitted == 0 && caps[i].inheritable == 0, 46, c'!caps[i].effective && !caps[i].permitted && !caps[i].inheritable') { return 1 }
		}
		C.errno = 0
		if !require(C.fcntl(200, C.F_GETFD) == -1 && C.errno == C.EBADF, 48, c'fcntl(200, F_GETFD) == -1 && errno == EBADF') { return 1 }
		if !require(C.getenv(c'UNTRUSTED') == nil, 49, c'getenv("UNTRUSTED") == NULL') { return 1 }
		if !require(C.getenv(c'EXPLICIT') != nil && C.strcmp(C.getenv(c'EXPLICIT'), c'literal;$(id)') == 0, 50, c'getenv("EXPLICIT") && !strcmp(getenv("EXPLICIT"), "literal;$(id)")') { return 1 }
		if C.strcmp(mode, c'kill') == 0 {
			C.socket(C.AF_INET, C.SOCK_STREAM, 0)
			return 1
		}
		if C.strcmp(mode, c'no-rpath') == 0 {
			C.errno = 0
			if !require(C.open(c'/tmp/sandbox-readable', C.O_RDONLY) == -1 && C.errno == C.ENOSYS, 57, c'open("/tmp/sandbox-readable", O_RDONLY) == -1 && errno == ENOSYS') { return 1 }
			return 0
		}
		fd := C.open(c'/tmp/sandbox-readable', C.O_RDONLY)
		if !require(fd >= 0, 61, c'fd >= 0') { return 1 }
		mut data := [8]char{}
		if !require(C.read(fd, &data[0], sizeof(data)) == 4 && C.strcmp(&data[0], c'safe') == 0, 63, c'read(fd, data, sizeof(data)) == 4 && !strcmp(data, "safe")') { return 1 }
		if !require(C.close(fd) == 0, 64, c'close(fd) == 0') { return 1 }
		C.errno = 0
		if !require(C.open(c'/tmp/sandbox-hidden', C.O_RDONLY) == -1 && C.errno == C.ENOENT, 66, c'open("/tmp/sandbox-hidden", O_RDONLY) == -1 && errno == ENOENT') { return 1 }
		C.errno = 0
		if !require(C.open(c'/tmp/sandbox-readable', C.O_WRONLY) == -1 && C.errno == C.EACCES, 68, c'open("/tmp/sandbox-readable", O_WRONLY) == -1 && errno == EACCES') { return 1 }
		C.errno = 0
		if !require(C.socket(C.AF_INET, C.SOCK_STREAM, 0) == -1 && C.errno == C.ENOSYS, 70, c'socket(AF_INET, SOCK_STREAM, 0) == -1 && errno == ENOSYS') { return 1 }
		C.errno = 0
		if !require(C.mmap(nil, 4096, C.PROT_READ | C.PROT_EXEC, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0) == voidptr(C.MAP_FAILED) && C.errno == C.ENOSYS, 72, c'mmap(NULL, 4096, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0) == MAP_FAILED && errno == ENOSYS') { return 1 }
		C.errno = 0
		if !require(C.vksb_unveil(c'/tmp/sandbox-hidden', c'r') == -1 && C.errno == C.EPERM, 75, c'sb_unveil("/tmp/sandbox-hidden", "r") == -1 && errno == EPERM') { return 1 }
		C.errno = 0
		if !require(C.vksb_pledge(c'stdio rpath wpath inet error unveil', nil) == -1 && C.errno == C.EPERM, 77, c'sb_pledge("stdio rpath wpath inet error unveil", NULL) == -1 && errno == EPERM') { return 1 }
		for cap := i32(0); cap <= 40; cap++ {
			if !require(C.vksb_prctl(C.SB_PR_CAPBSET_READ, u64(cap)) == 0, 78, c'sb_prctl(SB_PR_CAPBSET_READ, (unsigned long)cap) == 0') { return 1 }
		}
	}
	return 0
}

fn run_case(promises &char, mode &char, extra_path &char, program &char, exit_code i32, signal_number i32) i32 {
	unsafe {
		pid := C.fork()
		if !require(pid >= 0, 86, c'pid >= 0') { return 1 }
		if pid == 0 {
			mut args := [&char(c'vinix-sandbox'), &char(c'--promises'), promises,
				&char(c'--uid'), &char(c'1000'), &char(c'--gid'), &char(c'1000'),
				&char(c'--unveil'), &char(c'/tmp/sandbox-readable'), &char(c'r'),
				&char(c'--env'), &char(c'EXPLICIT=literal;$(id)'), &char(c'--'),
				program, &char(c'--sandbox-target'), mode, &char(nil)]!
			if extra_path != nil { args[8] = extra_path }
			C._exit(C.vinix_sandbox_main(16, &args[0]))
		}
		mut status := i32(0)
		if !require(C.waitpid(pid, &status, 0) == pid, 96, c'waitpid(pid, &status, 0) == pid') { return 1 }
		if signal_number != 0 {
			if !require(C.WIFSIGNALED(status) && C.WTERMSIG(status) == signal_number, 97, c'WIFSIGNALED(status) && WTERMSIG(status) == signal_number') { return 1 }
		} else {
			if !require(C.WIFEXITED(status) && C.WEXITSTATUS(status) == exit_code, 98, c'WIFEXITED(status) && WEXITSTATUS(status) == exit_code') { return 1 }
		}
	}
	return 0
}

fn write_fixture(path &char) i32 {
	fd := C.open(path, C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o644))
	if !require(fd >= 0 && C.write(fd, c'safe', 4) == 4 && C.close(fd) == 0, 105, c'fd >= 0 && write(fd, "safe", 4) == 4 && close(fd) == 0') { return 1 }
	if !require(C.chmod(path, 0o644) == 0, 106, c'chmod(path, 0644) == 0') { return 1 }
	return 0
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	unsafe {
		if argc == 3 && C.strcmp(argv[1], c'--sandbox-target') == 0 { return target(argv[2]) }
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		if !require(write_fixture(c'/tmp/sandbox-readable') == 0, 114, c'write_fixture("/tmp/sandbox-readable") == 0') { return 1 }
		if !require(write_fixture(c'/tmp/sandbox-hidden') == 0, 115, c'write_fixture("/tmp/sandbox-hidden") == 0') { return 1 }
		fd := C.open(c'/tmp/sandbox-hidden', C.O_RDONLY)
		if !require(fd >= 0 && C.dup2(fd, 200) == 200, 117, c'fd >= 0 && dup2(fd, 200) == 200') { return 1 }
		if fd != 200 { C.close(fd) }
		if !require(C.setenv(c'UNTRUSTED', c'do-not-inherit', 1) == 0, 119, c'setenv("UNTRUSTED", "do-not-inherit", 1) == 0') { return 1 }
		if !require(run_case(c'stdio rpath wpath error unveil', c'allowed', nil, c'/sbin/init', 0, 0) == 0, 120, c'run_case("stdio rpath wpath error unveil", "allowed", NULL, "/sbin/init", 0, 0) == 0') { return 1 }
		if !require(run_case(c'stdio error', c'no-rpath', nil, c'/sbin/init', 0, 0) == 0, 121, c'run_case("stdio error", "no-rpath", NULL, "/sbin/init", 0, 0) == 0') { return 1 }
		if !require(run_case(c'stdio rpath', c'kill', nil, c'/sbin/init', 0, C.SIGABRT) == 0, 122, c'run_case("stdio rpath", "kill", NULL, "/sbin/init", 0, SIGABRT) == 0') { return 1 }
		if !require(run_case(c'stdio unknown', c'allowed', nil, c'/sbin/init', 125, 0) == 0, 123, c'run_case("stdio unknown", "allowed", NULL, "/sbin/init", 125, 0) == 0') { return 1 }
		if !require(run_case(c'stdio rpath error', c'allowed', c'/missing/parent/file', c'/sbin/init', 125, 0) == 0, 124, c'run_case("stdio rpath error", "allowed", "/missing/parent/file", "/sbin/init", 125, 0) == 0') { return 1 }
		if !require(run_case(c'stdio rpath error', c'allowed', nil, c'/missing/parent/command', 125, 0) == 0, 125, c'run_case("stdio rpath error", "allowed", NULL, "/missing/parent/command", 125, 0) == 0') { return 1 }
		C.puts(c'APPLICATION SANDBOX GUEST PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
