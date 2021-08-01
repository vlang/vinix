module lib

pub fn bittest(bitmap voidptr, index u64) bool {
	unsafe {
		mut fbitmap := &u64(bitmap)
		bits_type := sizeof(u64) * 8
		test_index := index % bits_type
		test_sample := fbitmap[index / bits_type]
		return ((test_sample >> test_index) & u64(1)) != 0
	}
}

pub fn bitset(bitmap voidptr, index u64) {
	unsafe {
		mut fbitmap := &u64(bitmap)
		bits_type := sizeof(u64) * 8
		test_index := index % bits_type
		fbitmap[index / bits_type] |= u64(1) << test_index
	}
}

pub fn bitreset(bitmap voidptr, index u64) {
	unsafe {
		mut fbitmap := &u64(bitmap)
		bits_type := sizeof(u64) * 8
		test_index := index % bits_type
		fbitmap[index / bits_type] &= ~(u64(1) << test_index)
	}
}
