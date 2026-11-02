@[translated]
module compatcore

#include "linuxkpi_v_primitives.h"

// SPDX-License-Identifier: GPL-2.0-only

// Whitespace/matching/replacement portions from Linux 6.6.157 lib/string_helpers.c:
// *Copyright 31 August 2008 James Bottomley
// *Copyright (C) 2013, Intel Corporation
//

// Token/search portions from Linux 6.6.157 lib/string.c:
// *Copyright (C) 1991, 1992 Linus Torvalds
//

pub fn memchr(s voidptr, c i32, n uint) voidptr {
	unsafe {
		bytes := &u8(s)
		for i := uint(0); i < n; i++ {
			if i32(bytes[i]) == i32(u8(c)) {
				return voidptr((bytes + i))
			}
		}
		return nil
	}
}

pub fn memchr_inv(s voidptr, c i32, n uint) voidptr {
	unsafe {
		bytes := &u8(s)
		for i := uint(0); i < n; i++ {
			if i32(bytes[i]) != i32(u8(c)) {
				return voidptr((bytes + i))
			}
		}
		return nil
	}
}

pub fn strnlen(s &char, n uint) uint {
	unsafe {
		len := uint(0)
		for len < n && i32(s[len]) {
			len++
		}
		return uint(len)
	}
}

@[export: 'strscpy']
pub fn strscpy(dest &char, src &char, count uint) int {
	unsafe {
		if !count || count > uint(2147483647) {
			return int(-7)
		}
		for i := uint(0); i < count; i++ {
			c := src[i]
			dest[i] = c
			if !c {
				return int(int(i))
			}
		}
		dest[count - uint(1)] = i8(`\0`)
		return int(-7)
	}
}

@[export: 'strscpy_pad']
pub fn strscpy_pad(dest &char, src &char, count uint) int {
	unsafe {
		len := strscpy(dest, src, count)
		if len >= int(0) {
			C.memset(voidptr(dest + len + 1), 0, count - uint(len) - uint(1))
		}
		return int(len)
	}
}

@[export: 'kmemdup_nul']
pub fn kmemdup_nul(s &char, n uint, flags u32) &char {
	unsafe {
		if n == uint(-1) {
			return nil
		}
		copy := &char(C.kmalloc(n + uint(1), flags))
		if is_null(copy) {
			return nil
		}
		if n {
			C.memcpy(voidptr(copy), voidptr(s), n)
		}
		copy[n] = i8(`\0`)
		return copy
	}
}

@[export: 'kstrndup']
pub fn kstrndup(s &char, max uint, flags u32) &char {
	unsafe {
		return if s { kmemdup_nul(s, strnlen(s, max), flags) } else { &char(nil) }
	}
}

@[export: 'kstrdup']
pub fn kstrdup(s &char, flags u32) &char {
	unsafe {
		return kstrndup(s, uint(-1), flags)
	}
}

// Keep the original synchronous borrowed-string semantics. A newline is
// *equivalent to NUL only when it is the single trailing newline.

@[export: 'sysfs_streq']
pub fn sysfs_streq(s1 &char, s2 &char) bool {
	unsafe {
		for i32((*s1)) && i32((*s1)) == i32((*s2)) {
			s1 += 1
			s2 += 1
		}
		if i32((*s1)) == i32((*s2)) {
			return true != 0
		}
		if !(*s1) && i32((*s2)) == i8(`\n`) && !s2[1] {
			return true != 0
		}
		if i32((*s1)) == i8(`\n`) && !s1[1] && !(*s2) {
			return true != 0
		}
		return false != 0
	}
}

@[export: 'match_string']
pub fn match_string(array &&char, n uint, string_ &char) i32 {
	unsafe {
		// The explicit cast preserves Linux's usual conversion in index < n.

		for index := i32(0); uint(index) < n; index++ {
			item := array[index]
			if is_null(item) {
				break
			}
			if !C.strcmp(item, string_) {
				return index
			}
		}
		return -22
	}
}

@[export: '__sysfs_match_string']
pub fn sysfs_match_string(array &&char, n uint, str &char) i32 {
	unsafe {
		for index := i32(0); uint(index) < n; index++ {
			item := array[index]
			if is_null(item) {
				break
			}
			if sysfs_streq(item, str) {
				return index
			}
		}
		return -22
	}
}

@[export: 'strreplace']
pub fn strreplace(str &char, old char, new char) &char {
	unsafe {
		for s := str; (*s); s = s + 1 {
			if u8(*s) == u8(old) {
				*s = new
			}
		}
		return str
	}
}

pub fn strchr(s &char, c i32) &char {
	unsafe {
		for ; u8(*s) != u8(c); s = s + 1 {
			if i32((*s)) == i8(`\0`) {
				return nil
			}
		}
		return &char(s)
	}
}

pub fn strpbrk(cs &char, ct &char) &char {
	unsafe {
		sc := &char(0)
		for sc = cs; i32((*sc)) != i8(`\0`); sc = sc + 1 {
			if strchr(ct, i32(*sc)) != nil {
				return &char(sc)
			}
		}
		return nil
	}
}

pub fn strsep(s &&char, ct &char) &char {
	unsafe {
		sbegin := *s
		if uint(sbegin) == 0 { return nil }
		mut end := strpbrk(sbegin, ct)
		if uint(end) != 0 {
			*end = 0
			end += 1
		}
		*s = end
		return sbegin
	}
}

pub fn skip_spaces(str &char) &char {
	unsafe {
		for native_isspace(i32((*str))) {
			str += 1
		}
		return &char(str)
	}
}

@[export: 'strim']
pub fn strim(s &char) &char {
	unsafe {
		size := uint(0)
		end := &char(0)
		size = C.strlen(s)
		if !size {
			return s
		}
		// The pinned algorithm forms s - 1 for all-whitespace input. Keep its
		//	 *returned pointer and byte mutations while staying within the string.

		end = s + size
		for uint(end) > uint(s) && native_isspace(i32(end[-1])) {
			end += -1
		}
		*end = i8(`\0`)
		return skip_spaces(s)
	}
}

// Public Linux types retain native const qualifiers. The byte algorithms above
// consume these synchronous borrows through their existing pointer views.
@[typedef]
struct C.vks_const_char {}

@[typedef]
struct C.vks_const_void {}

@[export: 'memchr']
pub fn native_memchr(s &C.vks_const_void, c i32, n uint) voidptr {
 return unsafe { memchr(voidptr(s), c, n) }
}

@[export: 'memchr_inv']
pub fn native_memchr_inv(s &C.vks_const_void, c i32, n uint) voidptr {
 return unsafe { memchr_inv(voidptr(s), c, n) }
}

@[export: 'strnlen']
pub fn native_strnlen(s &C.vks_const_char, n uint) uint {
 return unsafe { strnlen(&char(s), n) }
}

@[export: 'strchr']
pub fn native_strchr(s &C.vks_const_char, c i32) &char {
 return unsafe { strchr(&char(s), c) }
}

@[export: 'strpbrk']
pub fn native_strpbrk(cs &C.vks_const_char, ct &C.vks_const_char) &char {
 return unsafe { strpbrk(&char(cs), &char(ct)) }
}

@[export: 'strsep']
pub fn native_strsep(s &&char, ct &C.vks_const_char) &char {
 return unsafe { strsep(s, &char(ct)) }
}

@[export: 'skip_spaces']
pub fn native_skip_spaces(s &C.vks_const_char) &char {
 return unsafe { skip_spaces(&char(s)) }
}
