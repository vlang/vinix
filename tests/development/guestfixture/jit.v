// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <sys/mount.h>
fn C.mount(&char, &char, &char, usize, voidptr) i32

// The request must fail at exec, before an unapproved runtime can start.
fn jit_denied(program &char) {
	unsafe {
		pid := C.fork()
		check(pid >= 0, 390)
		if pid == 0 {
			check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 391)
			check(C.setenv(c'VINIX_ALLOW_WX', c'1', 1) == 0, 392)
			args := [program, &char(c'--version'), &char(nil)]!
			C.execv(program, &args[0])
			C._exit(if *C.__errno_location() == C.EPERM { 0 } else { 1 })
		}
		mut status := i32(0)
		check(C.waitpid(pid, &status, 0) == pid && C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0, 393)
	}
}

fn reference_jit_prepare() bool {
	unsafe {
		marker := C.open(c'/home/developer/reference-jit', C.O_RDONLY)
		if marker < 0 { return false }
		check(C.close(marker) == 0, 394)
		mut st := C.stat{}
		check(C.stat(c'/opt/reference/share/jdk', &st) == 0 && st.st_uid == 0 && st.st_mode & 0o022 == 0, 395)
		jit_denied(c'/opt/reference/bin/java')
		check(C.mount(c'/opt/reference/share/jdk', c'/opt/reference/share/jdk', nil, usize(C.MS_BIND), nil) == 0, 396)
		check(C.mount(c'none', c'/opt/reference/share/jdk', nil,
			usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV), c'wxallowed') == 0, 397)
		// An approved JDK mount cannot authorize the unrelated build runner.
		jit_denied(c'/usr/bin/vinix-build')
		C.puts(c'DEVELOPMENT JIT APPROVAL PASS: UID 1000 request denied before approval and outside the read-only JDK mount')
		return true
	}
}

fn reference_jit_revoke(approved bool) {
	unsafe {
		if !approved { return }
		check(C.mount(c'none', c'/opt/reference/share/jdk', nil,
			usize(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY | C.MS_NOSUID | C.MS_NODEV), nil) == 0, 398)
		jit_denied(c'/opt/reference/bin/java')
		C.puts(c'DEVELOPMENT JIT REVOCATION PASS: UID 1000 runtime request denied after administrator revocation')
	}
}
