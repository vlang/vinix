// SPDX-License-Identifier: ISC
module ath10k

pub enum StationState {
	idle
	starting
	peer
	authenticating
	associating
	configuring
	keying
	connected
	failed
}

pub struct Station {
pub mut:
	state            StationState
	network          Network
	mac              [6]u8
	wpa              Wpa
	sequence         u16
	aid              u16
	deadline         u64
	retry_at         u64
	attempts         u32
	configuration    u32
	error            int
	key_reply        WpaReply
	key_stage        u32
	key_confirmed    u32
	response_pending bool
	key_deadline     u64
	echo             u32
}

pub fn (mut s Station) fail(code int) {
	s.state = .failed
	s.error = code
	s.wpa.clear()
	erase(unsafe { &s.key_reply }, sizeof(WpaReply))
	s.key_stage = 0
	s.response_pending = false
}

pub fn (mut s Station) begin(mut p Protocol, mut w Wmi, network &Network, pmk &[32]u8, nonce &[32]u8) bool {
	if !w.channel_allowed(network.channel) || network.rate_count == 0 || network.ssid_len == 0
		|| (network.secure && !rsn_supported(Blob{ data: unsafe { &network.rsn[0] }, len: network.rsn_len })) {
		return false
	}
	s.wpa.clear()
	s.network = *network
	s.mac = w.mac
	s.error = 0
	s.configuration = 0
	s.attempts = 0
	s.aid = 0
	s.key_stage = 0
	s.response_pending = false
	if network.secure {
		if *nonce == [32]u8{} { return false }
		s.wpa.pmk = *pmk
		s.wpa.station = w.mac
		s.wpa.ap = network.bssid
		s.wpa.snonce = *nonce
		s.wpa.started = true
	}
	if !w.start_station(mut p, network) {
		s.fail(-5)
		return false
	}
	s.deadline = p.transport.now() + 15 * u64(1000000000)
	s.state = .starting
	return true
}

fn (mut s Station) management_frame(association bool) WpaReply {
	mut frame := WpaReply{ len: 30 }
	put16(unsafe { &frame.data[0] }, 0, if association { u16(0) } else { u16(0xb0) })
	for i in 0 .. 6 {
		frame.data[4 + i] = s.network.bssid[i]
		frame.data[10 + i] = s.mac[i]
		frame.data[16 + i] = s.network.bssid[i]
	}
	put16(unsafe { &frame.data[0] }, 22, s.sequence << 4)
	s.sequence = (s.sequence + 1) & 4095
	if !association {
		put16(unsafe { &frame.data[0] }, 26, 1)
		return frame
	}
	// Advertise only legacy 20 MHz operation. No QoS/HT aggregation.
	put16(unsafe { &frame.data[0] }, 24, s.network.capabilities & 0x0431)
	put16(unsafe { &frame.data[0] }, 26, 10)
	frame.data[28] = 0
	frame.data[29] = s.network.ssid_len
	for i in u32(0) .. s.network.ssid_len { frame.data[30 + i] = s.network.ssid[i] }
	frame.len = 30 + s.network.ssid_len
	mut remaining := u32(s.network.rate_count)
	mut copied := u32(0)
	for id in [u8(1), 50]! {
		if remaining == 0 { break }
		count := if remaining > 8 { u32(8) } else { remaining }
		frame.data[frame.len] = id
		frame.data[frame.len + 1] = u8(count)
		for i in u32(0) .. count { frame.data[frame.len + 2 + i] = s.network.rates[copied + i] }
		frame.len += 2 + count
		copied += count
		remaining -= count
	}
	if s.network.secure {
		for i in u32(0) .. 22 { frame.data[frame.len + i] = client_rsn[i] }
		frame.len += 22
	}
	return frame
}

pub fn (mut s Station) management(frame Blob) {
	if frame.len < 24 || !equal_bytes(unsafe { frame.data + 4 }, unsafe { &s.mac[0] }, 6)
		|| !equal_bytes(unsafe { frame.data + 10 }, unsafe { &s.network.bssid[0] }, 6)
		|| !equal_bytes(unsafe { frame.data + 16 }, unsafe { &s.network.bssid[0] }, 6) {
		return
	}
	control := half(frame, 0)
	if control & 0x030c != 0 { return }
	kind := control & 0xfc
	if kind == 0xc0 || kind == 0xa0 {
		s.fail(-104)
		return
	}
	if frame.len < 30 { return }
	if s.state == .authenticating && kind == 0xb0 {
		if half(frame, 24) != 0 || half(frame, 26) != 2 { return }
		if half(frame, 28) != 0 {
			s.fail(-13)
			return
		}
		s.state = .associating
		s.attempts = 0
		s.retry_at = 0
	} else if s.state == .associating && kind == 0x10 {
		if half(frame, 26) != 0 {
			s.fail(-13)
			return
		}
		s.aid = half(frame, 28) & 0x3fff
		if s.aid == 0 || s.aid > 2007 {
			s.fail(-71)
			return
		}
		s.state = .configuring
	}
}

