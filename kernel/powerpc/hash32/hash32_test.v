module hash32

fn test_hash_encoding_and_collision_exhaustion() {
	assert primary(4, 0x40000000) == 4
	assert tag(4, 0x40000000, false) == 0x80000200
	assert tag(4, 0x40400000, true) == 0x80000241
	mut table := [8192]Pte{}
	for i in 0 .. 16 {
		address := u32(0x40000000) + u32(i) * 0x400000
		index := slot(unsafe { &table[0] }, 4, address)
		assert index >= 0
		assert u32(index) / 8 == if i < 8 { u32(4) } else { u32(1019) }
		table[index].tag = tag(4, address, i >= 8)
		assert find(unsafe { &table[0] }, 4, address) == index
		assert slot(unsafe { &table[0] }, 4, address) == -1
	}
	assert slot(unsafe { &table[0] }, 4, 0x44000000) == -1
	assert find(unsafe { &table[0] }, 4, 0x44000000) == -1
	// A removed secondary entry must be reusable without matching a primary
	// entry with the same abbreviated page index.
	removed := find(unsafe { &table[0] }, 4, 0x42000000)
	assert removed >= 0
	table[removed].tag = 0
	assert find(unsafe { &table[0] }, 4, 0x42000000) == -1
	assert slot(unsafe { &table[0] }, 4, 0x44000000) == removed
}
