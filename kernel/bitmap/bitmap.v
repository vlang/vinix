module bitmap

import memory
import lib

pub struct GenericBitmap {
mut:
	raw_bitmap voidptr
	entry_cnt  u64
}

pub fn (mut bmp GenericBitmap) initialise(entry_cnt u64) {
	bmp.entry_cnt = entry_cnt
	bmp.raw_bitmap = memory.calloc(lib.div_roundup(entry_cnt, u64(8)), 1)
}

pub fn (bmp GenericBitmap) alloc() ?u64 {
	for i := u64(0); i < bmp.entry_cnt; i++ {
		if lib.bittest(bmp.raw_bitmap, i) == false {
			lib.bitset(bmp.raw_bitmap, i)
			return i
		}
	}
	return none
}

pub fn (bmp GenericBitmap) free_entry(index u64) {
	if index < bmp.entry_cnt {
		lib.bitreset(bmp.raw_bitmap, index)
	}
}
