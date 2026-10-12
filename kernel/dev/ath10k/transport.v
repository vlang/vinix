// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// QCA6174/QCA9377 copy-engine and BMI protocol, adapted from Linux ath10k.
module ath10k

pub struct Hardware {
pub:
	cookie  voidptr
	read    fn (voidptr, u32) u32  = unsafe { nil }
	write   fn (voidptr, u32, u32) = unsafe { nil }
	clock   fn (voidptr) u64       = unsafe { nil }
	delay   fn (voidptr, u32)      = unsafe { nil }
	barrier fn ()                  = unsafe { nil }
}

struct Engine {
mut:
	source      u32
	destination u32
	tx_data     u32
	rx_data     u32
	tx_count    u32
	rx_count    u32
	size        u32
	tx_write    u32
	rx_read     u32
	rx_write    u32
}

pub struct Transport {
pub mut:
	hardware Hardware
	pool     Blob
	bus      u32
	engines  [8]Engine
	fault    bool
}

const transport_bytes = u32(512 * 1024)

fn put16(p &u8, offset u32, n u16) {
	unsafe {
		p[offset] = u8(n)
		p[offset + 1] = u8(n >> 8)
	}
}

fn put32(p &u8, offset u32, n u32) {
	unsafe {
		for i in 0 .. 4 { p[offset + u32(i)] = u8(n >> (i * 8)) }
	}
}

fn (t &Transport) read(offset u32) u32 { return t.hardware.read(t.hardware.cookie, offset) }

fn (t &Transport) write(offset u32, value u32) {
	t.hardware.write(t.hardware.cookie, offset, value)
}

fn (t &Transport) now() u64 { return t.hardware.clock(t.hardware.cookie) }

fn (t &Transport) delay(us u32) { t.hardware.delay(t.hardware.cookie, us) }

fn (t &Transport) barrier() { t.hardware.barrier() }

fn (t &Transport) wait(offset u32, mask u32, expected u32, ms u32) bool {
	start := t.now()
	for {
		value := t.read(offset)
		if value != 0xffffffff && value & mask == expected { return true }
		if t.now() - start >= u64(ms) * 1000000 { return false }
		t.delay(100)
	}
	return false
}

fn ce_base(id u32) u32 { return 0x34400 + id * 0x400 }

// The pool must be coherent, mapped for this PCI device, below 4 GiB and
// remain owned until bus mastering has stopped. No allocations occur here.
pub fn (mut t Transport) layout() bool {
	if t.pool.data == unsafe { nil } || t.pool.len < transport_bytes
		|| t.bus & 0xfff != 0 || u64(t.bus) + t.pool.len > u64(1) << 32
		|| t.hardware.read == unsafe { nil } || t.hardware.write == unsafe { nil }
		|| t.hardware.clock == unsafe { nil } || t.hardware.delay == unsafe { nil }
		|| t.hardware.barrier == unsafe { nil } {
		return false
	}
	mut offset := u32(0)
	for id in 0 .. 8 {
		tx := match id {
			0 { u32(16) }
			3 { u32(32) }
			4 { u32(128) }
			7 { u32(2) }
			else { u32(0) }
		}
		rx := match id {
			1, 2 { u32(64) }
			7 { u32(2) }
			else { u32(0) }
		}
		size := if id == 0 || id == 4 {
			u32(256)
		} else if id == 7 {
			u32(8192)
		} else {
			u32(2048)
		}
		offset = (offset + 255) & ~u32(255)
		mut e := Engine{ source: offset, tx_count: tx, rx_count: rx, size: size }
		offset += tx * 8
		e.destination = offset
		offset += rx * 8
		offset = (offset + 255) & ~u32(255)
		e.tx_data = offset
		offset += tx * size
		e.rx_data = offset
		offset += rx * size
		if offset > t.pool.len { return false }
		t.engines[id] = e
	}
	return true
}

