// SPDX-License-Identifier: ISC
module ath10k

import encoding.hex
import crypto.hmac
import crypto.sha1

fn test_sha1_hmac_and_pbkdf2_known_vectors() {
	abc := 'abc'.bytes()
	mut digest := sha1_new()
	digest.update(fixture_blob(abc))
	d := digest.finish()
	assert hex.encode(d[..]) == 'a9993e364706816aba3e25717850c26c9cd0d89d'
	key := []u8{len: 20, init: 0x0b}
	text := 'Hi There'.bytes()
	h := hmac_sha1(fixture_blob(key), fixture_blob(text))
	assert hex.encode(h[..]) == 'b617318655057264e28bc0b6fb378c8ef146be00'
	passphrase := 'password'.bytes()
	ssid := 'IEEE'.bytes()
	pmk := derive_pmk(fixture_blob(passphrase), fixture_blob(ssid)) or { panic('PMK failed') }
	assert hex.encode(pmk[..]) == 'f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e'
}

fn test_ptk_matches_independent_standard_library_hmac() {
	pmk := [32]u8{init: 0x17}
	sta := [u8(0), 1, 2, 3, 4, 5]!
	ap := [u8(0), 1, 2, 3, 4, 6]!
	snonce := [32]u8{init: 0x23}
	anonce := [32]u8{init: 0x31}
	ptk := derive_ptk(unsafe { &pmk }, unsafe { &sta }, unsafe { &ap }, unsafe { &snonce }, unsafe { &anonce })
	mut text := 'Pairwise key expansion\x00'.bytes()
	text << sta[..]
	text << ap[..]
	text << snonce[..]
	text << anonce[..]
	text << 0
	mut reference := []u8{}
	for i in 0 .. 3 {
		text[text.len - 1] = u8(i)
		reference << hmac.new(pmk[..], text, sha1.sum, sha1.block_size)
	}
	assert ptk[..] == reference[..48]
}

fn test_aes_fips197_and_rfc3394_key_unwrap_integrity() {
	key_bytes := hex.decode('000102030405060708090a0b0c0d0e0f') or { panic(err) }
	mut key := [16]u8{}
	for i in 0 .. 16 { key[i] = key_bytes[i] }
	aes := aes128(unsafe { &key })
	input_bytes := hex.decode('69c4e0d86a7b0430d8cdb78070b4c55a') or { panic(err) }
	mut input := [16]u8{}
	for i in 0 .. 16 { input[i] = input_bytes[i] }
	plain := aes.decrypt(unsafe { &input })
	assert hex.encode(plain[..]) == '00112233445566778899aabbccddeeff'
	mut wrapped := hex.decode('1fa68b0a8112b447aef34bd8fb5a7b829d3e862371d2cfe5') or { panic(err) }
	mut output := [16]u8{}
	length := unwrap_key(unsafe { &key }, fixture_blob(wrapped), unsafe { &output[0] }, 16) or { panic('unwrap failed') }
	assert length == 16 && hex.encode(output[..]) == '00112233445566778899aabbccddeeff'
	wrapped[0] ^= 1
	assert unwrap_key(unsafe { &key }, fixture_blob(wrapped), unsafe { &output[0] }, 16) == none
	assert output == [16]u8{}
	assert unwrap_key(unsafe { &key }, fixture_blob(wrapped), unsafe { &output[0] }, 15) == none
}
