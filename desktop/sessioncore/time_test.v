// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn test_network_time_validation_and_era() {
	mut packet := []u8{len: 48}
	packet[0] = 0x24
	packet[1] = 2
	token := [u8(1), 2, 3, 4, 5, 6, 7, 8]!
	for i in 0 .. 8 { packet[24 + i] = token[i] }
	seconds := u32(3976214400) // 2026-01-01
	for i in 0 .. 4 { packet[40 + i] = u8(seconds >> (24 - 8 * i)) }
	assert ntp_time(packet, token, 100) or { -1 } == 1767225600050
	wrapped := u32(28402304) // 2037-01-01, NTP era 1
	for i in 0 .. 4 { packet[40 + i] = u8(wrapped >> (24 - 8 * i)) }
	assert ntp_time(packet, token, 0)! == 2114380800000
	packet[0] = 0xe4
	if _ := ntp_time(packet, token, 100) {
		assert false
	}
	packet[0] = 0x24
	packet[24] = 0
	if _ := ntp_time(packet, token, 100) {
		assert false
	}
	packet[24] = 1
	if _ := ntp_time(packet, token, 2001) {
		assert false
	}
}
