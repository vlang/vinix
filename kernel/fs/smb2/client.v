// SPDX-License-Identifier: GPL-2.0-or-later
module smb2

import krandom

pub type Transfer = fn (voidptr, &u8, int, bool) bool

pub struct Client {
pub mut:
	context       voidptr
	transfer      Transfer = unsafe { nil }
	tx            &u8      = unsafe { nil }
	rx            &u8      = unsafe { nil }
	scratch       &u8      = unsafe { nil } // capacity+64, persistent and serialized
	message       u64
	session       u64
	tree          u32
	key           [16]u8
	signing       bool
	authenticated bool
	dead          bool
	readonly      bool
	fault         int
	diagnostic    string
	max_read      u32 = io_size
	max_write     u32 = io_size
	server_time   u64
	response_len  int
}

pub struct FileId {
pub mut:
	persistent  u64
	volatile_id u64
}

fn (mut c Client) fail(code int) {
	c.fault = code
}

fn (mut c Client) broken() {
	c.dead = true
	c.fault = 5
}

fn (mut c Client) header(command u16, body int) {
	zero(c.tx, 64 + body)
	put32(c.tx, 0, 0x424d53fe)
	put16(c.tx, 4, 64)
	put16(c.tx, 6, 1)
	put16(c.tx, 12, command)
	put16(c.tx, 14, 1)
	put64(c.tx, 24, c.message)
	put32(c.tx, 32, 0xfeff)
	put32(c.tx, 36, c.tree)
	put64(c.tx, 40, c.session)
}

fn (mut c Client) signature(p &u8, n int, out &u8) {
	zero(c.scratch, 64)
	for i in 0 .. 64 {
		unsafe {
			c.scratch[i] = (if i < 16 { c.key[i] } else { u8(0) }) ^ 0x36
		}
	}
	move(unsafe { &c.scratch[64] }, p, n)
	mut digest := [32]u8{}
	krandom.sha256_digest(c.scratch, u64(n + 64), unsafe { &digest })
	for i in 0 .. 64 {
		unsafe {
			c.scratch[i] ^= 0x36 ^ 0x5c
		}
	}
	move(unsafe { &c.scratch[64] }, unsafe { &digest[0] }, 32)
	krandom.sha256_digest(c.scratch, 96, unsafe { &digest })
	move(out, unsafe { &digest[0] }, 16)
	zero(unsafe { &digest[0] }, 32)
	zero(c.scratch, n + 64)
}

fn (mut c Client) verify_signature(p &u8, length int) bool {
	if length < 64 || length > capacity || get32(p, 16) & 8 == 0 { return false }
	mut received := [16]u8{}
	mut expected := [16]u8{}
	move(unsafe { &received[0] }, unsafe { &p[48] }, 16)
	zero(unsafe { &p[48] }, 16)
	c.signature(p, length, unsafe { &expected[0] })
	move(unsafe { &p[48] }, unsafe { &received[0] }, 16)
	mut mismatch := u8(0)
	for i in 0 .. 16 {
		mismatch |= received[i] ^ expected[i]
	}
	return mismatch == 0
}

// One synchronous request, no compounds/async/unsolicited messages. Any framing
// or identity failure kills the stream so no later call consumes stale bytes.
fn (mut c Client) call(command u16, n int) ?u32 {
	if c.dead || n < 64 || n > capacity {
		c.fail(5)
		return none
	}
	if c.authenticated && c.signing {
		put32(c.tx, 16, 8)
		c.signature(c.tx, n, unsafe { &c.tx[48] })
	}
	mut prefix := [4]u8{}
	prefix[1] = u8(n >> 16)
	prefix[2] = u8(n >> 8)
	prefix[3] = u8(n)
	if !c.transfer(c.context, unsafe { &prefix[0] }, 4, true)
		|| !c.transfer(c.context, c.tx, n, true)
		|| !c.transfer(c.context, unsafe { &prefix[0] }, 4, false) {
		c.broken()
		return none
	}
	len := int((u32(prefix[1]) << 16) | (u32(prefix[2]) << 8) | u32(prefix[3]))
	if prefix[0] != 0 || len < 64 || len > capacity {
		c.broken()
		return none
	}
	if !c.transfer(c.context, c.rx, len, false) {
		c.broken()
		return none
	}
	if get32(c.rx, 0) != 0x424d53fe || get16(c.rx, 4) != 64 || get16(c.rx, 12) != command
		|| get64(c.rx, 24) != c.message || get32(c.rx, 16) & 3 != 1 || get32(c.rx, 20) != 0 {
		c.broken()
		return none
	}
	if command > 1 && (get64(c.rx, 40) != c.session || get32(c.rx, 36) != c.tree) && command != 3 {
		c.broken()
		return none
	}
	if command == 3 && get64(c.rx, 40) != c.session {
		c.broken()
		return none
	}
	if c.authenticated && c.signing {
		if !c.verify_signature(c.rx, len) {
			c.broken()
			return none
		}
	}
	c.message++
	c.response_len = len
	status := get32(c.rx, 8)
	c.fault = status_errno(status)
	return status
}

