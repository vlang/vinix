// SPDX-License-Identifier: GPL-2.0-or-later
module helperfixture
#include "helper-fixture-v-abi.h"
fn C.assert(bool)
fn C.load_le32(voidptr) u32
fn C.load_le64(voidptr) u64
fn C.load_be32(voidptr) u32
fn C.store_be32(voidptr, u32)
fn C.align_up(u64, u64) u64
fn C.puts(&char) i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		// Every byte offset tests the bytewise helper's unaligned public ABI.
		for offset := u32(0); offset < 64; offset++ {
			mut bytes := [80]u8{}
			for i := u32(0); i < 80; i++ { bytes[i] = 0xa5 }
			for i := u32(0); i < 8; i++ { bytes[offset + i] = u8(i + 1) }
			C.assert(C.load_le32(&bytes[0] + offset) == u32(0x04030201))
			C.assert(C.load_le64(&bytes[0] + offset) == u64(0x0807060504030201))
			C.assert(C.load_be32(&bytes[0] + offset) == u32(0x01020304))
			C.store_be32(&bytes[0] + offset, 0x89abcdef)
			C.assert(bytes[offset] == 0x89 && bytes[offset + 1] == 0xab && bytes[offset + 2] == 0xcd && bytes[offset + 3] == 0xef)
			C.assert(bytes[offset + 4] == 5)
			if offset != 0 { C.assert(bytes[offset - 1] == 0xa5) }
		}
		for bit := u32(0); bit < 64; bit++ {
			alignment := u64(1) << bit
			C.assert(C.align_up(0, alignment) == 0)
			C.assert(C.align_up(alignment, alignment) == alignment)
			C.assert(C.align_up(alignment - 1, alignment) == if alignment == 1 { u64(0) } else { alignment })
			C.assert(C.align_up(~u64(0), alignment) == if alignment == 1 { ~u64(0) } else { u64(0) })
		}
		C.puts(c'Apple loader public byte helpers: PASS')
		return 0
	}
}
