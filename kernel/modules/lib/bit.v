module lib

pub fn bittest(bitmap &u64, index u64) bool {
	bits_type := sizeof(u64) * 8
	test_index := index % bits_type
	test_sample := unsafe { bitmap[index / bits_type] }
	return ((test_sample >> test_index) & 1) != 0
}

pub fn bitset(mut bitmap &u64, index u64) {
	bits_type := sizeof(u64) * 8
	test_index := index % bits_type
	bitmap[index / bits_type] |= 1 << test_index
}

pub fn bitreset(mut bitmap &u64, index u64) {
	bits_type := sizeof(u64) * 8
	test_index := index % bits_type
	bitmap[index / bits_type] &= ~(1 << test_index)
}
