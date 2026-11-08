module ramfs

fn checksum(mut bytes []u8) {
	for i in 148 .. 156 { bytes[i] = ` ` }
	mut sum := u32(0)
	for b in bytes[..512] { sum += b }
	for i := 154; i >= 148; i-- {
		bytes[i] = `0` + u8(sum & 7)
		sum >>= 3
	}
}

fn archive() []u8 {
	mut bytes := []u8{len: 2048}
	copy(mut bytes[..8], 'etc/motd'.bytes())
	copy(mut bytes[124..135], '00000000005'.bytes())
	bytes[156] = `0`
	copy(mut bytes[257..262], 'ustar'.bytes())
	copy(mut bytes[512..517], 'hello'.bytes())
	checksum(mut bytes)
	return bytes
}

fn test_valid_archive_and_every_truncation() {
	data := archive()
	mut image := Image{}
	assert parse(data.data, u32(data.len), mut image)
	assert image.count == 1 && image.files[0].size == 5
	assert image.find(c'etc/motd', 8) == 0
	assert image.find(c'etc/nope', 8) == -1
	for length in 0 .. data.len {
		assert !parse(data.data, u32(length), mut image)
	}
}

fn test_bad_checksum_overflow_and_paths() {
	mut image := Image{}
	mut bad := archive()
	bad[0] = `x`
	assert !parse(bad.data, u32(bad.len), mut image)
	for name in ['../motd', '/etc/motd', 'etc/../motd', 'etc//motd', 'etc/./motd'] {
		mut data := archive()
		for i in 0 .. 100 { data[i] = 0 }
		copy(mut data[..name.len], name.bytes())
		checksum(mut data)
		assert !parse(data.data, u32(data.len), mut image)
	}
	for value in ['77777777777', '00000002000', '00000000009'] {
		mut data := archive()
		copy(mut data[124..135], value.bytes())
		checksum(mut data)
		assert !parse(data.data, u32(data.len), mut image)
	}
}

fn test_duplicate_unsupported_entries_and_terminator() {
	mut image := Image{}
	good := archive()
	mut duplicate := good[..1024].clone()
	duplicate << good
	assert !parse(duplicate.data, u32(duplicate.len), mut image)
	for kind in [`1`, `2`, `3`, `4`, `5`, `x`, `g`] {
		mut bad := good.clone()
		bad[156] = kind
		checksum(mut bad)
		assert !parse(bad.data, u32(bad.len), mut image)
	}
	mut bad := good.clone()
	bad[2047] = 1
	assert !parse(bad.data, u32(bad.len), mut image)
	mut full := []u8{}
	for i in 0 .. 33 {
		mut entry := good[..1024].clone()
		entry[0] = `A` + u8(i)
		checksum(mut entry)
		full << entry
	}
	full << []u8{len: 1024}
	assert !parse(full.data, u32(full.len), mut image)
}
