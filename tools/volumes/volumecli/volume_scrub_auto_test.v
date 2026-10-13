// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_automatic_scrub_rejects_bad_arity_and_empty_paths_before_authentication_or_discovery() {
	unsafe {
		for verb in [&char(c'scrub-volume-auto'), &char(c'scrub-recovery-volume-auto')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
			for count in [2, 3, 4, 5, 7] { assert run(count, &args[0]) == 2 }
			for at in [2, 3, 4, 5] { args[at] = &char(c''); assert run(6, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}
