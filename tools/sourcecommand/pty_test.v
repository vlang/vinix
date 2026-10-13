// SPDX-License-Identifier: GPL-2.0-or-later
module sourcecommand

import os

fn test_fast_exit_and_failed_exec_keep_reserved_identity_and_retire_descriptors() {
	baseline := os.ls('/dev/fd') or { panic(err) }
	for index in 0 .. 1000 {
		command := if index % 2 == 0 { '/usr/bin/true' } else { '/vinix-nonexistent-pty-program' }
		mut child := spawn_pty([command], os.environ(), '') or { panic(err) }
		assert child.settle(2) or { panic(err) }
		assert (child.poll() or { panic(err) }).return_code == if index % 2 == 0 { 0 } else { 127 }
		child.close() or { panic(err) }
		child.close() or { panic(err) }
	}
	assert (os.ls('/dev/fd') or { panic(err) }).len == baseline.len
	mut status := i32(0)
	assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
}
