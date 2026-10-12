// SPDX-License-Identifier: ISC
module ath10k

import crypto.aes
import crypto.hmac
import crypto.sha1

// AP fixture uses the standard library's AES encryption and HMAC, not the
// driver's decrypt/unwrap/MIC implementation.
fn ap_wrap(key []u8, plain []u8) []u8 {
	cipher := aes.new_cipher(key) or { panic(err) }
	mut output := []u8{len: plain.len + 8}
	for i in 0 .. 8 { output[i] = 0xa6 }
	for i in 0 .. plain.len { output[8 + i] = plain[i] }
	n := plain.len / 8
	for j in 0 .. 6 {
		for i in 1 .. n + 1 {
			mut block := []u8{len: 16}
			for k in 0 .. 8 {
				block[k] = output[k]
				block[8 + k] = output[8 * i + k]
			}
			mut encrypted := []u8{len: 16}
			cipher.encrypt(mut encrypted, block)
			t := u64(n * j + i)
			for k in 0 .. 8 {
				output[k] = encrypted[k] ^ u8(t >> ((7 - k) * 8))
				output[8 * i + k] = encrypted[8 + k]
			}
		}
	}
	return output
}

fn ap_key_frame(w &Wpa, flags u16, replay u64, data []u8, active bool) []u8 {
	mut frame := []u8{len: 113 + data.len}
	for i in 0 .. 6 {
		frame[i] = w.station[i]
		frame[6 + i] = w.ap[i]
	}
	frame[12] = 0x88
	frame[13] = 0x8e
	frame[14] = 2
	frame[15] = 3
	frame[18] = 2
	put_be16(frame.data, 16, u16(95 + data.len))
	put_be16(frame.data, 19, flags)
	put_be16(frame.data, 21, 16)
	for i in 0 .. 8 { frame[23 + i] = u8(replay >> ((7 - i) * 8)) }
	for i in 0 .. 32 { frame[31 + i] = 0x31 }
	put_be16(frame.data, 111, u16(data.len))
	for i in 0 .. data.len { frame[113 + i] = data[i] }
	if flags & 0x100 != 0 {
		key := if active { w.active_ptk[..16] } else { w.ptk[..16] }
		mic := hmac.new(key, frame[14..], sha1.sum, sha1.block_size)
		for i in 0 .. 16 { frame[95 + i] = mic[i] }
	}
	return frame
}

fn test_wpa2_handshake_mic_key_confirmation_and_no_reinstallation() {
	mut w := Wpa{
		started: true
		station: [u8(2), 1, 2, 3, 4, 5]!
		ap:      [u8(2), 6, 7, 8, 9, 10]!
		snonce:  [32]u8{init: 0x23}
		pmk:     [32]u8{init: 0x17}
	}
	m1 := ap_key_frame(unsafe { &w }, 0x8a, 1, [], false)
	m2 := w.process(fixture_blob(m1)) or { panic('M1 refused') }
	assert m2.len == 135 && be16(Blob{ data: unsafe { &m2.data[0] }, len: m2.len }, 19) == 0x10a
	mut kde := []u8{}
	kde << client_rsn[..]
	kde << [u8(0xdd), 22, 0, 15, 172, 1, 1, 0]
	kde << []u8{len: 16, init: 0x42}
	kde << [u8(0xdd), 0]
	assert kde.len == 48
	wrapped := ap_wrap(w.ptk[16..32], kde)
	m3 := ap_key_frame(unsafe { &w }, 0x13ca, 2, wrapped, false)
	mut bad := m3.clone()
	bad[95] ^= 1
	assert w.process(fixture_blob(bad)) == none
	assert !w.install_pending
	reply := w.process(fixture_blob(m3)) or { panic('M3 refused') }
	assert reply.install_pairwise && reply.install_group && reply.group_index == 1
	assert w.install_pending && !w.pairwise_installed
	assert w.process(fixture_blob(m3)) == none // no M4 before target acknowledgements
	assert w.keys_installed(unsafe { &reply })
	duplicate := w.process(fixture_blob(m3)) or { panic('duplicate M3 refused') }
	assert !duplicate.install_pairwise && !duplicate.install_group && !w.install_pending
	new_counter := ap_key_frame(unsafe { &w }, 0x13ca, 3, wrapped, false)
	duplicate2 := w.process(fixture_blob(new_counter)) or { panic('M3 retry with new counter') }
	assert !duplicate2.install_pairwise && !duplicate2.install_group
	assert w.active_replay == 3
	same_nonce := ap_key_frame(unsafe { &w }, 0x8a, 4, [], false)
	assert w.process(fixture_blob(same_nonce)) == none
	group := ap_key_frame(unsafe { &w }, 0x1382, 5, wrapped, true)
	group_reply := w.process(fixture_blob(group)) or { panic('identical group key') }
	assert !group_reply.install_group && !w.install_pending
	assert w.process(fixture_blob(group)) == none
	w.clear()
	assert w.pmk == [32]u8{} && w.active_ptk == [48]u8{} && !w.started
}

fn test_rsn_rejects_tkip_only_and_required_management_protection() {
	mut rsn := client_rsn[..].clone()
	assert rsn_supported(fixture_blob(rsn))
	rsn[13] = 2
	assert !rsn_supported(fixture_blob(rsn))
	rsn[13] = 4
	rsn[20] = 0x40
	assert !rsn_supported(fixture_blob(rsn))
}
