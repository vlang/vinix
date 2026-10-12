// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// QCA9377 low-latency 32-bit HTT: Ethernet decapsulation, hardware CCMP,
// and management frames through HTT TX_FRM (firmware HTT API 3).
module ath10k

const rx_buffer_base = u32(0x80000)
const rx_address_ring = u32(0x100000)
const rx_alloc_index = u32(0x100800)
const tx_buffer_base = u32(0x110000)
const tx_fragment_base = u32(0x130000)
const rx_payload_offset = u32(300)

pub struct Htt {
pub mut:
	version            bool
	configured         bool
	full_reorder       bool
	peer_mac           [6]u8
	peer_mapped        bool
	peer_id            u16
	pairwise_confirmed u32
	group_confirmed    u32
	secure             bool
	unicast_pn         [17]u64
	group_pn           [17]u64
	rx_write           u32
	rx_read            u32
	rx_slots           [512]u16
	rx_owned           [256]bool
	tx_owned           [64]bool
	tx_next            u32
	rx_packets         u64
	rx_dropped         u64
	tx_queued          u64
	tx_completed       u64
	context            voidptr
	input              fn (voidptr, Blob)      = unsafe { nil }
	completed          fn (voidptr, u32, bool) = unsafe { nil }
}

pub fn (mut h Htt) request_version(mut p Protocol) bool {
	mut request := [4]u8{}
	return p.send(p.htt, Blob{ data: unsafe { &request[0] }, len: 4 })
}

fn (mut h Htt) post(mut p Protocol, slot u32) {
	// Clear ownership/completion before making the address visible to target.
	put32(p.transport.pool.data, rx_buffer_base + slot * 2048 + 4, 0)
	put32(p.transport.pool.data, rx_address_ring + h.rx_write * 4, p.transport.bus + rx_buffer_base + slot * 2048)
	h.rx_slots[h.rx_write] = u16(slot)
	h.rx_write = (h.rx_write + 1) & 511
	h.rx_owned[slot] = true
	p.transport.barrier()
	put32(p.transport.pool.data, rx_alloc_index, h.rx_write)
}

pub fn (mut h Htt) configure(mut p Protocol, full_reorder bool) bool {
	if !h.version || h.configured || p.transport.pool.len < 2 * 1024 * 1024 { return false }
	h.full_reorder = full_reorder
	h.rx_write = 0
	h.rx_read = 0
	for slot in u32(0) .. 128 { h.post(mut p, slot) }
	mut bytes := [40]u8{}
	bytes[0] = 2
	bytes[1] = 1
	put32(unsafe { &bytes[0] }, 4, p.transport.bus + rx_alloc_index)
	put32(unsafe { &bytes[0] }, 8, p.transport.bus + rx_address_ring)
	put16(unsafe { &bytes[0] }, 12, 512)
	put16(unsafe { &bytes[0] }, 14, 2048)
	put16(unsafe { &bytes[0] }, 16, 0xffff)
	put16(unsafe { &bytes[0] }, 18, u16(h.rx_write))
	// Offsets in dwords in the unified htt_rx_desc_v1 from Linux v6.6.
	offsets := [u16(59), 75, 21, 31, 3, 20, 6, 10, 1, 2]!
	for i in u32(0) .. 10 { put16(unsafe { &bytes[0] }, 20 + i * 2, offsets[i]) }
	if !p.send(p.htt, Blob{ data: unsafe { &bytes[0] }, len: 40 }) { return false }
	h.configured = true
	return true
}

