// SPDX-License-Identifier: GPL-2.0-or-later
module applefixture

fn put(mut bytes []u8, offset int, value u64, width int) {
	for index in 0 .. width { bytes[offset + index] = u8(value >> (index * 8)) }
}

// SDK-free, unencrypted ARM64 iOS Mach-O. Its actual LC_MAIN code returns the
// requested status. No host syscall or ELF execution can substitute for this.
pub fn image(status u8) []u8 {
	mut bytes := []u8{len: 16384}
	put(mut bytes, 0, 0xfeedfacf, 4)
	put(mut bytes, 4, 0x100000c, 4)
	put(mut bytes, 12, 2, 4) // MH_EXECUTE
	put(mut bytes, 16, 3, 4)
	put(mut bytes, 20, 120, 4)
	put(mut bytes, 24, 0x200000, 4) // MH_PIE
	put(mut bytes, 32, 0x19, 4) // LC_SEGMENT_64
	put(mut bytes, 36, 72, 4)
	for index, byte in '__TEXT'.bytes() { bytes[40 + index] = byte }
	put(mut bytes, 56, 0x100000000, 8)
	put(mut bytes, 64, u64(bytes.len), 8)
	put(mut bytes, 80, u64(bytes.len), 8)
	put(mut bytes, 88, 5, 4)
	put(mut bytes, 92, 5, 4)
	put(mut bytes, 104, 0x80000028, 4) // LC_MAIN
	put(mut bytes, 108, 24, 4)
	put(mut bytes, 112, 512, 8)
	put(mut bytes, 128, 0x32, 4) // LC_BUILD_VERSION
	put(mut bytes, 132, 24, 4)
	put(mut bytes, 136, 2, 4) // iOS
	put(mut bytes, 140, 0xf0000, 4)
	put(mut bytes, 512, u64(0x52800000 | u32(status) << 5), 4) // mov w0, #status
	put(mut bytes, 516, 0xd65f03c0, 4) // ret
	return bytes
}
