// SPDX-License-Identifier: GPL-2.0-or-later
// MS-NLMP 2.2.1, 2.2.2.7, 3.3.2; RFC 4178 (SPNEGO).
module smb2

pub const ntlm_flags = u32(0xa2888215) // Unicode, sign, request target, NTLM, always sign, ESS, target info, version, 128, 56; no key exchange.

pub fn ntlm_negotiate(out &u8) int {
	zero(out, 40)
	move(out, c'NTLMSSP\x00', 8)
	put32(out, 8, 1)
	put32(out, 12, ntlm_flags)
	unsafe {
		out[32] = 10
		out[39] = 15
	}
	put16(out, 34, 19041)
	return 40
}

fn security_buffer(p &u8, n int, at int) ?(int, int) {
	if !span(n, at, 8) { return none }
	len := int(get16(p, at))
	off := get32(p, at + 4)
	if off > u32(n) || !span(n, int(off), len) || get16(p, at + 2) < u16(len) { return none }
	return int(off), len
}

pub struct Challenge {
pub mut:
	flags         u32
	server        [8]u8
	timestamp     u64
	has_timestamp bool
	mic           bool
	info          [2048]u8
	info_len      int
}

pub fn parse_challenge(p &u8, n int, c &Challenge) bool {
	if n < 48 || n > 4096 { return false }
	for i in 0 .. 8 {
		if unsafe { p[i] != c'NTLMSSP\x00'[i] } { return false }
	}
	if get32(p, 8) != 2 { return false }
	flags := get32(p, 20)
	if flags & 0x00880201 != 0x00880201 { return false }
	name_off, name_len := security_buffer(p, n, 12) or { return false }
	header_len := if flags & 0x02000000 != 0 { 56 } else { 48 }
	if n < header_len || (name_len > 0 && (name_off < header_len || name_len % 2 != 0)) {
		return false
	}
	off, len := security_buffer(p, n, 40) or { return false }
	if off < header_len || len < 4 || len > 2048 { return false }
	unsafe {
		*c = Challenge{
			flags: flags
		}
		move(&c.server[0], &p[24], 8)
		move(&c.info[0], &p[off], len)
		c.info_len = len
	}
	mut at := 0
	for at < len {
		if !span(len, at, 4) { return false }
		id := get16(p, off + at)
		size := int(get16(p, off + at + 2))
		at += 4
		if !span(len, at, size) { return false }
		if id == 0 { return size == 0 && at == len }
		if id == 7 {
			if size != 8 { return false }
			unsafe {
				c.timestamp = get64(p, off + at)
				c.has_timestamp = true
			}
		}
		if id == 6 {
			if size != 4 { return false }
			unsafe {
				c.mic = get32(p, off + at) & 2 != 0
			}
		}
		if id == 10 && size != 16 { return false }
		at += size
	}
	return false
}

fn secbuf(out &u8, at int, offset int, len int) {
	put16(out, at, u16(len))
	put16(out, at + 2, u16(len))
	put32(out, at + 4, u32(offset))
}

