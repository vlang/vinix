module hash32

fn test_hash_encoding_and_collision_exhaustion() {
	assert primary(4, 0x40000000) == 4
	assert tag(4, 0x40000000, false) == 0x80000200
	assert tag(4, 0x40400000, true) == 0x80000241
	mut table := [entries]Pte{}
	for i in 0 .. 16 {
		address := u32(0x40000000) + u32(i) * 4096
		vsid := u32(4) ^ u32(i)
		index := slot(unsafe { &table[0] }, vsid, address)
		assert index >= 0
		assert u32(index) / 8 == if i < 8 { u32(4) } else { group_mask ^ 4 }
		table[index].tag = tag(vsid, address, i >= 8)
		assert find(unsafe { &table[0] }, vsid, address) == index
		assert slot(unsafe { &table[0] }, vsid, address) == -1
	}
	assert slot(unsafe { &table[0] }, 20, 0x40010000) == -1
	assert find(unsafe { &table[0] }, 20, 0x40010000) == -1
	// A removed secondary entry must be reusable without matching a primary
	// entry with the same abbreviated page index.
	removed := find(unsafe { &table[0] }, 12, 0x40008000)
	assert removed >= 0
	table[removed].tag = 0
	assert find(unsafe { &table[0] }, 12, 0x40008000) == -1
	assert slot(unsafe { &table[0] }, 20, 0x40010000) == removed
}
