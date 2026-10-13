// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_recovery_rewrap_syntax_rejects_before_input_access() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'rewrap-recovery-volume'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 4, 5, 7] { assert run(count, &args[0]) == 2 }
		for at in 2 .. 6 { args[at] = &char(c''); assert run(6, &args[0]) == 2; args[at] = &char(c'/unused') }
	}
}
