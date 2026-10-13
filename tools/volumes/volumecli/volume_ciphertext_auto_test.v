// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_automatic_ciphertext_commands_reject_bad_arity_and_empty_paths_before_io() {
	unsafe {
		for verb in [&char(c'hash-volume-auto'), &char(c'verify-volume-auto'), &char(c'hash-recovery-volume-auto'), &char(c'verify-recovery-volume-auto')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
			for count in [2, 3, 4, 6] { assert run(count, &args[0]) == 2 }
			for at in [2, 3, 4] { args[at] = &char(c''); assert run(5, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}