pub fn (mut s Station) input(frame Blob, now u64) {
	if (s.state != .keying && s.state != .connected) || !s.network.secure || s.response_pending {
		return
	}
	reply := s.wpa.process(frame) or { return }
	s.key_reply = reply
	s.response_pending = true
	s.key_stage = 0
	s.key_deadline = now + 3 * u64(1000000000)
}

// Called with TX serialized; all waits are handled by subsequent poll calls.
pub fn (mut s Station) tick(mut p Protocol, mut w Wmi, mut h Htt) {
	now := p.transport.now()
	if s.state != .idle && s.state != .failed && s.state != .connected && now >= s.deadline {
		s.fail(-110)
		return
	}
	if p.transport.fault {
		s.fail(-5)
		return
	}
	if s.response_pending && now >= s.key_deadline {
		s.fail(-110)
		return
	}
	if int(s.state) >= int(StationState.authenticating) && int(s.state) <= int(StationState.connected)
		&& (!h.peer_mapped || w.link_lost) {
		s.fail(-100)
		return
	}
	match s.state {
		.starting {
			if w.start_status != 0xffffffff && !w.started {
				s.fail(-5)
				return
			}
			if w.started && w.peer_create(mut p, unsafe { &s.network.bssid }) {
				h.peer_mac = s.network.bssid
				s.state = .peer
			}
		}
		.peer {
			if h.peer_mapped {
				s.state = .authenticating
				s.retry_at = 0
			}
		}
		.authenticating, .associating {
			if now < s.retry_at { return }
			if s.attempts >= 5 {
				s.fail(-110)
				return
			}
			frame := s.management_frame(s.state == .associating)
			h.transmit(mut p, Blob{ data: unsafe { &frame.data[0] }, len: frame.len }, true, false) or { return }
			s.retry_at = now + u64(1000000000)
			s.attempts++
		}
		.configuring {
			if s.configuration == 0 {
				if !w.associate(mut p, unsafe { &s.network }, s.aid) { return }
				s.configuration = 1
			}
			if s.configuration == 1 {
				if !w.up(mut p, unsafe { &s.network.bssid }, s.aid) { return }
				s.configuration = 2
			}
			if s.configuration == 2 {
				s.echo++
				if !w.echo(mut p, s.echo) {
					s.echo--
					return
				}
				s.configuration = 3
			}
			if w.echo_token == s.echo {
				s.state = if s.network.secure {
					StationState.keying
				} else {
					StationState.connected
				}
			}
		}
		.keying, .connected {
			if !s.response_pending { return }
			if s.key_stage == 0 {
				if s.key_reply.install_pairwise {
					s.key_confirmed = h.pairwise_confirmed
					if !w.install_key(mut p, unsafe { &s.network.bssid }, unsafe { &s.key_reply.pairwise }, 0, false, 0) {
						return
					}
					s.key_stage = 1
				} else {
					s.key_stage = 2
				}
			}
			if s.key_stage == 1 {
				if h.pairwise_confirmed == s.key_confirmed { return }
				h.unicast_pn = [17]u64{}
				s.key_stage = 2
			}
			if s.key_stage == 2 {
				if s.key_reply.install_group {
					s.key_confirmed = h.group_confirmed
					if !w.install_key(mut p, unsafe { &s.network.bssid }, unsafe { &s.key_reply.group }, s.key_reply.group_index, true, s.key_reply.group_rsc) {
						return
					}
					s.key_stage = 3
				} else {
					s.key_stage = 4
				}
			}
			if s.key_stage == 3 {
				if h.group_confirmed == s.key_confirmed { return }
				h.group_pn = [17]u64{init: s.key_reply.group_rsc}
				s.key_stage = 4
			}
			if s.key_stage == 4 {
				h.transmit(mut p, Blob{ data: unsafe { &s.key_reply.data[0] }, len: s.key_reply.len }, false, s.wpa.pairwise_installed) or { return }
				if s.key_reply.install_pairwise || s.key_reply.install_group {
					if s.wpa.keys_installed(unsafe { &s.key_reply }) { s.state = .connected }
				}
				s.response_pending = false
				erase(unsafe { &s.key_reply }, sizeof(WpaReply))
			}
		}
		else {}
	}
}