pub fn (mut t Transport) initialise_engines() {
	for id in u32(0) .. 8 {
		mut e := &t.engines[id]
		base := ce_base(id)
		t.write(base + 0x2c, 0)
		t.write(base + 0x34, 0)
		t.write(base + 0x30, 0x1f)
		t.write(base + 0x38, 0x7e0)
		if e.tx_count != 0 {
			for n in u32(0) .. e.tx_count * 8 {
				unsafe { t.pool.data[e.source + n] = 0 }
			}
			t.write(base, t.bus + e.source)
			t.write(base + 4, e.tx_count)
		}
		if e.rx_count != 0 {
			for n in u32(0) .. e.rx_count * 8 {
				unsafe { t.pool.data[e.destination + n] = 0 }
			}
			t.write(base + 8, t.bus + e.destination)
			t.write(base + 12, e.rx_count)
		}
		t.write(base + 0x10, e.size & 0xffff) // little-endian ring descriptors
		e.tx_write = 0
		e.rx_read = 0
		e.rx_write = 0
		t.write(base + 0x3c, 0)
		t.write(base + 0x40, 0)
	}
	// CE7 is exclusively used for explicit diagnostic source/destination
	// transfers. Post the normal target-to-host CE receive buffers instead.
	for id in [u32(1), 2]! {
		e := t.engines[id]
		for slot in u32(0) .. e.rx_count - 1 {
			t.post_receive(id, t.bus + e.rx_data + slot * e.size)
		}
	}
	t.fault = false
}

fn (mut t Transport) post_receive(id u32, address u32) {
	mut e := &t.engines[id]
	desc := unsafe { t.pool.data + e.destination + e.rx_write * 8 }
	put32(desc, 0, address)
	put32(desc, 4, 0)
	t.barrier()
	e.rx_write = (e.rx_write + 1) & (e.rx_count - 1)
	t.write(ce_base(id) + 0x40, e.rx_write)
}

fn (mut t Transport) submit_address(id u32, address u32, size u32, flags u16) bool {
	mut e := &t.engines[id]
	if t.fault || e.tx_count == 0 || size == 0 || size > e.size { return false }
	read := t.read(ce_base(id) + 0x44)
	if read >= e.tx_count {
		t.fault = true
		return false
	}
	next := (e.tx_write + 1) & (e.tx_count - 1)
	if next == read { return false }
	desc := unsafe { t.pool.data + e.source + e.tx_write * 8 }
	put32(desc, 0, address)
	put16(desc, 4, u16(size))
	put16(desc, 6, flags)
	t.barrier()
	e.tx_write = next
	t.write(ce_base(id) + 0x3c, next)
	return true
}

pub fn (mut t Transport) submit(id u32, b Blob) bool {
	if id >= 8 || b.data == unsafe { nil } { return false }
	e := t.engines[id]
	if b.len == 0 || b.len > e.size || e.tx_count == 0 { return false }
	read := t.read(ce_base(id) + 0x44)
	if read >= e.tx_count {
		t.fault = true
		return false
	}
	if (e.tx_write + 1) & (e.tx_count - 1) == read { return false }
	offset := e.tx_data + e.tx_write * e.size
	for i in u32(0) .. b.len {
		unsafe { t.pool.data[offset + i] = b.data[i] }
	}
	return t.submit_address(id, t.bus + offset, b.len, 0)
}

pub fn (mut t Transport) receive(id u32) ?Blob {
	if id >= 8 || t.fault { return none }
	e := t.engines[id]
	if e.rx_count == 0 { return none }
	desc := t.pool.view(e.destination + e.rx_read * 8, 8)
	t.barrier()
	size := desc.word(4) & 0xffff
	if size == 0 { return none }
	address := desc.word(0)
	if size > e.size || address < t.bus + e.rx_data
		|| address - t.bus - e.rx_data >= e.rx_count * e.size
		|| (address - t.bus - e.rx_data) % e.size != 0 {
		t.fault = true
		return none
	}
	t.barrier()
	return t.pool.view(address - t.bus, size)
}

pub fn (mut t Transport) release_receive(id u32) {
	mut e := &t.engines[id]
	desc := t.pool.view(e.destination + e.rx_read * 8, 8)
	address := desc.word(0)
	put32(desc.data, 4, 0)
	e.rx_read = (e.rx_read + 1) & (e.rx_count - 1)
	t.post_receive(id, address)
}

