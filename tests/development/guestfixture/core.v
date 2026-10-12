// SPDX-License-Identifier: GPL-2.0-or-later
// Public CLI fixture. The job payload is this same V executable, dispatched
// only by an explicitly selected environment variable.
@[has_globals]
module guestfixture

#include <native-abi.h>
@[typedef]
struct C.FILE {}

struct C.utsname {
	sysname [65]char
}

struct C.stat {
	st_uid  u32
	st_mode u32
}

@[c_extern]
__global C.stdout &C.FILE

fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.chmod(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.chdir(&char) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.fstat(i32, &C.stat) i32
fn C.uname(&C.utsname) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.getenv(&char) &char
fn C.setenv(&char, &char, i32) i32
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.pause() i32

fn check(ok bool, line int) {
	if !ok {
		unsafe { C.printf(c'DEVELOPMENT GUEST FAIL line=%d errno=%d\n', line, *C.__errno_location()) }
		C._exit(1)
	}
}

fn require_vinix() {
	mut kernel := C.utsname{}
	check(C.uname(unsafe { &kernel }) == 0
		&& C.strcmp(unsafe { &kernel.sysname[0] }, c'Vinix') == 0, 153)
}

fn write_text(path &char, value &char, length usize) {
	unsafe {
		fd := C.open(path, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0 && C.write(fd, value, length) == isize(length) && C.close(fd) == 0, 62)
	}
}

fn job_payload() i32 {
	unsafe {
		token := C.getenv(c'TEST_TOKEN')
		check(C.getuid() == 1000 && C.geteuid() == 1000 && C.getgid() == 1000 && C.getegid() == 1000, 69)
		check(token != nil && C.strcmp(token, c'vinix-native-fixture-secret') == 0, 70)
		check(C.getenv(c'UNSELECTED_PARENT_SECRET') == nil, 71)
		write_text(c'/home/developer/payload.done', c'completed', 9)
		// Both streams must be discarded by the scheduler, not saved in logs.
		C.puts(c'vinix-native-fixture-secret')
		C.write(2, c'vinix-native-fixture-secret\n', 28)
		return 0
	}
}

fn command(program &char, action &char, argument &char, extra &char) i32 {
	unsafe {
		mut argv := [5]&char{}
		argv[0] = program
		argv[1] = action
		argv[2] = argument
		argv[3] = extra
		pid := C.fork()
		check(pid >= 0, 91)
		if pid == 0 {
			C.execv(program, &argv[0])
			C._exit(127)
		}
		mut status := i32(0)
		check(C.waitpid(pid, &status, 0) == pid && C.WIFEXITED(status) != 0, 97)
		return C.WEXITSTATUS(status)
	}
}

fn private_receipt(path &char, expected &char) {
	unsafe {
		mut text := [8192]char{}
		fd := C.open(path, C.O_RDONLY)
		check(fd >= 0, 106)
		count := C.read(fd, &text[0], text.len - 1)
		mut st := C.stat{}
		check(C.fstat(fd, &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o077 == 0, 107)
		check(count > 0 && count < text.len - 1 && C.close(fd) == 0, 108)
		check(C.strstr(&text[0], c'vinix-native-fixture-secret') == nil, 109)
		check(C.strstr(&text[0], expected) != nil, 110)
		C.printf(c'DEVELOPMENT RECEIPT %s %s\n', path, &text[0])
	}
}

fn account_checks() {
	unsafe {
		check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 116)
		check(C.chdir(c'/home/developer') == 0, 117)
		check(C.setenv(c'UNSELECTED_PARENT_SECRET', c'parent-must-not-reach-job', 1) == 0, 118)
		for program in [&char(c'/usr/bin/vinix-build'), &char(c'/usr/bin/vinix-qualify'),
			&char(c'/usr/bin/vinix-vm'), &char(c'/usr/bin/vinix-jobs')]! {
			check(command(program, c'--help', nil, nil) == 0, 120)
		}
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/jobs.json', c'/home/developer/good') == 0, 123)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/good', nil) == 0, 124)
		private_receipt(c'/home/developer/good/state.json', c'"runs":1')
		private_receipt(c'/home/developer/good/plan.json', c'TEST_TOKEN')
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/good', nil) == 0, 127)
		private_receipt(c'/home/developer/good/state.json', c'"runs":1')
		mut proof := [10]char{}
		fd := C.open(c'/home/developer/payload.done', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &proof[0], 9) == 9 && C.close(fd) == 0 && C.strcmp(&proof[0], c'completed') == 0, 131)
		check(C.unlink(c'/home/developer/payload.done') == 0, 132)
		check(C.chmod(c'/home/developer/token', 0o644) == 0, 133)
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/jobs.json', c'/home/developer/public-token') == 0, 134)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/public-token', nil) == 1, 135)
		private_receipt(c'/home/developer/public-token/state.json', c'private file must be regular')
		check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 137)
		check(C.chmod(c'/home/developer/token', 0o600) == 0, 138)
		check(C.symlink(c'token', c'/home/developer/token-link') == 0, 139)
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/link-jobs.json', c'/home/developer/link-token') == 0, 140)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/link-token', nil) == 1, 141)
		private_receipt(c'/home/developer/link-token/state.json', c'cannot open private file')
		check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 143)
		C.puts(c'DEVELOPMENT ACCOUNT PASS: UID 1000 jobs, credentials, environment, receipts, interval, unsafe-file refusal')
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		if C.getenv(c'VINIX_DEVELOPMENT_PAYLOAD') != nil { return job_payload() }
		require_vinix()
		check(C.chown(c'/home/developer', 1000, 1000) == 0 && C.chmod(c'/home/developer', 0o700) == 0, 154)
		for path in [&char(c'/home/developer/token'), &char(c'/home/developer/jobs.json'),
			&char(c'/home/developer/link-jobs.json')]! {
			check(C.chown(path, 1000, 1000) == 0 && C.chmod(path, 0o600) == 0, 156)
		}
		// Even root must not silently run a schedule labelled as another account.
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/jobs.json', c'/root/wrong-owner') == 1, 159)
		pid := C.fork()
		check(pid >= 0, 161)
		if pid == 0 {
			account_checks()
			C._exit(0)
		}
		mut status := i32(0)
		check(C.waitpid(pid, &status, 0) == pid && status == 0, 164)
		C.puts(c'DEVELOPMENT GUEST PASS')
		for { C.pause() }
		return 0
	}
}
