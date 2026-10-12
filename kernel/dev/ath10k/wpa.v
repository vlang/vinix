// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// WPA2-PSK/CCMP station handshake. Firmware performs CCMP packet encryption;
// the host authenticates EAPOL, unwraps the GTK and installs keys through WMI.
module ath10k

const client_rsn = [u8(48), 20, 1, 0, 0, 15, 172, 4, 1, 0, 0, 15, 172, 4, 1, 0, 0, 15, 172, 2,
	0, 0]!

pub struct Wpa {
pub mut:
	pmk                [32]u8
	ptk                [48]u8
	active_ptk         [48]u8
	station            [6]u8
	ap                 [6]u8
	snonce             [32]u8
	anonce             [32]u8
	replay             u64
	active_replay      u64
	started            bool
	pending            bool
	install_pending    bool
	pairwise_installed bool
	group_installed    bool
	group_index        u8
	group_key          [16]u8
}

pub struct WpaReply {
pub mut:
	data             [256]u8
	len              u32
	install_pairwise bool
	install_group    bool
	pairwise         [16]u8
	group            [16]u8
	group_index      u8
	group_rsc        u64
	complete         bool
}

fn be16(b Blob, offset u32) u16 {
	unsafe {
		return u16(b.data[offset]) << 8 | u16(b.data[offset + 1])
	}
}

fn put_be16(data &u8, offset u32, value u16) {
	unsafe {
		data[offset] = u8(value >> 8)
		data[offset + 1] = u8(value)
	}
}

fn be64(b Blob, offset u32) u64 {
	mut value := u64(0)
	for i in u32(0) .. 8 { value = (value << 8) | u64(unsafe { b.data[offset + i] }) }
	return value
}

fn equal_bytes(a &u8, b &u8, length u32) bool {
	mut difference := u8(0)
	for i in u32(0) .. length {
		unsafe { difference |= a[i] ^ b[i] }
	}
	return difference == 0
}

pub fn rsn_supported(rsn Blob) bool {
	if rsn.len < 20 || unsafe { rsn.data[0] } != 48 || u32(unsafe { rsn.data[1] }) + 2 != rsn.len {
		return false
	}
	if half(rsn, 2) != 1 || rsn.word(4) != 0x04ac0f00 { return false }
	pairwise_count := u32(half(rsn, 8))
	if pairwise_count == 0 || pairwise_count > 16 || pairwise_count * 4 > rsn.len - 10 {
		return false
	}
	mut ccmp := false
	for i in u32(0) .. pairwise_count { if rsn.word(10 + i * 4) == 0x04ac0f00 { ccmp = true } }
	position := 10 + pairwise_count * 4
	if rsn.len - position < 2 { return false }
	akms := u32(half(rsn, position))
	if akms == 0 || akms > 16 || akms * 4 > rsn.len - position - 2 { return false }
	mut psk := false
	for i in u32(0) .. akms { if rsn.word(position + 2 + i * 4) == 0x02ac0f00 { psk = true } }
	end := position + 2 + akms * 4
	// This driver does not negotiate mandatory protected management frames.
	if rsn.len - end >= 2 && half(rsn, end) & 0x40 != 0 { return false }
	return ccmp && psk
}

pub fn (mut w Wpa) start(passphrase Blob, ssid Blob, station &[6]u8, ap &[6]u8, nonce &[32]u8) bool {
	if *nonce == [32]u8{} { return false }
	pmk := derive_pmk(passphrase, ssid) or { return false }
	w.clear()
	w.pmk = pmk
	w.station = *station
	w.ap = *ap
	w.snonce = *nonce
	w.started = true
	return true
}

struct SecretByte {
mut:
	volatile value u8
}

@[noinline]
fn erase(data voidptr, size u64) {
	for i in u64(0) .. size {
		unsafe { (&SecretByte(u64(data) + i)).value = 0 }
	}
}

pub fn (mut w Wpa) clear() { erase(voidptr(w), sizeof(Wpa)) }