fn (mut c Client) success(command u16, n int, minimum int, structure u16) ? {
	status := c.call(command, n)?
	if status != 0 { return none }
	if c.response_len < minimum || get16(c.rx, 64) != structure {
		c.broken()
		return none
	}
}

pub fn (mut c Client) negotiate(random &u8) ? {
	c.header(0, 38)
	put16(c.tx, 64, 36)
	put16(c.tx, 66, 1)
	put16(c.tx, 68, 1)
	move(unsafe { &c.tx[76] }, random, 16)
	put16(c.tx, 100, 0x0210)
	c.success(0, 102, 128, 65)?
	security_off := int(get16(c.rx, 120))
	security_len := int(get16(c.rx, 122))
	if (security_len > 0 && security_off < 128) || !span(c.response_len, security_off, security_len) {
		c.broken()
		return none
	}
	if get16(c.rx, 68) != 0x0210 {
		c.diagnostic = 'SMB2.1 required; SMB3 is unsupported'
		c.fail(95)
		return none
	}
	c.signing = get16(c.rx, 66) & 2 != 0
	c.max_read = get32(c.rx, 96)
	if c.max_read > io_size { c.max_read = io_size }
	c.max_write = get32(c.rx, 100)
	if c.max_write > io_size { c.max_write = io_size }
	if c.max_read == 0 || c.max_write == 0 {
		c.broken()
		return none
	}
	c.server_time = get64(c.rx, 104)
}

fn (mut c Client) setup(token &u8, n int) ?u32 {
	if n < 0 || n > 8192 {
		c.fail(22)
		return none
	}
	c.header(1, 24)
	put16(c.tx, 64, 25)
	unsafe {
		c.tx[67] = 1
	}
	put16(c.tx, 76, 88)
	put16(c.tx, 78, u16(n))
	move(unsafe { &c.tx[88] }, token, n)
	return c.call(1, 88 + n)
}

pub fn (mut c Client) login(user string, domain string, password string, guest bool, nonce &u8) ? {
	mut completed := false
	defer {
		if !completed {
			krandom.explicit_bzero(unsafe { &c.key[0] }, 16)
			c.authenticated = false
			c.session = 0
		}
	}
	mut token := [8192]u8{}
	mut raw := [4096]u8{}
	mut challenge := Challenge{}
	defer {
		zero(unsafe { &token[0] }, 8192)
		zero(unsafe { &raw[0] }, 4096)
		zero(unsafe { &u8(&challenge) }, int(sizeof(Challenge)))
	}
	initial := spnego_initial(unsafe { &token[0] }, 8192) or {
		c.fail(22)
		return none
	}
	status := c.setup(unsafe { &token[0] }, initial)?
	if status != 0xc0000016 {
		c.diagnostic = 'Server rejected offered NTLMv2 token; Kerberos-only authentication is unsupported'
		if status == 0 { c.fail(13) }
		return none
	}
	if c.response_len < 72 || get16(c.rx, 64) != 9 {
		c.broken()
		return none
	}
	c.session = get64(c.rx, 40)
	off := int(get16(c.rx, 68))
	len := int(get16(c.rx, 70))
	if off < 72 || !span(c.response_len, off, len) || len > 4096 {
		c.broken()
		return none
	}
	start, raw_len := spnego_token(unsafe { &c.rx[off] }, len) or {
		c.broken()
		return none
	}
	if raw_len == 0 {
		c.diagnostic = 'Server did not offer NTLMv2 (Kerberos-only authentication is unsupported)'
		c.fail(95)
		return none
	}
	move(unsafe { &raw[0] }, unsafe { &c.rx[off + start] }, raw_len)
	if !parse_challenge(unsafe { &raw[0] }, raw_len, unsafe { &challenge }) {
		c.broken()
		return none
	}
	n := ntlm_authenticate(unsafe { &challenge }, unsafe { &raw[0] }, raw_len, user, domain,
		password, guest, nonce, c.server_time, unsafe { &token[0] }, 8192, unsafe { &c.key[0] }) or {
		c.fail(22)
		return none
	}
	w := spnego_response(unsafe { &token[0] }, n, 8192) or {
		c.fail(22)
		return none
	}
	last := c.setup(unsafe { &token[0] }, w)?
	if last != 0 {
		zero(unsafe { &c.key[0] }, 16)
		return none
	}
	if c.response_len < 72 || get16(c.rx, 64) != 9 || get64(c.rx, 40) != c.session {
		c.broken()
		return none
	}
	last_off := int(get16(c.rx, 68))
	last_len := int(get16(c.rx, 70))
	if (last_len > 0 && last_off < 72) || !span(c.response_len, last_off, last_len) {
		c.broken()
		return none
	}
	if last_len > 0 {
		if !spnego_complete(unsafe { &c.rx[last_off] }, last_len) {
			c.broken()
			return none
		}
	}
	flags := get16(c.rx, 66)
	if flags & 4 != 0 || (flags & 3 != 0 && (!guest || c.signing)) {
		c.diagnostic = 'Guest signing or SMB encryption policy is unsupported'
		c.fail(95)
		return none
	}
	if flags & 3 == 0 {
		// SESSION_SETUP establishes the signing key: verify its successful
		// completion before publishing the session, not only later responses.
		if !c.verify_signature(c.rx, c.response_len) {
			c.broken()
			return none
		}
		c.signing = true
	}
	c.authenticated = true
	completed = true
}

