// SPDX-License-Identifier: GPL-2.0-or-later
module ninep

// The owner serializes an entire operation (including walking/opening/clunking)
// and supplies fixed buffers. Negative exchange results are Linux errno values.
// A malformed reply poisons the session; no subsequent request can reuse a tag
// or a FID whose server-side state is uncertain.
pub type Exchange = fn (voidptr, &u8, u32, &u8, u32) int

pub struct Client {
pub mut:
	context  voidptr
	exchange Exchange = unsafe { nil }
	tx       &u8      = unsafe { nil }
	rx       &u8      = unsafe { nil }
	msize    u32      = max_msize
	tag      u16
	fault    int
	dead     bool
	fids     [max_fids]bool
}

pub fn (mut c Client) fail(code int) {
	c.fault = code
}

fn (mut c Client) malformed() {
	c.fault = eproto
	c.dead = true
}

pub fn (mut c Client) begin(kind u8) Writer {
	if c.dead { return Writer{} }
	c.tag++
	if c.tag == notag { c.tag = 0 }
	return writer(c.tx, c.msize, kind, c.tag)
}

pub fn (mut c Client) call(mut w Writer, out &Reader) bool {
	if c.dead {
		c.fail(eio)
		return false
	}
	length := w.finish()
	if length == 0 || c.exchange == unsafe { nil } {
		c.fail(einval)
		return false
	}
	n := c.exchange(c.context, c.tx, length, c.rx, c.msize)
	if n < 0 {
		c.fail(if n >= -4095 { -n } else { eio })
		c.dead = true
		c.tx = unsafe { nil }
		c.rx = unsafe { nil }
		return false
	}
	kind := unsafe { c.tx[4] }
	code := reply(c.rx, u32(n), c.msize, kind, c.tag, out)
	if code != 0 {
		c.fail(code)
		if code == eproto { c.dead = true }
		return false
	}
	c.fault = 0
	return true
}

pub fn (mut c Client) allocate_fid() ?u32 {
	if c.dead {
		c.fail(eio)
		return none
	}
	for i in 0 .. max_fids {
		if !c.fids[i] {
			c.fids[i] = true
			return u32(i)
		}
	}
	c.fail(enospc)
	return none
}

pub fn (mut c Client) negotiate() ? {
	if c.dead {
		c.fail(eio)
		return none
	}
	requested := c.msize
	if requested < min_msize || requested > max_msize {
		c.fail(einval)
		return none
	}
	c.tag = notag
	mut w := writer(c.tx, requested, tversion, notag)
	w.dword(requested)
	w.text('9P2000.L')
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	accepted := r.dword()
	length := r.word()
	if length != 8 || !r.take(length) || !r.done() || accepted < min_msize || accepted > requested {
		c.malformed()
		return none
	}
	for i in 0 .. 8 {
		if unsafe { r.data[r.pos - 8 + u32(i)] } != '9P2000.L'[i] {
			c.malformed()
			return none
		}
	}
	c.msize = accepted
	c.tag = 0
}

pub fn (mut c Client) attach(uid u32) ?u32 {
	fid := c.allocate_fid()?
	mut w := c.begin(tattach)
	w.dword(fid)
	w.dword(nofid)
	w.text('')
	w.text('')
	w.dword(uid)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) {
		c.fids[fid] = false
		return none
	}
	qid := r.qid()
	if !r.done() || qid.kind & 0x80 == 0 {
		c.malformed()
		return none
	}
	return fid
}

pub fn (mut c Client) walk(fid u32, name string) ?u32 {
	if name != '' && !valid_name(name) {
		c.fail(einval)
		return none
	}
	fresh := c.allocate_fid()?
	mut w := c.begin(twalk)
	w.dword(fid)
	w.dword(fresh)
	w.word(if name == '' { u16(0) } else { u16(1) })
	if name != '' { w.text(name) }
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) {
		c.fids[fresh] = false
		return none
	}
	n := r.word()
	if n != (if name == '' { u16(0) } else { u16(1) }) {
		c.malformed()
		return none
	}
	if n == 1 { r.qid() }
	if !r.done() {
		c.malformed()
		return none
	}
	return fresh
}

pub fn (mut c Client) clunk(fid u32) ? {
	if fid >= max_fids || !c.fids[fid] {
		c.fail(einval)
		return none
	}
	mut w := c.begin(tclunk)
	w.dword(fid)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	if !r.done() {
		c.malformed()
		return none
	}
	c.fids[fid] = false
}

// Best effort cleanup must preserve the error from the operation itself.
pub fn (mut c Client) release(fid u32) {
	if c.dead { return }
	old := c.fault
	c.clunk(fid) or {}
	if old != 0 { c.fault = old }
}

pub fn (mut c Client) getattr(fid u32, out &Attr) ? {
	mut w := c.begin(tgetattr)
	w.dword(fid)
	w.qword(0x7ff)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	if !parse_attr(mut r, out) {
		c.malformed()
		return none
	}
}

pub fn (mut c Client) lopen(fid u32, flags u32) ?u32 {
	mut w := c.begin(tlopen)
	w.dword(fid)
	w.dword(flags)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	r.qid()
	unit := r.dword()
	if !r.done() {
		c.malformed()
		return none
	}
	return if unit == 0 || unit > c.msize - 24 { c.msize - 24 } else { unit }
}