fn verify_mic(frame Blob, key &u8) bool {
	length := u32(be16(frame, 16)) + 4
	if length > 1024 || length > frame.len - 14 { return false }
	mut bytes := [1024]u8{}
	for i in u32(0) .. length { bytes[i] = unsafe { frame.data[14 + i] } }
	for i in 81 .. 97 { bytes[i] = 0 }
	mic := hmac_sha1(Blob{ data: unsafe { key }, len: 16 }, Blob{ data: unsafe { &bytes[0] }, len: length })
	return equal_bytes(unsafe { &mic[0] }, unsafe { frame.data + 95 }, 16)
}

fn (w &Wpa) response(frame Blob, flags u16, nonce bool, rsn bool, active bool) WpaReply {
	mut reply := WpaReply{ len: if rsn { u32(135) } else { u32(113) } }
	for i in 0 .. 6 {
		reply.data[i] = w.ap[i]
		reply.data[6 + i] = w.station[i]
	}
	reply.data[12] = 0x88
	reply.data[13] = 0x8e
	reply.data[14] = unsafe { frame.data[14] }
	reply.data[15] = 3
	put_be16(unsafe { &reply.data[0] }, 16, u16(reply.len - 18))
	reply.data[18] = 2
	put_be16(unsafe { &reply.data[0] }, 19, flags)
	put_be16(unsafe { &reply.data[0] }, 21, 16)
	for i in 0 .. 8 { reply.data[23 + i] = unsafe { frame.data[23 + i] } }
	if nonce {
		for i in 0 .. 32 { reply.data[31 + i] = w.snonce[i] }
	}
	if rsn {
		put_be16(unsafe { &reply.data[0] }, 111, 22)
		for i in 0 .. 22 { reply.data[113 + i] = client_rsn[i] }
	}
	key := if active { unsafe { &w.active_ptk[0] } } else { unsafe { &w.ptk[0] } }
	mic := hmac_sha1(Blob{ data: key, len: 16 }, Blob{ data: unsafe { &reply.data[14] }, len: reply.len - 14 })
	for i in 0 .. 16 { reply.data[95 + i] = mic[i] }
	return reply
}

fn extract_group(bytes Blob, mut reply WpaReply) bool {
	mut position := u32(0)
	mut found := false
	for position < bytes.len {
		if bytes.len - position < 2 { return false }
		id := unsafe { bytes.data[position] }
		size := u32(unsafe { bytes.data[position + 1] })
		if id == 0xdd && size == 0 {
			for i in position + 2 .. bytes.len { if unsafe { bytes.data[i] } != 0 { return false } }
			break
		}
		position += 2
		if size > bytes.len - position { return false }
		if id == 0xdd && size >= 4 && bytes.word(position) == 0x01ac0f00 {
			if found || size != 22 || unsafe { bytes.data[position + 4] } & 0xf8 != 0 {
				return false
			}
			reply.group_index = unsafe { bytes.data[position + 4] } & 3
			for i in 0 .. 16 { reply.group[i] = unsafe { bytes.data[position + 6 + u32(i)] } }
			found = true
		} else if id == 48 {
			if !rsn_supported(bytes.view(position - 2, size + 2)) { return false }
		}
		position += size
	}
	reply.install_group = found
	return true
}

