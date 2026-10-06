@[translated]
module compatcore

#include "linuxkpi_v_primitives.h"

// SPDX-License-Identifier: GPL-2.0-only

// Kernel-string portion of Linux 6.6.157 lib/kstrtox.c. The substantive
// *conversion algorithms below are unchanged; tagged kstrtox_user supplies
// *user-memory wrappers through the separate native fault-safe copy backend.
// *Callers provide NUL-terminated kernel strings, writable results and base
// *zero or 2 through 16. Input is borrowed only for this synchronous call.

//
// *Convert integer string representation to an integer.
// *If an integer doesn't fit into specified type, -E is returned.
// * *Integer starts with optional sign.
// *kstrtou*) functions do not accept sign "-".
// * *Radix 0 means autodetection: leading "0x" implies radix 16,
// *leading "0" implies radix 8, otherwise radix is 10.
// *Autodetection hints work after optional sign, but not before.
// * *If -E is returned, result is not touched.
//

// Exact private lib/kstrtox.h overflow flag; no new public ABI.

@[export: '_parse_integer_fixup_radix']
pub fn parse_integer_fixup_radix(s &char, base &u32) &char {
	unsafe {
		if (*base) == u32(0) {
			if i32(s[0]) == i8(`0`) {
				if (i32(s[1]) | 32) == `x` && native_isxdigit(i32(s[2])) {
					*base = u32(16)
				} else {
					*base = u32(8)
				}
			} else {
				*base = u32(10)
			}
		}
		if (*base) == u32(16) && i32(s[0]) == i8(`0`) && (i32(s[1]) | 32) == `x` {
			s += 2
		}
		return s
	}
}

//
// *Convert non-negative integer string representation in explicitly given radix
// *to an integer. A maximum of max_chars characters will be converted.
// * *Return number of characters consumed maybe or-ed with overflow bit.
// *If overflow occurs, result integer (incorrect) is still returned.
// * *Don't you dare use this function.
//

@[export: '_parse_integer_limit']
pub fn parse_integer_limit(s &char, base u32, p &u64, max_chars usize) u32 {
	unsafe {
		res := u64(0)
		rv := u32(0)
		res = u64(0)
		rv = u32(0)
		for max_chars-- {
			c := u32((*s))
			lc := (c | u32(32))
			val := u32(0)
			if u32(`0`) <= c && c <= u32(`9`) {
				val = c - u32(`0`)
			} else if u32(`a`) <= lc && lc <= u32(`f`) {
				val = lc - u32(`a`) + u32(10)
			} else {
				break
			}
			if val >= base {
				break
			}
			//
			//		 *Check for overflow only if we are within range of
			//		 *it in the max base we support (16)
			//

			if res & (u64(-1) << 60) {
				if res > ((u64(-1) - u64(val)) / u64(base)) {
					rv |= (u32(1) << 31)
				}
			}
			res = res * u64(base) + u64(val)
			rv++
			s += 1
		}
		*p = res
		return rv
	}
}

@[export: '_parse_integer']
pub fn parse_integer(s &char, base u32, p &u64) u32 {
	unsafe {
		return parse_integer_limit(s, base, p, usize(2147483647))
	}
}

@[export: '_kstrtoull']
pub fn parse_unsigned(s &char, base u32, res &u64) i32 {
	unsafe {
		res_2 := u64(0)
		rv := u32(0)
		s = parse_integer_fixup_radix(s, &base)
		rv = parse_integer(s, base, &res_2)
		if rv & (u32(1) << 31) {
			return -34
		}
		if rv == u32(0) {
			return -22
		}
		s += rv
		if i32((*s)) == i8(`\n`) {
			s += 1
		}
		if *s {
			return -22
		}
		*res = res_2
		return 0
	}
}

//* *parse_unsigned - convert a string to an unsigned long long
// *@s: The start of the string. The string must be null-terminated, and may also
// * include a single newline before its terminating null. The first character
// * may also be a plus sign, but not a minus sign.
// *@base: The number base to use. The maximum supported base is 16. If base is
// * given as 0, then the base of the string is automatically detected with the
// * conventional semantics - If it begins with 0x the number will be parsed as a
// * hexadecimal (case insensitive), if it otherwise begins with 0, it will be
// * parsed as an octal number. Otherwise it will be parsed as a decimal.
// *@res: Where to write the result of the conversion on success.
// * *Returns 0 on success, -ERANGE on overflow and -EINVAL on parsing error.
// *Preferred over simple_strtoull(). Return code must be checked.
//

@[export: 'kstrtoull']
pub fn kstrtoull(s &char, base u32, res &u64) i32 {
	unsafe {
		if i32(s[0]) == i8(`+`) {
			s += 1
		}
		return parse_unsigned(s, base, res)
	}
}

//* *kstrtoll - convert a string to a long long
// *@s: The start of the string. The string must be null-terminated, and may also
// * include a single newline before its terminating null. The first character
// * may also be a plus sign or a minus sign.
// *@base: The number base to use. The maximum supported base is 16. If base is
// * given as 0, then the base of the string is automatically detected with the
// * conventional semantics - If it begins with 0x the number will be parsed as a
// * hexadecimal (case insensitive), if it otherwise begins with 0, it will be
// * parsed as an octal number. Otherwise it will be parsed as a decimal.
// *@res: Where to write the result of the conversion on success.
// * *Returns 0 on success, -ERANGE on overflow and -EINVAL on parsing error.
// *Preferred over simple_strtoll(). Return code must be checked.
//

