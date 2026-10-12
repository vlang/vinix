// SPDX-License-Identifier: GPL-2.0-only
// Register sequences adapted from Linux v6.6 r8169_main.c and
// r8169_phy_config.c, Realtek / Francois Romieu and contributors.
@[has_globals]
module rtl8169

__global (
	rtl_version  int
	rtl_phy_base u32 = 0xa400
)

// All indirect accesses have a deadline and fail the probe on timeout.
fn indirect_read(port u64, command u32) ?u16 {
	write32(port, command)
	if !wait32(port, 0x80000000, true) { return none }
	return u16(read32(port))
}

fn indirect_write(port u64, command u32) bool {
	write32(port, command | 0x80000000)
	return wait32(port, 0x80000000, false)
}

fn phy_read(reg u32) ?u16 {
	if reg == 0x1f { return if rtl_phy_base == 0xa400 { u16(0) } else { u16(rtl_phy_base >> 4) } }
	if reg > 0x1f || (rtl_phy_base != 0xa400 && reg < 0x10) { return none }
	index := if rtl_phy_base == 0xa400 { reg } else { reg - 0x10 }
	return indirect_read(0xb8, (rtl_phy_base + index * 2) << 15)
}

fn phy_write(reg u32, value u16) bool {
	if reg == 0x1f {
		rtl_phy_base = if value == 0 { u32(0xa400) } else { u32(value) << 4 }
		return true
	}
	if reg > 0x1f || (rtl_phy_base != 0xa400 && reg < 0x10) { return false }
	// G silicon requires PHY MCU interrupts enabled before reset or wake.
	if rtl_version == 40 && rtl_phy_base == 0xa400 && reg == 0 {
		set := if value & 0x8000 != 0 || value & 0x0800 == 0 { u32(0xfc000000) } else { u32(0) }
		if !eri_modify(0x1a8, 0xfc000000, set) { return false }
	}
	index := if rtl_phy_base == 0xa400 { reg } else { reg - 0x10 }
	return indirect_write(0xb8, ((rtl_phy_base + index * 2) << 15) | u32(value))
}

fn phy_modify(page u16, reg u32, clear u16, set u16) bool {
	if !phy_write(0x1f, page) { return false }
	value := phy_read(reg) or { return false }
	return phy_write(reg, (value & ~clear) | set) && phy_write(0x1f, 0)
}

fn phy_parameter(parameter u16, clear u16, set u16) bool {
	if !phy_write(0x1f, 0xa43) || !phy_write(0x13, parameter) { return false }
	value := phy_read(0x14) or { return false }
	return phy_write(0x14, (value & ~clear) | set) && phy_write(0x1f, 0)
}

fn mac_read(reg u32) u16 {
	write32(0xb0, reg << 15)
	return u16(read32(0xb0))
}

fn mac_write(reg u32, value u16) {
	write32(0xb0, 0x80000000 | (reg << 15) | u32(value))
}

fn mac_modify(reg u32, clear u16, set u16) {
	mac_write(reg, (mac_read(reg) & ~clear) | set)
}

fn eri_read(address u32) ?u32 {
	write32(0x74, address | 0xf000)
	if !wait32(0x74, 0x80000000, true) { return none }
	return read32(0x70)
}

fn eri_write(address u32, mask u32, value u32) bool {
	write32(0x70, value)
	return indirect_write(0x74, address | (mask << 12))
}

fn eri_modify(address u32, clear u32, set u32) bool {
	value := eri_read(address) or { return false }
	return eri_write(address, 15, (value & ~clear) | set)
}

fn ephy_modify(reg u32, clear u16, set u16) bool {
	value := indirect_read(0x80, reg << 16) or { return false }
	return indirect_write(0x80, (reg << 16) | u32((value & ~clear) | set))
}

// Firmware's OOB receiver owns the shared FIFO until this handshake.
fn leave_oob() bool {
	write32(0xf0, read32(0xf0) | (u32(1) << 19))
	pause_ms(2)
	write8(0x37, read8(0x37) & ~u8(0x0c))
	pause_ms(1)
	write8(0xd3, read8(0xd3) & ~u8(0x80))
	mac_modify(0xe8de, 0x4000, 0)
	if !wait8(0xd3, 2, true) { return false }
	mac_modify(0xe8de, 0, 0x8000)
	return wait8(0xd3, 2, true)
}

