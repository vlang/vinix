// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// qmp-powerdown: the power button turns the machine off.
//
// The guest has nothing to do here but say that it is ready and wait. The
// host then presses the button (QMP system_powerdown, which raises the
// machine's power button event), and what is judged is whether the machine
// goes off -- which the host sees for itself. A kernel that hands the button
// to init instead of acting on it would need this function to do the
// powering off.
module main

fn scenario_qmp_powerdown(mut t Test) {
	t.step('waiting for power button')
	idle()
}
