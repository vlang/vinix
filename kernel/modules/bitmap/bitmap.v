// bitmap.v: Bitmap utility.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module bitmap

import memory
import lib

pub struct GenericBitmap {
mut:
	raw_bitmap voidptr
	entry_cnt  u64
}

pub fn (mut bitmap GenericBitmap) initialise(entry_cnt u64) {
	bitmap.entry_cnt = entry_cnt
	bitmap.raw_bitmap = memory.calloc(lib.div_roundup(entry_cnt, u64(8)), 1)
}

pub fn (bitmap GenericBitmap) alloc() ?u64 {
	for i := u64(0); i < bitmap.entry_cnt; i++ {
		if lib.bittest(bitmap.raw_bitmap, i) == false {
			lib.bitset(bitmap.raw_bitmap, i)
			return i
		}
	}
	return none
}

pub fn (bitmap GenericBitmap) free_entry(index u64) {
	if index < bitmap.entry_cnt {
		lib.bitreset(bitmap.raw_bitmap, index)
	}
}
