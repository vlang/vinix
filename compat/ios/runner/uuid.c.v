// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn darwin_uuid_generate(output &u8) {
	previous := unsafe { *C.ios_errno_address() }
	// Native Darwin generates version-4 UUIDs. Use the host's secure entropy
	// source, then reserve the version and variant bits in the 16-byte value.
	// This void API cannot report failure; never publish a weak/constant ID.
	mut bytes := [16]u8{}
	if C.getentropy(unsafe { &bytes[0] }, 16) != 0 {
		panic('iOS: UUID native entropy source failed')
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	unsafe { C.memcpy(output, &bytes[0], 16) }
	darwin_set_errno(previous)
}
