// SPDX-License-Identifier: GPL-2.0-or-later
module nfs

// Kernel adapter supplies exact nonblocking transfers under ONE absolute
// deadline for an entire call (including every record fragment).
pub type Transfer = fn (voidptr, &u8, int, bool) bool
pub type Begin = fn (voidptr)

pub struct Client {
pub mut:
	context voidptr
	transfer Transfer = unsafe { nil }
	begin Begin = unsafe { nil }
	tx &u8 = unsafe { nil } // capacity+4 bytes, includes outbound record marker
	rx &u8 = unsafe { nil } // capacity bytes
	xid u32 = 1
	uid u32
	gid u32
	groups [16]u32
	group_count int
	dead bool
	fault int
	status u32
	ro bool
	rsize int = io_max
	wsize int = io_max
}

pub fn (mut c Client) poison(code int) {
	c.dead = true
	c.fault = code
}

pub fn (mut c Client) request(program u32, version u32, procedure u32) Xdr {
	mut w := Xdr{p: unsafe { c.tx + 4 }, n: capacity}
	if c.dead { c.fault = 5; w.bad = true; return w }
	if c.group_count < 0 || c.group_count > 16 { w.bad = true; return w }
	w.put32(c.xid); w.put32(0); w.put32(2)
	w.put32(program); w.put32(version); w.put32(procedure)
	w.put32(1) // AUTH_SYS; hostname "vinix", no security claims
	w.put32(u32(28 + c.group_count * 4))
	w.put32(c.xid); w.text('vinix', 255); w.put32(c.uid); w.put32(c.gid)
	w.put32(u32(c.group_count))
	for i in 0 .. c.group_count { w.put32(c.groups[i]) }
	w.put32(0); w.put32(0) // AUTH_NONE verifier
	return w
}

// Bounded multi-fragment record receive. Empty fragments are legal but count
// toward the limit; a malicious peer cannot hold the caller in an endless loop.
pub fn (mut c Client) record() ?int {
	mut total := 0
	mut marker := [4]u8{}
	for _ in 0 .. max_fragments {
		if !c.transfer(c.context, unsafe { &marker[0] }, 4, false) { c.poison(110); return none }
		mut m := Xdr{p: unsafe { &marker[0] }, n: 4}
		header := m.u32()
		n := header & 0x7fffffff
		if n > u32(capacity - total) { c.poison(5); return none }
		if n > 0 && !c.transfer(c.context, unsafe { c.rx + total }, int(n), false) { c.poison(110); return none }
		total += int(n)
		if header & 0x80000000 != 0 { return total }
	}
	c.poison(5)
	return none
}

pub fn (mut c Client) call(w &Xdr) ?Xdr {
	if c.dead { c.fault = 5; return none }
	if w.bad || w.at < 40 || w.at > capacity { c.fault = 22; return none }
	if c.begin != unsafe { nil } { c.begin(c.context) }
	mut marker := Xdr{p: c.tx, n: 4}
	marker.put32(0x80000000 | u32(w.at))
	if !c.transfer(c.context, c.tx, w.at + 4, true) { c.poison(110); return none }
	n := c.record()?
	mut r := Xdr{p: c.rx, n: n}
	if r.u32() != c.xid || r.u32() != 1 { c.poison(5); return none }
	c.xid++
	if c.xid == 0 { c.xid = 1 }
	reply := r.u32()
	if reply == 1 {
		reason := r.u32()
		if reason == 0 { r.u32(); r.u32() } else if reason == 1 { r.u32() } else { r.bad = true }
		if !r.finished() { c.poison(5) } else { c.fault = if reason == 1 { 13 } else { 95 } }
		return none
	}
	if reply != 0 { c.poison(5); return none }
	flavor := r.u32()
	verifier := r.opaque(400)
	if flavor != 0 || verifier.len != 0 { r.bad = true }
	accepted := r.u32()
	if accepted != 0 {
		if accepted == 2 { r.u32(); r.u32() }
		if accepted > 5 || !r.finished() { c.poison(5) } else { c.fault = if accepted == 5 { 5 } else { 95 } }
		return none
	}
	if r.bad { c.poison(5); return none }
	c.fault = 0
	return r
}

pub fn (mut c Client) finish(r &Xdr, status u32) ? {
	if !r.finished() { c.poison(5); return none }
	c.status = status
	c.fault = status_errno(status)
	if status != 0 { return none }
}

pub fn (mut c Client) null() ? {
	w := c.request(100003, 3, 0)
	r := c.call(unsafe { &w })?
	c.finish(unsafe { &r }, 0)?
}

pub fn (mut c Client) getport(program u32, version u32) ?u16 {
	mut w := c.request(100000, 2, 3)
	w.put32(program); w.put32(version); w.put32(6); w.put32(0)
	mut r := c.call(unsafe { &w })?
	port := r.u32()
	c.finish(unsafe { &r }, 0)?
	if port == 0 || port > 65535 { c.fault = 111; return none }
	return u16(port)
}

pub fn (mut c Client) mount_export(path string, out &FileHandle) ? {
	mut w := c.request(100005, 3, 1)
	w.text(path, 1024)
	mut r := c.call(unsafe { &w })?
	s := r.u32()
	if s == 0 {
		r.handle(out)
		n := r.u32()
		if n > 32 { r.bad = true }
		mut sys := false
		if !r.bad { for _ in 0 .. int(n) { if r.u32() == 1 { sys = true } } }
		c.finish(unsafe { &r }, s)?
		if !sys {
			// Successful MNT registered a mount even when no usable flavor was
			// offered. Remove that registration before reporting unsupported auth.
			c.unmount_export(path) or {}
			c.fault = 95
			return none
		}
	} else { c.finish(unsafe { &r }, s)? }
}

pub fn (mut c Client) unmount_export(path string) ? {
	mut w := c.request(100005, 3, 3)
	w.text(path, 1024)
	r := c.call(unsafe { &w })?
	c.finish(unsafe { &r }, 0)?
}

// EXPORT response stays borrowed. Adapter logs each bounded path/group; no
// follow-up request may overwrite rx until it finishes walking this result.
pub fn (mut c Client) exports() ?Xdr {
	w := c.request(100005, 3, 5)
	return c.call(unsafe { &w })
}
