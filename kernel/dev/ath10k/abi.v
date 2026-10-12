// SPDX-License-Identifier: ISC
module ath10k

// /dev/wlan0 shares the desktop Wi-Fi ABI with the Broadcom driver. Station
// phases are private diagnostics at offset 176, not the public driver state.
pub fn status_state(active bool, radio bool, stage u32, failure int, station StationState) u32 {
	if failure == -2 { return 1 } // firmware or board data missing
	if failure != 0 { return 6 }
	if !radio && stage == 8 { return 3 } // initialized, radio switched off
	if !active { return if stage == 0 { u32(1) } else { u32(2) } }
	return match station {
		.idle { 3 }
		.connected { 5 }
		.failed { 6 }
		else { 4 }
	}
}

pub fn (w &Wmi) pack_networks(data &u8) {
	erase(data, 1552)
	put32(data, 0, 1)
	put32(data, 4, u32(w.network_count))
	put32(data, 8, if w.scanning { u32(1) } else { u32(0) })
	put32(data, 12, u32(w.scan_error))
	for i in 0 .. w.network_count {
		n := w.networks[i]
		offset := u32(16 + i * 48)
		unsafe {
			data[offset] = n.ssid_len
			data[offset + 1] = if n.secure { u8(1) } else { u8(0) }
			for j in 0 .. 6 { data[offset + 8 + u32(j)] = n.bssid[j] }
			for j in 0 .. 32 { data[offset + 16 + u32(j)] = n.ssid[j] }
		}
		put16(data, offset + 2, n.channel)
		put16(data, offset + 4, u16(n.rssi))
	}
}
