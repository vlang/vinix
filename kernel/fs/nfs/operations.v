// SPDX-License-Identifier: GPL-2.0-or-later
module nfs

fn (mut c Client) nfs_request(proc u32, h &FileHandle) Xdr {
	mut w := c.request(100003, 3, proc)
	w.put_handle(h)
	return w
}

fn (mut c Client) writable() bool {
	if c.ro { c.fault = 30; return false }
	return true
}

pub fn (mut c Client) getattr(h &FileHandle, out &Attr) ? {
	w := c.nfs_request(1, h)
	mut r := c.call(w)?
	s := r.u32()
	if s == 0 { r.attr(out) }
	c.finish(unsafe { &r }, s)?
}

pub struct SetAttr {
pub mut:
	mode_set bool
	mode u32
	uid_set bool
	uid u32
	gid_set bool
	gid u32
	size_set bool
	size u64
	atime_set bool
	atime Stamp
	mtime_set bool
	mtime Stamp
}

fn (mut w Xdr) put_set(a &SetAttr) {
	w.put32(u32(a.mode_set)); if a.mode_set { w.put32(a.mode & 0o7777) }
	w.put32(u32(a.uid_set)); if a.uid_set { w.put32(a.uid) }
	w.put32(u32(a.gid_set)); if a.gid_set { w.put32(a.gid) }
	w.put32(u32(a.size_set)); if a.size_set { w.put64(a.size) }
	w.put32(if a.atime_set { u32(2) } else { u32(0) })
	if a.atime_set { w.put32(a.atime.sec); w.put32(a.atime.nsec) }
	w.put32(if a.mtime_set { u32(2) } else { u32(0) })
	if a.mtime_set { w.put32(a.mtime.sec); w.put32(a.mtime.nsec) }
}

pub fn (mut c Client) setattr(h &FileHandle, a &SetAttr) ? {
	if !c.writable() { return none }
	if (a.size_set && a.size > u64(0x7fffffffffffffff)) || (a.atime_set && a.atime.nsec >= 1000000000) || (a.mtime_set && a.mtime.nsec >= 1000000000) { c.fault = 22; return none }
	mut w := c.nfs_request(2, h)
	w.put_set(a); w.put32(0) // no ctime guard
	mut r := c.call(w)?
	s := r.u32()
	mut post := Attr{}
	r.wcc(unsafe { &post })
	c.finish(unsafe { &r }, s)?
}

pub fn (mut c Client) lookup(dir &FileHandle, name string, h &FileHandle, a &Attr) ? {
	if !component(name) { c.fault = 22; return none }
	mut w := c.nfs_request(3, dir)
	w.text(name, 255)
	mut r := c.call(w)?
	s := r.u32()
	mut has_attr := false
	if s == 0 { r.handle(h); has_attr = r.post_attr(a) }
	mut parent := Attr{}
	r.post_attr(unsafe { &parent })
	c.finish(unsafe { &r }, s)?
	if !has_attr { c.getattr(h, a)? }
}

pub fn (mut c Client) access(h &FileHandle, requested u32) ?u32 {
	mut w := c.nfs_request(4, h)
	w.put32(requested & 63)
	mut r := c.call(w)?
	s := r.u32()
	mut a := Attr{}
	r.post_attr(unsafe { &a })
	allowed := if s == 0 { r.u32() } else { u32(0) }
	if allowed & ~requested != 0 { r.bad = true }
	c.finish(unsafe { &r }, s)?
	return allowed
}

pub fn (mut c Client) read(h &FileHandle, offset u64, out &u8, count int) ?int {
	if count < 0 || count > c.rsize || count > io_max || offset > u64(0x7fffffffffffffff) - u64(count) { c.fault = 22; return none }
	mut w := c.nfs_request(6, h)
	w.put64(offset); w.put32(u32(count))
	mut r := c.call(w)?
	s := r.u32()
	mut a := Attr{}
	r.post_attr(unsafe { &a })
	mut data := ''
	if s == 0 {
		n := r.u32()
		eof := r.boolean()
		data = r.opaque(count)
		if n != u32(data.len) || (n == 0 && count > 0 && !eof) { r.bad = true }
	}
	c.finish(unsafe { &r }, s)?
	copy_bytes(out, data.str, data.len)
	return data.len
}

pub fn (mut c Client) write(h &FileHandle, offset u64, data &u8, count int) ?int {
	if !c.writable() { return none }
	if count < 0 || count > c.wsize || count > io_max || offset > u64(0x7fffffffffffffff) - u64(count) { c.fault = 22; return none }
	mut w := c.nfs_request(7, h)
	w.put64(offset); w.put32(u32(count)); w.put32(2) // FILE_SYNC
	w.put_opaque(data, count, io_max)
	mut r := c.call(w)?
	s := r.u32()
	mut a := Attr{}
	r.wcc(unsafe { &a })
	mut n := u32(0)
	if s == 0 {
		n = r.u32()
		stable := r.u32()
		r.u64() // write verifier; no unstable data is retained
		if n > u32(count) || (n == 0 && count > 0) || stable != 2 { r.bad = true }
	}
	c.finish(unsafe { &r }, s)?
	return int(n)
}

