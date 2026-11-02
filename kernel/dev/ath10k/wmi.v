// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// The QCA9377 firmware uses WMI TLV ABI 1.0, namespace QCA_/ML.
module ath10k

fn C.__builtin_alloca(uint) voidptr

struct Command {
mut:
	data [2048]u8
	len  u32 = 4
}

fn (mut c Command) header(id u32) { put32(unsafe { &c.data[0] }, 0, id) }

fn (mut c Command) section(tag u16, size u32) ?Blob {
	if size > 65535 || c.len > 2044 || size > 2044 - c.len { return none }
	put16(unsafe { &c.data[0] }, c.len, u16(size))
	put16(unsafe { &c.data[0] }, c.len + 2, tag)
	view := Blob{ data: unsafe { &c.data[0] + c.len + 4 }, len: size }
	c.len += 4 + size
	return view
}

fn (c &Command) blob() Blob { return Blob{ data: unsafe { &c.data[0] }, len: c.len } }

pub fn find_tlv(b Blob, wanted u16) ?Blob {
	mut position := u32(0)
	mut found := Blob{}
	mut seen := false
	for position < b.len {
		if b.len - position < 4 { return none }
		size := u32(half(b, position))
		tag := half(b, position + 2)
		position += 4
		if size > b.len - position { return none }
		if tag == wanted {
			if seen { return none }
			found = b.view(position, size)
			seen = true
		}
		position += size
	}
	if !seen { return none }
	return found
}

pub struct Network {
pub mut:
	ssid            [32]u8
	ssid_len        u8
	bssid           [6]u8
	channel         u16
	rssi            i16
	secure          bool
	capabilities    u16
	beacon_interval u16
	rates           [16]u8
	rate_count      u8
	rsn             [96]u8
	rsn_len         u8
}

struct MemoryChunk {
mut:
	id      u32
	address u32
	size    u32
}

pub struct Wmi {
pub mut:
	service_ready bool
	init_sent     bool
	ready         bool
	vdev          bool
	mac           [6]u8
	full_reorder  bool
	chunks        [16]MemoryChunk
	chunk_count   u32
	low2          u32
	high2         u32
	low5          u32
	high5         u32
	scanning      bool
	scan_id       u32
	scan_deadline u64
	scan_error    int
	networks      [32]Network
	network_count int
	started       bool
	start_status  u32
	echo_token    u32
	link_lost     bool
	context       voidptr
	management    fn (voidptr, Blob) = unsafe { nil }
}

fn service_bit(b Blob, bit u32) bool {
	// WMI's original service bitmap stores four service bits per u32.
	return bit < b.len && b.word((bit / 4) * 4) & (u32(1) << (bit % 4)) != 0
}

fn (mut w Wmi) services(mut p Protocol, data Blob) bool {
	if w.service_ready { return false }
	event := find_tlv(data, tag_struct_service_ready_event) or { return false }
	reg := find_tlv(data, tag_struct_hal_reg_capabilities) or { return false }
	bitmap := find_tlv(data, tag_array_uint32) or { return false }
	requests := find_tlv(data, tag_array_struct) or { return false }
	if event.len < 104 || reg.len < 36 || bitmap.len < 68 || bitmap.len % 4 != 0 { return false }
	if event.word(4) != 0x01000000 || event.word(12) != 0x5f414351
		|| event.word(16) != 0x4c4d || event.word(20) != 0 || event.word(24) != 0 {
		return false
	}
	number := event.word(72)
	if number > 16 { return false }
	mut position := u32(0)
	mut allocated := u32(2 * 1024 * 1024)
	mut count := u32(0)
	for position < requests.len {
		if requests.len - position < 20 || half(requests, position) != 16
			|| half(requests, position + 2) != tag_struct_wlan_host_mem_req || count >= number {
			return false
		}
		r := requests.view(position + 4, 16)
		id := r.word(0)
		unit := r.word(4)
		flags := r.word(8)
		mut units := r.word(12)
		if flags & ~u32(7) != 0 || unit == 0 || unit > 1024 * 1024 { return false }
		if flags & 6 != 0 {
			units = 17
		} else if flags & 1 != 0 {
			units = 2
		}
		bytes := u64((unit + 3) & ~u32(3)) * units
		allocated = (allocated + 255) & ~u32(255)
		if bytes == 0 || allocated > p.transport.pool.len || bytes > p.transport.pool.len - allocated {
			return false
		}
		for old in u32(0) .. count { if w.chunks[old].id == id { return false } }
		w.chunks[count] = MemoryChunk{ id: id, address: p.transport.bus + allocated, size: u32(bytes) }
		for n in u32(0) .. u32(bytes) {
			unsafe { p.transport.pool.data[allocated + n] = 0 }
		}
		allocated += u32(bytes)
		count++
		position += 20
	}
	if count != number { return false }
	w.chunk_count = count
	w.low2 = reg.word(20)
	w.high2 = reg.word(24)
	w.low5 = reg.word(28)
	w.high5 = reg.word(32)
	w.full_reorder = service_bit(bitmap, 65)
	w.service_ready = true
	return true
}