// A completion releases the packet, not the earlier CE source completion.
// Callers serialize transmit ownership against completion handling.
pub fn (mut h Htt) transmit(mut p Protocol, frame Blob, management bool, encrypt bool) ?u32 {
	if !h.configured || frame.len < 14 || frame.len > 1800 { return none }
	mut slot := h.tx_next
	mut found := false
	for _ in 0 .. 64 {
		if !h.tx_owned[slot] {
			found = true
			break
		}
		slot = (slot + 1) & 63
	}
	if !found { return none }
	address := p.transport.bus + tx_buffer_base + slot * 2048
	for i in u32(0) .. frame.len {
		unsafe { p.transport.pool.data[tx_buffer_base + slot * 2048 + i] = frame.data[i] }
	}
	fragment := tx_fragment_base + slot * 16
	put32(p.transport.pool.data, fragment, address)
	put32(p.transport.pool.data, fragment + 4, frame.len)
	put32(p.transport.pool.data, fragment + 8, 0)
	put32(p.transport.pool.data, fragment + 12, 0)
	mut command := [96]u8{}
	command[0] = 1
	command[1] = (if management { u8(0x61) } else { u8(0x40) }) | if encrypt {
		u8(0)
	} else {
		u8(4)
	}
	put16(unsafe { &command[0] }, 2, 0x800 | (if management { u16(17) } else { u16(16) } << 6))
	put16(unsafe { &command[0] }, 4, u16(frame.len))
	put16(unsafe { &command[0] }, 6, u16(slot))
	put32(unsafe { &command[0] }, 8, if management { address } else { p.transport.bus + fragment })
	put32(unsafe { &command[0] }, 12, 0xffff)
	prefetch := if frame.len < 64 { frame.len } else { u32(64) }
	for i in u32(0) .. prefetch { command[16 + i] = unsafe { frame.data[i] } }
	p.transport.barrier()
	if !p.send(p.htt, Blob{ data: unsafe { &command[0] }, len: 16 + ((prefetch + 3) & ~u32(3)) }) {
		return none
	}
	h.tx_owned[slot] = true
	h.tx_next = (slot + 1) & 63
	h.tx_queued++
	return slot
}

fn (mut h Htt) finish(slot u32, ok bool) {
	if slot >= 64 || !h.tx_owned[slot] { return }
	h.tx_owned[slot] = false
	h.tx_completed++
	if h.completed != unsafe { nil } { h.completed(h.context, slot, ok) }
}

fn (mut h Htt) deliver(mut p Protocol, slot u32, size u32, offload bool) {
	if slot >= 256 || !h.rx_owned[slot] {
		p.transport.fault = true
		return
	}
	h.rx_owned[slot] = false
	p.transport.barrier()
	buffer := p.transport.pool.view(rx_buffer_base + slot * 2048, 2048)
	mut length := size
	mut payload := rx_payload_offset
	mut valid := false
	if offload {
		length = u32(half(buffer, 0))
		payload = 7
		valid = unsafe { buffer.data[4] } == 0
	} else {
		attention := buffer.word(4)
		// Overflow, length, encryption, TKIP MIC, decryption and FCS errors.
		valid = attention & 0x80000000 != 0 && attention & 0x7d032398 == 0 && buffer.word(8) == 0
			&& (buffer.word(32) >> 8) & 3 == 2 && buffer.word(56) & 0x4c000 == 0xc000
		if length == 0 { length = buffer.word(24) & 0x3fff }
		payload += (buffer.word(72) >> 10) & 7
		// The first release deliberately rejects fragmented and aggregated
		// MSDUs. Replay windows advance only on complete CCMP data frames.
		info := buffer.word(12)
		if info & 0x2000 != 0 {
			valid = valid && info >> 28 == 6 && info & 0x7ff == h.peer_id
			tid := if attention & 0x40 != 0 { u32(16) } else { buffer.word(20) >> 28 }
			pn := u64(buffer.word(16)) | u64(buffer.word(20) & 0xffff) << 32
			multicast := attention & 4 != 0
			previous := if multicast { h.group_pn[tid] } else { h.unicast_pn[tid] }
			valid = valid && pn > previous
			if valid {
				if multicast { h.group_pn[tid] = pn } else { h.unicast_pn[tid] = pn }
			}
		} else if h.secure {
			valid = valid && length >= 14 && be16(buffer, payload + 12) == 0x888e
		}
	}
	if valid && length >= 14 && length <= 1518 && length <= buffer.len - payload {
		h.rx_packets++
		if h.input != unsafe { nil } { h.input(h.context, buffer.view(payload, length)) }
	} else {
		h.rx_dropped++
	}
	h.post(mut p, slot)
}

