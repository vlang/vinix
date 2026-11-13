// SPDX-License-Identifier: GPL-2.0-or-later
// RFC 1320 (MD4), RFC 1321 (MD5), RFC 2104 (HMAC), MS-NLMP 3.3.2.
// Legacy algorithms are restricted to NTLMv2 interoperability. No constant-time claim.
module smb2

const md4_shift1 = [u32(3), 7, 11, 19]!
const md4_shift2 = [u32(3), 5, 9, 13]!
const md4_shift3 = [u32(3), 9, 11, 15]!
const md4_permutation = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]!

const md5_k = [u32(0xd76aa478), 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
	0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193,
	0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453,
	0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
	0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9,
	0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5,
	0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
	0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235,
	0x2ad7d2bb, 0xeb86d391]!
const md5_s = [u32(7), 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21]!

fn rol(x u32, n u32) u32 {
	return (x << n) | (x >> (32 - n))
}

struct Digest {
mut:
	s      [4]u32
	b      [64]u8
	used   int
	length u64
	md4    bool
}

fn digest_init(d &Digest, md4 bool) {
	unsafe {
		*d = Digest{
			md4: md4
			s:   [u32(0x67452301), 0xefcdab89, 0x98badcfe, 0x10325476]!
		}
	}
}

fn digest_block(d &Digest) {
	mut x := [16]u32{}
	for i in 0 .. 16 {
		x[i] = get32(unsafe { &d.b[0] }, i * 4)
	}
	mut a := d.s[0]
	mut b := d.s[1]
	mut c := d.s[2]
	mut e := d.s[3]
	if d.md4 {
		for i in 0 .. 48 {
			mut f := u32(0)
			mut k := 0
			mut shift := u32(0)
			mut add := u32(0)
			if i < 16 {
				f = (b & c) | (~b & e)
				k = i
				shift = md4_shift1[i % 4]
			} else if i < 32 {
				f = (b & c) | (b & e) | (c & e)
				k = ((i - 16) % 4) * 4 + (i - 16) / 4
				shift = md4_shift2[i % 4]
				add = 0x5a827999
			} else {
				f = b ^ c ^ e
				k = md4_permutation[i - 32]
				shift = md4_shift3[i % 4]
				add = 0x6ed9eba1
			}
			t := rol(a + f + x[k] + add, shift)
			a = e
			e = c
			c = b
			b = t
		}
	} else {
		for i in 0 .. 64 {
			mut f := u32(0)
			mut g := 0
			if i < 16 {
				f = (b & c) | (~b & e)
				g = i
			} else if i < 32 {
				f = (e & b) | (~e & c)
				g = (5 * i + 1) % 16
			} else if i < 48 {
				f = b ^ c ^ e
				g = (3 * i + 5) % 16
			} else {
				f = c ^ (b | ~e)
				g = (7 * i) % 16
			}
			t := b + rol(a + f + md5_k[i] + x[g], md5_s[(i / 16) * 4 + i % 4])
			a = e
			e = c
			c = b
			b = t
		}
	}
	unsafe {
		d.s[0] += a
		d.s[1] += b
		d.s[2] += c
		d.s[3] += e
	}
}

fn digest_update(d &Digest, p &u8, n int) {
	for i in 0 .. n {
		unsafe {
			d.b[d.used] = p[i]
			d.used++
			d.length++
		}
		if d.used == 64 {
			digest_block(d)
			unsafe {
				d.used = 0
			}
		}
	}
}

fn digest_end(d &Digest, out &u8) {
	bits := d.length * 8
	unsafe {
		d.b[d.used] = 0x80
		d.used++
	}
	if d.used > 56 {
		for i in d.used .. 64 {
			unsafe {
				d.b[i] = 0
			}
		}
		digest_block(d)
		unsafe {
			d.used = 0
		}
	}
	for i in d.used .. 56 {
		unsafe {
			d.b[i] = 0
		}
	}
	put64(unsafe { &d.b[0] }, 56, bits)
	digest_block(d)
	for i in 0 .. 4 {
		put32(out, i * 4, d.s[i])
	}
	zero(unsafe { &u8(d) }, int(sizeof(Digest)))
}

pub fn md4(p &u8, n int, out &u8) {
	mut d := Digest{}
	digest_init(unsafe { &d }, true)
	digest_update(unsafe { &d }, p, n)
	digest_end(unsafe { &d }, out)
}

pub fn md5(p &u8, n int, out &u8) {
	mut d := Digest{}
	digest_init(unsafe { &d }, false)
	digest_update(unsafe { &d }, p, n)
	digest_end(unsafe { &d }, out)
}

pub fn hmac_md5(key &u8, kn int, p &u8, n int, out &u8) {
	mut pad := [64]u8{}
	mut inner := [16]u8{}
	mut d := Digest{}
	if kn > 64 {
		md5(key, kn, unsafe { &pad[0] })
	} else {
		move(unsafe { &pad[0] }, key, kn)
	}
	for i in 0 .. 64 {
		pad[i] ^= 0x36
	}
	digest_init(unsafe { &d }, false)
	digest_update(unsafe { &d }, unsafe { &pad[0] }, 64)
	digest_update(unsafe { &d }, p, n)
	digest_end(unsafe { &d }, unsafe { &inner[0] })
	for i in 0 .. 64 {
		pad[i] ^= 0x36 ^ 0x5c
	}
	digest_init(unsafe { &d }, false)
	digest_update(unsafe { &d }, unsafe { &pad[0] }, 64)
	digest_update(unsafe { &d }, unsafe { &inner[0] }, 16)
	digest_end(unsafe { &d }, out)
	zero(unsafe { &pad[0] }, 64)
	zero(unsafe { &inner[0] }, 16)
}

pub fn rc4(key &u8, kn int, p &u8, n int, out &u8) bool {
	if kn < 1 || kn > 256 || n < 0 { return false }
	mut s := [256]u8{}
	for i in 0 .. 256 {
		s[i] = u8(i)
	}
	mut j := 0
	for i in 0 .. 256 {
		j = (j + int(s[i]) + int(unsafe { key[i % kn] })) & 255
		t := s[i]
		s[i] = s[j]
		s[j] = t
	}
	mut i := 0
	j = 0
	for k in 0 .. n {
		i = (i + 1) & 255
		j = (j + int(s[i])) & 255
		t := s[i]
		s[i] = s[j]
		s[j] = t
		unsafe {
			out[k] = p[k] ^ s[(int(s[i]) + int(s[j])) & 255]
		}
	}
	zero(unsafe { &s[0] }, 256)
	return true
}

pub fn ntlmv2_hash(user string, domain string, password string, out &u8) bool {
	mut text := [1024]u8{}
	mut hash := [16]u8{}
	defer {
		zero(unsafe { &text[0] }, 1024)
		zero(unsafe { &hash[0] }, 16)
	}
	n := utf16(password, unsafe { &text[0] }, 1024, false) or { return false }
	md4(unsafe { &text[0] }, n, unsafe { &hash[0] })
	u := utf16(user, unsafe { &text[0] }, 1024, true) or { return false }
	d := utf16(domain, unsafe { &text[u] }, 1024 - u, false) or { return false }
	hmac_md5(unsafe { &hash[0] }, 16, unsafe { &text[0] }, u + d, out)
	return true
}