// Caller supplies unpredictable nonce from krandom and a Windows FILETIME.
// MIC covers the exact raw type 1, type 2 and zero-MIC type 3 messages.
pub fn ntlm_authenticate(c &Challenge, challenge &u8, challenge_len int, user string, domain string, password string, guest bool, nonce &u8, timestamp u64, out &u8, cap int, key &u8) ?int {
	if cap < 4096 || c.info_len < 4 || c.info_len > 2048 || challenge_len < 48
		|| challenge_len > 4096 {
		return none
	}
	zero(out, cap)
	zero(key, 16)
	move(out, c'NTLMSSP\x00', 8)
	put32(out, 8, 3)
	flags := c.flags & ntlm_flags
	put32(out, 60, flags)
	if flags & 0x02000000 != 0 {
		unsafe {
			out[64] = 10
			out[71] = 15
		}
		put16(out, 66, 19041)
	}
	mut at := 88 // MS-NLMP 2.2.1.3: zero Version slot when not negotiated, MIC at 72.
	d := utf16(if guest { '' } else { domain }, unsafe { &out[at] }, cap - at, false) or {
		return none
	}
	secbuf(out, 28, at, d)
	at += d
	u := utf16(if guest { '' } else { user }, unsafe { &out[at] }, cap - at, false) or {
		return none
	}
	secbuf(out, 36, at, u)
	at += u
	secbuf(out, 44, at, 0)
	secbuf(out, 52, at, 0)
	if guest {
		put32(out, 60, (flags | 0x800) & ~u32(0x10)) // Anonymous, no signing key.
		secbuf(out, 12, at, 1)
		at++
		secbuf(out, 20, at, 0)
		return at
	}
	mut hash := [16]u8{}
	mut proof := [16]u8{}
	mut work := [4096]u8{}
	defer {
		zero(unsafe { &hash[0] }, 16)
		zero(unsafe { &proof[0] }, 16)
		zero(unsafe { &work[0] }, 4096)
	}
	if !ntlmv2_hash(user, domain, password, unsafe { &hash[0] }) { return none }
	// LMv2 suppressed when server supplies timestamp (MS-NLMP 3.2.5.1.2).
	secbuf(out, 12, at, 24)
	if !c.has_timestamp {
		move(unsafe { &work[0] }, unsafe { &c.server[0] }, 8)
		move(unsafe { &work[8] }, nonce, 8)
		hmac_md5(unsafe { &hash[0] }, 16, unsafe { &work[0] }, 16, unsafe { &out[at] })
		move(unsafe { &out[at + 16] }, nonce, 8)
	}
	at += 24
	// temp = response version, reserved, timestamp, nonce, reserved, AV pairs, reserved.
	mut info := [2056]u8{}
	move(unsafe { &info[0] }, unsafe { &c.info[0] }, c.info_len)
	mut info_len := c.info_len
	if c.mic || c.has_timestamp {
		mut pos := 0
		mut found := false
		for pos + 4 <= info_len {
			id := get16(unsafe { &info[0] }, pos)
			size := int(get16(unsafe { &info[0] }, pos + 2))
			if id == 6 {
				put32(unsafe { &info[0] }, pos + 4, get32(unsafe { &info[0] }, pos + 4) | 2)
				found = true
				break
			}
			if id == 0 { break
			 }
			pos += 4 + size
		}
		if !found {
			pos = info_len - 4
			put16(unsafe { &info[0] }, pos, 6)
			put16(unsafe { &info[0] }, pos + 2, 4)
			put32(unsafe { &info[0] }, pos + 4, 2)
			zero(unsafe { &info[pos + 8] }, 4)
			info_len += 8
		}
	}
	blob_len := 32 + info_len
	if !span(cap, at, 16 + blob_len) { return none }
	secbuf(out, 20, at, 16 + blob_len)
	put32(out, at + 16, 0x00000101)
	put64(out, at + 24, if c.has_timestamp { c.timestamp } else { timestamp })
	move(unsafe { &out[at + 32] }, nonce, 8)
	move(unsafe { &out[at + 44] }, unsafe { &info[0] }, info_len)
	move(unsafe { &work[0] }, unsafe { &c.server[0] }, 8)
	move(unsafe { &work[8] }, unsafe { &out[at + 16] }, blob_len)
	hmac_md5(unsafe { &hash[0] }, 16, unsafe { &work[0] }, 8 + blob_len, unsafe { &proof[0] })
	move(unsafe { &out[at] }, unsafe { &proof[0] }, 16)
	hmac_md5(unsafe { &hash[0] }, 16, unsafe { &proof[0] }, 16, key)
	at += 16 + blob_len
	if c.mic || c.has_timestamp {
		// Flag MIC presence in AV_FLAGS when provided by server; server timestamp
		// also requires MIC under the Windows NTLMv2 interoperability rules.
		mut dctx := Digest{}
		mut pad := [64]u8{}
		mut inner := [16]u8{}
		mut nego := [40]u8{}
		ntlm_negotiate(unsafe { &nego[0] })
		for i in 0 .. 64 {
			pad[i] = (if i < 16 { unsafe { key[i] } } else { u8(0) }) ^ 0x36
		}
		digest_init(unsafe { &dctx }, false)
		digest_update(unsafe { &dctx }, unsafe { &pad[0] }, 64)
		digest_update(unsafe { &dctx }, unsafe { &nego[0] }, 40)
		digest_update(unsafe { &dctx }, challenge, challenge_len)
		digest_update(unsafe { &dctx }, out, at)
		digest_end(unsafe { &dctx }, unsafe { &inner[0] })
		for i in 0 .. 64 {
			pad[i] ^= 0x36 ^ 0x5c
		}
		digest_init(unsafe { &dctx }, false)
		digest_update(unsafe { &dctx }, unsafe { &pad[0] }, 64)
		digest_update(unsafe { &dctx }, unsafe { &inner[0] }, 16)
		digest_end(unsafe { &dctx }, unsafe { &out[72] })
		zero(unsafe { &pad[0] }, 64)
		zero(unsafe { &inner[0] }, 16)
	}
	return at
}

