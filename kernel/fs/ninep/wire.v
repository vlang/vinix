// SPDX-License-Identifier: GPL-2.0-or-later
// Allocation-free 9P2000.L framing. All offsets are checked by subtraction
// before indexing, copying, or narrowing to int. Shared by kernel and host tests.
module ninep

pub const max_msize = u32(65536)
pub const min_msize = u32(4096)
pub const max_name = 255
pub const max_fids = 2048
pub const max_nodes = 1024
pub const max_depth = 32
pub const notag = u16(0xffff)
pub const nofid = u32(0xffffffff)
pub const eio = 5
pub const einval = 22
pub const eoverflow = 75
pub const eproto = 71
pub const enospc = 28
pub const enotsup = 95
pub const tversion = u8(100)
pub const tattach = u8(104)
pub const twalk = u8(110)
pub const tread = u8(116)
pub const twrite = u8(118)
pub const tclunk = u8(120)
pub const tlopen = u8(12)
pub const tlcreate = u8(14)
pub const tgetattr = u8(24)
pub const tsetattr = u8(26)
pub const treaddir = u8(40)
pub const tfsync = u8(50)
pub const tmkdir = u8(72)
pub const trenameat = u8(74)
pub const tunlinkat = u8(76)

pub struct Reader {
pub mut:
	data   &u8 = unsafe { nil }
	length u32
	pos    u32
	ok     bool
}

pub fn reader(data &u8, length u32) Reader {
	return Reader{ data: data, length: length, ok: data != unsafe { nil } && length <= max_msize }
}

pub fn (mut r Reader) take(n u32) bool {
	if !r.ok || r.pos > r.length || n > r.length - r.pos {
		r.ok = false
		return false
	}
	r.pos += n
	return true
}

pub fn (mut r Reader) byte() u8 {
	if !r.take(1) { return 0 }
	return unsafe { r.data[r.pos - 1] }
}

pub fn (mut r Reader) word() u16 {
	lo := r.byte()
	hi := r.byte()
	return u16(lo) | (u16(hi) << 8)
}

pub fn (mut r Reader) dword() u32 {
	lo := r.word()
	hi := r.word()
	return u32(lo) | (u32(hi) << 16)
}

pub fn (mut r Reader) qword() u64 {
	lo := r.dword()
	hi := r.dword()
	return u64(lo) | (u64(hi) << 32)
}

pub fn (r &Reader) done() bool { return r.ok && r.pos == r.length }

pub struct Writer {
pub mut:
	data     &u8 = unsafe { nil }
	capacity u32
	pos      u32
	ok       bool
}

pub fn writer(data &u8, capacity u32, kind u8, tag u16) Writer {
	mut w := Writer{ data: data, capacity: capacity, ok: data != unsafe { nil } && capacity >= 7 && capacity <= max_msize }
	w.dword(0)
	w.byte(kind)
	w.word(tag)
	return w
}

pub fn (mut w Writer) byte(value u8) {
	if !w.ok || w.pos >= w.capacity {
		w.ok = false
		return
	}
	unsafe { w.data[w.pos] = value }
	w.pos++
}

pub fn (mut w Writer) word(value u16) {
	w.byte(u8(value))
	w.byte(u8(value >> 8))
}

pub fn (mut w Writer) dword(value u32) {
	w.word(u16(value))
	w.word(u16(value >> 16))
}

pub fn (mut w Writer) qword(value u64) {
	w.dword(u32(value))
	w.dword(u32(value >> 32))
}

pub fn (mut w Writer) raw(data &u8, length u32) {
	if !w.ok || w.pos > w.capacity || length > w.capacity - w.pos
		|| (length != 0 && data == unsafe { nil }) {
		w.ok = false
		return
	}
	for i := u32(0); i < length; i++ {
		unsafe { w.data[w.pos + i] = data[i] }
	}
	w.pos += length
}

pub fn (mut w Writer) text(value string) {
	if value.len < 0 || value.len > 65535 {
		w.ok = false
		return
	}
	w.word(u16(value.len))
	w.raw(value.str, u32(value.len))
}

pub fn (mut w Writer) finish() u32 {
	if !w.ok || w.pos < 7 { return 0 }
	for i in 0 .. 4 {
		unsafe { w.data[i] = u8(w.pos >> (i * 8)) }
	}
	return w.pos
}

