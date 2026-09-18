// SPDX-License-Identifier: GPL-2.0-or-later
module krandom

// Known-answer fixtures independently computed with cryptography 46.0.4's
// ChaCha20 implementation (64-bit little-endian counter + 64-bit nonce).
// The zero-key/counter/nonce block also matches the published ChaCha20 vector.
fn test_chacha20_known_block() {
	mut rng := Generator{}
	mut words := [16]u32{}
	rng.block(mut words)
	assert words == [u32(0xade0b876), 0x903df1a0, 0xe56a5d40, 0x28bd8653,
		0xb819d2bd, 0x1aed8da0, 0xccef36a8, 0xc70d778b, 0x7c5941da, 0x8d485751,
		0x3fe02477, 0x374ad8b8, 0xf4b8436a, 0x1ca11815, 0x69b687c3, 0x8665eeb2]!
}

fn test_each_small_request_retires_its_key() {
	mut rng := Generator{}
	mut out := [1]u8{}
	rng.fill_locked(&out[0], 1)
	assert out[0] == 0x76
	// The next full block, not the exposed byte or its block, supplies the key.
	assert rng.key == [u32(0xbee7079f), 0x7a385155, 0x7c97ba98, 0x0d082d73,
		0xa0290fcb, 0x6965e348, 0x3e53c612, 0xed7aee32]!
	assert rng.nonce == [u32(0x7621b729), 0x434ee69c]!
	assert rng.counter == 0
	assert rng.output_ctr == 0

	rng.fill_locked(&out[0], 1)
	assert out[0] == 0x5f
	assert rng.key == [u32(0xbc789114), 0x19abd15c, 0x18374bf5, 0x8363d630,
		0xae72a6b4, 0x91698311, 0x0e2b345b, 0x093624c4]!
	assert rng.nonce == [u32(0x2ffbf603), 0x38ecc065]!
	assert rng.counter == 0
	assert rng.output_ctr == 0
}

fn test_empty_request_preserves_state() {
	mut rng := Generator{
		counter: 123
		output_ctr: 7
	}
	rng.key[0] = 0x12345678
	rng.nonce[0] = 0x87654321
	key := rng.key
	nonce := rng.nonce
	rng.fill_locked(unsafe { nil }, 0)
	assert rng.key == key
	assert rng.nonce == nonce
	assert rng.counter == 123
	assert rng.output_ctr == 7
}

fn test_partial_blocks_do_not_overwrite_caller_bounds() {
	for n in [1, 63, 64, 65, 127, 128, 129] {
		mut rng := Generator{ secure: true }
		mut out := []u8{len: n + 2, init: u8(0xa5)}
		rng.fill_locked(&out[1], u64(n))
		assert out[0] == 0xa5
		assert out[n + 1] == 0xa5
		assert out[1] == 0x76
		assert rng.key != [8]u32{}
		assert rng.counter == 0
		assert rng.output_ctr == 0
		assert rng.secure
		unsafe { out.free() }
	}
}

fn test_large_request_keeps_internal_rekey_limit() {
	mut exact := Generator{}
	mut out := []u8{len: 1024 * 1024 + 3, init: u8(0xa5)}
	defer { unsafe { out.free() } }
	exact.fill_locked(&out[1], 1024 * 1024)
	assert out[0] == 0xa5
	assert out[1024 * 1024 + 1] == 0xa5
	// No extra rekey when the last block already reached the internal limit.
	assert exact.key == [u32(0x70ddfd59), 0x29d29c99, 0x0a2a3497, 0x74bb0457,
		0x1b63e5f5, 0x56784aee, 0x2a479d8b, 0xa70a69cf]!
	assert exact.nonce == [u32(0xe3556f1f), 0xa4516cff]!
	assert exact.counter == 0
	assert exact.output_ctr == 0

	mut over := Generator{}
	over.fill_locked(&out[1], 1024 * 1024 + 1)
	assert out[0] == 0xa5
	assert out[1024 * 1024 + 2] == 0xa5
	assert out[1024 * 1024 + 1] == 0xc9
	assert over.key == [u32(0xffa74d21), 0x95575b93, 0x253f9b89, 0x7bede488,
		0x2f1f5d6d, 0x0d952efb, 0x691d395e, 0xe087dc97]!
	assert over.nonce == [u32(0xfd76db8a), 0xd48ed4b3]!
	assert over.counter == 0
	assert over.output_ctr == 0
}

fn test_readiness_policy_survives_rekey() {
	generator = unsafe { nil }
	mut out := [u8(0xa5)]!
	assert !fill(&out[0], 1, false)
	assert out[0] == 0xa5
	initialise()
	defer {
		unsafe { free(generator) }
		generator = unsafe { nil }
	}
	assert !is_ready()
	assert !fill(&out[0], 1, false)
	assert out[0] == 0xa5
	assert fill(&out[0], 1, true)
	assert !is_ready()
	assert generator.counter == 0
	assert generator.output_ctr == 0
	generator.secure = true
	assert is_ready()
	assert fill(&out[0], 1, false)
	assert is_ready()
	assert generator.counter == 0
}
