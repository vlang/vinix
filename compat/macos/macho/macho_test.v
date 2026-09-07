module macho

fn put_le_u32(mut data []u8, offset int, value u32) {
	for byte in 0 .. 4 {
		data[offset + byte] = u8(value >> (byte * 8))
	}
}

fn put_le_u64(mut data []u8, offset int, value u64) {
	for byte in 0 .. 8 {
		data[offset + byte] = u8(value >> (byte * 8))
	}
}

fn put_be_u32(mut data []u8, offset int, value u32) {
	for byte in 0 .. 4 {
		shift := (3 - byte) * 8
		data[offset + byte] = u8(value >> shift)
	}
}

fn synthetic_executable() []u8 {
	mut data := []u8{len: 256}
	put_le_u32(mut data, 0, magic_64)
	put_le_u32(mut data, 4, cpu_type_arm64)
	put_le_u32(mut data, 12, mh_execute)
	put_le_u32(mut data, 16, 2)
	put_le_u32(mut data, 20, 96)
	put_le_u32(mut data, 32, lc_segment_64)
	put_le_u32(mut data, 36, 72)
	copy(mut data[40..], '__TEXT'.bytes())
	put_le_u64(mut data, 56, 0x100000000)
	put_le_u64(mut data, 64, 0x1000)
	put_le_u64(mut data, 72, 0)
	put_le_u64(mut data, 80, 256)
	put_le_u32(mut data, 88, 5)
	put_le_u32(mut data, 92, 5)
	put_le_u32(mut data, 104, lc_main)
	put_le_u32(mut data, 108, 24)
	put_le_u64(mut data, 112, 128)
	return data
}

fn test_parse_thin_arm64_executable() {
	data := synthetic_executable()
	image := parse(data, cpu_type_arm64) or { panic(err) }
	assert image.cpu_type == cpu_type_arm64
	assert image.entry_file_offset == 128
	assert image.segments.len == 1
	assert image.segments[0].name == '__TEXT'
	assert image.segments[0].initial_protection == 5
}

fn test_selects_arm64_slice_from_fat_container() {
	thin := synthetic_executable()
	mut fat := []u8{len: 48 + thin.len}
	put_be_u32(mut fat, 0, fat_magic)
	put_be_u32(mut fat, 4, 2)
	put_be_u32(mut fat, 8, cpu_type_x86_64)
	put_be_u32(mut fat, 16, 48)
	put_be_u32(mut fat, 20, 1)
	put_be_u32(mut fat, 28, cpu_type_arm64)
	put_be_u32(mut fat, 36, 48)
	put_be_u32(mut fat, 40, u32(thin.len))
	copy(mut fat[48..], thin)
	selected := select_architecture(fat, cpu_type_arm64) or { panic(err) }
	assert selected.len == thin.len
	assert le_u32(selected, 4) or { 0 } == cpu_type_arm64
}

fn test_rejects_out_of_bounds_segment() {
	mut data := synthetic_executable()
	put_le_u64(mut data, 80, 257)
	parse(data, cpu_type_arm64) or {
		assert err.msg().contains('outside')
		return
	}
	assert false
}

fn test_rejects_wrong_architecture() {
	data := synthetic_executable()
	parse(data, cpu_type_x86_64) or {
		assert err.msg().contains('architecture')
		return
	}
	assert false
}

fn test_rejects_modern_chained_fixups_explicitly() {
	mut data := synthetic_executable()
	put_le_u32(mut data, 104, lc_dyld_chained_fixups)
	parse(data, cpu_type_arm64) or {
		assert err.msg().contains('chained fixups')
		return
	}
	assert false
}
