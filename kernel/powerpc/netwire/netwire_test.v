// SPDX-License-Identifier: GPL-2.0-or-later
module netwire

fn fixture() []u8 {
	mut frame := []u8{len: 342}
	data := &u8(frame.data)
	frame[12] = 8
	frame[14] = 0x45
	frame[22] = 64
	frame[23] = 17
	put16(data, 16, 328)
	put32(data, 26, 0x0a000202)
	put32(data, 30, 0xffffffff)
	put16(data, 34, 67)
	put16(data, 36, 68)
	put16(data, 38, 308)
	frame[42] = 2; frame[43] = 1; frame[44] = 6
	put32(data, 46, 0x12345678)
	put32(data, 58, 0x0a00020f)
	for i, b in [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56] { frame[70 + i] = b }
	put32(data, 278, 0x63825363)
	options := [u8(53), 1, 2, 54, 4, 10, 0, 2, 2, 1, 4, 255, 255, 255, 0, 3, 4, 10, 0, 2, 2, 51, 4, 0, 0, 14, 16, 255]
	for i, b in options { frame[282 + i] = b }
	put16(data, 24, checksum(unsafe { &data[14] }, 20, 0))
	return frame
}

fn test_internet_checksum_and_odd_byte() {
	data := [u8(0), 1, 0xf2, 3, 0xf4, 0xf5, 0xf6, 0xf7]
	assert checksum(data.data, 8, 0) == 0x220d
	assert checksum(data.data, 3, 0) == 0x0dfe
}

fn test_dhcp_lengths_identity_and_options() {
	mac := [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56]
	frame := fixture()
	offer := dhcp(frame.data, u32(frame.len), 0x12345678, mac.data)
	assert offer.valid && offer.kind == 2 && offer.address == 0x0a00020f
	assert offer.server == 0x0a000202 && offer.mask == 0xffffff00 && offer.lease == 3600
	for n in 0 .. frame.len { assert !dhcp(frame.data, u32(n), 0x12345678, mac.data).valid }
	assert !dhcp(frame.data, u32(frame.len), 0x12345679, mac.data).valid
	for index in [14, 16, 20, 24, 34, 36, 38, 42, 43, 44, 46, 70, 278, 283, 286, 292, 304] {
		mut corrupted := frame.clone()
		corrupted[index] ^= 0xff
		assert !dhcp(corrupted.data, u32(corrupted.len), 0x12345678, mac.data).valid
	}
	mut overload := frame.clone()
	overload[309] = 52; overload[310] = 1; overload[311] = 1; overload[312] = 255
	assert !dhcp(overload.data, u32(overload.len), 0x12345678, mac.data).valid
	mut duplicate := frame.clone()
	duplicate[309] = 54; duplicate[310] = 4; duplicate[315] = 255
	assert !dhcp(duplicate.data, u32(duplicate.len), 0x12345678, mac.data).valid
}

fn test_udp_checksum_and_fragment_rejection() {
	mac := [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56]
	mut frame := fixture()
	data := &u8(frame.data)
	pseudo := u32(0x0a00 + 0x0202 + 0xffff + 0xffff + 17 + 308)
	put16(data, 40, checksum(unsafe { &data[34] }, 308, pseudo))
	assert dhcp(data, u32(frame.len), 0x12345678, mac.data).valid
	frame[300] ^= 1
	assert !dhcp(data, u32(frame.len), 0x12345678, mac.data).valid
	put16(data, 40, 0)
	frame[20] = 0x20
	put16(data, 24, 0)
	put16(data, 24, checksum(unsafe { &data[14] }, 20, 0))
	assert !ipv4(data, u32(frame.len)).valid
}
