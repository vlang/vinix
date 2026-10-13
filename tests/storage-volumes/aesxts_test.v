// SPDX-License-Identifier: GPL-2.0-or-later
module aesxts
import os
import encoding.hex
import crypto.aes

fn decode_fixed(text string, output &u8, count int) {
	bytes := hex.decode(text) or { panic(err.msg()) }; assert bytes.len == count
	unsafe { for i in 0 .. count { output[i] = bytes[i] } }
}

fn test_aes256_fips197_block_and_complete_nist_xts_prefixes_in_both_directions() {
	mut key := [32]u8{}; for i in 0 .. 32 { key[i] = u8(i) }; mut schedule := [240]u8{}; expand(&key[0], &schedule[0])
	mut plain := [16]u8{}; decode_fixed('00112233445566778899aabbccddeeff', &plain[0], 16)
	mut expected := [16]u8{}; decode_fixed('8ea2b7ca516745bfeafc49904b496089', &expected[0], 16)
	mut encrypted := plain; block(&schedule[0], mut encrypted, false); assert encrypted == expected
	block(&schedule[0], mut encrypted, true); assert encrypted == plain
	mut count := 0
	for record in os.read_file(os.dir(@FILE) + '/aesxts_vectors.rsp')!.replace('\r', '').split('\n\n') {
		mut fields := map[string]string{}
		for line in record.split_into_lines() { pair := line.split(' = '); if pair.len == 2 { fields[pair[0]] = pair[1] } }
		if 'Key' !in fields { continue }
		mut keys := [64]u8{}; decode_fixed(fields['Key'], &keys[0], 64); mut cipher := Cipher{}; assert initialize(mut cipher, unsafe { &keys })
		pt := hex.decode(fields['PT'])!; ct := hex.decode(fields['CT'])!; assert pt.len == ct.len && pt.len % 16 == 0 && pt.len <= 512
		mut data := [512]u8{}; for i in 0 .. pt.len { data[i] = pt[i] }; original := data
		unit := fields['DataUnitSeqNumber'].u64(); assert crypt(&cipher, &data[0], 512, 512, unit, false)
		for i in 0 .. ct.len { assert data[i] == ct[i], 'NIST vector ' + fields['COUNT'] }
		assert crypt(&cipher, &data[0], 512, 512, unit, true) && data == original; clear(mut cipher); assert cipher == Cipher{}; count++
	}
	assert count == 60
}

// Independent table-based library AES plus a scalar polynomial tweak oracle.
fn oracle(key []u8, data []u8, sector int, first u64, decrypt bool) []u8 {
	data_cipher := aes.new_cipher(key[..32]); tweak_cipher := aes.new_cipher(key[32..])
	mut result := data.clone()
	for at := 0; at < data.len; at += sector {
		mut number := []u8{len: 16}; unit := first + u64(at / sector)
		for i in 0 .. 8 { number[i] = u8(unit >> (8 * i)) }; mut tweak := []u8{len: 16}; tweak_cipher.encrypt(mut tweak, number)
		for offset := 0; offset < sector; offset += 16 {
			mut input := []u8{len: 16}; mut output := []u8{len: 16}; for i in 0 .. 16 { input[i] = data[at + offset + i] ^ tweak[i] }
			if decrypt { data_cipher.decrypt(mut output, input) } else { data_cipher.encrypt(mut output, input) }
			for i in 0 .. 16 { result[at + offset + i] = output[i] ^ tweak[i] }
			mut polynomial := [17]u8{}; for i in 0 .. 16 { polynomial[i] |= tweak[i] << 1; polynomial[i + 1] |= tweak[i] >> 7 }
			if polynomial[16] != 0 { polynomial[0] ^= 0x87 }; for i in 0 .. 16 { tweak[i] = polynomial[i] }
		}
	}
	return result
}

fn test_sector_units_offsets_chunking_canaries_bounds_and_rejected_initialization() {
	mut key := [64]u8{}; for i in 0 .. 64 { key[i] = u8(i * 37 + 19) }; mut cipher := Cipher{}; assert initialize(mut cipher, unsafe { &key })
	for sector in [512, 4096] { for first in [u64(0), 1, 0x1020304050607080, u64(-1) - 1] {
		mut data := [8194]u8{init: 0x91}; bytes := sector * 2
		for i in 0 .. bytes { data[i + 1] = u8(i * 13 + 7) }; original := data
		expected := oracle(key[..], data[1 .. bytes + 1], sector, first, false)
		assert crypt(&cipher, &data[1], u64(bytes), u64(sector), first, false)
		assert data[0] == 0x91 && data[bytes + 1] == 0x91; for i in 0 .. bytes { assert data[i + 1] == expected[i] }
		assert oracle(key[..], expected, sector, first, true) == original[1 .. bytes + 1]
		assert crypt(&cipher, &data[1], u64(sector), u64(sector), first, true)
		assert crypt(&cipher, &data[sector + 1], u64(sector), u64(sector), first + 1, true) && data == original
	} }
	mut bytes := [512]u8{init: 0x81}; old := bytes
	for size in [u64(1), 511, 513, 65537, u64(-1)] { assert !crypt(&cipher, &bytes[0], size, 512, 0, false) && bytes == old }
	assert !crypt(&cipher, &bytes[0], 1024, 512, u64(-1), false) && bytes == old
	assert !crypt(&cipher, unsafe { nil }, 512, 512, 0, false) && !crypt(&cipher, &bytes[0], 512, 256, 0, false)
	assert crypt(&cipher, unsafe { nil }, 0, 512, u64(-1), false)
	old_cipher := cipher; mut repeated := [64]u8{}; assert !initialize(mut cipher, unsafe { &repeated }) && cipher == old_cipher
	clear(mut cipher); assert cipher == Cipher{} && !crypt(&cipher, &bytes[0], 512, 512, 0, false)
}
