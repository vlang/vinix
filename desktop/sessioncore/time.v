// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

// Validate the entire SNTP reply before trusting a network clock. The caller
// generates a fresh, unpredictable transmit token for each request.
pub fn ntp_time(packet []u8, token [8]u8, elapsed_ms i64) !i64 {
	if packet.len != 48 || elapsed_ms < 0 || elapsed_ms > 2000 {
		return error('invalid time response')
	}
	version := (packet[0] >> 3) & 7
	if packet[0] >> 6 == 3 || version < 3 || version > 4 || packet[0] & 7 != 4 || packet[1] < 1 || packet[1] > 15 {
		return error('unsynchronized time server')
	}
	for i in 0 .. 8 {
		if packet[24 + i] != token[i] { return error('time response belongs to another request') }
	}
	seconds := u32(packet[40]) << 24 | u32(packet[41]) << 16 | u32(packet[42]) << 8 | u32(packet[43])
	fraction := u32(packet[44]) << 24 | u32(packet[45]) << 16 | u32(packet[46]) << 8 | u32(packet[47])
	// NTP era 1 starts in 2036. Support 2020..2100 independently of a broken RTC.
	era := if seconds < 2208988800 { i64(1) << 32 } else { i64(0) }
	unix_ms := (i64(seconds) + era - 2208988800) * 1000 + i64((u64(fraction) * 1000) >> 32) + elapsed_ms / 2
	if unix_ms < 1577836800000 || unix_ms >= 4102444800000 {
		return error('network clock out of range')
	}
	root_delay := u32(packet[4]) << 24 | u32(packet[5]) << 16 | u32(packet[6]) << 8 | u32(packet[7])
	dispersion := u32(packet[8]) << 24 | u32(packet[9]) << 16 | u32(packet[10]) << 8 | u32(packet[11])
	if i32(root_delay) < 0 || root_delay > 2 * 65536 || dispersion > 2 * 65536 {
		return error('unreliable network clock')
	}
	return unix_ms
}