pub fn (mut c Client) lcreate(fid u32, name string, mode u32, gid u32) ? {
	if !valid_name(name) {
		c.fail(einval)
		return none
	}
	mut w := c.begin(tlcreate)
	w.dword(fid)
	w.text(name)
	w.dword(2)
	// Linux-dialect modes include the inode kind. QEMU mapped-xattr stores
	// this value verbatim; stripping S_IFREG creates a typeless remote inode.
	w.dword(0o100000 | (mode & 0o7777))
	w.dword(gid)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	r.qid()
	r.dword()
	if !r.done() {
		c.malformed()
		return none
	}
}

pub fn (mut c Client) mkdir(fid u32, name string, mode u32, gid u32) ? {
	if !valid_name(name) {
		c.fail(einval)
		return none
	}
	mut w := c.begin(tmkdir)
	w.dword(fid)
	w.text(name)
	w.dword(0o40000 | (mode & 0o7777))
	w.dword(gid)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	r.qid()
	if !r.done() {
		c.malformed()
		return none
	}
}

pub fn (mut c Client) setattr(fid u32, mask u32, attr &Attr) ? {
	if mask & ~u32(0x1ff) != 0 || attr.size > 0x7fffffffffffffff
		|| attr.atime_nsec >= 1000000000 || attr.mtime_nsec >= 1000000000 {
		c.fail(einval)
		return none
	}
	mut w := c.begin(tsetattr)
	w.dword(fid)
	w.dword(mask)
	w.dword(attr.mode & 0o177777)
	w.dword(attr.uid)
	w.dword(attr.gid)
	w.qword(attr.size)
	w.qword(attr.atime_sec)
	w.qword(attr.atime_nsec)
	w.qword(attr.mtime_sec)
	w.qword(attr.mtime_nsec)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	if !r.done() {
		c.malformed()
		return none
	}
}

pub fn (mut c Client) read(fid u32, offset u64, buf &u8, count u32) ?u32 {
	if !valid_range(offset, count) || count > c.msize - 24 || (count != 0 && buf == unsafe { nil }) {
		c.fail(einval)
		return none
	}
	mut w := c.begin(tread)
	w.dword(fid)
	w.qword(offset)
	w.dword(count)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	mut start := u32(0)
	mut n := u32(0)
	if !payload(mut r, count, unsafe { &start }, unsafe { &n }) {
		c.malformed()
		return none
	}
	for i := u32(0); i < n; i++ {
		unsafe { buf[i] = c.rx[start + i] }
	}
	return n
}

pub fn (mut c Client) write(fid u32, offset u64, buf &u8, count u32) ?u32 {
	if !valid_range(offset, count) || count > c.msize - 24 || (count != 0 && buf == unsafe { nil }) {
		c.fail(einval)
		return none
	}
	mut w := c.begin(twrite)
	w.dword(fid)
	w.qword(offset)
	w.dword(count)
	w.raw(buf, count)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	n := r.dword()
	if !r.done() || n > count {
		c.malformed()
		return none
	}
	return n
}

// Consume one entry but validate the entire bounded reply before returning it.
// A caller may issue another RPC immediately; no view of rx escapes. Cookies
// are opaque, and loops across replies are bounded by the owner's scan budget.
pub fn (mut c Client) readdir_one(fid u32, offset u64, count u32, out &DirEntry) ?bool {
	if count < 280 || count > c.msize - 24 {
		c.fail(einval)
		return none
	}
	mut w := c.begin(treaddir)
	w.dword(fid)
	w.qword(offset)
	w.dword(count)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	mut start := u32(0)
	mut n := u32(0)
	if !payload(mut r, count, unsafe { &start }, unsafe { &n }) {
		c.malformed()
		return none
	}
	if n == 0 { return false }
	mut entries := reader(unsafe { c.rx + start }, n)
	mut previous := offset
	mut first := true
	mut entry := DirEntry{}
	for entries.pos < entries.length {
		if !next_entry(mut entries, previous, unsafe { &entry }) {
			c.malformed()
			return none
		}
		previous = entry.offset
		if first {
			unsafe { *out = entry }
			first = false
		}
	}
	if !entries.done() {
		c.malformed()
		return none
	}
	return true
}

pub fn (mut c Client) renameat(old_dir u32, old_name string, new_dir u32, new_name string) ? {
	if !valid_name(old_name) || !valid_name(new_name) {
		c.fail(einval)
		return none
	}
	mut w := c.begin(trenameat)
	w.dword(old_dir)
	w.text(old_name)
	w.dword(new_dir)
	w.text(new_name)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	if !r.done() {
		c.malformed()
		return none
	}
}

pub fn (mut c Client) unlinkat(dir u32, name string, directory bool) ? {
	if !valid_name(name) {
		c.fail(einval)
		return none
	}
	mut w := c.begin(tunlinkat)
	w.dword(dir)
	w.text(name)
	w.dword(if directory { u32(0x200) } else { u32(0) })
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	if !r.done() {
		c.malformed()
		return none
	}
}

pub fn (mut c Client) fsync(fid u32) ? {
	mut w := c.begin(tfsync)
	w.dword(fid)
	w.dword(0)
	mut r := Reader{}
	if !c.call(mut w, unsafe { &r }) { return none }
	if !r.done() {
		c.malformed()
		return none
	}
}
