// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module collectorguestfixture

#include <native-abi.h>

struct C.snapshot {}
struct C.stat {
mut:
	st_size i64
}
struct C.filter {
mut:
	code u16
	jt u8
	jf u8
	k u32
}
struct C.program {
mut:
	length u16
	instructions &C.filter
}
@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout voidptr
fn C.__builtin_alloca(usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strstr(&char, &char) &char
fn C.strlen(&char) usize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(voidptr, voidptr, i32, usize) i32
fn C.access(&char, i32) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.fork() i32
fn C.prctl(i32, ...) i32
fn C.syscall(i64, ...) i64
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) i64
fn C.write(i32, voidptr, usize) i64
fn C.chmod(&char, u32) i32
fn C.symlink(&char, &char) i32
fn C.link(&char, &char) i32
fn C.unlink(&char) i32
fn C.stat(&char, &C.stat) i32
fn C.unshare(i32) i32
fn C.pause() i32
fn C.vka_main(i32, &&char) i32
fn C.vka_log_stat(i32, u32) i32
fn C.vka_open_log(&char, i32) i32
fn C.vka_read_snapshot(&char, &C.snapshot) i32

fn check(ok bool, line i32) bool {
	if !ok {
		expression := match line {
			47 { &char(c'mount("proc", "/proc", "proc", 0, NULL) == 0') }
			49 { &char(c'child >= 0') }
			59 { &char(c'waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0') }
			62 { &char(c'run_once(path) == 0') }
			64 { &char(c'fd >= 0 && log_stat(fd, 0) == 0') }
			67 { &char(c'used > 0') }
			70 { &char(c'decisions == CAPACITY') }
			71 { &char(c'strstr(buffer, "first=1 last=72 count=72 reason=not_observed")') }
			72 { &char(c'strstr(buffer, "completed=1") && strstr(buffer, "reason=one_shot") && !strstr(buffer, "boot=unknown")') }
			74 { &char(c'run_once(path) == 0') }
			75 { &char(c'fd >= 0') }
			76 { &char(c'used > 0') }
			77 { &char(c'first != NULL') }
			78 { &char(c'second != NULL') }
			79 { &char(c'memcmp(first + strlen("session_start session="), second + strlen("session_start session="), 32)') }
			82 { &char(c'chmod(path, 0644) == 0 && run_once(path) == 1 && chmod(path, 0600) == 0') }
			83 { &char(c'fd >= 0 && run_once(path) == 1') }
			84 { &char(c'symlink(path, "/root/audit-collector-test/link.log") == 0') }
			85 { &char(c'run_once("/root/audit-collector-test/link.log") == 1') }
			86 { &char(c'link(path, "/root/audit-collector-test/hardlink.log") == 0 && run_once(path) == 1') }
			87 { &char(c'unlink("/root/audit-collector-test/hardlink.log") == 0') }
			88 { &char(c'run_once(path) == 0') }
			91 { &char(c'fd >= 0') }
			92 { &char(c'used > 0') }
			93 { &char(c'fd >= 0') }
			94 { &char(c'write(fd, buffer, (size_t)used) == used') }
			97 { &char(c'collector_main(6, diagnostic_args) == 0') }
			99 { &char(c'stat(path, &before) == 0') }
			100 { &char(c'child >= 0') }
			110 { &char(c'waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0') }
			111 { &char(c'stat(path, &after) == 0 && before.st_size == after.st_size') }
			else { &char(c'') }
		}
		unsafe { C.printf(c'SECURITY AUDIT COLLECTOR VM FAIL line %d: %s errno=%d\n', line, expression, C.errno) }
	}
	return ok
}

fn run_once(path &char) i32 {
	unsafe {
		mut args := [&char(c'vinix-security-audit'), &char(c'--once'), &char(c'--log'), path, &char(nil)]!
		return C.vka_main(4, &args[0])
	}
}

