@[translated]
module compatcore

#include "linuxkpi_v_primitives.h"

// SPDX-License-Identifier: GPL-2.0-or-later

// Linux 6.6 bitmap semantics: unused tail bits are unspecified except where
// *they affect a scalar result, or the API explicitly clears them. The native
// *implementation has no device/MM dependency and allocates only in alloc().
// *Parsing, devres, user-buffer, remapping and region APIs remain unresolved.

fn bitmap_words(nbits u32) usize {
	unsafe {
		// BITS_TO_LONGS(UINT_MAX) can overflow its unsigned rounding addition.

		return usize(nbits / u32(64) + i32(u32((nbits % u32(64) != u32(0)))))
	}
}

@[export: 'bitmap_alloc']
pub fn bitmap_alloc(nbits u32, flags u32) &u64 {
	unsafe {
		return C.kmalloc_array(bitmap_words(nbits), sizeof(u64), flags)
	}
}

@[export: 'bitmap_zalloc']
pub fn bitmap_zalloc(nbits u32, flags u32) &u64 {
	unsafe {
		return bitmap_alloc(nbits, flags | 256)
	}
}

@[export: 'bitmap_alloc_node']
pub fn bitmap_alloc_node(nbits u32, flags u32, node i32) &u64 {
	unsafe {
		// There is one native allocation domain. -1 is Linux NUMA_NO_NODE.

		if node != -1 && node != 0 {
			return nil
		}
		return bitmap_alloc(nbits, flags)
	}
}

@[export: 'bitmap_zalloc_node']
pub fn bitmap_zalloc_node(nbits u32, flags u32, node i32) &u64 {
	unsafe {
		return bitmap_alloc_node(nbits, flags | 256, node)
	}
}

@[export: 'bitmap_free']
pub fn bitmap_free(bitmap &u64) {
	unsafe {
		C.kfree(voidptr(bitmap))
	}
}

@[export: '__bitmap_equal']
pub fn bitmap_equal(a &u64, b &u64, nbits u32) bool {
	unsafe {
		full := usize(nbits / u32(64))
		for i := usize(0); i < full; i++ {
			if a[i] != b[i] {
				return false != 0
			}
		}
		return !(nbits % u32(64)) || !((a[full] ^ b[full]) & (u64(-1) >> ((-u32(nbits)) & u32(63))))
	}
}

@[export: '__bitmap_or_equal']
pub fn bitmap_or_equal(a &u64, b &u64, c &u64, nbits u32) bool {
	unsafe {
		full := usize(nbits / u32(64))
		for i := usize(0); i < full; i++ {
			if (a[i] | b[i]) != c[i] {
				return false != 0
			}
		}
		return !(nbits % u32(64)) || !(((a[full] | b[full]) ^ c[full]) & (u64(-1) >> ((-u32(nbits)) & u32(63))))
	}
}

@[export: '__bitmap_complement']
pub fn bitmap_complement(dst &u64, src &u64, nbits u32) {
	unsafe {
		i := usize(0)
		words := bitmap_words(nbits)
		for i < words {
			dst[i] = ~src[i]
			i++
		}
	}
}

@[export: '__bitmap_and']
pub fn bitmap_and(dst &u64, a &u64, b &u64, nbits u32) bool {
	unsafe {
		full := usize(nbits / u32(64))
		any := u64(0)
		for i := usize(0); i < full; i++ {
			any |= assign_word(&dst[i], u64(a[i] & b[i]))
		}
		if nbits % u32(64) {
			any |= assign_word(&dst[full], u64(a[full] & b[full] & (u64(-1) >> ((-u32(nbits)) & u32(63)))))
		}
		return any != u64(false)
	}
}

@[export: '__bitmap_andnot']
pub fn bitmap_andnot(dst &u64, a &u64, b &u64, nbits u32) bool {
	unsafe {
		full := usize(nbits / u32(64))
		any := u64(0)
		for i := usize(0); i < full; i++ {
			any |= assign_word(&dst[i], u64(a[i] & ~b[i]))
		}
		if nbits % u32(64) {
			any |= assign_word(&dst[full], u64(a[full] & ~b[full] & (u64(-1) >> ((-u32(nbits)) & u32(63)))))
		}
		return any != u64(false)
	}
}

@[export: '__bitmap_or']
pub fn bitmap_or(dst &u64, a &u64, b &u64, nbits u32) {
	unsafe {
		i := usize(0)
		words := bitmap_words(nbits)
		for i < words {
			dst[i] = a[i] | b[i]
			i++
		}
	}
}

@[export: '__bitmap_xor']
pub fn bitmap_xor(dst &u64, a &u64, b &u64, nbits u32) {
	unsafe {
		i := usize(0)
		words := bitmap_words(nbits)
		for i < words {
			dst[i] = a[i] ^ b[i]
			i++
		}
	}
}

@[export: '__bitmap_replace']
pub fn bitmap_replace(dst &u64, old &u64, new &u64, mask &u64, nbits u32) {
	unsafe {
		i := usize(0)
		words := bitmap_words(nbits)
		for i < words {
			dst[i] = (old[i] & ~mask[i]) | (new[i] & mask[i])
			i++
		}
	}
}