pub fn (mut c Client) create(dir &FileHandle, name string, mode u32, directory bool, h &FileHandle, a &Attr) ? {
	if !c.writable() { return none }
	if !component(name) { c.fault = 22; return none }
	mut w := c.nfs_request(if directory { u32(9) } else { u32(8) }, dir)
	w.text(name, 255)
	if !directory { w.put32(1) } // GUARDED: never truncate an existing file
	attributes := SetAttr{mode_set: true, mode: mode}
	w.put_set(unsafe { &attributes })
	mut r := c.call(w)?
	s := r.u32()
	mut has_handle := false
	mut has_attr := false
	if s == 0 {
		has_handle = r.boolean()
		if has_handle { r.handle(h) }
		has_attr = r.post_attr(a)
	}
	mut parent := Attr{}
	r.wcc(unsafe { &parent })
	c.finish(unsafe { &r }, s)?
	if !has_handle { c.lookup(dir, name, h, a)? } else if !has_attr { c.getattr(h, a)? }
}

pub fn (mut c Client) remove(dir &FileHandle, name string, directory bool) ? {
	if !c.writable() { return none }
	if !component(name) { c.fault = 22; return none }
	mut w := c.nfs_request(if directory { u32(13) } else { u32(12) }, dir)
	w.text(name, 255)
	mut r := c.call(w)?
	s := r.u32()
	mut parent := Attr{}
	r.wcc(unsafe { &parent })
	c.finish(unsafe { &r }, s)?
}

pub fn (mut c Client) rename(from &FileHandle, old string, to &FileHandle, name string) ? {
	if !c.writable() { return none }
	if !component(old) || !component(name) { c.fault = 22; return none }
	mut w := c.nfs_request(14, from)
	w.text(old, 255); w.put_handle(to); w.text(name, 255)
	mut r := c.call(w)?
	s := r.u32()
	mut parent := Attr{}
	r.wcc(unsafe { &parent }); r.wcc(unsafe { &parent })
	c.finish(unsafe { &r }, s)?
}

// Entire page is validated before the adapter publishes any entry. Cookie
// values are opaque: equality/cycle detection, never numeric ordering.
pub fn (mut c Client) readdirplus(h &FileHandle, cookie u64, verifier u64, new_verifier &u64, eof &bool) ?Xdr {
	mut w := c.nfs_request(17, h)
	w.put64(cookie); w.put64(verifier); w.put32(8192); w.put32(32768)
	mut r := c.call(w)?
	s := r.u32()
	mut a := Attr{}
	r.post_attr(unsafe { &a })
	if s != 0 { c.finish(unsafe { &r }, s)?; return none }
	v := r.u64()
	start := r.at
	mut entry := Entry{}
	mut last := cookie
	mut count := 0
	for r.boolean() {
		if r.bad || count >= max_entries { r.bad = true; break }
		r.entry(unsafe { &entry })
		if entry.cookie == 0 || entry.cookie == last { r.bad = true }
		last = entry.cookie
		count++
	}
	end := r.boolean()
	if count == 0 && !end { r.bad = true }
	if cookie != 0 && v != verifier { r.bad = true }
	c.finish(unsafe { &r }, 0)?
	unsafe { *new_verifier = v; *eof = end }
	r.at = start
	return r
}

pub struct FsInfo {
pub mut:
	total u64
	free u64
	available u64
	files u64
	ffree u64
	favailable u64
	invariant u32
}

pub fn (mut c Client) fsstat(h &FileHandle, out &FsInfo) ? {
	w := c.nfs_request(18, h)
	mut r := c.call(w)?
	s := r.u32()
	mut a := Attr{}
	r.post_attr(unsafe { &a })
	if s == 0 {
		unsafe { out.total = r.u64(); out.free = r.u64(); out.available = r.u64(); out.files = r.u64(); out.ffree = r.u64(); out.favailable = r.u64(); out.invariant = r.u32() }
	}
	c.finish(unsafe { &r }, s)?
}

pub struct PathConf {
pub mut:
	linkmax u32
	namemax u32
	no_trunc bool
	chown_restricted bool
	case_insensitive bool
	case_preserving bool
}

pub fn (mut c Client) pathconf(h &FileHandle, out &PathConf) ? {
	w := c.nfs_request(20, h)
	mut r := c.call(w)?
	s := r.u32()
	mut a := Attr{}
	r.post_attr(unsafe { &a })
	if s == 0 {
		unsafe { out.linkmax = r.u32(); out.namemax = r.u32(); out.no_trunc = r.boolean(); out.chown_restricted = r.boolean(); out.case_insensitive = r.boolean(); out.case_preserving = r.boolean() }
		if out.namemax == 0 { r.bad = true }
	}
	c.finish(unsafe { &r }, s)?
}
