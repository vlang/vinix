// SPDX-License-Identifier: GPL-2.0-or-later
module inet

import netcore

pub fn carrier_selftest() {
	net_lock.acquire()
	ok := netcore.carrier_selftest()
	net_lock.release()
	if !ok { panic('network carrier/DHCP selftest failed') }
}