@[export: '__bitmap_intersects']
pub fn bitmap_intersects(a &u64, b &u64, nbits u32) bool {
	unsafe {
		full := usize(nbits / u32(64))
		for i := usize(0); i < full; i++ {
			if a[i] & b[i] {
				return true != 0
			}
		}
		return (nbits % u32(64)) && (a[full] & b[full] & (u64(-1) >> ((-u32(nbits)) & u32(63))))
	}
}

@[export: '__bitmap_subset']
pub fn bitmap_subset(a &u64, b &u64, nbits u32) bool {
	unsafe {
		full := usize(nbits / u32(64))
		for i := usize(0); i < full; i++ {
			if a[i] & ~b[i] {
				return false != 0
			}
		}
		return !(nbits % u32(64)) || !(a[full] & ~b[full] & (u64(-1) >> ((-u32(nbits)) & u32(63))))
	}
}

@[export: '__bitmap_weight']
pub fn bitmap_weight(src &u64, nbits u32) u32 {
	unsafe {
		full := usize(nbits / u32(64))
		weight := u32(0)
		for i := usize(0); i < full; i++ {
			weight += native_hweight_long(src[i])
		}
		if nbits % u32(64) {
			weight += native_hweight_long(src[full] & (u64(-1) >> ((-u32(nbits)) & u32(63))))
		}
		return weight
	}
}

@[export: '__bitmap_weight_and']
pub fn bitmap_weight_and(a &u64, b &u64, nbits u32) u32 {
	unsafe {
		full := usize(nbits / u32(64))
		weight := u32(0)
		for i := usize(0); i < full; i++ {
			weight += native_hweight_long(a[i] & b[i])
		}
		if nbits % u32(64) {
			weight += native_hweight_long(a[full] & b[full] & (u64(-1) >> ((-u32(nbits)) & u32(63))))
		}
		return weight
	}
}

@[export: '__bitmap_set']
pub fn bitmap_set(map_ &u64, start u32, len i32) {
	unsafe {
		for {
			if len < 0 || u32(len) > (u32(2147483647) * 2 + 1) - start {
				C.vinix_linuxkpi_bug(c'kernel/linuxkpi/compatcore/bitmap.v', 198)
			}
			// while()
			break
		}
		if !len {
			return
		}
		word := map_ + (start / u32(64))
		offset := start % u32(64)
		for len {
			chunk := u32(64) - offset
			if chunk > u32(len) {
				chunk = u32(len)
			}
			*word |= (u64(-1) >> ((-u32(chunk)) & u32(63))) << offset
			word += 1
			len -= chunk
			offset = u32(0)
		}
	}
}

@[export: '__bitmap_clear']
pub fn bitmap_clear(map_ &u64, start u32, len i32) {
	unsafe {
		for {
			if len < 0 || u32(len) > (u32(2147483647) * 2 + 1) - start {
				C.vinix_linuxkpi_bug(c'kernel/linuxkpi/compatcore/bitmap.v', 213)
			}
			// while()
			break
		}
		if !len {
			return
		}
		word := map_ + (start / u32(64))
		offset := start % u32(64)
		for len {
			chunk := u32(64) - offset
			if chunk > u32(len) {
				chunk = u32(len)
			}
			*word &= ~((u64(-1) >> ((-u32(chunk)) & u32(63))) << offset)
			word += 1
			len -= chunk
			offset = u32(0)
		}
	}
}

@[export: '__bitmap_shift_right']
pub fn bitmap_shift_right(dst &u64, src &u64, shift u32, nbits u32) {
	unsafe {
		words := bitmap_words(nbits)
		if !words {
			return
		}
		if shift >= nbits {
			C.memset(voidptr(dst), 0, words * sizeof(u64))
			return
		}
		off := usize(shift / u32(64))
		rem := shift % u32(64)
		tail := (u64(-1) >> ((-u32(nbits)) & u32(63)))
		// Ascending stores preserve src when dst == src.

		for i := usize(0); i < words - off; i++ {
			from := i + off
			lower := src[from]
			if from == words - usize(1) {
				lower &= tail
			}
			upper := u64(0)
			if rem && from + usize(1) < words {
				upper = src[from + usize(1)]
				if from + usize(1) == words - usize(1) {
					upper &= tail
				}
				upper <<= u32(64) - rem
			}
			dst[i] = (lower >> rem) | upper
		}
		C.memset(voidptr(dst + words - off), 0, off * sizeof(u64))
	}
}

@[export: '__bitmap_shift_left']
pub fn bitmap_shift_left(dst &u64, src &u64, shift u32, nbits u32) {
	unsafe {
		words := bitmap_words(nbits)
		if !words {
			return
		}
		if shift >= nbits {
			C.memset(voidptr(dst), 0, words * sizeof(u64))
			return
		}
		off := usize(shift / u32(64))
		rem := shift % u32(64)
		// Descending stores preserve src when dst == src. Tail is unspecified,
		//     *matching Linux's multiword left shift.

		for i := words - off; i > usize(0); i-- {
			from := i - usize(1)
			lower := if rem && from { src[from - usize(1)] >> (u32(64) - rem) } else { u64(0) }
			dst[from + off] = (src[from] << rem) | lower
		}
		C.memset(voidptr(dst), 0, off * sizeof(u64))
	}
}

