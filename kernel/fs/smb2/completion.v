// SPDX-License-Identifier: GPL-2.0-or-later
module smb2

fn spnego_complete(p &u8, length int) bool {
	r := spnego_parse(p, length) or { return false }
	return r.state == 0 && r.token_len == 0 && r.mic_len == 0
}

// MS-NLMP ESS SIGNKEY/MAC. KEY_EXCH is not offered: no RC4 checksum.
// Each direction starts at sequence zero; sign the exact DER MechTypeList.
fn mechlist_mic(key &u8, server bool, out &u8) {
	magic := if server {
		c'session key to server-to-client signing key magic constant\x00'
	} else {
		c'session key to client-to-server signing key magic constant\x00'
	}
	mut material := [80]u8{}
	mut signing_key := [16]u8{}
	mut digest := [16]u8{}
	mut message := [18]u8{}
	mechs := [u8(0x30), 0x0c, 6, 0x0a, 0x2b, 6, 1, 4, 1, 0x82, 0x37, 2, 2, 0x0a]!
	move(unsafe { &material[0] }, key, 16)
	move(unsafe { &material[16] }, magic, 59)
	md5(unsafe { &material[0] }, 75, unsafe { &signing_key[0] })
	move(unsafe { &message[4] }, unsafe { &mechs[0] }, 14)
	hmac_md5(unsafe { &signing_key[0] }, 16, unsafe { &message[0] }, 18, unsafe { &digest[0] })
	zero(out, 16)
	put32(out, 0, 1)
	move(unsafe { &out[4] }, unsafe { &digest[0] }, 8)
	zero(unsafe { &material[0] }, 80)
	zero(unsafe { &signing_key[0] }, 16)
	zero(unsafe { &digest[0] }, 16)
}

fn verify_mechlist_mic(key &u8, p &u8) bool {
	mut expected := [16]u8{}
	mechlist_mic(key, true, unsafe { &expected[0] })
	mut difference := u8(0)
	for i in 0 .. 16 {
		difference |= expected[i] ^ unsafe { p[i] }
	}
	zero(unsafe { &expected[0] }, 16)
	return difference == 0
}

fn spnego_mic_response(key &u8, p &u8, cap int) ?int {
	if cap < 24 { return none }
	mechlist_mic(key, false, p)
	a := der_wrap(p, 16, 4, cap)?
	b := der_wrap(p, a, 0xa3, cap)?
	c := der_wrap(p, b, 0x30, cap)?
	return der_wrap(p, c, 0xa1, cap)
}

// Wrap a raw NTLM token and append the independent SPNEGO mechanism-list MIC.
fn spnego_token_mic_response(key &u8, p &u8, n int, cap int) ?int {
	a := der_wrap(p, n, 4, cap)?
	b := der_wrap(p, a, 0xa2, cap)?
	if !span(cap, b, 20) { return none }
	unsafe {
		p[b] = 0xa3
		p[b + 1] = 18
		p[b + 2] = 4
		p[b + 3] = 16
	}
	mechlist_mic(key, false, unsafe { &p[b + 4] })
	c := der_wrap(p, b + 20, 0x30, cap)?
	return der_wrap(p, c, 0xa1, cap)
}

// Bound the complete SMB security buffer before parsing even unused DER fields.
fn (mut c Client) setup_response() ?NegTokenResp {
	if c.response_len < 72 || get16(c.rx, 64) != 9 || get64(c.rx, 40) != c.session {
		c.broken()
		return none
	}
	off := int(get16(c.rx, 68))
	length := int(get16(c.rx, 70))
	if off < 72 || !span(c.response_len, off, length) {
		c.broken()
		return none
	}
	mut r := spnego_parse(unsafe { &c.rx[off] }, length) or {
		c.diagnostic = 'Malformed SPNEGO authentication response'
		c.broken()
		return none
	}
	r.token_at += off
	r.mic_at += off
	return r
}
