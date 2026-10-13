// SPDX-License-Identifier: GPL-2.0-or-later
module aesxts

fn C.__builtin_alloca(usize) voidptr

// AES-256-XTS with full 512/4096-byte storage data units. State and all
// workspaces are caller-owned. No secret-indexed tables or secret branches.
pub struct Cipher {
mut:
	data [240]u8
	tweak [240]u8
	ready bool
}

struct SecretByte {
mut:
	volatile value u8
}

struct Workspace {
mut:
	state [16]u8
	tweak [16]u8
}

// Volatile byte stores survive dead-store elimination, including on failure.
pub fn erase(buffer voidptr, bytes usize) {
	for i := usize(0); i < bytes; i++ { unsafe { (&SecretByte(usize(buffer) + i)).value = 0 } }
}

pub fn clear(mut cipher Cipher) { erase(unsafe { &cipher }, sizeof(Cipher)) }

@[inline]
fn xtime(value u8) u8 { return (value << 1) ^ (u8(0x1b) & (u8(0) - (value >> 7))) }

@[inline]
fn multiply(a u8, b u8) u8 {
	mut x := a; mut y := b; mut result := u8(0)
	for _ in 0 .. 8 { result ^= x & (u8(0) - (y & 1)); x = xtime(x); y >>= 1 }
	return result
}

// Fixed addition chain for x^254 in GF(2^8); zero maps to zero too.
@[inline]
fn inverse(value u8) u8 {
	x2 := multiply(value, value); x4 := multiply(x2, x2); x8 := multiply(x4, x4)
	x16 := multiply(x8, x8); x32 := multiply(x16, x16); x64 := multiply(x32, x32); x128 := multiply(x64, x64)
	return multiply(multiply(multiply(x2, x4), multiply(x8, x16)), multiply(multiply(x32, x64), x128))
}

@[inline]
fn rotate(value u8, bits u8) u8 { return (value << bits) | (value >> (8 - bits)) }

@[inline]
fn substitute(value u8) u8 {
	x := inverse(value)
	return x ^ rotate(x, 1) ^ rotate(x, 2) ^ rotate(x, 3) ^ rotate(x, 4) ^ 0x63
}

// Sixteen lanes share each finite-field operation. Every lane's polynomial
// reduction follows the AES modulus x^8 + x^4 + x^3 + x + 1.
@[direct_array_access]
fn multiply_lanes(a &u32, b &u32, output &u32) {
	mut product := [15]u32{}; defer { erase(unsafe { &product[0] }, sizeof(product)) }
	unsafe { for i in 0 .. 8 { for j in 0 .. 8 { product[i + j] ^= a[i] & b[j] } } }
	for i := 14; i >= 8; i-- { carry := product[i]; product[i - 8] ^= carry; product[i - 7] ^= carry; product[i - 5] ^= carry; product[i - 4] ^= carry }
	unsafe { for i in 0 .. 8 { output[i] = product[i] } }
}

@[direct_array_access]
fn sub_bytes(mut state [16]u8, decrypt bool) {
	mut lanes := [8]u32{}; mut powers := [8][8]u32{}; mut result := [8]u32{}; mut transformed := [8]u32{}
	defer { erase(unsafe { &lanes[0] }, sizeof(lanes)); erase(unsafe { &powers[0] }, sizeof(powers)); erase(unsafe { &result[0] }, sizeof(result)); erase(unsafe { &transformed[0] }, sizeof(transformed)) }
	for bit in 0 .. 8 { for lane in 0 .. 16 { lanes[bit] |= u32((state[lane] >> bit) & 1) << lane } }
	if decrypt { for bit in 0 .. 8 { transformed[bit] = lanes[(bit + 7) & 7] ^ lanes[(bit + 5) & 7] ^ lanes[(bit + 2) & 7] ^ ((u32(0) - u32((0x05 >> bit) & 1)) & 0xffff) }; lanes = transformed }
	powers[0] = lanes; for power in 1 .. 8 { multiply_lanes(unsafe { &powers[power - 1][0] }, unsafe { &powers[power - 1][0] }, unsafe { &powers[power][0] }) }
	result = powers[1]; for power in 2 .. 8 { multiply_lanes(unsafe { &result[0] }, unsafe { &powers[power][0] }, unsafe { &result[0] }) }
	if !decrypt { for bit in 0 .. 8 { transformed[bit] = result[bit] ^ result[(bit + 7) & 7] ^ result[(bit + 6) & 7] ^ result[(bit + 5) & 7] ^ result[(bit + 4) & 7] ^ ((u32(0) - u32((0x63 >> bit) & 1)) & 0xffff) }; result = transformed }
	for lane in 0 .. 16 { state[lane] = 0; for bit in 0 .. 8 { state[lane] |= u8((result[bit] >> lane) & 1) << bit } }
}