pub fn (mut w Wmi) receive(mut p Protocol, packet Blob) {
	if packet.len < 4 {
		p.transport.fault = true
		return
	}
	id := packet.word(0) & 0x00ffffff
	data := packet.view(4, packet.len - 4)
	match id {
		0xb001 {
			event := find_tlv(data, tag_struct_roam_event) or { return }
			if event.len >= 12 && event.word(0) == 0 && event.word(4) == 2 { w.link_lost = true }
		}
		echo_id {
			echo := find_tlv(data, tag_struct_echo_event) or { return }
			if echo.len == 4 { w.echo_token = echo.word(0) }
		}
		1 {
			if !w.services(mut p, data) { p.transport.fault = true }
		}
		2 {
			event := find_tlv(data, tag_struct_ready_event) or {
				p.transport.fault = true
				return
			}
			if event.len < 36 || event.word(32) != 0 || !w.init_sent {
				p.transport.fault = true
				return
			}
			for i in 0 .. 6 { w.mac[i] = unsafe { event.data[24 + i] } }
			if w.mac == [6]u8{} || w.mac[0] & 1 != 0 {
				p.transport.fault = true
				return
			}
			w.ready = true
		}
		0x3001 {
			event := find_tlv(data, tag_struct_scan_event) or { return }
			if event.len < 24 || event.word(16) != w.scan_id { return }
			if event.word(0) & 0x52 != 0 {
				w.scanning = false
				w.scan_error = if event.word(4) == 0 { 0 } else { -3 }
			}
		}
		0x5001 {
			event := find_tlv(data, tag_struct_vdev_start_response_event) or { return }
			if event.len < 16 || event.word(0) != 0 { return }
			w.start_status = event.word(12)
			w.started = w.start_status == 0
		}
		0x7001 {
			header := find_tlv(data, tag_struct_mgmt_rx_hdr) or { return }
			frame := find_tlv(data, tag_array_byte) or { return }
			if header.len < 40 || header.word(16) > frame.len || header.word(20) != 0 { return }
			actual := frame.view(0, header.word(16))
			w.beacon(actual, i16(int(i32(header.word(4))) - 95), u16(header.word(0)))
			if w.management != unsafe { nil } { w.management(w.context, actual) }
		}
		else {}
	}
}

pub fn (mut w Wmi) initialise(mut p Protocol) bool {
	if !w.service_ready || w.init_sent { return false }
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(1)
	command := c.section(tag_struct_init_cmd, 28) or { return false }
	abi := [u32(0x01000000), 53, 0x5f414351, 0x4c4d, 0, 0]!
	for i in u32(0) .. 6 { put32(command.data, i * 4, abi[i]) }
	put32(command.data, 24, w.chunk_count)
	config := c.section(tag_struct_resource_config, 176) or { return false }
	values := [u32(1), 16, if w.full_reorder { u32(1) } else { u32(0) },
		if w.full_reorder { u32(1) } else { u32(0) }, 2, 32, 16, 1, 1, 100, 100, 100, 40, 2, 1,
		1, 1, 8, 0, 0, 0, 1024, 32, 0, 0, 0, 0, 1, 64, 2, 0, 0, 1, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0]!
	for i in u32(0) .. 44 { put32(config.data, i * 4, values[i]) }
	array := c.section(tag_array_struct, w.chunk_count * 20) or { return false }
	for i in u32(0) .. w.chunk_count {
		offset := i * 20
		put16(array.data, offset, 16)
		put16(array.data, offset + 2, tag_struct_wlan_host_memory_chunk)
		put32(array.data, offset + 4, w.chunks[i].id)
		put32(array.data, offset + 8, w.chunks[i].address)
		put32(array.data, offset + 12, w.chunks[i].size)
	}
	if !p.send(p.wmi, c.blob()) { return false }
	w.init_sent = true
	return true
}