pub fn (mut w Wpa) process(frame Blob) ?WpaReply {
	if !w.started || frame.len < 113 || !equal_bytes(frame.data, unsafe { &w.station[0] }, 6)
		|| !equal_bytes(unsafe { frame.data + 6 }, unsafe { &w.ap[0] }, 6) {
		return none
	}
	if be16(frame, 12) != 0x888e || unsafe { frame.data[15] } != 3
		|| unsafe { frame.data[14] } == 0 || unsafe { frame.data[14] } > 2 || unsafe { frame.data[18] } != 2 {
		return none
	}
	length := u32(be16(frame, 16))
	if length < 95 || length > 1020 || length + 18 > frame.len { return none }
	data_length := u32(be16(frame, 111))
	if data_length != length - 95 { return none }
	flags := be16(frame, 19)
	if flags & 7 != 2 || flags & 0xc00 != 0 || flags & 0x80 == 0 || be16(frame, 21) != 16 {
		return none
	}
	replay := be64(frame, 23)
	pairwise := flags & 8 != 0
	has_mic := flags & 0x100 != 0
	if pairwise && !has_mic {
		if flags & 0x1240 != 0 || replay < w.active_replay || replay < w.replay { return none }
		if w.pending && replay == w.replay {
			if !equal_bytes(unsafe { frame.data + 31 }, unsafe { &w.anonce[0] }, 32) { return none }
			return w.response(frame, 0x10a, true, true, false)
		}
		if w.install_pending { return none }
		for i in 0 .. 32 { w.anonce[i] = unsafe { frame.data[31 + i] } }
		if w.anonce == [32]u8{} { return none }
		w.ptk = derive_ptk(unsafe { &w.pmk }, unsafe { &w.station }, unsafe { &w.ap }, unsafe { &w.snonce }, unsafe { &w.anonce })
		// A new replay counter cannot make an already installed PTK new.
		if w.pairwise_installed && w.ptk == w.active_ptk { return none }
		w.replay = replay
		w.pending = true
		return w.response(frame, 0x10a, true, true, false)
	}
	if !has_mic || flags & 0x200 == 0 { return none }
	if pairwise {
		if !w.pending || replay < w.replay || !equal_bytes(unsafe { frame.data + 31 }, unsafe { &w.anonce[0] }, 32)
			|| !verify_mic(frame, unsafe { &w.ptk[0] }) {
			return none
		}
		mut reply := w.response(frame, 0x30a, false, false, false)
		// Retransmitted M3 can elicit M4, but can never reinstall a key or
		// reset the hardware CCMP packet number (KRACK prevention).
		if w.install_pending { return none }
		if w.pairwise_installed && w.ptk == w.active_ptk {
			w.replay = replay
			w.active_replay = replay
			return reply
		}
		if flags & 0x40 == 0 || flags & 0x1000 == 0 { return none }
		mut kek := [16]u8{}
		for i in 0 .. 16 {
			kek[i] = w.ptk[16 + i]
			reply.pairwise[i] = w.ptk[32 + i]
		}
		mut plain := [512]u8{}
		defer {
			erase(unsafe { &plain[0] }, 512)
			erase(unsafe { &kek[0] }, 16)
		}
		size := unwrap_key(unsafe { &kek }, frame.view(113, data_length), unsafe { &plain[0] }, 512) or { return none }
		if !extract_group(Blob{ data: unsafe { &plain[0] }, len: size }, mut reply) { return none }
		if reply.install_group && w.group_installed && reply.group == w.group_key && reply.group_index == w.group_index {
			reply.install_group = false
		}
		for i in 0 .. 8 { reply.group_rsc |= u64(unsafe { frame.data[79 + i] }) << (i * 8) }
		reply.install_pairwise = true
		w.replay = replay
		w.install_pending = true
		return reply
	}
	if !w.pairwise_installed || replay <= w.active_replay || !verify_mic(frame, unsafe { &w.active_ptk[0] })
		|| flags & 0x1000 == 0 {
		return none
	}
	mut reply := w.response(frame, 0x302, false, false, true)
	mut kek := [16]u8{}
	for i in 0 .. 16 { kek[i] = w.active_ptk[16 + i] }
	mut plain := [512]u8{}
	defer {
		erase(unsafe { &plain[0] }, 512)
		erase(unsafe { &kek[0] }, 16)
	}
	size := unwrap_key(unsafe { &kek }, frame.view(113, data_length), unsafe { &plain[0] }, 512) or { return none }
	if !extract_group(Blob{ data: unsafe { &plain[0] }, len: size }, mut reply) || !reply.install_group {
		return none
	}
	if w.install_pending { return none }
	if w.group_installed && reply.group == w.group_key && reply.group_index == w.group_index {
		w.active_replay = replay
		reply.install_group = false
		return reply
	}
	for i in 0 .. 8 { reply.group_rsc |= u64(unsafe { frame.data[79 + i] }) << (i * 8) }
	w.replay = replay
	w.install_pending = true
	return reply
}

// Called only after the WMI key-install completion events confirm success.
pub fn (mut w Wpa) keys_installed(reply &WpaReply) bool {
	if !w.install_pending { return w.pairwise_installed && w.group_installed }
	if reply.install_pairwise {
		w.active_ptk = w.ptk
		w.pairwise_installed = true
	}
	if reply.install_group {
		w.group_key = reply.group
		w.group_index = reply.group_index
		w.group_installed = true
	}
	w.install_pending = false
	w.active_replay = w.replay
	return w.pairwise_installed && w.group_installed
}