// The transport's used length must describe exactly one frame. A short used
// length cannot expose stale DMA bytes from the preceding request.
pub fn reply(data &u8, length u32, msize u32, kind u8, tag u16, out &Reader) int {
	if length < 7 || length > max_msize || length > msize || msize < min_msize { return eproto }
	mut r := reader(data, length)
	declared := r.dword()
	actual_kind := r.byte()
	actual_tag := r.word()
	if !r.ok || declared != length || actual_tag != tag { return eproto }
	if actual_kind == 7 {
		code := r.dword()
		if !r.done() || code == 0 || code > 4095 { return eproto }
		return int(code)
	}
	// Rerror is not a legal Linux dialect reply; do not allocate its string.
	if actual_kind != kind + 1 { return eproto }
	unsafe { *out = r }
	return 0
}

pub struct Qid {
pub mut:
	kind    u8
	version u32
	path    u64
}

pub fn (mut r Reader) qid() Qid {
	return Qid{ kind: r.byte(), version: r.dword(), path: r.qword() }
}

pub struct Attr {
pub mut:
	valid      u64
	qid        Qid
	mode       u32
	uid        u32
	gid        u32
	nlink      u64
	rdev       u64
	size       u64
	blksize    u64
	blocks     u64
	atime_sec  u64
	atime_nsec u64
	mtime_sec  u64
	mtime_nsec u64
	ctime_sec  u64
	ctime_nsec u64
}

pub fn parse_attr(mut r Reader, out &Attr) bool {
	mut a := Attr{}
	a.valid = r.qword()
	a.qid = r.qid()
	a.mode = r.dword()
	a.uid = r.dword()
	a.gid = r.dword()
	a.nlink = r.qword()
	a.rdev = r.qword()
	a.size = r.qword()
	a.blksize = r.qword()
	a.blocks = r.qword()
	a.atime_sec = r.qword()
	a.atime_nsec = r.qword()
	a.mtime_sec = r.qword()
	a.mtime_nsec = r.qword()
	a.ctime_sec = r.qword()
	a.ctime_nsec = r.qword()
	// btime, generation, data_version. Required wire fields even when invalid.
	for _ in 0 .. 4 { r.qword() }
	if !r.done() || a.valid & 0x7ff != 0x7ff || a.size > 0x7fffffffffffffff
		|| a.blocks > 0x7fffffffffffffff || a.blksize > max_msize
		|| a.atime_sec > 0x7fffffffffffffff || a.mtime_sec > 0x7fffffffffffffff
		|| a.ctime_sec > 0x7fffffffffffffff || a.atime_nsec >= 1000000000
		|| a.mtime_nsec >= 1000000000 || a.ctime_nsec >= 1000000000 {
		return false
	}
	kind := a.mode & 0xf000
	if kind != 0x4000 && kind != 0x8000 && kind != 0xa000 && kind != 0x6000
		&& kind != 0x2000 && kind != 0x1000 && kind != 0xc000 {
		return false
	}
	if (a.qid.kind & 0x80 != 0) != (kind == 0x4000) { return false }
	unsafe { *out = a }
	return true
}

pub struct DirEntry {
pub mut:
	qid    Qid
	offset u64
	kind   u8
	length u16
	name   [256]u8
}

pub fn valid_name(name string) bool {
	if name.len == 0 || name.len > max_name || name == '.' || name == '..' { return false }
	for c in name { if c == 0 || c == `/` { return false } }
	return true
}

// No heap-backed strings or lists. The caller supplies one reusable entry.
pub fn next_entry(mut r Reader, previous u64, out &DirEntry) bool {
	if !r.ok || r.pos >= r.length { return false }
	mut entry := DirEntry{}
	entry.qid = r.qid()
	entry.offset = r.qword()
	entry.kind = r.byte()
	entry.length = r.word()
	if !r.ok || entry.length == 0 || entry.length > max_name || entry.offset == previous
		|| !r.take(entry.length) {
		r.ok = false
		return false
	}
	start := r.pos - entry.length
	for i in 0 .. int(entry.length) {
		c := unsafe { r.data[start + u32(i)] }
		if c == 0 || c == `/` {
			r.ok = false
			return false
		}
		entry.name[i] = c
	}
	unsafe { *out = entry }
	return true
}

// Validate count before exposing data. Consumers can then copy exactly count.
pub fn payload(mut r Reader, requested u32, offset &u32, count &u32) bool {
	n := r.dword()
	start := r.pos
	if n > requested || !r.take(n) || !r.done() { return false }
	unsafe {
		*offset = start
		*count = n
	}
	return true
}

pub fn valid_range(offset u64, length u64) bool {
	return offset <= 0x7fffffffffffffff && length <= u64(0x7fffffffffffffff) - offset
}
