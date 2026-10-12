// SPDX-License-Identifier: ISC
module ath10k

fn test_public_wifi_states_keep_ready_radio_controls_enabled() {
	for state in [StationState.idle, .starting, .peer, .authenticating, .associating,
		.configuring, .keying, .connected] {
		public_state := status_state(true, true, 8, 0, state)
		assert public_state >= 3 && public_state <= 5
	}
	assert status_state(true, true, 8, 0, .idle) == 3
	assert status_state(true, true, 8, 0, .connected) == 5
	assert status_state(true, true, 8, 0, .failed) == 6
	assert status_state(false, false, 8, 0, .failed) == 3
	assert status_state(false, true, 1, -2, .failed) == 1
	assert status_state(false, true, 6, -5, .failed) == 6
	assert status_state(false, true, 4, 0, .idle) == 2
}

fn test_scan_results_round_trip_through_desktop_consumer() {
	mut w := Wmi{ network_count: 2, scan_error: -110 }
	w.networks[0] = Network{ ssid_len: 4, ssid: [u8(`h`), `o`, `m`, `e`, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!,
		bssid: [u8(2), 3, 4, 5, 6, 7]!, channel: 6, rssi: -47, secure: true }
	w.networks[1].ssid_len = 32
	for i in 0 .. 32 { w.networks[1].ssid[i] = u8(`a` + i % 26) }
	w.networks[1].channel = 11
	w.networks[1].rssi = -83
	mut bytes := []u8{len: 1552, init: 0xff}
	defer { unsafe { bytes.free() } }
	w.pack_networks(bytes.data)
	mut state := WifiState{}
	assert parse_wifi_networks(bytes, mut state)
	assert state.count == 2 && state.scan_error == -110
	assert state.networks[0].ssid == w.networks[0].ssid
	assert state.networks[0].bssid == w.networks[0].bssid
	assert state.networks[0].channel == 6 && state.networks[0].rssi == -47
	assert state.networks[0].secure
	assert state.networks[1].ssid == w.networks[1].ssid
	assert !state.networks[1].secure
	assert bytes[22] == 0 && bytes[23] == 0 && bytes[30] == 0 && bytes[31] == 0
	assert bytes[112] == 0 && bytes[1551] == 0 // unused entries cleared
}
