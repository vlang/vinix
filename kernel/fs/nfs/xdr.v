// SPDX-License-Identifier: GPL-2.0-or-later
module nfs

pub const io_max = 65536
pub const capacity = io_max + 4096
pub const max_entries = 4096
pub const max_fragments = 128

// All views borrow caller storage. No network length is converted to int until
// it has been checked against an int-sized remaining span and policy limit.
pub struct Xdr {
pub mut:
	p &u8 = unsafe { nil }
	n int
	at int
	bad bool
}

pub fn span(n int, at int, count int) bool {
	return n >= 0 && at >= 0 && count >= 0 && at <= n && count <= n - at
}

pub fn copy_bytes(dst &u8, src &u8, n int) {
	unsafe { for i in 0 .. n { dst[i] = src[i] } }
}

pub fn (mut x Xdr) take(n int) int {
	if x.bad || !span(x.n, x.at, n) { x.bad = true; return 0 }
	at := x.at
	x.at += n
	return at
}

pub fn (mut x Xdr) u32() u32 {
	at := x.take(4)
	if x.bad { return 0 }
	unsafe { return u32(x.p[at]) << 24 | u32(x.p[at+1]) << 16 | u32(x.p[at+2]) << 8 | u32(x.p[at+3]) }
}

pub fn (mut x Xdr) u64() u64 {
	hi := x.u32()
	lo := x.u32()
	return u64(hi) << 32 | u64(lo)
}

pub fn (mut x Xdr) boolean() bool {
	v := x.u32()
	if v > 1 { x.bad = true }
	return v == 1
}

pub fn (mut x Xdr) put32(v u32) {
	at := x.take(4)
	if x.bad { return }
	unsafe { x.p[at] = u8(v >> 24); x.p[at+1] = u8(v >> 16); x.p[at+2] = u8(v >> 8); x.p[at+3] = u8(v) }
}

pub fn (mut x Xdr) put64(v u64) {
	x.put32(u32(v >> 32))
	x.put32(u32(v))
}

// RFC4506 requires zero padding. Return a borrowed view; never allocate.
pub fn (mut x Xdr) opaque(limit int) string {
	size := x.u32()
	if x.bad || limit < 0 || size > u32(limit) || x.at > x.n || size > u32(x.n - x.at) {
		x.bad = true; return ''
	}
	n := int(size)
	at := x.take(n)
	pad := (4 - (n & 3)) & 3
	padding := x.take(pad)
	if x.bad { return '' }
	unsafe {
		for i in 0 .. pad { if x.p[padding+i] != 0 { x.bad = true } }
		return tos(x.p + at, n)
	}
}

pub fn (mut x Xdr) put_opaque(p &u8, n int, limit int) {
	if n < 0 || n > limit { x.bad = true; return }
	x.put32(u32(n))
	at := x.take(n)
	pad := (4 - (n & 3)) & 3
	padding := x.take(pad)
	if x.bad { return }
	copy_bytes(unsafe { x.p + at }, p, n)
	unsafe { for i in 0 .. pad { x.p[padding+i] = 0 } }
}

pub fn (mut x Xdr) text(s string, limit int) { x.put_opaque(s.str, s.len, limit) }
pub fn (x &Xdr) finished() bool { return !x.bad && x.at == x.n }

pub struct FileHandle {
pub mut:
	bytes [64]u8
	len int
}

pub fn (mut x Xdr) handle(out &FileHandle) {
	s := x.opaque(64)
	if s.len == 0 { x.bad = true }
	if x.bad { return }
	unsafe { out.len = s.len; copy_bytes(&out.bytes[0], s.str, s.len) }
}

pub fn (mut x Xdr) put_handle(h &FileHandle) {
	if h.len < 1 || h.len > 64 { x.bad = true; return }
	x.put_opaque(unsafe { &h.bytes[0] }, h.len, 64)
}

pub struct Stamp {
pub mut:
	sec u32
	nsec u32
}

pub struct Attr {
pub mut:
	kind u32
	mode u32
	nlink u32
	uid u32
	gid u32
	size u64
	used u64
	major u32
	minor u32
	fsid u64
	fileid u64
	atime Stamp
	mtime Stamp
	ctime Stamp
}

pub fn (mut x Xdr) stamp() Stamp {
	t := Stamp{x.u32(), x.u32()}
	if t.nsec >= 1000000000 { x.bad = true }
	return t
}

pub fn (mut x Xdr) attr(out &Attr) {
	unsafe {
		out.kind = x.u32(); out.mode = x.u32(); out.nlink = x.u32()
		out.uid = x.u32(); out.gid = x.u32(); out.size = x.u64(); out.used = x.u64()
		out.major = x.u32(); out.minor = x.u32(); out.fsid = x.u64(); out.fileid = x.u64()
		out.atime = x.stamp(); out.mtime = x.stamp(); out.ctime = x.stamp()
		if out.kind < 1 || out.kind > 7 || out.size > u64(0x7fffffffffffffff) || out.used > u64(0x7fffffffffffffff) { x.bad = true }
	}
}

pub fn (mut x Xdr) post_attr(out &Attr) bool {
	present := x.boolean()
	if present { x.attr(out) }
	return present
}

pub fn (mut x Xdr) wcc(out &Attr) bool {
	if x.boolean() { x.u64(); x.stamp(); x.stamp() }
	return x.post_attr(out)
}

pub fn component(s string) bool {
	if s.len < 1 || s.len > 255 || s == '.' || s == '..' { return false }
	for ch in s { if ch == 0 || ch == `/` { return false } }
	return true
}

pub struct Entry {
pub mut:
	name string // borrowed from RPC receive buffer until the next request
	fileid u64
	cookie u64
	attr Attr
	handle FileHandle
	has_attr bool
	has_handle bool
}

pub fn (mut x Xdr) entry(out &Entry) {
	unsafe {
		*out = Entry{}
		out.fileid = x.u64(); out.name = x.opaque(255); out.cookie = x.u64()
		if out.name.len == 0 { x.bad = true }
		for ch in out.name { if ch == 0 || ch == `/` { x.bad = true } }
		out.has_attr = x.post_attr(&out.attr)
		out.has_handle = x.boolean()
		if out.has_handle { x.handle(&out.handle) }
	}
}

// NFS statuses are not Linux errno values above the traditional range.
pub fn status_errno(status u32) int {
	return match status {
		0 { 0 }
		1 { 1 } 2 { 2 } 5 { 5 } 6 { 6 } 13 { 13 } 17 { 17 }
		18 { 18 } 19 { 19 } 20 { 20 } 21 { 21 } 22 { 22 }
		27 { 27 } 28 { 28 } 30 { 30 } 31 { 31 } 63 { 36 }
		66 { 39 } 69 { 122 } 70 { 116 } 71 { 66 }
		10001 { 116 } 10002 { 22 } 10003 { 22 } 10004 { 95 }
		10005 { 90 } 10006 { 5 } 10007 { 22 } 10008 { 11 }
		else { 5 }
	}
}
