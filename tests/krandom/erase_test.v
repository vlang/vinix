// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

fn test_explicit_bzero_range_and_guards() {
	for offset in 0 .. 64 {
		for length in 0 .. 65 {
			mut bytes := [128]u8{}
			for i in 0 .. bytes.len {
				bytes[i] = 0xa5
			}
			explicit_bzero(unsafe { &bytes[offset] }, usize(length))
			for i in 0 .. bytes.len {
				expected := if i >= offset && i < offset + length { u8(0) } else { u8(0xa5) }
				assert bytes[i] == expected
			}
		}
	}
}

fn test_explicit_bzero_empty_null() {
	explicit_bzero(unsafe { nil }, 0)
}