// BMI owns CE0 and CE1 until DONE. A timeout poisons the transport: none of
// the DMA buffers can be reused until a complete reset/quiesce has succeeded.
pub fn (mut t Transport) bmi(request Blob, expected u32) ?Blob {
	if expected > 2048 || !t.submit(0, request) { return none }
	start := t.now()
	for {
		if t.fault { return none }
		sent := t.read(ce_base(0) + 0x44) == t.engines[0].tx_write
		if sent {
			if expected == 0 { return Blob{} }
			if reply := t.receive(1) {
				if reply.len < expected {
					t.fault = true
					return none
				}
				return reply
			}
		}
		if t.now() - start >= 2 * u64(1000000000) {
			t.fault = true
			return none
		}
		t.delay(100)
	}
	return none
}

pub fn (mut t Transport) bmi_word(command u32, address u32, value u32) ?u32 {
	mut bytes := [16]u8{}
	put32(unsafe { &bytes[0] }, 0, command)
	put32(unsafe { &bytes[0] }, 4, address)
	put32(unsafe { &bytes[0] }, 8, if command == 2 || command == 3 { u32(4) } else { value })
	put32(unsafe { &bytes[0] }, 12, value)
	length := match command {
		8 { u32(4) }
		6, 13 { u32(8) }
		3 { u32(16) }
		else { u32(12) }
	}
	expected := if command == 2 || command == 4 || command == 6 {
		u32(4)
	} else if command == 8 {
		u32(12)
	} else {
		u32(0)
	}
	reply := t.bmi(Blob{ data: unsafe { &bytes[0] }, len: length }, expected) or { return none }
	if expected != 0 {
		result := reply.word(if command == 8 { u32(4) } else { u32(0) })
		t.release_receive(1)
		return result
	}
	return u32(0)
}

pub fn (mut t Transport) bmi_write(address u32, b Blob) bool {
	mut position := u32(0)
	for position < b.len {
		mut bytes := [256]u8{}
		remaining := b.len - position
		size := if remaining < 244 { remaining } else { u32(244) }
		padded := (size + 3) & ~u32(3)
		put32(unsafe { &bytes[0] }, 0, 3)
		put32(unsafe { &bytes[0] }, 4, address + position)
		put32(unsafe { &bytes[0] }, 8, padded)
		for i in u32(0) .. size { bytes[12 + i] = unsafe { b.data[position + i] } }
		t.bmi(Blob{ data: unsafe { &bytes[0] }, len: 12 + padded }, 0) or { return false }
		position += size
	}
	return true
}

pub fn (mut t Transport) download(address u32, b Blob) bool {
	t.bmi_word(13, address, 0) or { return false }
	mut position := u32(0)
	for position < b.len {
		mut bytes := [256]u8{}
		remaining := b.len - position
		size := if remaining < 248 { remaining } else { u32(248) }
		padded := (size + 3) & ~u32(3)
		put32(unsafe { &bytes[0] }, 0, 14)
		put32(unsafe { &bytes[0] }, 4, padded)
		for i in u32(0) .. size { bytes[8 + i] = unsafe { b.data[position + i] } }
		t.bmi(Blob{ data: unsafe { &bytes[0] }, len: 8 + padded }, 0) or { return false }
		position += size
	}
	t.bmi_word(13, 0, 0) or { return false }
	return true
}

// Diagnostic CE7 reaches target RAM before the bootloader starts accepting
// BMI commands. Its address translation differs below and above 1 MiB.
pub fn (mut t Transport) diagnostic(address u32, writing bool, value u32) ?u32 {
	if t.fault || address & 3 != 0 || address >= 0x500000 { return none }
	mut e := &t.engines[7]
	translated := ((t.read(0x3a000) & 0x7ff) << 21) | (address & 0xfffff) |
		if address >= 0x100000 { u32(0x100000) } else { u32(0) }
	put32(t.pool.data, e.tx_data, value)
	t.post_receive(7, if writing { translated } else { t.bus + e.rx_data })
	if !t.submit_address(7, if writing { t.bus + e.tx_data } else { translated }, 4, 0) {
		return none
	}
	start := t.now()
	for {
		desc := t.pool.view(e.destination + e.rx_read * 8, 8)
		t.barrier()
		if t.read(ce_base(7) + 0x44) == e.tx_write && desc.word(4) & 0xffff == 4 {
			t.barrier()
			result := t.pool.word(e.rx_data)
			put32(desc.data, 4, 0)
			e.rx_read = (e.rx_read + 1) & 1
			return result
		}
		if t.now() - start >= 2 * u64(1000000000) {
			t.fault = true
			return none
		}
		t.delay(100)
	}
	return none
}
