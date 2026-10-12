// SPDX-License-Identifier: ISC
module ath10k

fn test_tx_ring_wrap_and_bmi_timeout_never_reuses_pending_dma() {
	mut hw := &FakeHardware{}
	bytes := []u8{len: 4 * 1024 * 1024}
	mut p := fixture_protocol(hw, bytes)
	packet := [u8(1), 2, 3, 4]
	for _ in 0 .. 15 {
		assert p.transport.submit(0, fixture_blob(packet))
	}
	assert !p.transport.submit(0, fixture_blob(packet))
	hw.registers[(ce_base(0) + 0x44) / 4] = 15
	for _ in 0 .. 15 {
		assert p.transport.submit(0, fixture_blob(packet))
	}
	assert !p.transport.submit(0, fixture_blob(packet))
	mut timed := fixture_protocol(hw, bytes)
	assert timed.transport.bmi_word(8, 0, 0) == none
	assert timed.transport.fault
	assert !timed.transport.submit(0, fixture_blob(packet))
}

fn test_rx_bounds_and_htc_credit_trailers() {
	hw := &FakeHardware{}
	bytes := []u8{len: 4 * 1024 * 1024}
	mut p := fixture_protocol(hw, bytes)
	e := p.transport.engines[1]
	put32(bytes.data, e.destination, p.transport.bus - 1)
	put16(bytes.data, e.destination + 4, 16)
	assert p.transport.receive(1) == none
	assert p.transport.fault
	mut credits := Protocol{ credit_count: 10, credit_size: 256 }
	mut message := [16]u8{}
	message[1] = 2
	message[4] = 8
	put16(unsafe { &message[0] }, 2, 8)
	message[8] = 1
	message[9] = 4
	message[12] = 1
	message[13] = 5
	credits.frame(Blob{ data: unsafe { &message[0] }, len: 16 })
	assert credits.credits[1] == 5 && !credits.transport.fault
	message[13] = 6
	credits.frame(Blob{ data: unsafe { &message[0] }, len: 16 })
	assert credits.transport.fault && credits.credits[1] == 5
}

fn test_key_command_layout_channel_limits_and_management_address_checks() {
	hw := &FakeHardware{ complete: true }
	bytes := []u8{len: 4 * 1024 * 1024}
	mut p := fixture_protocol(hw, bytes)
	mut w := Wmi{ vdev: true, low2: 2412, high2: 2462 }
	mac := [u8(2), 3, 4, 5, 6, 7]!
	key := [16]u8{init: 0xa5}
	assert w.install_key(mut p, unsafe { &mac }, unsafe { &key }, 2, true, 0x10203040506)
	e := p.transport.engines[3]
	command := p.transport.pool.view(e.tx_data + 8, 120)
	assert command.word(0) == 0x5009
	data := find_tlv(command.view(4, command.len - 4), tag_struct_vdev_install_key_cmd) or { panic('key command TLV') }
	assert data.len == 92 && data.word(12) == 2 && data.word(16) == 1 && data.word(20) == 4
	assert data.word(24) == 0x03040506 && data.word(28) == 0x102 && data.word(80) == 16
	assert w.channel_allowed(1) && w.channel_allowed(11)
	assert !w.channel_allowed(12) && !w.channel_allowed(36)
	mut station := Station{
		state:   .authenticating
		mac:     mac
		network: Network{ bssid: [u8(2), 8, 9, 10, 11, 12]! }
	}
	mut response := [30]u8{}
	put16(unsafe { &response[0] }, 0, 0xb0)
	put16(unsafe { &response[0] }, 26, 2)
	for i in 0 .. 6 {
		response[4 + i] = station.mac[i]
		response[10 + i] = station.network.bssid[i]
		response[16 + i] = station.network.bssid[i]
	}
	response[10] ^= 2
	station.management(Blob{ data: unsafe { &response[0] }, len: 30 })
	assert station.state == .authenticating
	response[10] ^= 2
	station.management(Blob{ data: unsafe { &response[0] }, len: 30 })
	assert station.state == .associating
}

