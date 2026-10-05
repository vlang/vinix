module stubs

// These C ABI entry points are also used by V's generated code. Keep them
// allocation-free: allocating, slicing or copying an aggregate here could
// call the very memory primitive being implemented.
// Word accesses are naturally aligned and entirely inside the requested
// range. The kernel builds with -fno-strict-aliasing for raw memory accesses.
@[export: 'memcpy']
pub fn memcpy(dest voidptr, src voidptr, n usize) voidptr {
	unsafe {
		mut d := &u8(dest)
		mut s := &u8(src)
		mut left := n
		if (usize(d) ^ usize(s)) & 7 == 0 {
			for left != 0 && usize(d) & 7 != 0 {
				*d = *s
				d++
				s++
				left--
			}
			mut dw := &u64(d)
			mut sw := &u64(s)
			for left >= 64 {
				dw[0] = sw[0]
				dw[1] = sw[1]
				dw[2] = sw[2]
				dw[3] = sw[3]
				dw[4] = sw[4]
				dw[5] = sw[5]
				dw[6] = sw[6]
				dw[7] = sw[7]
				dw += 8
				sw += 8
				left -= 64
			}
			for left >= 8 {
				*dw = *sw
				dw++
				sw++
				left -= 8
			}
			d = &u8(dw)
			s = &u8(sw)
		}
		for left != 0 {
			*d = *s
			d++
			s++
			left--
		}
	}
	return dest
}

@[export: 'memset']
pub fn memset(dest voidptr, value int, n usize) voidptr {
	unsafe {
		mut d := &u8(dest)
		mut left := n
		byte := u8(value)
		for left != 0 && usize(d) & 7 != 0 {
			*d = byte
			d++
			left--
		}
		fill := u64(byte) * u64(0x0101010101010101)
		mut dw := &u64(d)
		for left >= 64 {
			dw[0] = fill
			dw[1] = fill
			dw[2] = fill
			dw[3] = fill
			dw[4] = fill
			dw[5] = fill
			dw[6] = fill
			dw[7] = fill
			dw += 8
			left -= 64
		}
		for left >= 8 {
			*dw = fill
			dw++
			left -= 8
		}
		d = &u8(dw)
		for left != 0 {
			*d = byte
			d++
			left--
		}
	}
	return dest
}

@[export: 'memmove']
pub fn memmove(dest voidptr, src voidptr, n usize) voidptr {
	unsafe {
		mut d := &u8(dest)
		s := &u8(src)
		if usize(dest) < usize(src) {
			for i := usize(0); i < n; i++ {
				d[i] = s[i]
			}
		} else if usize(dest) > usize(src) {
			mut i := n
			for i != 0 {
				i--
				d[i] = s[i]
			}
		}
	}
	return dest
}

@[export: 'memcmp']
pub fn memcmp(first voidptr, second voidptr, n usize) int {
	unsafe {
		a := &u8(first)
		b := &u8(second)
		for i := usize(0); i < n; i++ {
			if a[i] != b[i] {
				return if a[i] < b[i] { -1 } else { 1 }
			}
		}
	}
	return 0
}

@[export: 'atoi']
pub fn atoi(text_ptr &char) int {
	unsafe {
		mut text := &u8(text_ptr)
		for *text == ` ` || *text == `\t` || *text == `\n` || *text == `\r`
			|| *text == `\f` || *text == `\v` {
			text++
		}
		negative := *text == `-`
		if negative || *text == `+` {
			text++
		}
		// Accumulate negatively so INT_MIN does not need a positive int value.
		mut value := 0
		for *text >= `0` && *text <= `9` {
			value = value * 10 - int(*text - `0`)
			text++
		}
		return if negative { value } else { -value }
	}
}
