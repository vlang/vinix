// SPDX-License-Identifier: ISC
module ath10k

fn channel_frequency(channel u16) u32 {
	return if channel >= 1 && channel <= 11 { 2407 + u32(channel) * 5 } else { u32(0) }
}

pub fn (mut w Wmi) echo(mut p Protocol, token u32) bool {
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(echo_id)
	data := c.section(tag_struct_echo_cmd, 4) or { return false }
	put32(data.data, 0, token)
	return p.send(p.wmi, c.blob())
}

fn (w &Wmi) channel_allowed(channel u16) bool {
	f := channel_frequency(channel)
	return f != 0 && f >= w.low2 && f <= w.high2
}

fn fill_channel(data Blob, frequency u32, passive bool) {
	put32(data.data, 0, frequency)
	put32(data.data, 4, frequency)
	put32(data.data, 12, 1 | if passive { u32(1 << 7) } else { u32(0) }) // 11g, 20 MHz
	// Conservative 10 dBm ceiling, further bounded by board regulatory data.
	put32(data.data, 16, 20 << 8 | 20 << 16)
	put32(data.data, 20, 20 << 8)
}

pub fn (mut w Wmi) channel_table(mut p Protocol) bool {
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x3003)
	data := c.section(tag_struct_scan_chan_list_cmd, 4) or { return false }
	mut count := u32(0)
	for channel in u16(1) .. 12 { if w.channel_allowed(channel) { count++ } }
	if count == 0 { return false }
	put32(data.data, 0, count)
	array := c.section(tag_array_struct, count * 28) or { return false }
	mut index := u32(0)
	for channel in u16(1) .. 12 {
		if !w.channel_allowed(channel) { continue }
		put16(array.data, index, 24)
		put16(array.data, index + 2, tag_struct_channel)
		fill_channel(array.view(index + 4, 24), channel_frequency(channel), true)
		index += 28
	}
	return p.send(p.wmi, c.blob())
}

pub fn (mut w Wmi) start_station(mut p Protocol, network &Network) bool {
	if !w.vdev || w.started || !w.channel_allowed(network.channel) { return false }
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x5003)
	data := c.section(tag_struct_vdev_start_request_cmd, 72) or { return false }
	put32(data.data, 4, 1)
	put32(data.data, 8, if network.beacon_interval == 0 {
		u32(100)
	} else {
		u32(network.beacon_interval)
	})
	put32(data.data, 12, 1)
	put32(data.data, 20, network.ssid_len)
	for i in u32(0) .. network.ssid_len {
		unsafe { data.data[24 + i] = network.ssid[i] }
	}
	channel := c.section(tag_struct_channel, 24) or { return false }
	fill_channel(channel, channel_frequency(network.channel), false)
	c.section(tag_array_struct, 0) or { return false }
	w.start_status = 0xffffffff
	return p.send(p.wmi, c.blob())
}

pub fn (mut w Wmi) peer_create(mut p Protocol, mac &[6]u8) bool {
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x6001)
	data := c.section(tag_struct_peer_create_cmd, 16) or { return false }
	for i in 0 .. 6 {
		unsafe { data.data[4 + i] = mac[i] }
	}
	put32(data.data, 12, 1)
	return p.send(p.wmi, c.blob())
}

pub fn (mut w Wmi) associate(mut p Protocol, network &Network, aid u16) bool {
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x6005)
	data := c.section(tag_struct_peer_assoc_complete_cmd, 76) or { return false }
	for i in 0 .. 6 {
		unsafe { data.data[i] = network.bssid[i] }
	}
	put32(data.data, 12, 1)
	put32(data.data, 16, aid)
	put32(data.data, 20, 1 | if network.secure { u32(4 | 16) } else { u32(0) })
	put32(data.data, 24, network.capabilities)
	put32(data.data, 28, 10)
	put32(data.data, 48, 1)
	put32(data.data, 56, 1)
	put32(data.data, 68, network.rate_count)
	rates := c.section(tag_array_byte, (u32(network.rate_count) + 3) & ~u32(3)) or { return false }
	for i in u32(0) .. network.rate_count {
		unsafe { rates.data[i] = network.rates[i] & 0x7f }
	}
	c.section(tag_array_byte, 0) or { return false }
	c.section(tag_struct_vht_rate_set, 16) or { return false }
	return p.send(p.wmi, c.blob())
}

pub fn (mut w Wmi) up(mut p Protocol, mac &[6]u8, aid u16) bool {
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	c.header(0x5005)
	data := c.section(tag_struct_vdev_up_cmd, 16) or { return false }
	put32(data.data, 4, aid)
	for i in 0 .. 6 {
		unsafe { data.data[8 + i] = mac[i] }
	}
	return p.send(p.wmi, c.blob())
}

pub fn (mut w Wmi) install_key(mut p Protocol, mac &[6]u8, key &[16]u8, index u8, group bool, rsc u64) bool {
	mut c := unsafe { &Command(C.__builtin_alloca(sizeof(Command))) }
	unsafe { *c = Command{} }
	defer { erase(unsafe { &c.data[0] }, 2048) }
	c.header(0x5009)
	data := c.section(tag_struct_vdev_install_key_cmd, 92) or { return false }
	for i in 0 .. 6 {
		unsafe { data.data[4 + i] = mac[i] }
	}
	put32(data.data, 12, index)
	put32(data.data, 16, if group { u32(1) } else { u32(0) })
	put32(data.data, 20, 4) // WMI_TLV_CIPHER_AES_CCM
	put32(data.data, 24, u32(rsc))
	put32(data.data, 28, u32(rsc >> 32))
	put32(data.data, 80, 16)
	bytes := c.section(tag_array_byte, 16) or { return false }
	for i in 0 .. 16 {
		unsafe { bytes.data[i] = key[i] }
	}
	return p.send(p.wmi, c.blob())
}