// Definite, minimal DER length. In-place wrapping preserves the raw NTLM token.
fn der_wrap(p &u8, n int, tag u8, cap int) ?int {
	if n < 0 || n > 65535 { return none }
	h := if n < 128 {
		2
	} else if n < 256 {
		3
	} else {
		4
	}
	if !span(cap, h, n) { return none }
	for i := n - 1; i >= 0; i-- {
		unsafe {
			p[i + h] = p[i]
		}
	}
	unsafe {
		p[0] = tag
		p[1] = if h == 2 { u8(n) } else { u8(0x80 + h - 2) }
	}
	if h == 3 {
		unsafe {
			p[2] = u8(n)
		}
	}
	if h == 4 {
		unsafe {
			p[2] = u8(n >> 8)
			p[3] = u8(n)
		}
	}
	return n + h
}

pub fn spnego_response(p &u8, n int, cap int) ?int {
	a := der_wrap(p, n, 4, cap)?
	b := der_wrap(p, a, 0xa2, cap)?
	c := der_wrap(p, b, 0x30, cap)?
	return der_wrap(p, c, 0xa1, cap)
}

// A bounded DER TLV; reject indefinite, nonminimal and overflowing lengths.
fn der_element(p &u8, n int, at int) ?(u8, int, int, int) {
	if !span(n, at, 2) { return none }
	tag := unsafe { p[at] }
	first := unsafe { p[at + 1] }
	mut start := at + 2
	mut length := int(first)
	if first & 0x80 != 0 {
		count := int(first & 0x7f)
		if count < 1 || count > 2 || !span(n, start, count) || unsafe { p[start] } == 0 {
			return none
		}
		length = 0
		for i in 0 .. count {
			length = length * 256 + int(unsafe { p[start + i] })
		}
		if length < 128 || (count == 2 && length < 256) { return none }
		start += count
	}
	if !span(n, start, length) { return none }
	return tag, start, length, start + length
}

// Only NegTokenResp.sequence.responseToken may contain the NTLM challenge.
// Missing token is distinct from malformed DER, for mechanism diagnostics.
struct NegTokenResp {
mut:
	state     int = -1
	token_at  int
	token_len int
	mic_at    int
	mic_len   int
}

fn spnego_parse(p &u8, n int) ?NegTokenResp {
	if n < 0 || n > 8192 { return none }
	tag, start, length, end := der_element(p, n, 0)?
	if tag != 0xa1 || end != n { return none }
	tag2, seq, seq_len, seq_end := der_element(p, end, start)?
	if tag2 != 0x30 || seq_end != start + length { return none }
	mut at := seq
	mut previous := int(0x9f)
	mut result := NegTokenResp{}
	for at < seq + seq_len {
		field, body, size, next := der_element(p, seq_end, at)?
		if int(field) <= previous || field < 0xa0 || field > 0xa3 { return none }
		previous = int(field)
		inner, data, data_len, inner_end := der_element(p, next, body)?
		if inner_end != body + size { return none }
		if field == 0xa0 {
			if inner != 0x0a || data_len != 1 || unsafe { p[data] } > 3 { return none }
			result.state = int(unsafe { p[data] })
		} else if field == 0xa1 {
			if inner != 6 || data_len != 10 { return none }
			oid := [u8(0x2b), 6, 1, 4, 1, 0x82, 0x37, 2, 2, 0x0a]!
			for i in 0 .. 10 {
				if unsafe { p[data + i] } != oid[i] { return none }
			}
		} else {
			if inner != 4 { return none }
			if field == 0xa2 {
				result.token_at = data
				result.token_len = data_len
			} else {
				if data_len != 16 { return none }
				result.mic_at = data
				result.mic_len = data_len
			}
		}
		at = next
	}
	return result
}

fn spnego_token(p &u8, n int) ?(int, int) {
	r := spnego_parse(p, n)?
	return r.token_at, r.token_len
}

pub fn spnego_initial(p &u8, cap int) ?int {
	// RFC 4178 initialContextToken containing NTLM mechanism OID.
	if cap < 74 { return none }
	const_prefix := [u8(0x60), 0x48, 0x06, 0x06, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x02, 0xa0, 0x3e,
		0x30, 0x3c, 0xa0, 0x0e, 0x30, 0x0c, 0x06, 0x0a, 0x2b, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37,
		0x02, 0x02, 0x0a, 0xa2, 0x2a, 0x04, 0x28]!
	// Type 1 includes its 8-byte version field; all lengths are exact DER.
	move(p, unsafe { &const_prefix[0] }, 34)
	ntlm_negotiate(unsafe { &p[34] })
	return 74
}
