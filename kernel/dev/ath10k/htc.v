// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
module ath10k

pub struct Protocol {
pub mut:
	transport          Transport
	ready              bool
	setup              bool
	credit_size        u16
	credit_count       u16
	credits            [9]u16
	sequence           [9]u8
	wmi                u8
	htt                u8
	connected_service  u16
	connected_endpoint u8
	connected_status   u8
	context            voidptr
	event              fn (voidptr, u8, Blob) = unsafe { nil }
}

fn half(b Blob, offset u32) u16 {
	unsafe {
		return u16(b.data[offset]) | u16(b.data[offset + 1]) << 8
	}
}

pub fn (mut p Protocol) send(endpoint u8, data Blob) bool {
	if p.transport.fault || endpoint >= 9 || data.len > 2040 { return false }
	engine := if endpoint == 0 {
		u32(0)
	} else if endpoint == p.wmi {
		u32(3)
	} else if endpoint == p.htt {
		u32(4)
	} else {
		return false
	}
	if engine != 3 && data.len > 248 { return false }
	mut charge := u16(0)
	if endpoint == p.wmi && endpoint != 0 {
		if p.credit_size == 0 { return false }
		charge = u16((data.len + 8 + p.credit_size - 1) / p.credit_size)
		if charge > p.credits[endpoint] { return false }
	}
	mut packet := [2048]u8{}
	packet[0] = endpoint
	packet[1] = if charge != 0 { u8(1) } else { u8(0) }
	put16(unsafe { &packet[0] }, 2, u16(data.len))
	packet[5] = p.sequence[endpoint]
	for i in u32(0) .. data.len { packet[8 + i] = unsafe { data.data[i] } }
	if !p.transport.submit(engine, Blob{ data: unsafe { &packet[0] }, len: data.len + 8 }) {
		return false
	}
	p.sequence[endpoint]++
	p.credits[endpoint] -= charge
	return true
}

fn (mut p Protocol) frame(b Blob) {
	if b.len < 8 {
		p.transport.fault = true
		return
	}
	endpoint := unsafe { b.data[0] }
	flags := unsafe { b.data[1] }
	mut length := u32(half(b, 2))
	if endpoint >= 9 || length > b.len - 8 {
		p.transport.fault = true
		return
	}
	if flags & 2 != 0 {
		trailer := u32(unsafe { b.data[4] })
		if trailer > length || trailer < 4 {
			p.transport.fault = true
			return
		}
		length -= trailer
		mut offset := u32(8) + length
		end := offset + trailer
		for offset < end {
			if end - offset < 4 {
				p.transport.fault = true
				return
			}
			kind := unsafe { b.data[offset] }
			size := u32(unsafe { b.data[offset + 1] })
			offset += 4
			if size > end - offset {
				p.transport.fault = true
				return
			}
			if kind == 1 {
				if size % 4 != 0 {
					p.transport.fault = true
					return
				}
				for n := u32(0); n < size; n += 4 {
					id := unsafe { b.data[offset + n] }
					count := u16(unsafe { b.data[offset + n + 1] })
					if id >= 9 || u32(p.credits[id]) + count > p.credit_count {
						p.transport.fault = true
						return
					}
					p.credits[id] += count
				}
			}
			offset += size
		}
	}
	if length == 0 { return }
	data := b.view(8, length)
	if endpoint == 0 {
		if length < 2 {
			p.transport.fault = true
			return
		}
		match half(data, 0) {
			1 {
				if length < 8 || p.ready {
					p.transport.fault = true
					return
				}
				p.credit_count = half(data, 2)
				p.credit_size = half(data, 4)
				if p.credit_count == 0 || p.credit_count > 255 || p.credit_size == 0 {
					p.transport.fault = true
					return
				}
				p.ready = true
			}
			3 {
				if length < 8 {
					p.transport.fault = true
					return
				}
				p.connected_service = half(data, 2)
				p.connected_status = unsafe { data.data[4] }
				p.connected_endpoint = unsafe { data.data[5] }
			}
			else {}
		}
	} else if p.event != unsafe { nil } {
		p.event(p.context, endpoint, data)
	}
}

pub fn (mut p Protocol) poll() {
	if p.transport.fault { return }
	for engine in [u32(1), 2]! {
		for _ in 0 .. 64 {
			packet := p.transport.receive(engine) or { break }
			p.frame(packet)
			if p.transport.fault { return }
			p.transport.release_receive(engine)
		}
	}
}

pub fn (mut p Protocol) wait_ready() bool {
	start := p.transport.now()
	for !p.ready && !p.transport.fault {
		p.poll()
		if p.transport.now() - start >= 3 * u64(1000000000) { return false }
		p.transport.delay(100)
	}
	return p.ready && !p.transport.fault
}

pub fn (mut p Protocol) connect(service u16) ?u8 {
	if !p.ready || p.setup || (service != 0x100 && service != 0x300) { return none }
	mut bytes := [8]u8{}
	put16(unsafe { &bytes[0] }, 0, 2)
	put16(unsafe { &bytes[0] }, 2, service)
	put16(unsafe { &bytes[0] }, 4, if service == 0x100 { p.credit_count << 8 } else { u16(8) })
	p.connected_service = 0
	if !p.send(0, Blob{ data: unsafe { &bytes[0] }, len: 8 }) { return none }
	start := p.transport.now()
	for p.connected_service == 0 && !p.transport.fault {
		p.poll()
		if p.transport.now() - start >= 3 * u64(1000000000) { return none }
		p.transport.delay(100)
	}
	if p.transport.fault || p.connected_service != service || p.connected_status != 0
		|| p.connected_endpoint == 0 || p.connected_endpoint >= 9 {
		return none
	}
	id := p.connected_endpoint
	if service == 0x100 {
		p.wmi = id
		p.credits[id] = p.credit_count
	} else {
		p.htt = id
	}
	return id
}

pub fn (mut p Protocol) finish_setup() bool {
	mut bytes := [12]u8{}
	put16(unsafe { &bytes[0] }, 0, 5)
	if p.wmi == 0 || p.htt == 0 || p.wmi == p.htt || !p.send(0, Blob{ data: unsafe { &bytes[0] }, len: 12 }) {
		return false
	}
	p.setup = true
	return true
}
