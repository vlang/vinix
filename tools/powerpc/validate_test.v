module main

import encoding.binary

fn minimal_tree() []u8 {
	mut bytes := []u8{len: 104}
	for at, value in {
		0:   u32(0xd00dfeed)
		4:   104
		8:   88
		12:  104
		16:  40
		20:  17
		24:  16
		36:  16
		88:  1
		96:  2
		100: 9
	} {
		binary.big_endian_put_u32(mut bytes[at..at + 4], value)
	}
	return bytes
}

fn test_fdt_rejects_truncation_and_malformed_structure() {
	bytes := minimal_tree()
	assert validate_tree(bytes) or { 0 } == 1
	for size in 0 .. bytes.len {
		if _ := validate_tree(bytes[..size]) {
			assert false, 'accepted truncated FDT (${size})'
		}
	}
	for at, value in {
		0:   u32(0)
		4:   103
		8:   0xfffffffc
		12:  100
		32:  0xffffffff
		36:  12
		88:  2
		92:  0x61000000
		96:  9
		100: 0
	} {
		mut invalid := bytes.clone()
		binary.big_endian_put_u32(mut invalid[at..at + 4], value)
		if _ := validate_tree(invalid) {
			assert false, 'accepted invalid FDT field at ${at}'
		}
	}
}
