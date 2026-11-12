// SPDX-License-Identifier: GPL-2.0-or-later
module launchhold

// Borrowed for the synchronous call. The caller owns a verified shared
// generation lease at lease_fd and must not close, unlock or reuse it during
// this call. The caller must preserve its default, waitable SIGCHLD policy.
pub struct Command {
pub:
	program string
	directory string
	arguments []string
}

// The private non-execing holder keeps its own lease copy until its initial
// client and adopted descendants retire. SIGKILL of that holder is outside
// this guarantee. This primitive does not authenticate a Wine server/prefix.
pub fn run(command Command, lease_fd i32) !int {
	$if linux {
		$if amd64 || arm64 { return run_linux(command, lease_fd) }
		$else { return error('generation lease supervision supports Linux AMD64 and AArch64') }
	}
	$else { return error('generation lease supervision requires Linux subreaping') }
}
