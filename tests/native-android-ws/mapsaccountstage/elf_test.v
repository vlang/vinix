// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

fn set16(mut bytes []u8, at int, value u16) {
	for index in 0 .. 2 { bytes[at + index] = u8(value >> (8 * index)) }
}

fn set64(mut bytes []u8, at int, value u64) {
	for index in 0 .. 8 { bytes[at + index] = u8(value >> (8 * index)) }
}

fn fixture() []u8 {
	mut bytes := []u8{len: 512}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { bytes[index] = value }
	set16(mut bytes, 16, 3)
	set16(mut bytes, 18, 183)
	bytes[20] = 1
	set64(mut bytes, 32, 64)
	set16(mut bytes, 52, 64)
	set16(mut bytes, 54, 56)
	set16(mut bytes, 56, 2)
	bytes[64] = 1
	set64(mut bytes, 64 + 16, 0x1000)
	set64(mut bytes, 64 + 32, 512)
	set64(mut bytes, 64 + 40, 512)
	bytes[120] = 2
	set64(mut bytes, 120 + 8, 192)
	set64(mut bytes, 120 + 16, 0x10c0)
	set64(mut bytes, 120 + 32, 80)
	set64(mut bytes, 192, 5)
	set64(mut bytes, 200, 0x1180)
	set64(mut bytes, 208, 10)
	set64(mut bytes, 216, 128)
	set64(mut bytes, 224, 1)
	set64(mut bytes, 232, 1)
	set64(mut bytes, 240, 14)
	set64(mut bytes, 248, 10)
	for index, value in '\x00libc.so\x00\x00libsample.so\x00'.bytes() { bytes[384 + index] = value }
	return bytes
}

fn test_dependency_and_soname() {
	parsed := inspect_elf(fixture())!
	assert parsed.needed == ['libc.so']
	assert parsed.soname == 'libsample.so'
	assert parsed.interpreter == ''
}

fn test_malformed_dynamic_inputs_rejected() {
	mut cases := [][]u8{}
	for at, value in {4: u64(1), 32: 500, 152: 79, 192: 15, 208: 5, 216: 99999,
		200: 0xfffffffffffffff0, 232: 128, 256: 1} {
		mut bytes := fixture()
		if at == 4 { bytes[4] = u8(value) } else { set64(mut bytes, at, value) }
		cases << bytes
	}
	mut path := fixture()
	path[385] = `/`
	cases << path
	mut unterm := fixture()
	for index in 385 .. 512 { unterm[index] = `x` }
	cases << unterm
	for bytes in cases {
		if _ := inspect_elf(bytes) { assert false, 'malformed ELF accepted' }
	}
}

fn test_static_and_wrong_interpreter() {
	mut bytes := fixture()
	set16(mut bytes, 56, 1)
	assert inspect_elf(bytes)!.needed.len == 0
	bytes = fixture()
	bytes[120] = 3
	set64(mut bytes, 120 + 8, 384)
	set64(mut bytes, 120 + 32, 9)
	if _ := inspect_elf(bytes) { assert false, 'unexpected interpreter accepted' }
}

fn test_dynamic_mapping_matches_loader() {
	for address in [u64(0), 0x10c8, 0xfffffffffffffff0] {
		mut bytes := fixture()
		set64(mut bytes, 120 + 16, address)
		if _ := inspect_elf(bytes) { assert false, 'unmapped or mismatched dynamic span accepted' }
	}
	for partial in [false, true] {
		mut overlap := fixture()
		// Move the table beyond all three program headers, then add an overlapping LOAD.
		table := overlap[192..272].clone()
		for index, value in table { overlap[256 + index] = value }
		set64(mut overlap, 128, 256)
		set64(mut overlap, 136, 0x1100)
		set16(mut overlap, 56, 3)
		for index in 176 .. 232 { overlap[index] = 0 }
		overlap[176] = 1
		set64(mut overlap, 176 + 16, if partial { u64(0x1120) } else { u64(0x1000) })
		set64(mut overlap, 176 + 32, if partial { u64(16) } else { u64(512) })
		set64(mut overlap, 176 + 40, if partial { u64(16) } else { u64(512) })
		if _ := inspect_elf(overlap) { assert false, 'ambiguous dynamic mapping accepted' }
	}
}

fn test_runpath_is_exposed_for_artifact_policy() {
	mut bytes := fixture()
	set64(mut bytes, 240, 29)
	assert inspect_elf(bytes)!.runpath == 'libsample.so'
}
