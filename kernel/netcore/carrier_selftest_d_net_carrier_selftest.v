// SPDX-License-Identifier: GPL-2.0-or-later
// Opt-in boot regression using the production adapter and the real lwIP
// DHCP state machine. No physical Realtek controller is required.
@[translated]
module netcore

#include <lwip/prot/dhcp.h>

pub struct C.dhcp {
pub mut:
	state u8
	tries u8
}

pub fn carrier_selftest() bool {
	unsafe {
		original_driver := net_active_driver
		original_mac := net_active_mac
		vinix_net_detach()
		defer {
			vinix_net_detach()
			if original_driver != driver_none {
				_ = vinix_net_attach(&original_mac[0], original_driver)
			}
		}
		mac := [u8(2), 0, 0, 0, 0, 1]!
		for driver in [driver_rtl8169, driver_ath10k]! {
			if vinix_net_attach(&mac[0], driver) != 0 { return false }
			if vinix_net_owner() != driver { return false }
			client := &C.dhcp(net_physical_netif.client_data[C.LWIP_NETIF_CLIENT_DATA_INDEX_DHCP])
			if is_null(client) || vinix_net_carrier() != 0 || client.state != C.DHCP_STATE_INIT {
				return false
			}
			// Interface enumeration must work while IPv4 and carrier are absent.
			mut fields := [16]u64{}
			if vinix_net_counters(1, &fields[0]) != 1
				|| vinix_net_counters(2, &fields[0]) != 1
				|| net_physical_netif.ip_addr.u_addr.ip4.addr != 0 { return false }
			vinix_net_set_link(driver_e1000, 1)
			if vinix_net_carrier() != 0 || client.state != C.DHCP_STATE_INIT { return false }
			vinix_net_set_link(driver, 1)
			if vinix_net_carrier() != 1 || client.state != C.DHCP_STATE_SELECTING || client.tries != 1 {
				return false
			}
			// Repeated up reports must not send another DISCOVER or reset retries.
			vinix_net_set_link(driver, 1)
			if client.state != C.DHCP_STATE_SELECTING || client.tries != 1 { return false }
			vinix_net_set_link(driver, 0)
			if vinix_net_carrier() != 0 { return false }
			vinix_net_set_link(driver, 1)
			if vinix_net_carrier() != 1 || client.state != C.DHCP_STATE_SELECTING || client.tries != 1 {
				return false
			}
			vinix_net_detach()
			if vinix_net_counters(2, &fields[0]) != 0 { return false }
		}
		C.kprintf(c'NET-CARRIER PASS: deferred DHCP, immediate carrier discovery, reconnect, driver ownership\n')
		C.printf_benchmark(c'NET-CARRIER PASS: deferred DHCP, immediate carrier discovery, reconnect, driver ownership\n')
		return true
	}
}