pub fn (mut w Wmi) create_vdev(mut p Protocol) bool {
	if !w.ready || w.vdev { return false }
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x5001)
	data := c.section(tag_struct_vdev_create_cmd, 20) or { return false }
	put32(data.data, 4, 2) // station, vdev 0, no P2P subtype
	for i in 0 .. 6 {
		unsafe { data.data[12 + i] = w.mac[i] }
	}
	if !p.send(p.wmi, c.blob()) { return false }
	w.vdev = true
	return true
}

pub fn (mut w Wmi) scan(mut p Protocol) bool {
	if !w.vdev || w.scanning { return false }
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x3001)
	data := c.section(tag_struct_start_scan_cmd, 100) or { return false }
	w.scan_id = 0xa000 | ((w.scan_id + 1) & 0xfff)
	common := [w.scan_id, u32(0xa001), 0, 1, 0x7f, 40, 120, 50, 500, 0, 0, 1000, 20000, 5, 0x21]!
	for i in u32(0) .. 15 { put32(data.data, i * 4, common[i]) }
	// Passive scans request no probe transmissions. The target's board
	// regulatory limits still apply; no channels outside the 2.4 GHz table.
	mut count := u32(0)
	for channel in u16(1) .. 12 { if w.channel_allowed(channel) { count++ } }
	if count == 0 { return false }
	put32(data.data, 64, count)
	channels := c.section(tag_array_uint32, count * 4) or { return false }
	mut index := u32(0)
	for channel in u16(1) .. 12 {
		if w.channel_allowed(channel) {
			put32(channels.data, index * 4, channel_frequency(channel))
			index++
		}
	}
	c.section(tag_array_fixed_struct, 0) or { return false }
	c.section(tag_array_fixed_struct, 0) or { return false }
	c.section(tag_array_byte, 0) or { return false }
	if !p.send(p.wmi, c.blob()) { return false }
	w.scanning = true
	w.scan_error = 0
	w.network_count = 0
	w.scan_deadline = p.transport.now() + 25 * u64(1000000000)
	return true
}

pub fn (mut w Wmi) beacon(frame Blob, rssi i16, channel u16) {
	if frame.len < 36 { return }
	control := half(frame, 0)
	if control & 0x00fc != 0x80 && control & 0x00fc != 0x50 { return }
	mut network := Network{
		channel:         channel
		rssi:            if rssi < -127 {
			i16(-127)
		} else if rssi > 0 {
			i16(0)
		} else {
			rssi
		}
		capabilities:    half(frame, 34)
		beacon_interval: half(frame, 32)
	}
	network.secure = network.capabilities & 0x10 != 0
	for i in 0 .. 6 { network.bssid[i] = unsafe { frame.data[16 + i] } }
	if network.bssid[0] & 1 != 0 || network.bssid == [6]u8{} { return }
	mut position := u32(36)
	for position < frame.len {
		if frame.len - position < 2 { return }
		id := unsafe { frame.data[position] }
		size := u32(unsafe { frame.data[position + 1] })
		position += 2
		if size > frame.len - position { return }
		match id {
			0 {
				if size > 32 { return }
				network.ssid_len = u8(size)
				for n in u32(0) .. size { network.ssid[n] = unsafe { frame.data[position + n] } }
			}
			1, 50 {
				for n in u32(0) .. size {
					if network.rate_count == 16 { break }
					network.rates[network.rate_count] = unsafe { frame.data[position + n] }
					network.rate_count++
				}
			}
			3 {
				if size == 1 { network.channel = u16(unsafe { frame.data[position] }) }
			}
			48 {
				if size + 2 <= 96 {
					network.rsn[0] = 48
					network.rsn[1] = u8(size)
					network.rsn_len = u8(size + 2)
					for n in u32(0) .. size {
						network.rsn[2 + n] = unsafe { frame.data[position + n] }
					}
				}
			}
			else {}
		}
		position += size
	}
	if network.channel < 1 || network.channel > 233 { return }
	for i in 0 .. w.network_count {
		if w.networks[i].bssid == network.bssid {
			w.networks[i] = network
			return
		}
	}
	if w.network_count < 32 {
		w.networks[w.network_count] = network
		w.network_count++
	}
}
