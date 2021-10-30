module stubs

[export: 'toupper']
pub fn toupper(c int) int {
	return if c >= int(`a`) && c <= int(`z`) { c - 0x20 } else { c }
}

[export: 'memcpy']
pub fn memcpy(dest voidptr, const_src voidptr, size u64) voidptr {
	unsafe {
		mut destm := &byte(dest)
		srcm := &byte(const_src)

		for i := 0; i < size; i++ {
			destm[i] = srcm[i]
		}
	}
	return dest
}

[export: 'memset']
pub fn memset(dest voidptr, c int, size u64) voidptr {
	unsafe {
		mut destm := &byte(dest)

		for i := 0; i < size; i++ {
			destm[i] = byte(c)
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
pub fn memmove(dest &C.void, const_src &C.void, size u64) &C.void {
	unsafe {
		mut destm := &byte(dest)
		srcm := &byte(const_src)

		if const_src > dest {
			for i := 0; i < size; i++ {
				destm[i] = srcm[i]
			}
		} else if const_src < dest {
			for i := size; i > 0; i-- {
				destm[i - 1] = srcm[i - 1]
			}
		}

		return dest
	}
}

[export: 'memcmp']
pub fn memcmp(const_s1 &C.void, const_s2 &C.void, size u64) int {
	unsafe {
		s1 := &byte(const_s1)
		s2 := &byte(const_s2)

		for i := 0; i < size; i++ {
			if s1[i] != s2[i] {
				return if s1[i] < s2[i] { -1 } else { 1 }
			}
		}
	}
	return 0
}

[export: 'strcpy']
pub fn strcpy(dest &C.char, const_src &C.char) &C.char {
	mut i := u64(0)

	unsafe {
		mut destm := &byte(voidptr(dest))
		srcm := &byte(voidptr(const_src))

		for {
			if srcm[i] != 0 {
				destm[i] = srcm[i]
			} else {
				destm[i] = byte(0)
				return dest
			}

			i++
		}

		return dest
	}
}

[export: 'strncpy']
pub fn strncpy(dest &C.char, const_src &C.char, n u64) &C.char {
	mut i := u64(0)

	unsafe {
		mut destm := &byte(voidptr(dest))
		srcm := &byte(voidptr(const_src))

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
pub fn strcmp(const_s1 &C.char, const_s2 &C.char) int {
	unsafe {
		mut i := u64(0)
		s1 := &byte(const_s1)
		s2 := &byte(const_s2)

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
pub fn strncmp(const_s1 &C.char, const_s2 &C.char, size u64) int {
	unsafe {
		s1 := &byte(const_s1)
		s2 := &byte(const_s2)

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
pub fn strlen(const_ptr &C.char) u64 {
	mut i := u64(0)

	unsafe {
		ptr := &byte(voidptr(const_ptr))
		for {
			if ptr[i] == 0 {
				break
			}

			i++
		}
	}
	return i
}
