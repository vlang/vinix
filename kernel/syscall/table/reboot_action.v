// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

import syspower

// What a reboot(2) command asks for, by Linux's numbers. A halt powers the
// machine off, as it always has here: `halt` in a virtual machine is expected
// to end it, and a halted PC with its fans running helps nobody.
fn reboot_action(command u32) syspower.Action {
	return if command == 0x01234567 { syspower.Action.restart } else { syspower.Action.power_off }
}
