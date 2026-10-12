// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// Fixed-storage WPA2 SHA-1/HMAC/PBKDF2 and RFC 3394 AES key unwrapping.
// No allocator, strings, secret-bearing slices, or floating point operations.
module ath10k

struct Sha1 {
mut:
	state  [5]u32
	block  [64]u8
	used   u32
	length u64
}

fn sha1_new() Sha1 {
	return Sha1{ state: [u32(0x67452301), 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0]! }
}

fn rotate(n u32, bits int) u32 { return (n << bits) | (n >> (32 - bits)) }

fn (mut s Sha1) compress() {
	mut w := [80]u32{}
	for i in 0 .. 16 {
		j := i * 4
		w[i] = u32(s.block[j]) << 24 | u32(s.block[j + 1]) << 16 | u32(s.block[j + 2]) << 8 | u32(s.block[j + 3])
	}
	for i in 16 .. 80 { w[i] = rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1) }
	mut a := s.state[0]
	mut b := s.state[1]
	mut c := s.state[2]
	mut d := s.state[3]
	mut e := s.state[4]
	for i in 0 .. 80 {
		f := if i < 20 {
			(b & c) | (~b & d)
		} else if i < 40 || i >= 60 {
			b ^ c ^ d
		} else {
			(b & c) | (b & d) | (c & d)
		}
		k := if i < 20 {
			u32(0x5a827999)
		} else if i < 40 {
			u32(0x6ed9eba1)
		} else if i < 60 {
			u32(0x8f1bbcdc)
		} else {
			u32(0xca62c1d6)
		}
		temporary := rotate(a, 5) + f + e + k + w[i]
		e = d
		d = c
		c = rotate(b, 30)
		b = a
		a = temporary
	}
	s.state[0] += a
	s.state[1] += b
	s.state[2] += c
	s.state[3] += d
	s.state[4] += e
}

fn (mut s Sha1) byte(value u8) {
	s.block[s.used] = value
	s.used++
	s.length++
	if s.used == 64 {
		s.compress()
		s.used = 0
	}
}

fn (mut s Sha1) update(data Blob) {
	for i in u32(0) .. data.len { s.byte(unsafe { data.data[i] }) }
}

fn (mut s Sha1) finish() [20]u8 {
	bits := s.length * 8
	s.byte(0x80)
	for s.used != 56 { s.byte(0) }
	for shift := 56; shift >= 0; shift -= 8 { s.byte(u8(bits >> shift)) }
	mut result := [20]u8{}
	for i in 0 .. 20 { result[i] = u8(s.state[i / 4] >> ((3 - i % 4) * 8)) }
	return result
}

fn hmac_sha1(key Blob, data Blob) [20]u8 {
	mut k := [64]u8{}
	if key.len > 64 {
		mut digest := sha1_new()
		digest.update(key)
		hash := digest.finish()
		for i in 0 .. 20 { k[i] = hash[i] }
	} else {
		for i in u32(0) .. key.len { k[i] = unsafe { key.data[i] } }
	}
	mut inner := sha1_new()
	for i in 0 .. 64 { inner.byte(k[i] ^ 0x36) }
	inner.update(data)
	inner_hash := inner.finish()
	mut outer := unsafe { &Sha1(C.__builtin_alloca(sizeof(Sha1))) }
	unsafe { *outer = sha1_new() }
	for i in 0 .. 64 { outer.byte(k[i] ^ 0x5c) }
	outer.update(Blob{ data: unsafe { &inner_hash[0] }, len: 20 })
	return outer.finish()
}

pub fn derive_pmk(passphrase Blob, ssid Blob) ?[32]u8 {
	if passphrase.len < 8 || passphrase.len > 63 || ssid.len == 0 || ssid.len > 32 { return none }
	mut result := [32]u8{}
	mut salt := [36]u8{}
	for i in u32(0) .. ssid.len { salt[i] = unsafe { ssid.data[i] } }
	for block in 1 .. 3 {
		salt[ssid.len + 3] = u8(block)
		mut value := hmac_sha1(passphrase, Blob{ data: unsafe { &salt[0] }, len: ssid.len + 4 })
		mut combined := value
		for _ in 1 .. 4096 {
			value = hmac_sha1(passphrase, Blob{ data: unsafe { &value[0] }, len: 20 })
			for i in 0 .. 20 { combined[i] ^= value[i] }
		}
		for i in 0 .. 20 {
			position := (block - 1) * 20 + i
			if position < 32 { result[position] = combined[i] }
		}
	}
	return result
}

fn blob_less(a Blob, b Blob) bool {
	for i in u32(0) .. a.len {
		x := unsafe { a.data[i] }
		y := unsafe { b.data[i] }
		if x != y { return x < y }
	}
	return false
}

pub fn derive_ptk(pmk &[32]u8, station &[6]u8, ap &[6]u8, snonce &[32]u8, anonce &[32]u8) [48]u8 {
	mut text := [100]u8{}
	label := 'Pairwise key expansion'
	for i in 0 .. label.len { text[i] = label[i] }
	sta := Blob{ data: unsafe { &station[0] }, len: 6 }
	bss := Blob{ data: unsafe { &ap[0] }, len: 6 }
	sta_first := blob_less(sta, bss)
	s := Blob{ data: unsafe { &snonce[0] }, len: 32 }
	a := Blob{ data: unsafe { &anonce[0] }, len: 32 }
	s_first := blob_less(s, a)
	for i in 0 .. 6 {
		text[23 + i] = unsafe { if sta_first { station[i] } else { ap[i] } }
		text[29 + i] = unsafe { if sta_first { ap[i] } else { station[i] } }
	}
	for i in 0 .. 32 {
		text[35 + i] = unsafe { if s_first { snonce[i] } else { anonce[i] } }
		text[67 + i] = unsafe { if s_first { anonce[i] } else { snonce[i] } }
	}
	mut ptk := [48]u8{}
	for block in 0 .. 3 {
		text[99] = u8(block)
		digest := hmac_sha1(Blob{ data: unsafe { &pmk[0] }, len: 32 }, Blob{ data: unsafe { &text[0] }, len: 100 })
		for i in 0 .. 20 { if block * 20 + i < 48 { ptk[block * 20 + i] = digest[i] } }
	}
	return ptk
}

