// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os

pub const smoke_success_exit = 37
pub const smoke_argument_error_exit = 99

fn smoke_put(mut data []u8, offset int, value u64, size int) {
	for i in 0 .. size {
		data[offset + i] = u8(value >> (8 * i))
	}
}

fn smoke_name(mut data []u8, offset int, name string) {
	for i, byte in name {
		data[offset + i] = byte
	}
}

// smoke_image creates a synthetic, SDK-free iOS ARM64 executable. Its entry
// validates argc/argv and returns 37, or 99 when an extra argument is supplied.
// This verifies mapping, startup, argument forwarding and returning to the
// Linux runner; it is not a Fortnite fixture or evidence of game progress.
pub fn smoke_image() []u8 {
	mut data := []u8{len: 0x4000}
	base := u64(0x100000000)
	entry := u64(0x200)
	code := [u32(0x7100041f), // cmp w0, #1
	0x54000101, // b.ne failure (+32)
	0xb40000e1, // cbz x1, failure (+28)
	0xf9400022, // ldr x2, [x1]
	0xb40000a2, // cbz x2, failure (+20)
	0xf9400422, // ldr x2, [x1, #8]
	0xb5000062, // cbnz x2, failure (+12)
	0x528004a0, // mov w0, #37
	0xd65f03c0, // ret
	0x52800c60, // failure: mov w0, #99
	0xd65f03c0]!

	// mach_header_64: ARM64, MH_EXECUTE, four commands, MH_PIE.
	smoke_put(mut data, 0, 0xfeedfacf, 4)
	smoke_put(mut data, 4, 0x100000c, 4)
	smoke_put(mut data, 12, 2, 4)
	smoke_put(mut data, 16, 4, 4)
	smoke_put(mut data, 20, 72 + 152 + 24 + 24, 4)
	smoke_put(mut data, 24, 0x200000, 4)

	// An unmapped __PAGEZERO followed by one read/execute __TEXT segment.
	smoke_put(mut data, 32, 0x19, 4)
	smoke_put(mut data, 36, 72, 4)
	smoke_name(mut data, 40, '__PAGEZERO')
	smoke_put(mut data, 64, base, 8)
	smoke_put(mut data, 104, 0x19, 4)
	smoke_put(mut data, 108, 152, 4)
	smoke_name(mut data, 112, '__TEXT')
	smoke_put(mut data, 128, base, 8)
	smoke_put(mut data, 136, u64(data.len), 8)
	smoke_put(mut data, 152, u64(data.len), 8)
	smoke_put(mut data, 160, 5, 4)
	smoke_put(mut data, 164, 5, 4)
	smoke_put(mut data, 168, 1, 4)
	// section_64: __text, with both instruction attributes and 4-byte alignment.
	smoke_name(mut data, 176, '__text')
	smoke_name(mut data, 192, '__TEXT')
	smoke_put(mut data, 208, base + entry, 8)
	smoke_put(mut data, 216, u64(code.len * 4), 8)
	smoke_put(mut data, 224, entry, 4)
	smoke_put(mut data, 228, 2, 4)
	smoke_put(mut data, 240, 0x80000400, 4)

	// LC_MAIN and LC_BUILD_VERSION (iOS 15.0); no imports or fixups.
	smoke_put(mut data, 256, 0x80000028, 4)
	smoke_put(mut data, 260, 24, 4)
	smoke_put(mut data, 264, entry, 8)
	smoke_put(mut data, 280, 0x32, 4)
	smoke_put(mut data, 284, 24, 4)
	smoke_put(mut data, 288, 2, 4)
	smoke_put(mut data, 292, 0xf0000, 4)
	smoke_put(mut data, 296, 0xf0000, 4)
	for i, instruction in code {
		smoke_put(mut data, int(entry) + i * 4, u64(instruction), 4)
	}
	return data
}

// write_smoke writes the generated synthetic executable to a fresh evidence path.
pub fn write_smoke(path string) ! {
	if os.exists(path) || os.is_link(path) {
		return error('synthetic iOS smoke output must be fresh: ${path}')
	}
	data := smoke_image()
	defer { unsafe { data.free() } }
	os.write_file_array(path, data)!
}
