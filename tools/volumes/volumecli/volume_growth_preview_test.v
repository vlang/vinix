// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_growth_preview_syntax_rejects_invalid_paths_arity_and_sizes_before_io() {
	unsafe {
		for verb in [&char(c'plan-preview-grow-volume'), &char(c'plan-preview-grow-recovery-volume')]! {
			mut args := [&char(c'vinix-volume'), verb, &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'16777216'), &char(c'8192'), &char(nil)]!
			for count in [2, 3, 4, 5, 6, 8] { assert run(count, &args[0]) == 2 }
			for at in [2, 3, 4] { args[at] = &char(c''); assert run(7, &args[0]) == 2; args[at] = &char(c'/unused') }
			for at in [5, 6] {
				for value in [c'', c'0', c'-1', c'0x2000', c'8192x', c'18446744073709551616'] { args[at] = &char(value); assert run(7, &args[0]) == 2 }
				args[at] = if at == 5 { &char(c'16777216') } else { &char(c'8192') }
			}
		}
	}
}
