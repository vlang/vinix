// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

fn wifi_fixture_put_at(mut bytes []u8, offset int, value u32) {
	for i in 0 .. 4 {
		bytes[offset + i] = u8(value >> (i * 8))
	}
}

fn wifi_mock_state(radio bool, scanning bool) MockDevice {
	mut status := []u8{len: wifi_status_size}
	wifi_fixture_put_at(mut status, 0, 3)
	wifi_fixture_put_at(mut status, 160, if radio { u32(1) } else { u32(0) })
	wifi_fixture_put_at(mut status, 164, if scanning { u32(1) } else { u32(0) })
	wifi_fixture_put_at(mut status, 168, 2)
	mut networks := []u8{len: wifi_networks_size}
	wifi_fixture_put_at(mut networks, 0, 1)
	wifi_fixture_put_at(mut networks, 4, 2)
	wifi_fixture_put_at(mut networks, 8, if scanning { u32(1) } else { u32(0) })
	// Secured 5 GHz network.
	networks[16] = 5
	networks[17] = 1
	networks[18] = 44
	networks[20] = u8(0xd6) // -42, little endian i16
	networks[21] = u8(0xff)
	networks[24] = 2
	for i, byte in 'Vinix'.bytes() {
		networks[32 + i] = byte
	}
	// Open 2.4 GHz network.
	offset := 16 + wifi_network_entry_size
	networks[offset] = 5
	networks[offset + 2] = 6
	networks[offset + 4] = u8(0xbd) // -67
	networks[offset + 5] = u8(0xff)
	networks[offset + 8] = 2
	for i, byte in 'Guest'.bytes() {
		networks[offset + 16 + i] = byte
	}
	return MockDevice{
		path: wifi_path
		wifi_status_reply: status
		wifi_network_reply: networks
	}
}

fn test_wifi_read_and_parse_networks() {
	mut mock := wifi_mock_state(true, false)
	mut state := WifiState{}
	assert read_wifi_with(mut mock, mut state) == .ok
	assert state.driver_state == 3 && state.radio_on && !state.scanning && state.writable
	assert state.count == 2
	assert state.networks[0].ssid_len == 5
	assert state.networks[0].ssid[..5].bytestr() == 'Vinix'
	assert state.networks[0].secure && state.networks[0].channel == 44 && state.networks[0].rssi == -42
	assert state.networks[1].ssid[..5].bytestr() == 'Guest'
	assert !state.networks[1].secure && state.networks[1].channel == 6 && state.networks[1].rssi == -67
	assert mock.opens == 1 && mock.closes == 1 && mock.stats == 1 && mock.ioctls == 2 && !mock.live
}

fn test_wifi_readonly_and_invalid_responses() {
	mut readonly := wifi_mock_state(true, false)
	readonly.rw_error = .permission
	mut state := WifiState{}
	assert read_wifi_with(mut readonly, mut state) == .ok
	assert !state.writable && readonly.opens == 2 && readonly.closes == 1
	mut malformed := wifi_mock_state(true, false)
	malformed.wifi_network_reply[16] = 33
	assert read_wifi_with(mut malformed, mut state) == .invalid
	assert malformed.closes == 1 && !malformed.live
	mut regular := wifi_mock_state(true, false)
	regular.character = false
	assert read_wifi_with(mut regular, mut state) == .invalid
	assert regular.closes == 1 && regular.ioctls == 0
}

fn test_wifi_radio_and_scan_actions_revalidate() {
	mut off := wifi_mock_state(true, false)
	off.interrupted_ioctls = 1
	assert wifi_action_with(mut off, WifiAction.radio_off) == .ok
	assert off.ioctl_request == wifi_ioctl_radio && off.ioctl_written == [u8(0), 0, 0, 0]
	assert off.ioctls == 3 && off.closes == 1
	mut on := wifi_mock_state(false, false)
	assert wifi_action_with(mut on, WifiAction.radio_on) == .ok
	assert on.ioctl_request == wifi_ioctl_radio && on.ioctl_written[0] == 1
	mut scan := wifi_mock_state(true, false)
	assert wifi_action_with(mut scan, WifiAction.scan) == .ok
	assert scan.ioctl_request == wifi_ioctl_scan && scan.ioctl_written.len == 0
	mut disabled := wifi_mock_state(false, false)
	assert wifi_action_with(mut disabled, WifiAction.scan) == .disabled
	assert disabled.ioctls == 1
}

fn test_wifi_missing_permissions_and_cold_driver() {
	mut missing := wifi_mock_state(true, false)
	missing.open_error = .unavailable
	mut state := WifiState{}
	assert read_wifi_with(mut missing, mut state) == .unavailable
	assert missing.closes == 0
	mut denied := wifi_mock_state(true, false)
	denied.rw_error = .permission
	assert wifi_action_with(mut denied, WifiAction.radio_off) == .permission
	assert denied.opens == 1 && denied.closes == 0
	mut cold := wifi_mock_state(false, false)
	wifi_fixture_put_at(mut cold.wifi_status_reply, 0, 1)
	assert wifi_action_with(mut cold, WifiAction.radio_on) == .not_ready
	assert cold.ioctls == 1 && cold.closes == 1
}