@[export: 'kstrtoll']
pub fn kstrtoll(s &char, base u32, res &i64) i32 {
	unsafe {
		tmp := u64(0)
		rv := i32(0)
		if i32(s[0]) == i8(`-`) {
			rv = parse_unsigned(s + 1, base, &tmp)
			if rv < 0 {
				return rv
			}
			if i64(-tmp) > i64(0) {
				return -34
			}
			*res = i64(-tmp)
		} else {
			rv = kstrtoull(s, base, &tmp)
			if rv < 0 {
				return rv
			}
			if i64(tmp) < i64(0) {
				return -34
			}
			*res = i64(tmp)
		}
		return 0
	}
}

// Internal, do not use.

@[export: '_kstrtoul']
pub fn kstrtoul(s &char, base u32, res &u64) i32 {
	unsafe {
		tmp := u64(0)
		rv := i32(0)
		rv = kstrtoull(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != u64(tmp) {
			return -34
		}
		*res = tmp
		return 0
	}
}

// Internal, do not use.

@[export: '_kstrtol']
pub fn kstrtol(s &char, base u32, res &i64) i32 {
	unsafe {
		tmp := i64(0)
		rv := i32(0)
		rv = kstrtoll(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != i64(tmp) {
			return -34
		}
		*res = tmp
		return 0
	}
}

//* *kstrtouint - convert a string to an unsigned int
// *@s: The start of the string. The string must be null-terminated, and may also
// * include a single newline before its terminating null. The first character
// * may also be a plus sign, but not a minus sign.
// *@base: The number base to use. The maximum supported base is 16. If base is
// * given as 0, then the base of the string is automatically detected with the
// * conventional semantics - If it begins with 0x the number will be parsed as a
// * hexadecimal (case insensitive), if it otherwise begins with 0, it will be
// * parsed as an octal number. Otherwise it will be parsed as a decimal.
// *@res: Where to write the result of the conversion on success.
// * *Returns 0 on success, -ERANGE on overflow and -EINVAL on parsing error.
// *Preferred over simple_strtoul(). Return code must be checked.
//

@[export: 'kstrtouint']
pub fn kstrtouint(s &char, base u32, res &u32) i32 {
	unsafe {
		tmp := u64(0)
		rv := i32(0)
		rv = kstrtoull(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != u64(u32(tmp)) {
			return -34
		}
		*res = u32(tmp)
		return 0
	}
}

//* *kstrtoint - convert a string to an int
// *@s: The start of the string. The string must be null-terminated, and may also
// * include a single newline before its terminating null. The first character
// * may also be a plus sign or a minus sign.
// *@base: The number base to use. The maximum supported base is 16. If base is
// * given as 0, then the base of the string is automatically detected with the
// * conventional semantics - If it begins with 0x the number will be parsed as a
// * hexadecimal (case insensitive), if it otherwise begins with 0, it will be
// * parsed as an octal number. Otherwise it will be parsed as a decimal.
// *@res: Where to write the result of the conversion on success.
// * *Returns 0 on success, -ERANGE on overflow and -EINVAL on parsing error.
// *Preferred over simple_strtol(). Return code must be checked.
//

@[export: 'kstrtoint']
pub fn kstrtoint(s &char, base u32, res &i32) i32 {
	unsafe {
		tmp := i64(0)
		rv := i32(0)
		rv = kstrtoll(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != i64(i32(tmp)) {
			return -34
		}
		*res = i32(tmp)
		return 0
	}
}

@[export: 'kstrtou16']
pub fn kstrtou16(s &char, base u32, res &u16) i32 {
	unsafe {
		tmp := u64(0)
		rv := i32(0)
		rv = kstrtoull(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != u64(u16(tmp)) {
			return -34
		}
		*res = u16(tmp)
		return 0
	}
}

@[export: 'kstrtos16']
pub fn kstrtos16(s &char, base u32, res &i16) i32 {
	unsafe {
		tmp := i64(0)
		rv := i32(0)
		rv = kstrtoll(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != i64(i16(tmp)) {
			return -34
		}
		*res = i16(tmp)
		return 0
	}
}

@[export: 'kstrtou8']
pub fn kstrtou8(s &char, base u32, res &u8) i32 {
	unsafe {
		tmp := u64(0)
		rv := i32(0)
		rv = kstrtoull(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != u64(u8(tmp)) {
			return -34
		}
		*res = u8(tmp)
		return 0
	}
}

@[export: 'kstrtos8']
pub fn kstrtos8(s &char, base u32, res &char) i32 {
	unsafe {
		tmp := i64(0)
		rv := i32(0)
		rv = kstrtoll(s, base, &tmp)
		if rv < 0 {
			return rv
		}
		if tmp != i64(i8(tmp)) {
			return -34
		}
		*res = i8(tmp)
		return 0
	}
}

//* *kstrtobool - convert common user inputs into boolean values
// *@s: input string
// *@res: result
// * *This routine returns 0 iff the first character is one of 'YyTt1NnFf0', or
// *[oO][NnFf] for "on" and "off". Otherwise it will return -EINVAL.  Value
// *pointed to by res is updated upon finding a match.
//

@[export: 'kstrtobool']
pub fn kstrtobool(s &char, res &bool) i32 {
	unsafe {
		if is_null(s) {
			return -22
		}
		match i32(s[0]) {
			i32(`y`), i32(`Y`), i32(`t`), i32(`T`), i32(`1`) {
				*res = (1 != 0)
				return 0
			}
			i32(`n`), i32(`N`), i32(`f`), i32(`F`), i32(`0`) {
				*res = (0 != 0)
				return 0
			}
			i32(`o`), i32(`O`) {
				match i32(s[1]) {
					i32(`n`), i32(`N`) {
						*res = (1 != 0)
						return 0
					}
					i32(`f`), i32(`F`) {
						*res = (0 != 0)
						return 0
					}
					else {
					}
				}
			}
			else {
			}
		}

		return -22
	}
}