@[direct_array_access]
fn expand(key &u8, schedule &u8) {
	unsafe { for i in 0 .. 32 { schedule[i] = key[i] } }
	mut rcon := u8(1); mut word := [4]u8{}; defer { erase(&word[0], sizeof(word)) }
	for at := 32; at < 240; at += 4 {
		unsafe { for i in 0 .. 4 { word[i] = schedule[at - 4 + i] } }
		if at % 32 == 0 {
			first := word[0]; word[0] = substitute(word[1]) ^ rcon; word[1] = substitute(word[2])
			word[2] = substitute(word[3]); word[3] = substitute(first); rcon = xtime(rcon)
		} else if at % 32 == 16 { for i in 0 .. 4 { word[i] = substitute(word[i]) } }
		unsafe { for i in 0 .. 4 { schedule[at + i] = schedule[at + i - 32] ^ word[i] } }
	}
}

// Both key halves must be independent AES-256 keys. Invalid initialization
// preserves the caller; callers erase rejected key material explicitly.
@[direct_array_access]
pub fn initialize(mut cipher Cipher, key &[64]u8) bool {
	mut difference := u8(0); unsafe { for i in 0 .. 32 { difference |= key[i] ^ key[i + 32] } }
	if difference == 0 { return false }
	expand(unsafe { &key[0] }, &cipher.data[0]); expand(unsafe { &key[32] }, &cipher.tweak[0]); cipher.ready = true
	return true
}

@[direct_array_access]
fn add_key(mut state [16]u8, schedule &u8, round int) {
	unsafe { for i in 0 .. 16 { state[i] ^= schedule[round * 16 + i] } }
}

@[direct_array_access]
fn shift(mut state [16]u8, decrypt bool) {
	mut previous := state; defer { erase(&previous[0], sizeof(previous)) }
	for row in 0 .. 4 { for column in 0 .. 4 {
		from := if decrypt { (column + 4 - row) & 3 } else { (column + row) & 3 }
		state[column * 4 + row] = previous[from * 4 + row]
	} }
}

@[direct_array_access]
fn mix(mut state [16]u8, decrypt bool) {
	for column in 0 .. 4 {
		at := column * 4
		if decrypt {
			u := xtime(xtime(state[at] ^ state[at + 2])); v := xtime(xtime(state[at + 1] ^ state[at + 3]))
			state[at] ^= u; state[at + 2] ^= u; state[at + 1] ^= v; state[at + 3] ^= v
		}
		a := state[at]; b := state[at + 1]; c := state[at + 2]; d := state[at + 3]; all := a ^ b ^ c ^ d
		state[at] = a ^ all ^ xtime(a ^ b); state[at + 1] = b ^ all ^ xtime(b ^ c)
		state[at + 2] = c ^ all ^ xtime(c ^ d); state[at + 3] = d ^ all ^ xtime(d ^ a)
	}
}

@[direct_array_access]
fn block(schedule &u8, mut state [16]u8, decrypt bool) {
	add_key(mut state, schedule, if decrypt { 14 } else { 0 })
	for step in 1 .. 15 {
		if decrypt {
			shift(mut state, true); sub_bytes(mut state, true)
			add_key(mut state, schedule, 14 - step); if step != 14 { mix(mut state, true) }
		} else {
			sub_bytes(mut state, false); shift(mut state, false)
			if step != 14 { mix(mut state, false) }; add_key(mut state, schedule, step)
		}
	}
}

@[direct_array_access]
fn advance(mut tweak [16]u8) {
	mut carry := u8(0)
	for i in 0 .. 16 { next := tweak[i] >> 7; tweak[i] = (tweak[i] << 1) | carry; carry = next }
	tweak[0] ^= u8(0x87) & (u8(0) - carry)
}

// In-place, complete native-sector units, with little-endian 64-bit unit
// numbers in a zero-extended 128-bit tweak. Bounds reject before mutation.
@[direct_array_access]
pub fn crypt(cipher &Cipher, data &u8, bytes u64, sector u64, first u64, decrypt bool) bool {
	if !cipher.ready || (sector != 512 && sector != 4096) || bytes % sector != 0
		|| bytes > 65536 || (bytes != 0 && data == unsafe { nil })
		|| (bytes != 0 && bytes / sector - 1 > u64(-1) - first) { return false }
	mut workspace := unsafe { &Workspace(C.__builtin_alloca(sizeof(Workspace))) }; unsafe { *workspace = Workspace{} }
	defer { erase(workspace, sizeof(Workspace)) }
	for at := u64(0); at < bytes; at += sector {
		unit := first + at / sector; workspace.tweak = [16]u8{}
		for i in 0 .. 8 { workspace.tweak[i] = u8(unit >> (i * 8)) }; block(unsafe { &cipher.tweak[0] }, mut workspace.tweak, false)
		for offset := u64(0); offset < sector; offset += 16 {
			unsafe { for i in 0 .. 16 { workspace.state[i] = data[at + offset + u64(i)] ^ workspace.tweak[i] } }
			block(unsafe { &cipher.data[0] }, mut workspace.state, decrypt)
			unsafe { for i in 0 .. 16 { data[at + offset + u64(i)] = workspace.state[i] ^ workspace.tweak[i] } }; advance(mut workspace.tweak)
		}
	}
	return true
}
