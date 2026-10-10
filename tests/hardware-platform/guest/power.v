// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// power-button-init and restart: the two ways out of the machine that
// qmp-powerdown does not cover.
//
// A power button press is offered to init first, when init has a handler for
// the signal `poweroff` sends it: a desktop saves what is open before the
// machine goes. power-button-init is an init with that handler, and passes
// when the press reaches it rather than turning the machine off under it.
//
// restart asks for a reset, which the host sees for itself.
@[has_globals]
module main

import os

__global power_button_asked = false

fn on_power_off_request(_ os.Signal) {
	power_button_asked = true
}

fn scenario_power_button_init(mut t Test) {
	os.signal_opt(.usr2, on_power_off_request) or {
		t.check(false, 'could not install a SIGUSR2 handler: ${err}')
		return
	}
	t.step('waiting for power button')
	asked := wait_until(30000, fn () bool {
		return power_button_asked
	})
	t.check(asked, 'the power button press did not reach init within 30 s')
}

fn scenario_restart(mut t Test) {
	t.restarts = true
}
