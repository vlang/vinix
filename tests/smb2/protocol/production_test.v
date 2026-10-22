// SPDX-License-Identifier: GPL-2.0-or-later
module smb2

import encoding.hex
import crypto.hmac
import crypto.sha256
import crypto.md5 as md5_std

fn expect(p &u8, n int, value string) {
	want := hex.decode(value) or { panic(err) }
	assert want.len == n
	for i in 0 .. n {
		assert unsafe { p[i] } == want[i], 'vector mismatch at ${i}'
	}
}

fn test_rfc1320_md4() {
	mut out := [16]u8{}
	md4(c'', 0, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, '31d6cfe0d16ae931b73c59d7e0c089c0')
	md4(c'a', 1, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, 'bde52cb31de33e46245e05fbdbd6fb24')
	md4(c'abc', 3, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, 'a448017aaf21d8525fc10ae87aa6729d')
	md4(c'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 62, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, '043f8582f241db351ce627e153e7f0e4')
}

fn test_rfc1321_md5_and_rfc2202_hmac() {
	mut out := [16]u8{}
	md5(c'', 0, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, 'd41d8cd98f00b204e9800998ecf8427e')
	md5(c'abc', 3, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, '900150983cd24fb0d6963f7d28e17f72')
	mut key := [16]u8{}
	for i in 0 .. 16 {
		key[i] = 0x0b
	}
	hmac_md5(unsafe { &key[0] }, 16, c'Hi There', 8, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, '9294727a3638bb1c13f48ef8158bfc9d')
	hmac_md5(c'Jefe', 4, c'what do ya want for nothing?', 28, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, '750c783e6ab0b503eaa86e310a5db738')
}

fn test_rc4_rfc6229() {
	key := [u8(1), 2, 3, 4, 5]!
	mut input := [32]u8{}
	mut out := [32]u8{}
	assert rc4(unsafe { &key[0] }, 5, unsafe { &input[0] }, 32, unsafe { &out[0] })
	expect(unsafe { &out[0] }, 32,
		'b2396305f03dc027ccc3524a0a1118a86982944f18fc82d589c403a47a0d0919')
	assert !rc4(unsafe { &key[0] }, 0, unsafe { &input[0] }, 32, unsafe { &out[0] })
}

fn test_ms_nlmp_response_key_vector() {
	mut out := [16]u8{}
	assert ntlmv2_hash('User', 'Domain', 'Password', unsafe { &out[0] })
	expect(unsafe { &out[0] }, 16, '0c868a403bfd7a93a3001ef22ef02e3f')
}

fn test_ms_nlmp_published_ntlmv2_response() {
	// MS-NLMP 4.2.4.3 Messages, User / Domain / Password, zero FILETIME.
	// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nlmp/bc612491-fb0b-4829-91bc-7c6b95ff67fe
	raw := hex.decode('4e544c4d53535000020000000c000c003800000033828ae20123456789abcdef00000000000000002400240044000000060070170000000f53006500720076006500720002000c0044006f006d00610069006e0001000c0053006500720076006500720000000000') or {
		panic(err)
	}
	mut c := Challenge{}
	assert parse_challenge(raw.data, raw.len, unsafe { &c })
	nonce := [u8(0xaa), 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa]!
	mut out := [4096]u8{}
	mut key := [16]u8{}
	n := ntlm_authenticate(unsafe { &c }, raw.data, raw.len, 'User', 'Domain', 'Password', false,
		unsafe { &nonce[0] }, 0, unsafe { &out[0] }, 4096, unsafe { &key[0] }) or {
		panic('authenticate')
	}
	nt_at, nt_len := security_buffer(unsafe { &out[0] }, n, 20) or { panic('security buffer') }
	assert nt_len == 84
	expect(unsafe { &out[nt_at] }, 84,
		'68cd0ab851e51c96aabc927bebef6a1c01010000000000000000000000000000aaaaaaaaaaaaaaaa0000000002000c0044006f006d00610069006e0001000c005300650072007600650072000000000000000000')
	lm_at, lm_len := security_buffer(unsafe { &out[0] }, n, 12) or { panic('lm buffer') }
	assert lm_len == 24
	expect(unsafe { &out[lm_at] }, 24, '86c35097ac9cec102554764a57cccc19aaaaaaaaaaaaaaaa')
}

fn test_spnego_der_rejects_scanning_and_bad_lengths() {
	mut p := [256]u8{}
	raw := ntlm_negotiate(unsafe { &p[0] })
	n := spnego_response(unsafe { &p[0] }, raw, 256) or { panic('wrap') }
	at, len := spnego_token(unsafe { &p[0] }, n) or { panic('DER') }
	assert len == 40 && get32(unsafe { &p[0] }, at + 8) == 1
	for truncated in 0 .. n {
		if _, _ := spnego_token(unsafe { &p[0] }, truncated) { assert false
		 }
	}
	if _, _ := spnego_token(unsafe { &p[0] }, n + 1) { assert false
	 }
	p[1] = 0x80
	if _, _ := spnego_token(unsafe { &p[0] }, n) { assert false
	 }
	zero(unsafe { &p[0] }, 256)
	ntlm_negotiate(unsafe { &p[20] })
	if _, _ := spnego_token(unsafe { &p[0] }, 60) { assert false
	 }
}

fn test_production_header_signature_matches_sha256_hmac() {
	mut tx := [capacity]u8{}
	mut scratch := [capacity + 64]u8{}
	mut signature := [16]u8{}
	mut c := Client{
		tx:      unsafe { &tx[0] }
		scratch: unsafe { &scratch[0] }
	}
	for i in 0 .. 16 {
		c.key[i] = u8(i)
	}
	c.header(8, 49)
	c.signature(c.tx, 113, unsafe { &signature[0] })
	expected := hmac.new(c.key[..], tx[..113], sha256.sum, 64)
	for i in 0 .. 16 {
		assert signature[i] == expected[i]
	}
}

fn test_challenge_parser_malformed() {
	mut p := [128]u8{}
	mut c := Challenge{}
	move(unsafe { &p[0] }, c'NTLMSSP\x00', 8)
	put32(unsafe { &p[0] }, 8, 2)
	put32(unsafe { &p[0] }, 20, ntlm_flags & ~u32(0x02000000))
	secbuf(unsafe { &p[0] }, 40, 48, 4)
	assert parse_challenge(unsafe { &p[0] }, 52, unsafe { &c })
	secbuf(unsafe { &p[0] }, 12, 127, 2)
	assert !parse_challenge(unsafe { &p[0] }, 52, unsafe { &c })
	secbuf(unsafe { &p[0] }, 12, 0, 0)
	for n in 0 .. 52 {
		assert !parse_challenge(unsafe { &p[0] }, n, unsafe { &c })
	}
	put32(unsafe { &p[0] }, 44, 0xffffffff)
	assert !parse_challenge(unsafe { &p[0] }, 52, unsafe { &c })
	secbuf(unsafe { &p[0] }, 40, 48, 4)
	put16(unsafe { &p[0] }, 50, 65535)
	assert !parse_challenge(unsafe { &p[0] }, 52, unsafe { &c })
	put16(unsafe { &p[0] }, 50, 0)
	put16(unsafe { &p[0] }, 48, 7)
	assert !parse_challenge(unsafe { &p[0] }, 52, unsafe { &c })
}

fn test_timestamp_mic_av_flag_and_zero_version_slot() {
	mut raw := [64]u8{}
	p := unsafe { &raw[0] }
	move(p, c'NTLMSSP\x00', 8)
	put32(p, 8, 2)
	put32(p, 20, ntlm_flags & ~u32(0x02000000))
	secbuf(p, 40, 48, 16)
	put16(p, 48, 7)
	put16(p, 50, 8)
	put64(p, 52, 123456)
	mut challenge := Challenge{}
	assert parse_challenge(p, 64, unsafe { &challenge })
	mut nonce := [8]u8{}
	mut out := [4096]u8{}
	mut key := [16]u8{}
	n := ntlm_authenticate(unsafe { &challenge }, p, 64, 'User', 'Domain', 'Password', false,
		unsafe { &nonce[0] }, 0, unsafe { &out[0] }, 4096, unsafe { &key[0] }) or {
		panic('MIC authenticate')
	}
	assert get64(unsafe { &out[0] }, 64) == 0
	nt_at, _ := security_buffer(unsafe { &out[0] }, n, 20) or { panic('NT response') }
	assert get16(unsafe { &out[0] }, nt_at + 56) == 6
		&& get32(unsafe { &out[0] }, nt_at + 60) & 2 != 0
	mut received := [16]u8{}
	move(unsafe { &received[0] }, unsafe { &out[72] }, 16)
	zero(unsafe { &out[72] }, 16)
	mut nego := [40]u8{}
	ntlm_negotiate(unsafe { &nego[0] })
	mut transcript := []u8{}
	transcript << nego[..]
	transcript << raw[..]
	transcript << out[..n]
	expected := hmac.new(key[..], transcript, crypto_md5, 64)
	for i in 0 .. 16 {
		assert expected[i] == received[i]
	}
}

fn crypto_md5(data []u8) []u8 {
	mut result := []u8{len: 16}
	md5(data.data, data.len, result.data)
	return result
}

fn test_directory_parser_malformed_and_external_layout() {
	// Independently specified FILE_ID_BOTH_DIR_INFORMATION layout (MS-FSCC 2.4.17).
	mut p := [120]u8{}
	mut e := DirEntry{}
	put64(unsafe { &p[0] }, 40, 123)
	put32(unsafe { &p[0] }, 56, 0x20)
	put32(unsafe { &p[0] }, 60, 6)
	put64(unsafe { &p[0] }, 96, 0x1234)
	put16(unsafe { &p[0] }, 104, u16(`a`))
	put16(unsafe { &p[0] }, 106, u16(`b`))
	put16(unsafe { &p[0] }, 108, u16(`c`))
	assert parse_entry(unsafe { &p[0] }, 110, unsafe { &e })
	assert e.length == 3 && e.attr.size == 123 && e.attr.ino == 0x1234
	for n in 0 .. 110 {
		assert !parse_entry(unsafe { &p[0] }, n, unsafe { &e })
	}
	put32(unsafe { &p[0] }, 0, 104)
	assert !parse_entry(unsafe { &p[0] }, 110, unsafe { &e })
	put32(unsafe { &p[0] }, 0, 0xffffffff)
	assert !parse_entry(unsafe { &p[0] }, 110, unsafe { &e })
	put32(unsafe { &p[0] }, 0, 0)
	put32(unsafe { &p[0] }, 60, 0xfffffffe)
	assert !parse_entry(unsafe { &p[0] }, 110, unsafe { &e })
	put32(unsafe { &p[0] }, 60, 6)
	put16(unsafe { &p[0] }, 104, u16(`/`))
	assert !parse_entry(unsafe { &p[0] }, 110, unsafe { &e })
}

fn test_options_source_and_utf16_limits() {
	mut o := Options{}
	mut address := u32(0)
	mut share := ''
	mut host := ''
	assert parse_options('domain=Domain,user=User,password=Password,ro', unsafe { &o }) && o.ro
	assert !parse_options('user=x,password=x,password=y', unsafe { &o })
	assert !parse_options('guest,guest', unsafe { &o })
	assert !parse_options('sec=krb5', unsafe { &o })
	assert parse_source('//192.168.1.4/share', unsafe { &address }, unsafe { &share },
		unsafe { &host })
	assert address == 0x0401a8c0 && share == 'share'
	assert !parse_source('//256.1.1.1/share', unsafe { &address }, unsafe { &share },
		unsafe { &host })
	assert !parse_source('//1.1.1.1/share/path', unsafe { &address }, unsafe { &share },
		unsafe { &host })
	mut buf := [8]u8{}
	assert utf16('😀', unsafe { &buf[0] }, 4, false) or { -1 } == 4
	assert (utf16('abc', unsafe { &buf[0] }, 5, false) or { -1 }) == -1
	assert !span(100, 99, 2) && !span(100, -1, 1) && !span(100, 1, -1)
}

struct Fake {
mut:
	frame    [512]u8
	length   int
	position int
	mic_sent bool
}

fn fake_transfer(ctx voidptr, p &u8, n int, sending bool) bool {
	mut f := unsafe { &Fake(ctx) }
	if sending {
		assert n >= 68 && unsafe { p[0] } == 0
		assert (int(unsafe { p[1] }) << 16 | int(unsafe { p[2] }) << 8 | int(unsafe { p[3] })) == n - 4
		if n > 92 && get16(p, 16) == 1 {
			if r := spnego_parse(unsafe { &p[92] }, n - 92) {
				if r.mic_len == 16 && r.token_len == 0 { f.mic_sent = true }
			}
		}
		if n >= 125 && get16(p, 16) == 5 && get16(p, 114) == 0 {
			assert n == 125 && unsafe { p[124] } == 0
		}
		return true
	}
	if !span(f.length, f.position, n) { return false }
	move(p, unsafe { &f.frame[f.position] }, n)
	f.position += n
	return true
}

fn test_production_client_rejects_bad_frame_and_identity() {
	mut tx := [capacity]u8{}
	mut rx := [capacity]u8{}
	mut scratch := [capacity + 64]u8{}
	mut fake := Fake{}
	mut c := Client{
		context:  unsafe { &fake }
		transfer: fake_transfer
		tx:       unsafe { &tx[0] }
		rx:       unsafe { &rx[0] }
		scratch:  unsafe { &scratch[0] }
	}
	fake.length = 4
	fake.frame[1] = 1
	fake.frame[2] = 0
	fake.frame[3] = 1
	c.header(8, 49)
	_ := c.call(8, 113) or { u32(0) }
	assert c.dead
	c.dead = false
	fake.position = 0
	fake.length = 68
	zero(unsafe { &fake.frame[0] }, 256)
	fake.frame[3] = 64
	p := unsafe { &fake.frame[4] }
	put32(p, 0, 0x424d53fe)
	put16(p, 4, 64)
	put16(p, 12, 8)
	put32(p, 16, 1)
	put64(p, 24, 999)
	_ = c.call(8, 113) or { u32(0) }
	assert c.dead
}

fn test_status_mapping() {
	assert status_errno(0xc000006d) == 13
	assert status_errno(0xc00000cc) == 2
	assert status_errno(0xc00000a2) == 30
}

fn test_readonly_share_may_retain_acl_and_delete_rights() {
	for index, rights in [u32(0x001f00a9), u32(0x001f01ff)] {
		mut tx := [capacity]u8{}
		mut rx := [capacity]u8{}
		mut scratch := [capacity + 64]u8{}
		mut fake := Fake{}
		mut c := Client{
			context:  unsafe { &fake }
			transfer: fake_transfer
			tx:       unsafe { &tx[0] }
			rx:       unsafe { &rx[0] }
			scratch:  unsafe { &scratch[0] }
		}
		frame(unsafe { &fake }, 3, 80, 16)
		fake.frame[4 + 66] = 1
		put32(unsafe { &fake.frame[4] }, 76, rights)
		c.tree_connect(r'\\server\share') or { panic('tree') }
		assert c.readonly == (index == 0)
	}
}

fn test_final_spnego_requires_accept_complete_without_mic() {
	mut response := [u8(0xa1), 7, 0x30, 5, 0xa0, 3, 0x0a, 1, 0]!
	assert spnego_complete(unsafe { &response[0] }, response.len)
	for state in 1 .. 4 {
		response[8] = u8(state)
		assert !spnego_complete(unsafe { &response[0] }, response.len)
	}
	response[8] = 0
	for length in 0 .. response.len {
		assert !spnego_complete(unsafe { &response[0] }, length)
	}
	mic := [u8(0xa1), 13, 0x30, 11, 0xa0, 3, 0x0a, 1, 0, 0xa3, 4, 4, 2, 0, 0]!
	assert !spnego_complete(unsafe { &mic[0] }, mic.len)
}

fn test_final_response_signature_and_failure_erasure() {
	mut tx := [capacity]u8{}
	mut rx := [capacity]u8{}
	mut scratch := [capacity + 64]u8{}
	mut fake := Fake{}
	mut c := Client{
		context:  unsafe { &fake }
		transfer: fake_transfer
		tx:       unsafe { &tx[0] }
		rx:       unsafe { &rx[0] }
		scratch:  unsafe { &scratch[0] }
	}
	put32(c.rx, 16, 8)
	c.signature(c.rx, 72, unsafe { &c.rx[48] })
	assert c.verify_signature(c.rx, 72)
	rx[64] ^= 1
	assert !c.verify_signature(c.rx, 72)
	put32(c.rx, 16, 0)
	assert !c.verify_signature(c.rx, 72)
	for i in 0 .. 16 {
		c.key[i] = 0xaa
	}
	mut nonce := [8]u8{}
	c.login('User', 'Domain', 'Password', false, unsafe { &nonce[0] }) or {}
	assert !c.authenticated && c.session == 0
	for byte in c.key {
		assert byte == 0
	}
}

fn test_unused_file_name_and_short_name_lengths() {
	mut data := [128]u8{}
	mut attr := Attr{}
	mut entry := DirEntry{}
	p := unsafe { &data[0] }
	assert parse_all_info(p, 100, unsafe { &attr })
	put32(p, 96, 0xffffffff)
	assert !parse_all_info(p, 128, unsafe { &attr })
	zero(p, 128)
	data[68] = 25
	assert !parse_entry(p, 104, unsafe { &entry })
	data[68] = 1
	assert !parse_entry(p, 104, unsafe { &entry })
}

fn frame(f &Fake, command u16, size int, structure u16) {
	unsafe {
		*f = Fake{
			length: size + 4
		}
	}
	p := unsafe { &f.frame[4] }
	unsafe {
		f.frame[2] = u8(size >> 8)
		f.frame[3] = u8(size)
	}
	put32(p, 0, 0x424d53fe)
	put16(p, 4, 64)
	put16(p, 12, command)
	put32(p, 16, 1)
	put16(p, 64, structure)
}

fn test_unused_negotiate_blob_and_create_context_bounds() {
	mut tx := [capacity]u8{}
	mut rx := [capacity]u8{}
	mut scratch := [capacity + 64]u8{}
	mut fake := Fake{}
	mut nonce := [16]u8{}
	mut c := Client{
		context:  unsafe { &fake }
		transfer: fake_transfer
		tx:       unsafe { &tx[0] }
		rx:       unsafe { &rx[0] }
		scratch:  unsafe { &scratch[0] }
	}
	frame(unsafe { &fake }, 0, 128, 65)
	p := unsafe { &fake.frame[4] }
	put16(p, 68, 0x0210)
	put32(p, 96, 32768)
	put32(p, 100, 32768)
	put16(p, 120, 127)
	put16(p, 122, 2)
	c.negotiate(unsafe { &nonce[0] }) or {}
	assert c.dead
	c.dead = false
	c.message = 0
	frame(unsafe { &fake }, 5, 152, 89)
	put32(p, 144, 0xffffffff)
	put32(p, 148, 16)
	_ := c.create('x', 0x80, 1, false) or { FileId{} }
	assert c.dead
	c.dead = false
	c.message = 0
	frame(unsafe { &fake }, 5, 160, 89)
	put32(p, 144, 152)
	put32(p, 148, 8)
	_ = c.create('x', 0x80, 1, false) or { FileId{} }
	assert c.fault == 95
}

fn test_spnego_mic_crypto_and_bounded_fields() {
	mut key := [16]u8{}
	for i in 0 .. 16 {
		key[i] = u8(i)
	}
	mut mic := [16]u8{}
	// Independent stdlib MD5/HMAC oracle, including the terminating magic NUL.
	for server in [false, true] {
		magic := if server {
			'session key to server-to-client signing key magic constant\x00'
		} else {
			'session key to client-to-server signing key magic constant\x00'
		}
		mut material := key[..].clone()
		material << magic.bytes()
		derived := md5_std.sum(material)
		message := hex.decode('00000000300c060a2b06010401823702020a') or { panic(err) }
		checksum := hmac.new(derived, message, md5_std.sum, 64)
		mechlist_mic(unsafe { &key[0] }, server, unsafe { &mic[0] })
		assert get32(unsafe { &mic[0] }, 0) == 1
		assert get32(unsafe { &mic[0] }, 12) == 0
		for i in 0 .. 8 {
			assert mic[4 + i] == checksum[i]
		}
	}
	assert verify_mechlist_mic(unsafe { &key[0] }, unsafe { &mic[0] })
	for i in 0 .. 16 {
		mic[i] ^= 1
		assert !verify_mechlist_mic(unsafe { &key[0] }, unsafe { &mic[0] })
		mic[i] ^= 1
	}
	mut token := [256]u8{}
	raw := ntlm_negotiate(unsafe { &token[0] })
	n := spnego_token_mic_response(unsafe { &key[0] }, unsafe { &token[0] }, raw, 256) or {
		panic('wrap')
	}
	r := spnego_parse(unsafe { &token[0] }, n) or { panic('parse') }
	assert r.state == -1 && r.token_len == 40 && r.mic_len == 16
	for size in 0 .. n {
		if _ := spnego_parse(unsafe { &token[0] }, size) { assert false
		 }
	}
	// Even the unused MIC must have a valid, completely bounded inner length.
	token[r.mic_at - 1] = 17
	if _ := spnego_parse(unsafe { &token[0] }, n) { assert false
	 }
}

fn append_setup(mut fake Fake, mut signer Client, id u64, status u32, blob &u8, size int, sign bool) {
	at := fake.length
	p := unsafe { &fake.frame[at + 4] }
	length := 72 + size
	unsafe {
		fake.frame[at + 2] = u8(length >> 8)
		fake.frame[at + 3] = u8(length)
	}
	put32(p, 0, 0x424d53fe)
	put16(p, 4, 64)
	put32(p, 8, status)
	put16(p, 12, 1)
	put32(p, 16, if sign { u32(9) } else { u32(1) })
	put64(p, 24, id)
	put64(p, 40, 7)
	put16(p, 64, 9)
	put16(p, 68, 72)
	put16(p, 70, u16(size))
	move(unsafe { &p[72] }, blob, size)
	if sign { signer.signature(p, length, unsafe { &p[48] }) }
	fake.length += 4 + length
}

fn test_login_mic_continuation_signed_completion_and_rejections() {
	// Script complete framed production SESSION_SETUP exchanges. Mutations test
	// server MIC, final SMB signature, repeated request-mic, and rejected state.
	for mode in 0 .. 6 {
		mut tx := [capacity]u8{}
		mut rx := [capacity]u8{}
		mut scratch := [capacity + 64]u8{}
		mut fake := Fake{}
		mut c := Client{
			context:  unsafe { &fake }
			transfer: fake_transfer
			tx:       unsafe { &tx[0] }
			rx:       unsafe { &rx[0] }
			scratch:  unsafe { &scratch[0] }
		}
		mut raw := [256]u8{}
		move(unsafe { &raw[0] }, c'NTLMSSP\x00', 8)
		put32(unsafe { &raw[0] }, 8, 2)
		put32(unsafe { &raw[0] }, 20, ntlm_flags)
		secbuf(unsafe { &raw[0] }, 40, 56, 4)
		mut challenge := Challenge{}
		assert parse_challenge(unsafe { &raw[0] }, 60, unsafe { &challenge })
		mut nonce := [8]u8{}
		mut auth := [4096]u8{}
		_ := ntlm_authenticate(unsafe { &challenge }, unsafe { &raw[0] }, 60, 'User', 'Domain',
			'Password', false, unsafe { &nonce[0] }, 0, unsafe { &auth[0] }, 4096,
			unsafe { &c.key[0] }) or { panic('auth') }
		// First reply: accept-incomplete plus a challenge.
		n := spnego_response(unsafe { &raw[0] }, 60, 256) or { panic('wrap') }
		// Insert negState before the responseToken inside the short DER sequence.
		for i := n - 1; i >= 4; i-- {
			raw[i + 5] = raw[i]
		}
		raw[1] += 5
		raw[3] += 5
		raw[4] = 0xa0
		raw[5] = 3
		raw[6] = 0x0a
		raw[7] = 1
		raw[8] = 1
		append_setup(mut fake, mut c, 0, 0xc0000016, unsafe { &raw[0] }, n + 5, false)
		mut request := [u8(0xa1), 27, 0x30, 25, 0xa0, 3, 0x0a, 1, 3, 0xa3, 18, 4, 16, 0, 0, 0,
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]!
		mechlist_mic(unsafe { &c.key[0] }, true, unsafe { &request[13] })
		if mode == 1 { request[17] ^= 1 }
		if mode == 4 { request[8] = 2 }
		if mode == 5 { request[8] = 1 } // Samba accept-incomplete with a verified MIC.
		append_setup(mut fake, mut c, 1, 0xc0000016, unsafe { &request[0] }, 29, false)
		complete := [u8(0xa1), 7, 0x30, 5, 0xa0, 3, 0x0a, 1, 0]!
		if mode == 3 {
			append_setup(mut fake, mut c, 2, 0xc0000016, unsafe { &request[0] }, 29, false)
		} else {
			append_setup(mut fake, mut c, 2, 0, unsafe { &complete[0] }, 9, true)
		}
		if mode == 2 { fake.frame[fake.length - 1] ^= 1 }
		// login itself must derive the key before verifying the server MIC/signature.
		zero(unsafe { &c.key[0] }, 16)
		c.login('User', 'Domain', 'Password', false, unsafe { &nonce[0] }) or {}
		assert c.authenticated == (mode == 0 || mode == 5)
		if mode == 0 || mode == 5 {
			assert c.signing && c.message == 3 && fake.mic_sent
		} else {
			assert c.session == 0
			for byte in c.key {
				assert byte == 0
			}
		}
	}
}

fn test_anonymous_ntlm_has_no_identity_or_session_key() {
	mut challenge := Challenge{
		flags:    ntlm_flags
		info_len: 4
	}
	mut raw := [60]u8{}
	mut output := [4096]u8{}
	mut nonce := [8]u8{}
	mut key := [16]u8{}
	for i in 0 .. 16 {
		key[i] = 0xaa
	}
	n := ntlm_authenticate(unsafe { &challenge }, unsafe { &raw[0] }, 60, 'ignored-user',
		'ignored-domain', 'ignored-password', true, unsafe { &nonce[0] }, 0, unsafe { &output[0] },
		4096, unsafe { &key[0] }) or { panic('anonymous') }
	for at in [20, 28, 36, 44, 52] {
		_, size := security_buffer(unsafe { &output[0] }, n, at) or { panic('buffer') }
		assert size == 0
	}
	assert get32(unsafe { &output[0] }, 60) & 0x810 == 0x800
	for byte in key {
		assert byte == 0
	}
}
