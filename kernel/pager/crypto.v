// SPDX-License-Identifier: GPL-2.0-or-later
module pager

import krandom

@[inline]
fn rotate(value u32, amount u32) u32 {
	return (value << amount) | (value >> (32 - amount))
}

fn quarter(a &u32, b &u32, c &u32, d &u32) {
	unsafe {
		*a += *b
		*d = rotate(*d ^ *a, 16)
		*c += *d
		*b = rotate(*b ^ *c, 12)
		*a += *b
		*d = rotate(*d ^ *a, 8)
		*c += *d
		*b = rotate(*b ^ *c, 7)
	}
}

// RFC 8439 ChaCha20, counter one. Each disk write gets a distinct 96-bit
// nonce under independently generated, activation-lifetime keys.
pub fn crypt(key &[32]u8, nonce &[12]u8, data &u8, length int) {
	mut state := [16]u32{}
	state[0] = 0x61707865
	state[1] = 0x3320646e
	state[2] = 0x79622d32
	state[3] = 0x6b206574
	for i in 0 .. 8 {
		state[4 + i] = u32(key[i * 4]) | u32(key[i * 4 + 1]) << 8 |
			u32(key[i * 4 + 2]) << 16 | u32(key[i * 4 + 3]) << 24
	}
	state[12] = 1
	for i in 0 .. 3 {
		state[13 + i] = u32(nonce[i * 4]) | u32(nonce[i * 4 + 1]) << 8 |
			u32(nonce[i * 4 + 2]) << 16 | u32(nonce[i * 4 + 3]) << 24
	}
	for at := 0; at < length; at += 64 {
		mut words := state
		for _ in 0 .. 10 {
			quarter(&words[0], &words[4], &words[8], &words[12])
			quarter(&words[1], &words[5], &words[9], &words[13])
			quarter(&words[2], &words[6], &words[10], &words[14])
			quarter(&words[3], &words[7], &words[11], &words[15])
			quarter(&words[0], &words[5], &words[10], &words[15])
			quarter(&words[1], &words[6], &words[11], &words[12])
			quarter(&words[2], &words[7], &words[8], &words[13])
			quarter(&words[3], &words[4], &words[9], &words[14])
		}
		for i in 0 .. 16 { words[i] += state[i] }
		count := if length - at < 64 { length - at } else { 64 }
		for i in 0 .. count {
			unsafe { data[at + i] ^= u8(words[i / 4] >> u32((i % 4) * 8)) }
		}
		krandom.explicit_bzero(&words[0], sizeof(words))
		state[12]++
	}
	krandom.explicit_bzero(&state[0], sizeof(state))
}

// RFC 2104 HMAC-SHA256. Workspace is borrowed, length+64 bytes. Keys are
// exactly 32 bytes; tests also use zero-padded shorter RFC 4231 keys.
pub fn authenticate(key &[32]u8, data &u8, length int, workspace &u8, output &[32]u8) {
	for i in 0 .. 64 {
		unsafe { workspace[i] = (if i < 32 { key[i] } else { u8(0) }) ^ u8(0x36) }
	}
	unsafe { C.memcpy(&workspace[64], data, usize(length)) }
	mut inner := [32]u8{}
	krandom.sha256_digest(workspace, u64(length + 64), unsafe { &inner })
	mut outer := [96]u8{}
	for i in 0 .. 64 { outer[i] = (if i < 32 { key[i] } else { u8(0) }) ^ u8(0x5c) }
	unsafe { C.memcpy(&outer[64], &inner[0], 32) }
	krandom.sha256_digest(&outer[0], 96, output)
	krandom.explicit_bzero(&inner[0], sizeof(inner))
	krandom.explicit_bzero(&outer[0], sizeof(outer))
	krandom.explicit_bzero(workspace, usize(length + 64))
}

fn valid_tag(left &[32]u8, right &[32]u8) bool {
	mut difference := u8(0)
	for i in 0 .. 32 { difference |= left[i] ^ right[i] }
	return difference == 0
}
