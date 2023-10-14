// string.v: Stubs for the generated V code.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module stubs

[export: 'toupper']
pub fn toupper(c int) int {
	return if c >= int(`a`) && c <= int(`z`) { c - 0x20 } else { c }
}

[export: 'memcpy']
pub fn memcpy(dest voidptr, src voidptr, size u64) voidptr {
	unsafe {
		mut destm := &u8(dest)
		srcm := &u8(src)

		for i := 0; i < size; i++ {
			destm[i] = srcm[i]
		}
	}
	return dest
}

[export: 'memset']
pub fn memset(dest voidptr, c int, size u64) voidptr {
	unsafe {
		mut destm := &u8(dest)

		for i := 0; i < size; i++ {
			destm[i] = u8(c)
		}
	}
	return dest
}

[export: 'memset64']
pub fn memset64(dest voidptr, c int, size u64) voidptr {
	unsafe {
		mut destm := &u64(dest)

		for i := 0; i < size; i++ {
			destm[i] = u64(c)
		}
	}
	return dest
}

[export: 'memmove']
pub fn memmove(dest voidptr, src voidptr, size u64) voidptr {
	unsafe {
		mut destm := &u8(dest)
		srcm := &u8(src)

		if src > dest {
			for i := 0; i < size; i++ {
				destm[i] = srcm[i]
			}
		} else if src < dest {
			for i := size; i > 0; i-- {
				destm[i - 1] = srcm[i - 1]
			}
		}

		return dest
	}
}

[export: 'memcmp']
pub fn memcmp(_s1 voidptr, _s2 voidptr, size u64) int {
	unsafe {
		s1 := &u8(_s1)
		s2 := &u8(_s2)

		for i := 0; i < size; i++ {
			if s1[i] != s2[i] {
				return if s1[i] < s2[i] { -1 } else { 1 }
			}
		}
	}
	return 0
}

[export: 'strcpy']
pub fn strcpy(dest &char, src &char) &char {
	mut i := u64(0)

	unsafe {
		mut destm := &u8(voidptr(dest))
		srcm := &u8(voidptr(src))

		for {
			if srcm[i] != 0 {
				destm[i] = srcm[i]
			} else {
				destm[i] = u8(0)
				return dest
			}

			i++
		}

		return dest
	}
}

[export: 'strncpy']
pub fn strncpy(dest &char, src &char, n u64) &char {
	mut i := u64(0)

	unsafe {
		mut destm := &u8(voidptr(dest))
		srcm := &u8(voidptr(src))

		for {
			if i >= n {
				return dest
			}

			if srcm[i] != 0 {
				destm[i] = srcm[i]
			} else {
				break
			}

			i++
		}

		for j := i; j < n; j++ {
			destm[j] = 0
		}

		return dest
	}
}

[export: 'strcmp']
pub fn strcmp(_s1 &char, _s2 &char) int {
	unsafe {
		mut i := u64(0)
		s1 := &u8(_s1)
		s2 := &u8(_s2)

		for {
			c1 := s1[i]
			c2 := s2[i]

			if c1 != c2 {
				return int(c1) - int(c2)
			}

			if c1 == 0 {
				return 0
			}

			i++
		}
	}
	return 0
}

[export: 'strncmp']
pub fn strncmp(_s1 &char, _s2 &char, size u64) int {
	unsafe {
		s1 := &u8(_s1)
		s2 := &u8(_s2)

		for i := 0; i < size; i++ {
			c1 := s1[i]
			c2 := s2[i]

			if c1 != c2 {
				return int(c1) - int(c2)
			}

			if c1 == 0 {
				return 0
			}
		}
	}
	return 0
}

[export: 'strlen']
pub fn strlen(_ptr &char) u64 {
	mut i := u64(0)

	unsafe {
		ptr := &u8(voidptr(_ptr))
		for {
			if ptr[i] == 0 {
				break
			}

			i++
		}
	}
	return i
}
