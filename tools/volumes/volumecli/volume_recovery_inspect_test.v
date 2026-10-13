// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_recovery_inspection_syntax_rejects_before_input_access() {
	unsafe {
		for verb in [&char(c'show-recovery-volume'), &char(c'discover-recovery-volume')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(c'ro'), &char(nil)]!
			for count in [2, 3, 5, 6] { assert run(count, &args[0]) == 2 }
			for at in 2 .. 4 { args[at] = &char(c''); assert run(4, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}
