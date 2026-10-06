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

@[export: 'memchr']
pub fn memchr(s voidptr, c i32, n usize) voidptr {
	unsafe {
		bytes := &u8(s)
		for i := usize(0); i < n; i++ {
			if i32(bytes[i]) == i32(u8(c)) {
				return voidptr((bytes + i))
			}
		}
		return nil
	}
}

@[export: 'memchr_inv']
pub fn memchr_inv(s voidptr, c i32, n usize) voidptr {
	unsafe {
		bytes := &u8(s)
		for i := usize(0); i < n; i++ {
			if i32(bytes[i]) != i32(u8(c)) {
				return voidptr((bytes + i))
			}
		}
		return nil
	}
}

@[export: 'strnlen']
pub fn strnlen(s &char, n usize) usize {
	unsafe {
		len := usize(0)
		for len < n && i32(s[len]) {
			len++
		}
		return usize(len)
	}
}

@[export: 'strscpy']
pub fn strscpy(dest &char, src &char, count usize) isize {
	unsafe {
		if !count || count > usize(2147483647) {
			return isize(-7)
		}
		for i := usize(0); i < count; i++ {
			c := src[i]
			dest[i] = c
			if !c {
				return isize(isize(i))
			}
		}
		dest[count - usize(1)] = i8(`\0`)
		return isize(-7)
	}
}

@[export: 'strscpy_pad']
pub fn strscpy_pad(dest &char, src &char, count usize) isize {
	unsafe {
		len := strscpy(dest, src, count)
		if len >= isize(0) {
			C.memset(voidptr(dest + len + 1), 0, count - usize(len) - usize(1))
		}
		return isize(len)
	}
}

@[export: 'kmemdup_nul']
pub fn kmemdup_nul(s &char, n usize, flags u32) &char {
	unsafe {
		if n == usize(-1) {
			return nil
		}
		copy := &char(C.kmalloc(n + usize(1), flags))
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
pub fn kstrndup(s &char, max usize, flags u32) &char {
	unsafe {
		return if s { kmemdup_nul(s, strnlen(s, max), flags) } else { &char(nil) }
	}
}

@[export: 'kstrdup']
pub fn kstrdup(s &char, flags u32) &char {
	unsafe {
		return kstrndup(s, usize(-1), flags)
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
pub fn match_string(array &&char, n usize, string_ &char) i32 {
	unsafe {
		// The explicit cast preserves Linux's usual conversion in index < n.

		for index := i32(0); usize(index) < n; index++ {
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
pub fn sysfs_match_string(array &&char, n usize, str &char) i32 {
	unsafe {
		for index := i32(0); usize(index) < n; index++ {
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

@[export: 'strchr']
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

@[export: 'strpbrk']
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

@[export: 'strsep']
pub fn strsep(s &&char, ct &char) &char {
	unsafe {
		sbegin := *s
		if usize(sbegin) == 0 { return nil }
		mut end := strpbrk(sbegin, ct)
		if usize(end) != 0 {
			*end = 0
			end += 1
		}
		*s = end
		return sbegin
	}
}

@[export: 'skip_spaces']
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
		size := usize(0)
		end := &char(0)
		size = C.strlen(s)
		if !size {
			return s
		}
		// The pinned algorithm forms s - 1 for all-whitespace input. Keep its
		//	 *returned pointer and byte mutations while staying within the string.

		end = s + size
		for usize(end) > usize(s) && native_isspace(i32(end[-1])) {
			end += -1
		}
		*end = i8(`\0`)
		return skip_spaces(s)
	}
}
