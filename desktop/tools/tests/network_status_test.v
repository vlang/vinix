// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn network_test_no_carrier(_ &char, flags &u16) int {
	unsafe { *flags = u16(C.IFF_UP | C.IFF_BROADCAST | C.IFF_MULTICAST) }
	return 0
}

fn network_test_carrier(_ &char, flags &u16) int {
	unsafe { *flags = u16(C.IFF_UP | C.IFF_RUNNING) }
	return 0
}

fn network_test_absent(_ &char, _ &u16) int { return C.ENODEV }
fn network_test_failed(_ &char, _ &u16) int { return C.EIO }

fn network_test_no_address_query(_ &char, _ &u32) int {
	assert false, 'IPv4 must not be queried without carrier'
	return C.EIO
}

fn network_test_no_address(_ &char, _ &u32) int { return C.EADDRNOTAVAIL }

fn network_test_address(_ &char, address &u32) int {
	unsafe { *address = 0x0f02000a }
	return 0
}

fn test_unplugged_adapter_is_disconnected_without_querying_dhcp_address() {
	link, address := sample_ethernet_with(network_test_no_carrier, network_test_no_address_query)
	assert link == .disconnected && address == 0
	absent, _ := sample_ethernet_with(network_test_absent, network_test_no_address_query)
	assert absent == .absent
	failed, _ := sample_ethernet_with(network_test_failed, network_test_no_address_query)
	assert failed == .unknown
}

fn test_connect_acquire_lease_unplug_updates_text_and_hides_old_address() {
	set_desktop_language(.en)
	mut d := Desktop{}
	acquiring, zero := sample_ethernet_with(network_test_carrier, network_test_no_address)
	d.apply_tray_sample(TraySample{ ethernet: acquiring, address: zero })
	assert acquiring == .pending && zero == 0
	assert d.tray.ethernet_line == 'Ethernet: acquiring an address'
	assert d.tray_glyph(.network) == 'builtin:network_pending'
	connected, address := sample_ethernet_with(network_test_carrier, network_test_address)
	d.apply_tray_sample(TraySample{ ethernet: connected, address: address })
	assert connected == .connected
	assert d.tray.address_line == 'IPv4 address 10.0.2.15'
	// A lease can remain stored in the kernel after unplugging. Carrier takes
	// precedence, so the disconnected tray must hide that old address.
	disconnected, old_address := sample_ethernet_with(network_test_no_carrier, network_test_address)
	d.apply_tray_sample(TraySample{ ethernet: disconnected, address: old_address })
	assert disconnected == .disconnected && old_address == 0
	assert d.tray.ethernet_line == 'Ethernet: disconnected'
	assert d.tray.network_tip == 'Not connected'
	assert d.tray.address_line == ''
	assert d.tray_glyph(.network) == 'builtin:network_offline'
	set_desktop_language(.ru)
	d.apply_tray_sample(d.tray.sample)
	assert d.tray.ethernet_line == 'Ethernet: нет соединения'
	set_desktop_language(.en)
}

fn test_interface_flags_native_ifreq_abi_and_missing_interface() {
	mut flags := u16(0)
	name := 'vinix-no-if'
	assert interface_flags(&char(name.str), &flags) != 0
	$if macos {
		loopback := 'lo0'
		assert interface_flags(&char(loopback.str), &flags) == 0
		assert flags & u16(C.IFF_LOOPBACK) != 0
	} $else $if linux {
		loopback := 'lo'
		assert interface_flags(&char(loopback.str), &flags) == 0
		assert flags & u16(C.IFF_LOOPBACK) != 0
	}
}