fn gf_multiply(a u8, b u8) u8 {
	mut x := a
	mut y := b
	mut product := u8(0)
	for _ in 0 .. 8 {
		if y & 1 != 0 { product ^= x }
		high := x & 0x80
		x <<= 1
		if high != 0 { x ^= 0x1b }
		y >>= 1
	}
	return product
}

fn aes_substitute(value u8) u8 {
	mut inv := u8(0)
	if value != 0 {
		inv = 1
		mut base := value
		mut exponent := 254
		for exponent != 0 {
			if exponent & 1 != 0 { inv = gf_multiply(inv, base) }
			base = gf_multiply(base, base)
			exponent >>= 1
		}
	}
	mut result := inv ^ 0x63
	for shift in 1 .. 5 { result ^= (inv << shift) | (inv >> (8 - shift)) }
	return result
}

struct Aes128 {
mut:
	keys    [176]u8
	inverse [256]u8
}

fn aes128(key &[16]u8) Aes128 {
	mut aes := Aes128{}
	for i in 0 .. 16 { aes.keys[i] = unsafe { key[i] } }
	for i in 0 .. 256 { aes.inverse[aes_substitute(u8(i))] = u8(i) }
	mut rcon := u8(1)
	for position := 16; position < 176; position += 4 {
		mut temp := [aes.keys[position - 4], aes.keys[position - 3], aes.keys[position - 2],
			aes.keys[position - 1]]!
		if position % 16 == 0 {
			temp = [aes_substitute(temp[1]) ^ rcon, aes_substitute(temp[2]), aes_substitute(temp[3]),
				aes_substitute(temp[0])]!
			rcon = gf_multiply(rcon, 2)
		}
		for i in 0 .. 4 { aes.keys[position + i] = aes.keys[position + i - 16] ^ temp[i] }
	}
	return aes
}

fn (a &Aes128) decrypt(input &[16]u8) [16]u8 {
	mut state := [16]u8{}
	for i in 0 .. 16 { state[i] = unsafe { input[i] } ^ a.keys[160 + i] }
	for round := 9; round >= 0; round-- {
		previous := state
		for column in 0 .. 4 {
			for row in 0 .. 4 {
				state[column * 4 + row] = a.inverse[previous[((column - row + 4) % 4) * 4 + row]]
			}
		}
		for i in 0 .. 16 { state[i] ^= a.keys[round * 16 + i] }
		if round != 0 {
			for column in 0 .. 4 {
				i := column * 4
				x := [state[i], state[i + 1], state[i + 2], state[i + 3]]!
				state[i] = gf_multiply(x[0], 14) ^ gf_multiply(x[1], 11) ^ gf_multiply(x[2], 13) ^ gf_multiply(x[3], 9)
				state[i + 1] = gf_multiply(x[0], 9) ^ gf_multiply(x[1], 14) ^ gf_multiply(x[2], 11) ^ gf_multiply(x[3], 13)
				state[i + 2] = gf_multiply(x[0], 13) ^ gf_multiply(x[1], 9) ^ gf_multiply(x[2], 14) ^ gf_multiply(x[3], 11)
				state[i + 3] = gf_multiply(x[0], 11) ^ gf_multiply(x[1], 13) ^ gf_multiply(x[2], 9) ^ gf_multiply(x[3], 14)
			}
		}
	}
	return state
}

pub fn unwrap_key(kek &[16]u8, wrapped Blob, output &u8, capacity u32) ?u32 {
	if wrapped.len < 24 || wrapped.len % 8 != 0 || wrapped.len - 8 > capacity || wrapped.len > 512 {
		return none
	}
	n := (wrapped.len / 8) - 1
	mut a := [8]u8{}
	for i in 0 .. 8 { a[i] = unsafe { wrapped.data[i] } }
	for i in u32(0) .. wrapped.len - 8 {
		unsafe { output[i] = wrapped.data[8 + i] }
	}
	aes := aes128(kek)
	for round := 5; round >= 0; round-- {
		for i := n; i > 0; i-- {
			counter := u64(n) * u64(round) + i
			mut input := [16]u8{}
			for j in 0 .. 8 {
				input[j] = a[j] ^ u8(counter >> ((7 - j) * 8))
				input[8 + j] = unsafe { output[(i - 1) * 8 + u32(j)] }
			}
			value := aes.decrypt(unsafe { &input })
			for j in 0 .. 8 {
				a[j] = value[j]
				unsafe { output[(i - 1) * 8 + u32(j)] = value[8 + j] }
			}
		}
	}
	mut difference := u8(0)
	for byte in a { difference |= byte ^ 0xa6 }
	if difference != 0 {
		for i in u32(0) .. wrapped.len - 8 {
			unsafe { output[i] = 0 }
		}
		return none
	}
	return wrapped.len - 8
}