fn tests() i32 {
	unsafe {
		C.puts(c'SECURITY AUDIT COLLECTOR VM: producing events')
		if C.access(c'/proc/security_audit', C.F_OK) != 0 {
			if !check(C.mount(c'proc', c'/proc', c'proc', u64(0), nil) == 0, 47) { return 1 }
		}
		mut child := C.fork()
		if !check(child >= 0, 49) { return 1 }
		if child == 0 {
			mut code := [
				C.filter{code: 0x20, jt: 0, jf: 0, k: 0},
				C.filter{code: 0x15, jt: 0, jf: 1, k: u32(C.SYS_getpid)},
				C.filter{code: 0x06, jt: 0, jf: 0, k: 0x7ffc0000},
				C.filter{code: 0x06, jt: 0, jf: 0, k: 0x7fff0000},
			]!
			mut p := C.program{length: 4, instructions: &code[0]}
			if C.prctl(C.PR_SET_NO_NEW_PRIVS, i32(1), i32(0), i32(0), i32(0)) != 0 || C.syscall(i64(C.SYS_seccomp), i32(1), i32(0), &p) != 0 { C._exit(1) }
			for i := i32(0); i < 200; i++ { if C.syscall(i64(C.SYS_getpid)) <= 0 { C._exit(2) } }
			C._exit(0)
		}
		status := &i32(C.__builtin_alloca(sizeof(i32)))
		if !check(C.waitpid(child, status, i32(0)) == child && C.WIFEXITED(*status) != 0 && C.WEXITSTATUS(*status) == 0, 59) { return 1 }
		C.puts(c'SECURITY AUDIT COLLECTOR VM: collecting first session')
		path := &char(c'/root/audit-collector-test/seccomp.log')
		if !check(run_once(path) == 0, 62) { return 1 }
		mut fd := C.open(path, C.O_RDONLY)
		if !check(fd >= 0 && C.vka_log_stat(fd, u32(0)) == 0, 64) { return 1 }
		buffer := &char(C.__builtin_alloca(usize(C.OUTPUT_BYTES)))
		C.memset(buffer, 0, usize(C.OUTPUT_BYTES))
		mut used := C.read(fd, buffer, usize(C.OUTPUT_BYTES) - 1)
		if !check(used > 0, 67) { return 1 }
		C.close(fd)
		mut decisions := usize(0)
		mut line := &char(voidptr(buffer))
		for {
			line = C.strstr(line, c'decision ')
			if line == nil { break }
			decisions++
			line++
		}
		if !check(decisions == usize(C.CAPACITY), 70) { return 1 }
		if !check(C.strstr(buffer, c'first=1 last=72 count=72 reason=not_observed') != nil, 71) { return 1 }
		if !check(C.strstr(buffer, c'completed=1') != nil && C.strstr(buffer, c'reason=one_shot') != nil && C.strstr(buffer, c'boot=unknown') == nil, 72) { return 1 }
		C.puts(c'SECURITY AUDIT COLLECTOR VM: collecting second session')
		if !check(run_once(path) == 0, 74) { return 1 }
		fd = C.open(path, C.O_RDONLY)
		if !check(fd >= 0, 75) { return 1 }
		used = C.read(fd, buffer, usize(C.OUTPUT_BYTES) - 1)
		if !check(used > 0, 76) { return 1 }
		buffer[used] = 0
		C.close(fd)
		first := C.strstr(buffer, c'session_start session=')
		if !check(first != nil, 77) { return 1 }
		second := C.strstr(first + 1, c'session_start session=')
		if !check(second != nil, 78) { return 1 }
		if !check(C.memcmp(first + C.strlen(c'session_start session='), second + C.strlen(c'session_start session='), 32) != 0, 79) { return 1 }
		C.puts(c'SECURITY AUDIT COLLECTOR VM: checking log protections')
		if !check(C.chmod(path, u32(0o644)) == 0 && run_once(path) == 1 && C.chmod(path, u32(0o600)) == 0, 82) { return 1 }
		fd = C.vka_open_log(path, -1)
		if !check(fd >= 0 && run_once(path) == 1, 83) { return 1 }
		C.close(fd)
		if !check(C.symlink(path, c'/root/audit-collector-test/link.log') == 0, 84) { return 1 }
		if !check(run_once(c'/root/audit-collector-test/link.log') == 1, 85) { return 1 }
		if !check(C.link(path, c'/root/audit-collector-test/hardlink.log') == 0 && run_once(path) == 1, 86) { return 1 }
		if !check(C.unlink(c'/root/audit-collector-test/hardlink.log') == 0, 87) { return 1 }
		if !check(run_once(path) == 0, 88) { return 1 }
		source_path := &char(c'/root/audit-collector-test/snapshot')
		fd = C.open(c'/proc/security_audit', C.O_RDONLY)
		if !check(fd >= 0, 91) { return 1 }
		used = C.read(fd, buffer, usize(C.OUTPUT_BYTES))
		if !check(used > 0, 92) { return 1 }
		C.close(fd)
		fd = C.open(source_path, C.O_WRONLY | C.O_CREAT | C.O_EXCL, i32(0o600))
		if !check(fd >= 0, 93) { return 1 }
		if !check(C.write(fd, buffer, usize(used)) == used, 94) { return 1 }
		C.close(fd)
		mut diagnostic_args := [&char(c'vinix-security-audit'), &char(c'--once'), &char(c'--log'), &char(path), &char(c'--source'), &char(source_path), &char(nil)]!
		if !check(C.vka_main(6, &diagnostic_args[0]) == 0, 97) { return 1 }
		before := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		after := &C.stat(C.__builtin_alloca(sizeof(C.stat)))
		if !check(C.stat(path, before) == 0, 99) { return 1 }
		child = C.fork()
		if !check(child >= 0, 100) { return 1 }
		if child == 0 {
			if C.unshare(C.CLONE_NEWUSER) != 0 { C._exit(2) }
			diagnostic := &C.snapshot(C.__builtin_alloca(sizeof(C.snapshot)))
			if C.vka_read_snapshot(source_path, diagnostic) != 0 { C._exit(4) }
			accessible_log := C.vka_open_log(path, -1)
			if accessible_log < 0 { C._exit(5) }
			C.close(accessible_log)
			C._exit(if C.vka_main(6, &diagnostic_args[0]) == 1 { i32(0) } else { i32(3) })
		}
		if !check(C.waitpid(child, status, i32(0)) == child && C.WIFEXITED(*status) != 0 && C.WEXITSTATUS(*status) == 0, 110) { return 1 }
		if !check(C.stat(path, after) == 0 && before.st_size == after.st_size, 111) { return 1 }
		C.puts(c'SECURITY AUDIT COLLECTOR VM PASS')
	}
	return 0
}

@[export: 'main']
pub fn entry() i32 {
	unsafe { C.setvbuf(C.stdout, nil, C._IONBF, usize(0)) }
	if tests() != 0 { C.puts(c'SECURITY AUDIT COLLECTOR VM FAIL') }
	for { C.pause() }
	return 0
}