fn test_receive_ccmp_replay_and_fragment_errors_are_dropped() {
	hw := &FakeHardware{}
	bytes := []u8{len: 4 * 1024 * 1024}
	mut p := fixture_protocol(hw, bytes)
	mut h := Htt{ version: true, peer_id: 5, secure: true }
	assert h.configure(mut p, true)
	put32(bytes.data, rx_buffer_base + 4, 0x80000040)
	put32(bytes.data, rx_buffer_base + 12, 0x60002005)
	put32(bytes.data, rx_buffer_base + 16, 1)
	put32(bytes.data, rx_buffer_base + 32, 0x200)
	put32(bytes.data, rx_buffer_base + 56, 0xc000)
	h.deliver(mut p, 0, 60, false)
	assert h.rx_packets == 1 && h.unicast_pn[16] == 1
	put32(bytes.data, rx_buffer_base + 4, 0x80000040)
	h.deliver(mut p, 0, 60, false)
	assert h.rx_packets == 1 && h.rx_dropped == 1
	put32(bytes.data, rx_buffer_base + 4, 0x80002040)
	put32(bytes.data, rx_buffer_base + 16, 2)
	h.deliver(mut p, 0, 60, false)
	assert h.rx_dropped == 2 && h.unicast_pn[16] == 1
	mut offload := [16]u8{}
	offload[0] = 0x12
	offload[1] = 0x20
	put16(unsafe { &offload[0] }, 6, 1)
	put32(unsafe { &offload[0] }, 8, p.transport.bus + rx_buffer_base)
	h.receive(mut p, Blob{ data: unsafe { &offload[0] }, len: 16 })
	assert h.rx_dropped == 3 && h.rx_owned[0] && !p.transport.fault
}

fn test_station_waits_for_both_matching_htt_key_acknowledgements() {
	hw := &FakeHardware{ complete: true }
	bytes := []u8{len: 4 * 1024 * 1024}
	mut p := fixture_protocol(hw, bytes)
	mut w := Wmi{}
	mut h := Htt{ version: true, peer_mapped: true, peer_id: 5 }
	assert h.configure(mut p, false)
	mut s := Station{
		state:            .keying
		deadline:         1000000000000
		key_deadline:     1000000000000
		network:          Network{ secure: true }
		response_pending: true
		wpa:              Wpa{ install_pending: true }
		key_reply:        WpaReply{ len: 113, install_pairwise: true, install_group: true, group_index: 1 }
	}
	s.tick(mut p, mut w, mut h)
	assert s.key_stage == 1 && s.state == .keying && h.tx_queued == 0
	mut ack := [28]u8{}
	ack[0] = 0xb
	ack[1] = 0x86
	put16(unsafe { &ack[0] }, 2, 6)
	h.receive(mut p, Blob{ data: unsafe { &ack[0] }, len: 28 })
	s.tick(mut p, mut w, mut h)
	assert s.key_stage == 1 && h.pairwise_confirmed == 0
	put16(unsafe { &ack[0] }, 2, 5)
	h.receive(mut p, Blob{ data: unsafe { &ack[0] }, len: 28 })
	s.tick(mut p, mut w, mut h)
	assert s.key_stage == 3 && s.state == .keying && h.tx_queued == 0
	ack[1] = 7
	h.receive(mut p, Blob{ data: unsafe { &ack[0] }, len: 28 })
	s.tick(mut p, mut w, mut h)
	assert s.key_stage == 3
	ack[1] = 6
	h.receive(mut p, Blob{ data: unsafe { &ack[0] }, len: 28 })
	s.tick(mut p, mut w, mut h)
	assert s.state == .connected && h.tx_queued == 1 && !s.response_pending
	h.peer_mapped = false
	s.tick(mut p, mut w, mut h)
	assert s.state == .failed && !s.wpa.pairwise_installed && s.wpa.active_ptk == [48]u8{}
}
