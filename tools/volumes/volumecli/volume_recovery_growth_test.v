// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn test_recovery_growth_cli_rejects_invalid_sizes_paths_and_arity_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'plan-grow-recovery-volume'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(c'16777216'), &char(c'8192'), &char(c'/unused'), &char(nil)]!
		for count in [2, 3, 4, 5, 6, 7, 9] { assert run(count, &args[0]) == 2 }
		for at in [2, 3, 4, 7] { args[at] = &char(c''); assert run(8, &args[0]) == 2; args[at] = &char(c'/unused') }
		for at in [5, 6] {
			for value in [c'', c'0', c'-1', c'0x2000', c'8192x', c'18446744073709551616'] { args[at] = &char(value); assert run(8, &args[0]) == 2 }
			args[at] = if at == 5 { &char(c'16777216') } else { &char(c'8192') }
		}
	}
}
