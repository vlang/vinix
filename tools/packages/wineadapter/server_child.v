// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

// Borrowed only during start_child. The caller admits the executable and its
// environment, and supplies the foreground arguments (including any loader or
// translator). This primitive does not establish signed executable identity.
pub struct ServerCommand {
pub:
	program string
	arguments []string
}

// One owner, no copying, concurrent calls, other waiters or SIGCHLD changes.
// Keep default waitable SIGCHLD for this entire lifetime. There is deliberately
// no close that abandons a child: collect a natural exit or explicitly terminate.
// Retain this value while its borrowed PID is used for endpoint admission.
// Exclude asynchronous thread cancellation; cancellation of the owning caller
// outside these calls still requires an owner-provided cleanup policy.
pub struct ServerChild {
mut:
	pid i32
	report i32 = -1
	exec_complete bool
	failure_stage i32
	failure_errno i32
	restore_pending bool
	inherited_mask u64
}

pub struct ServerChildExit {
pub:
	collected bool
	code int
}

// Fork a direct child only after idle namespace admission. The child starts in
// the held prefix directory, inherits stdio and the caller's environment/signal
// mask, and closes all descriptors >=3 before exec except its CLOEXEC report.
// No daemonization, implicit '-f', protocol contact or server readiness claim.
// Call exec_ready immediately after return: if parent signal-mask restoration
// failed, ownership is still returned and exec_ready retries restoration before
// inspecting the report. collect/terminate also retry it before other work.
pub fn (server &ServerDirectory) start_child(guard &LaunchGuard, data string, command ServerCommand) !ServerChild {
	$if linux {
		$if amd64 || arm64 { return server.start_child_linux(guard, data, command) }
		$else { return error('Wine server child requires Linux AMD64 or AArch64') }
	} $else { return error('Wine server child requires Linux fork and descriptor isolation') }
}

// Borrowed, unreaped direct-child PID; zero after collection. Never signal or
// collect it independently. An exec acknowledgement is not a liveness proof.
pub fn (child &ServerChild) process_id() i32 { return child.pid }

// Nonblocking exec-status observation. False means pending; true means report
// EOF without a failure record. A pre-exec signal death can also produce EOF:
// authenticate the live child/lock/peer separately before calling it ready.
// Failure records remain reportable until collection; this never reaps.
pub fn (mut child ServerChild) exec_ready() !bool {
	$if linux {
		$if amd64 || arm64 { return child.exec_ready_linux() }
	}
	return error('Wine server child requires Linux AMD64 or AArch64')
}

// Nonblocking exact-child wait. A collected status consumes PID ownership and
// closes the report. Exits return 0..255; signals return 128 + signal number.
pub fn (mut child ServerChild) collect() !ServerChildExit {
	$if linux {
		$if amd64 || arm64 { return child.collect_linux(false) }
	}
	return error('Wine server child requires Linux AMD64 or AArch64')
}

// SIGKILL only this still-owned, unreaped direct child, then wait for it. This
// wait is not bounded and is not a descendant barrier. Wait errors retain the
// object for retry. Never use after another waiter consumed the PID.
pub fn (mut child ServerChild) terminate() !int {
	$if linux {
		$if amd64 || arm64 { return child.terminate_linux() }
	}
	return error('Wine server child requires Linux AMD64 or AArch64')
}