pub fn (mut c Client) tree_connect(unc string) ? {
	c.header(3, 8)
	put16(c.tx, 64, 9)
	put16(c.tx, 68, 72)
	n := utf16(unc, unsafe { &c.tx[72] }, max_path * 2, false) or {
		c.fail(22)
		return none
	}
	put16(c.tx, 70, u16(n))
	c.success(3, 72 + n, 80, 16)?
	if unsafe { c.rx[66] } != 1 || get32(c.rx, 68) & 0x8000 != 0 {
		c.fail(95)
		return none
	}
	c.tree = get32(c.rx, 36)
	// TREE_CONNECT.MaximalAccess, never a fabricated share read-only flag.
	c.readonly = get32(c.rx, 76) & 0x000d0116 == 0
}

fn fid_put(p &u8, at int, id FileId) {
	put64(p, at, id.persistent)
	put64(p, at + 8, id.volatile_id)
}

pub fn (mut c Client) create(path string, access u32, disposition u32, directory bool) ?FileId {
	if c.readonly && (access & 0x000d0116 != 0 || disposition != 1) {
		c.fail(30)
		return none
	}
	c.header(5, 56)
	put16(c.tx, 64, 57)
	put32(c.tx, 68, 2)
	put32(c.tx, 88, access)
	put32(c.tx, 92, if directory { u32(16) } else { u32(128) })
	put32(c.tx, 96, 7)
	put32(c.tx, 100, disposition)
	put32(c.tx, 104, if directory { u32(1) } else { u32(0x40) })
	n := utf16(path, unsafe { &c.tx[120] }, max_path * 2, false) or {
		c.fail(36)
		return none
	}
	put16(c.tx, 108, 120)
	put16(c.tx, 110, u16(n))
	c.success(5, 120 + n, 152, 89)?
	context_off := get32(c.rx, 144)
	context_len := get32(c.rx, 148)
	if context_off > u32(c.response_len) || context_len > u32(c.response_len)
		|| (context_len > 0 && (context_off < 152 || context_off % 8 != 0))
		|| !span(c.response_len, int(context_off), int(context_len)) {
		c.broken()
		return none
	}
	// No CREATE contexts were requested, so no extension is accepted implicitly.
	if context_len != 0 {
		c.fail(95)
		return none
	}
	return FileId{get64(c.rx, 128), get64(c.rx, 136)}
}

pub fn (mut c Client) close(id FileId) ? {
	c.header(6, 24)
	put16(c.tx, 64, 24)
	fid_put(c.tx, 72, id)
	c.success(6, 88, 124, 60)?
}

pub fn (mut c Client) query_info(id FileId, attr &Attr) ? {
	c.header(16, 40)
	put16(c.tx, 64, 41)
	unsafe {
		c.tx[66] = 1
		c.tx[67] = 18
	}
	put32(c.tx, 68, 256)
	fid_put(c.tx, 88, id)
	c.success(16, 104, 72, 9)?
	off := int(get16(c.rx, 66))
	n := get32(c.rx, 68)
	if n > 256 || off < 72 || !span(c.response_len, off, int(n))
		|| !parse_all_info(unsafe { &c.rx[off] }, int(n), attr) {
		c.broken()
		return none
	}
}