fn configure_mac() bool {
	// Keep ASPM and clock requests disabled; GU silicon can disrupt the bus
	// when they are enabled. PCIe Link Control is also disabled by probe.
	write8(0x53, read8(0x53) & ~u8(0x80))
	write8(0x56, read8(0x56) & ~u8(1))
	if !eri_write(0xc8, 15, 0x00080010) || !eri_write(0xe8, 15, 0x00020006)
		|| !eri_write(0xcc, 1, 0x38) || !eri_write(0xd0, 1, 0x48)
		|| !eri_modify(0xdc, 1, 0) || !eri_modify(0xdc, 0, 1)
		|| !eri_write(0x2f8, 3, 0x1d8f) || !eri_write(0xc0, 3, 0)
		|| !eri_write(0xb8, 3, 0) || !eri_modify(0x2fc, 1, 6)
		|| !eri_modify(0x1b0, 0x1000, 0) {
		return false
	}
	write32(0xf0, read32(0xf0) & ~(u32(1) << 19))
	write8(0x54, read8(0x54) & ~u8(6)) // no L2/L3 reset / jumbo frames
	write8(0x55, read8(0x55) & ~u8(1))
	mac_modify(0xc0ac, 0, 0x1f80)
	// Disable EEE until the driver has link-state and power policy support.
	mac_modify(0xe040, 3, 0)
	if !ephy_modify(0, 8, 0) || !ephy_modify(0x0c, 0x3ff0, 0x0820) { return false }
	if rtl_version == 40 {
		return ephy_modify(0x1e, 0, 1) && ephy_modify(0x19, 0x8000, 0)
	}
	return ephy_modify(0x19, 0xffff, 0x7c00) && ephy_modify(0x1e, 0xffff, 0x20eb)
		&& ephy_modify(0x0d, 0xffff, 0x1666) && ephy_modify(0, 0xffff, 0x10a3)
		&& ephy_modify(6, 0xffff, 0xf050) && ephy_modify(4, 0, 0x10)
		&& ephy_modify(0x1d, 0x4000, 0)
}

fn configure_phy() bool {
	rtl_phy_base = 0xa400
	// Power up before firmware writes; do not inherit firmware's power-down.
	if !phy_write(0, 0x1000) { return false }
	pause_ms(20)
	if rtl_version == 40 {
		if !apply_firmware(unsafe { &firmware_g[0] }, firmware_g.len) { return false }
		if !wait_phy_reset() {
			print('rtl8169: firmware PHY reset timed out\n')
			return false
		}
		if !phy_write(0x1f, 0xa46) { return false }
		a := phy_read(0x10) or { return false }
		b := phy_read(0x13) or { return false }
		if !phy_modify(0xbcc, 0x12, 0x8000, if a & 0x100 == 0 { u16(0x8000) } else { u16(0) })
			|| !phy_modify(0xc41, 0x15, 2, if b & 0x100 != 0 { u16(2) } else { u16(0) })
			|| !phy_modify(0xa44, 0x11, 0, 0x000c)
			|| !phy_modify(0xbcc, 0x14, 0x100, 0)
			|| !phy_modify(0xa44, 0x11, 0, 0xc0)
			|| !phy_parameter(0x8084, 0x6000, 0)
			|| !phy_modify(0xa43, 0x10, 0, 0x1003)
			|| !phy_modify(0xa4b, 0x11, 0, 4)
			|| !phy_parameter(0x8012, 0, 0x8000)
			|| !phy_modify(0xc42, 0x11, 0x2000, 0x4000) {
			return false
		}
		if !phy_write(0x1f, 0xbcd) || !phy_write(0x14, 0x5065) || !phy_write(0x14, 0xd065)
			|| !phy_write(0x1f, 0xbc8) || !phy_write(0x11, 0x5655)
			|| !phy_write(0x1f, 0xbcd) || !phy_write(0x14, 0x1065)
			|| !phy_write(0x14, 0x9065) || !phy_write(0x14, 0x1065) {
			return false
		}
	} else {
		if !apply_firmware(unsafe { &firmware_gu[0] }, firmware_gu.len)
			|| !wait_phy_reset() {
			return false
		}
	}
	if !phy_modify(0xa43, 0x10, 4, 0) || !phy_modify(0xa43, 0x11, 0, 0x10)
		|| !phy_write(0x1f, 0) {
		return false
	}
	// Disable EEE advertisement via standard Clause 22 MMD indirection.
	if !phy_write(13, 7) || !phy_write(14, 0x3c) || !phy_write(13, 0x4007)
		|| !phy_write(14, 0) || !phy_write(13, 0) {
		return false
	}
	if !phy_write(0, 0x9000) || !wait_phy_reset() {
		print('rtl8169: PHY soft reset timed out\n')
		return false
	}
	// Advertise 10/100 and 1000 full duplex; checksum and VLAN offloads off.
	return phy_write(4, 0x01e1) && phy_write(9, 0x0200) && phy_write(0, 0x1200)
}
