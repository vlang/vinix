// SPDX-License-Identifier: GPL-2.0-or-later
module display

import encoding.binary

fn test_virtual_display_mode_has_a_defined_sixty_hertz_refresh_rate() {
	for dimensions in [[850, 600]!, [1100, 760]!, [1920, 1080]!] {
		packet := timed_mode(140, 33, u16(dimensions[0]), u16(dimensions[1]))
		clock := binary.little_endian_u32(packet[16..20])
		htotal := binary.little_endian_u16(packet[24..26])
		vtotal := binary.little_endian_u16(packet[32..34])
		assert clock / (u32(htotal) * u32(vtotal)) == 60
		assert packet.len == int(binary.little_endian_u16(packet[2..4])) * 4
		assert packet[40..50].bytestr() == 'vinix-60hz'
	}
}

fn test_nonlocal_display_is_rejected_before_connecting() {
	for name in ['', 'localhost:0', ':abc', ':-1'] {
		mut refused := false
		ensure_refresh(name) or { refused = true }
		assert refused
	}
}
