// SPDX-License-Identifier: GPL-2.0-or-later
module elffixture

// Structural publisher-admission fixtures only; these bytes are never executed.
pub fn put(mut bytes []u8, offset int, value u64) {
	for i in 0 .. 8 { bytes[offset + i] = u8(value >> (8 * i)) }
}

pub fn image(architecture string, kind string) []u8 {
	mut bytes := []u8{len: 512}
	for i, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = byte }
	bytes[16] = if kind == 'static' { u8(2) } else { u8(3) }
	bytes[18] = if architecture == 'aarch64' { u8(183) } else { u8(62) }
	bytes[20] = 1; bytes[52] = 64; bytes[54] = 56
	bytes[56] = if kind == 'pie' { u8(2) } else { u8(1) }
	put(mut bytes, 24, if kind == 'shared' { u64(0) } else { u64(0x100100) })
	put(mut bytes, 32, 64)
	bytes[64] = 1; bytes[68] = 5
	put(mut bytes, 80, 0x100000)
	put(mut bytes, 96, u64(bytes.len)); put(mut bytes, 104, 768); put(mut bytes, 112, 4096)
	if kind == 'pie' {
		name := '/lib/ld-musl-' + architecture + '.so.1'
		bytes[120] = 3; bytes[124] = 4
		put(mut bytes, 128, 320); put(mut bytes, 152, u64(name.len + 1))
		put(mut bytes, 160, u64(name.len + 1)); put(mut bytes, 168, 1)
		for i, byte in name.bytes() { bytes[320 + i] = byte }
	}
	return bytes
}
