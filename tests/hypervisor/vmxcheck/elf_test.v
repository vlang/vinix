// SPDX-License-Identifier: GPL-2.0-only
module vmxcheck

fn put(mut data []u8, offset int, width int, value u64) {
	for index in 0 .. width { data[offset + index] = u8(value >> (index * 8)) }
}

fn elf_fixture(name string) []u8 {
	mut data := []u8{len: 448}
	for index, value in [u8(0x7f), `E`, `L`, `F`, 2, 1] { data[index] = value }
	put(mut data, 40, 8, 64)
	put(mut data, 58, 2, 64)
	put(mut data, 60, 2, 4)
	// Section 1 is five instruction bytes at a full-width virtual address.
	address := u64(0xf123456789abcdef)
	put(mut data, 128 + 4, 4, 1)
	put(mut data, 128 + 16, 8, address)
	put(mut data, 128 + 24, 8, 320)
	put(mut data, 128 + 32, 8, 5)
	for index, value in [u8(0x48), 0x89, 0xe5, 0x90, 0xc3] { data[320 + index] = value }
	names := ('\x00' + name + '\x00other\x00').bytes()
	put(mut data, 192 + 4, 4, 3)
	put(mut data, 192 + 24, 8, 328)
	put(mut data, 192 + 32, 8, u64(names.len))
	for index, value in names { data[328 + index] = value }
	// Three ordinary ELF64 records, including the required empty first symbol.
	put(mut data, 256 + 4, 4, 2)
	put(mut data, 256 + 24, 8, 360)
	put(mut data, 256 + 32, 8, 72)
	put(mut data, 256 + 40, 4, 2)
	put(mut data, 256 + 56, 8, 24)
	put(mut data, 384, 4, 1)
	put(mut data, 390, 2, 1)
	put(mut data, 392, 8, address + 1)
	put(mut data, 400, 8, 3)
	put(mut data, 408, 4, u64(name.len + 2))
	put(mut data, 414, 2, 1)
	put(mut data, 416, 8, address + 4)
	put(mut data, 424, 8, 1)
	return data
}

fn elf_failure(data []u8, name string, message string) {
	elf_symbol(data, 'fixture.o', name) or {
		assert err.msg() == message
		return
	}
	assert false, 'accepted malformed ELF: ${message}'
}

fn test_elf_full_width_addresses_unicode_names_and_exact_slices() {
	for name in ['function', 'fünction', '函数'] {
		data := elf_fixture(name)
		assert elf_symbol(data, 'fixture.o', name)! == [u8(0x89), 0xe5, 0x90]
		assert elf_symbol(data, 'fixture.o', 'other')! == [u8(0xc3)]
	}
	mut data := elf_fixture('function')
	put(mut data, 400, 8, 0)
	assert elf_symbol(data, 'fixture.o', 'function')!.len == 0
	elf_failure(data, 'absent', 'missing absent in fixture.o')
	put(mut data, 256 + 4, 4, 11) // SHT_DYNSYM does not satisfy the original reader.
	elf_failure(data, 'function', 'missing function in fixture.o')
}

fn test_elf_truncation_strides_indexes_names_and_symbol_ranges() {
	fixture := elf_fixture('function')
	for length in 0 .. 64 {
		elf_failure(fixture[..length], 'function', 'not little-endian ELF64: fixture.o')
	}
	mut endian := fixture.clone()
	endian[5] = 2
	elf_failure(endian, 'function', 'not little-endian ELF64: fixture.o')
	for mutation in [
		[40, 8, -1],
		[40, 8, 400],
		[192 + 24, 8, 448],
		[256 + 32, 8, 1000],
	] {
		mut data := fixture.clone()
		put(mut data, mutation[0], mutation[1], u64(mutation[2]))
		elf_failure(data, 'function', 'truncated ELF64 range')
	}
	for mutation, message in {
		'58':  'invalid ELF64 section stride'
		'296': 'invalid ELF64 string-table index'
		'312': 'invalid ELF64 symbol stride'
		'384': 'invalid ELF64 symbol-name offset'
		'390': 'invalid ELF64 symbol-section index'
		'392': 'invalid ELF64 symbol address'
		'400': 'ELF64 symbol exceeds its section'
	} {
		mut data := fixture.clone()
		offset := mutation.int()
		width := if offset in [58, 390] {
			2
		} else if offset in [296, 384] {
			4
		} else {
			8
		}
		value := if offset in [58, 312, 392] { u64(0) } else { u64(65535) }
		put(mut data, offset, width, value)
		elf_failure(data, 'function', message)
	}
	mut size := fixture.clone()
	put(mut size, 256 + 32, 8, 71)
	elf_failure(size, 'function', 'invalid ELF64 symbol stride')
	mut unterminated := fixture.clone()
	put(mut unterminated, 192 + 32, 8, 9)
	elf_failure(unterminated, 'function', 'unterminated ELF64 symbol name')
	mut address := fixture.clone()
	put(mut address, 392, 8, u64(-1))
	elf_failure(address, 'function', 'ELF64 symbol exceeds its section')
	mut invalid := fixture.clone()
	invalid[329] = 0xff
	elf_symbol(invalid, 'fixture.o', 'function') or {
		assert err.msg().contains('Invalid UTF-8')
		return
	}
	assert false, 'accepted invalid UTF-8 symbol name'
}
