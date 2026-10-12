// SPDX-License-Identifier: ISC
module ath10k

fn test_repeated_protocol_commands_and_crypto_keep_malloc_flat() {
	$if macos {
		hw := &FakeHardware{ complete: true }
		bytes := []u8{len: 4 * 1024 * 1024}
		mut p := fixture_protocol(hw, bytes)
		mut w := Wmi{}
		key := [16]u8{init: 0x17}
		mac := [u8(2), 3, 4, 5, 6, 7]!
		message := [32]u8{init: 0x31}
		// Warm host runtime code and allocator bookkeeping before measuring.
		_ = fixture_live_bytes()
		_ = hmac_sha1(Blob{ data: unsafe { &key[0] }, len: 16 }, Blob{ data: unsafe { &message[0] }, len: 32 })
		before := fixture_live_bytes()
		for _ in 0 .. 1000 {
			p.credits[1] = 32
			assert w.install_key(mut p, unsafe { &mac }, unsafe { &key }, 0, false, 0)
			_ = hmac_sha1(Blob{ data: unsafe { &key[0] }, len: 16 }, Blob{ data: unsafe { &message[0] }, len: 32 })
		}
		after := fixture_live_bytes()
		assert after == before
	}
}