pub fn (mut c Client) read(id FileId, offset u64, out &u8, count int) ?int {
	if count < 0 || count > int(c.max_read) {
		c.fail(22)
		return none
	}
	c.header(8, 49)
	put16(c.tx, 64, 49)
	put32(c.tx, 68, u32(count))
	put64(c.tx, 72, offset)
	fid_put(c.tx, 80, id)
	status := c.call(8, 113)?
	if status == 0xc0000011 { return 0 }
	if status != 0 { return none }
	if c.response_len < 80 || get16(c.rx, 64) != 17 {
		c.broken()
		return none
	}
	off := int(unsafe { c.rx[66] })
	n := get32(c.rx, 68)
	if n > u32(count) || off < 80 || !span(c.response_len, off, int(n)) {
		c.broken()
		return none
	}
	move(out, unsafe { &c.rx[off] }, int(n))
	return int(n)
}

pub fn (mut c Client) write(id FileId, offset u64, p &u8, count int) ?int {
	if c.readonly {
		c.fail(30)
		return none
	}
	if count < 0 || count > int(c.max_write) {
		c.fail(22)
		return none
	}
	c.header(9, 48)
	put16(c.tx, 64, 49)
	put16(c.tx, 66, 112)
	put32(c.tx, 68, u32(count))
	put64(c.tx, 72, offset)
	fid_put(c.tx, 80, id)
	move(unsafe { &c.tx[112] }, p, count)
	c.success(9, 112 + count, 80, 17)?
	channel_off := int(get16(c.rx, 76))
	channel_len := int(get16(c.rx, 78))
	if (channel_len > 0 && channel_off < 80) || !span(c.response_len, channel_off, channel_len) {
		c.broken()
		return none
	}
	if channel_len != 0 {
		c.fail(95)
		return none
	}
	n := get32(c.rx, 68)
	if n > u32(count) || (n == 0 && count != 0) {
		c.broken()
		return none
	}
	return int(n)
}

pub fn (mut c Client) set_info(id FileId, class u8, p &u8, n int) ? {
	if c.readonly {
		c.fail(30)
		return none
	}
	if n < 0 || n > 4096 {
		c.fail(22)
		return none
	}
	c.header(17, 32)
	put16(c.tx, 64, 33)
	unsafe {
		c.tx[66] = 1
		c.tx[67] = class
	}
	put32(c.tx, 68, u32(n))
	put16(c.tx, 72, 96)
	fid_put(c.tx, 80, id)
	move(unsafe { &c.tx[96] }, p, n)
	c.success(17, 96 + n, 66, 2)?
}

pub fn (mut c Client) rename(id FileId, path string, replace bool) ? {
	mut data := [4096]u8{}
	data[0] = if replace { u8(1) } else { u8(0) }
	n := utf16(path, unsafe { &data[20] }, 4096 - 20, false) or {
		c.fail(36)
		return none
	}
	put32(unsafe { &data[0] }, 16, u32(n))
	c.set_info(id, 10, unsafe { &data[0] }, 20 + n)?
}

pub fn (mut c Client) directory(id FileId, restart bool) ?bool {
	c.header(14, 34)
	put16(c.tx, 64, 33)
	unsafe {
		c.tx[66] = 37
		c.tx[67] = if restart { u8(1) } else { u8(0) }
	}
	fid_put(c.tx, 72, id)
	put16(c.tx, 88, 96)
	put16(c.tx, 90, 2)
	put32(c.tx, 92, io_size)
	put16(c.tx, 96, 42)
	status := c.call(14, 98)?
	if status == 0x80000006 { return false }
	if status != 0 { return none }
	if c.response_len < 72 || get16(c.rx, 64) != 9 {
		c.broken()
		return none
	}
	off := int(get16(c.rx, 66))
	n := get32(c.rx, 68)
	if n > io_size || n == 0 || off < 72 || !span(c.response_len, off, int(n)) {
		c.broken()
		return none
	}
	return true
}

pub fn (mut c Client) flush(id FileId) ? {
	c.header(7, 24)
	put16(c.tx, 64, 24)
	fid_put(c.tx, 72, id)
	c.success(7, 88, 68, 4)?
}
