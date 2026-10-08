module pager

import encoding.hex

fn test_chacha20_rfc8439_block_and_hmac_rfc4231() {
	mut key := [32]u8{}
	for i in 0 .. 32 { key[i] = u8(i) }
	mut nonce := [12]u8{}
	nonce[3] = 9
	nonce[7] = 0x4a
	mut block := [64]u8{}
	crypt(unsafe { &key }, unsafe { &nonce }, &block[0], 64)
	expected := hex.decode('10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e') or { panic(err) }
	for i in 0 .. 64 {
		assert block[i] == expected[i]
	}
	mut hkey := [32]u8{}
	for i in 0 .. 20 { hkey[i] = 0x0b }
	mut workspace := [128]u8{}
	mut tag := [32]u8{}
	authenticate(unsafe { &hkey }, c'Hi There', 8, &workspace[0], unsafe { &tag })
	hmac := hex.decode('b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7') or { panic(err) }
	for i in 0 .. 32 {
		assert tag[i] == hmac[i]
	}
	for value in workspace {
		assert value == 0
	}
}

fn test_compressor_roundtrips_native_pages_and_rejects_corruption() {
	mut input := [16384]u8{}
	mut packed := [2048]u8{}
	mut output := [16384]u8{}
	for length in [4096, 16384] {
		for mode in 0 .. 4 {
			for i in 0 .. length {
				input[i] = match mode {
					0 { u8(0) }
					1 { u8(i % 251) }
					2 { u8(i / 130) }
					else { u8((i % 500) / 7) }
				}
			}
			size := compress(&input[0], length, &packed[0], packed.len)
			assert size > 0 && size < packed.len
			assert decompress(&packed[0], size, &output[0], length)
			for i in 0 .. length {
				assert input[i] == output[i]
			}
			assert !decompress(&packed[0], size - 1, &output[0], length)
		}
	}
	mut random := u32(51)
	for i in 0 .. 16384 {
		random ^= random << 13
		random ^= random >> 17
		random ^= random << 5
		input[i] = u8(random)
	}
	assert compress(&input[0], 16384, &packed[0], packed.len) == 0
	for bad in [[u8(0x80), 0, 0], [u8(0x80), 1, 0], [u8(10), 1, 2]] {
		assert !decompress(bad.data, bad.len, &output[0], 4096)
	}
}
