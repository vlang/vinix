// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

#include <sys/syscall.h>

@[typedef]
struct C.siginfo_t {
	si_pid i32
}

fn C.syscall(isize, ...) isize

fn signal_identity_checks() {
	unsafe {
		check(C.getuid() == 1000 && C.geteuid() == 1000, 370)
		// Matching namespace membership does not grant another account's PID.
		check(C.kill(1, 0) == -1 && *C.__errno_location() == C.EPERM, 371)
		check(C.kill(1, C.SIGTERM) == -1 && *C.__errno_location() == C.EPERM, 372)
		pid := C.fork()
		check(pid >= 0, 373)
		if pid == 0 { C._exit(23) }
		deadline := job_clock() + 10000000000
		for {
			mut info := C.siginfo_t{}
			check(C.syscall(C.SYS_waitid, C.P_PID, u32(pid), &info,
				C.WEXITED | C.WNOHANG | C.WNOWAIT, voidptr(nil)) == 0, 374)
			if info.si_pid == pid { break }
			check(job_clock() < deadline, 375)
			C.usleep(10000)
		}
		// WNOWAIT retains the child's identity after its namespaces retired.
		// Signal probes and real signals are still authorized until reap.
		for _ in 0 .. 100 {
			check(C.kill(pid, 0) == 0 && C.kill(pid, C.SIGTERM) == 0, 376)
		}
		mut status := i32(0)
		check(C.waitpid(pid, &status, 0) == pid && C.WIFEXITED(status) != 0
			&& C.WEXITSTATUS(status) == 23, 377)
		check(C.kill(pid, 0) == -1 && *C.__errno_location() == C.ESRCH, 378)
		C.puts(c'DEVELOPMENT SIGNAL IDENTITY PASS: UID 1000, foreign-account refusal, 100 authorized zombie probes/signals, ESRCH after reap')
	}
}