pub fn (mut h Htt) receive(mut p Protocol, message Blob) {
	if message.len < 4 {
		p.transport.fault = true
		return
	}
	kind := unsafe { message.data[0] }
	match kind {
		3 {
			if message.len >= 12 && unsafe { message.data[1] } == 0
				&& equal_bytes(unsafe { message.data + 4 }, unsafe { &h.peer_mac[0] }, 6) {
				h.peer_id = half(message, 2)
				h.peer_mapped = true
			}
		}
		4 {
			if message.len >= 4 && half(message, 2) == h.peer_id { h.peer_mapped = false }
		}
		0xb {
			if message.len < 28 || !h.peer_mapped || half(message, 2) != h.peer_id
				|| unsafe { message.data[1] } & 0x7f != 6 {
				return
			}
			if unsafe { message.data[1] } & 0x80 != 0 {
				h.pairwise_confirmed++
			} else {
				h.group_confirmed++
			}
		}
		0 {
			// QCA9377 ABI 3 uses TX_FRM for data and management frames.
			if unsafe { message.data[2] } < 3 {
				p.transport.fault = true
				return
			}
			h.version = true
		}
		7, 0xd {
			count := u32(unsafe { message.data[2] })
			if count > 64 || count * 2 > message.len - 4 {
				p.transport.fault = true
				return
			}
			ok := unsafe { message.data[1] } & 7 == 0
			for i in u32(0) .. count { h.finish(u32(half(message, 4 + i * 2)), ok) }
		}
		0xe {
			if message.len < 12 {
				p.transport.fault = true
				return
			}
			h.finish(message.word(4), message.word(8) == 0)
		}
		0x12 {
			if !h.full_reorder || message.len < 8 { return }
			// Firmware offload uses Native WiFi without a CCMP descriptor/PN.
			// This release discards those and fragmented indications, while
			// returning their buffers so they cannot exhaust the receive ring.
			unsupported := unsafe { message.data[1] } & 0x60 != 0
			count := u32(half(message, 6))
			if count > 128 || count * 8 > message.len - 8 {
				p.transport.fault = true
				return
			}
			mut seen := [256]bool{}
			for i in u32(0) .. count {
				address := message.word(8 + i * 8)
				base := p.transport.bus + rx_buffer_base
				if address < base || address - base >= 256 * 2048 || (address - base) % 2048 != 0 {
					p.transport.fault = true
					return
				}
				slot := (address - base) / 2048
				if seen[slot] || !h.rx_owned[slot] {
					p.transport.fault = true
					return
				}
				seen[slot] = true
			}
			for i in u32(0) .. count {
				address := message.word(8 + i * 8)
				slot := (address - p.transport.bus - rx_buffer_base) / 2048
				if unsupported {
					h.rx_owned[slot] = false
					h.rx_dropped++
					h.post(mut p, slot)
				} else {
					h.deliver(mut p, slot, u32(half(message, 12 + i * 8)), false)
				}
			}
		}
		1 {
			if h.full_reorder { return }
			// Legacy station operation without host aggregation: consume the
			// ordered posted buffers whose DMA completion bit is set.
			for _ in 0 .. 128 {
				slot := u32(h.rx_slots[h.rx_read])
				p.transport.barrier()
				if p.transport.pool.word(rx_buffer_base + slot * 2048 + 4) & 0x80000000 == 0 {
					break
				}
				h.rx_read = (h.rx_read + 1) & 511
				h.deliver(mut p, slot, 0, false)
			}
		}
		else {}
	}
}