@[export: 'bitmap_from_arr32']
pub fn bitmap_from_arr32(dst &u64, src &u32, nbits u32) {
	unsafe {
		halfwords := usize(nbits / u32(32) + i32(u32((nbits % u32(32) != u32(0)))))
		for i := usize(0); i < halfwords; i += usize(2) {
			value := u64(src[i])
			if i + usize(1) < halfwords {
				value |= u64(src[i + usize(1)]) << 32
			}
			dst[i / usize(2)] = value
		}
		if nbits % u32(64) {
			dst[bitmap_words(nbits) - usize(1)] &= (u64(-1) >> ((-u32(nbits)) & u32(63)))
		}
	}
}

@[export: 'bitmap_to_arr32']
pub fn bitmap_to_arr32(dst &u32, src &u64, nbits u32) {
	unsafe {
		halfwords := usize(nbits / u32(32) + i32(u32((nbits % u32(32) != u32(0)))))
		for i := usize(0); i < halfwords; i += usize(2) {
			value := src[i / usize(2)]
			dst[i] = u32(value)
			if i + usize(1) < halfwords {
				dst[i + usize(1)] = u32((value >> 32))
			}
		}
		if nbits % u32(32) {
			dst[halfwords - usize(1)] &= u32(-1) >> (u32(32) - nbits % u32(32))
		}
	}
}

// Called repeatedly by the native integration test, with the caller measuring
// *pages around the batches. Every error path releases its owned allocation.

@[export: 'vinix_linuxkpi_bitmap_runtime_selftest']
pub fn vinix_linuxkpi_bitmap_runtime_selftest() i32 {
	unsafe {
		a := [u64(-1), u64(-1), u64(-1)]!

		b := [u64(0), u64(0), ~u64(1)]!

		dst := [3]u64{}
		packed := [5]u32{}
		result := i32(-5)
		mut __c2v_condition_0 := false
		mut __c2v_condition_1 := false
		__c2v_condition_1 = i32(bitmap_intersects(&a[0], &b[0], u32(129)))
		__c2v_condition_0 = __c2v_condition_1
		if !__c2v_condition_0 {
			mut __c2v_condition_2 := false
			__c2v_condition_2 = bitmap_weight(&b[0], u32(129))
			__c2v_condition_0 = __c2v_condition_2
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_3 := false
			__c2v_condition_3 = !bitmap_subset(&b[0], &a[0], u32(129))
			__c2v_condition_0 = __c2v_condition_3
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_4 := false
			__c2v_condition_4 = i32(bitmap_and(&dst[0], &a[0], &b[0], u32(129)))
			__c2v_condition_0 = __c2v_condition_4
		}
		if __c2v_condition_0 {
			return result
		}
		if !bitmap_andnot(&dst[0], &a[0], &b[0], u32(129)) || dst[2] != u64(1) || bitmap_weight(&dst[0], u32(129)) != u32(129) {
			return result
		}
		bitmap_to_arr32(&packed[0], &a[0], u32(129))
		if packed[4] != u32(1) {
			return result
		}
		bitmap_from_arr32(&dst[0], &packed[0], u32(129))
		if dst[2] != u64(1) || !bitmap_equal(&a[0], &dst[0], u32(129)) {
			return result
		}
		bitmap_shift_right(&dst[0], &a[0], u32(128), u32(129))
		if dst[0] != u64(1) || dst[1] || dst[2] {
			return result
		}
		bitmap_shift_left(&dst[0], &dst[0], u32(128), u32(129))
		if dst[0] || dst[1] || dst[2] != u64(1) {
			return result
		}
		map_ := bitmap_zalloc(u32(4097), 3264)
		if is_null(map_) {
			return -12
		}
		if bitmap_weight(map_, u32(4097)) {
			goto out
		}
		bitmap_set(map_, u32(63), 3970)
		if bitmap_weight(map_, u32(4097)) != u32(3970) {
			goto out
		}
		bitmap_clear(map_, u32(64), 3968)
		if bitmap_weight(map_, u32(4097)) != u32(2) || !native_test_bit(u32(63), map_) || !native_test_bit(u32(4032), map_) {
			goto out
		}
		bitmap_shift_right(map_, map_, u32(63), u32(4097))
		if bitmap_weight(map_, u32(4097)) != u32(2) || !native_test_bit(u32(0), map_) || !native_test_bit(u32(3969), map_) {
			goto out
		}
		bitmap_shift_left(map_, map_, u32(63), u32(4097))
		if bitmap_weight(map_, u32(4097)) != u32(2) || !native_test_bit(u32(63), map_) || !native_test_bit(u32(4032), map_) {
			goto out
		}
		result = 0
		out:
		bitmap_free(map_)
		return result
	}
}

fn assign_word(p &u64, value u64) u64 {
	unsafe {
		*p = value
		return value
	}
}
