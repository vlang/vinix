// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn scenario_net_carrier(mut t Test) {
	log := read_text('/proc/bootlog') or { t.check(false, 'carrier selftest boot log unavailable'); return }
	t.check(log.contains('NET-CARRIER PASS:'), 'production DHCP/carrier boot selftest ran')
	t.check(network_works(30), 'restored interface completes DHCP and exchanges packets')
}
