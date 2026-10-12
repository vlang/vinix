// SPDX-License-Identifier: GPL-2.0-only
// Realtek PHY bytecode semantics from Linux v6.6 r8169_firmware.c.
module rtl8169

fn apply_firmware(code &u32, count int) bool {
	mut index := 0
	mut previous := u16(0)
	mut reads := 0
	mut mcu := false
	mut steps := 0
	mut delayed := u64(0)
	rtl_phy_base = 0xa400
	for index < count {
		steps++
		if index < 0 || steps > 100000 {
			print('rtl8169: firmware instruction budget exhausted\n')
			return false
		}
		action := unsafe { code[index] }
		if action == 0 { break }
		reg := (action >> 16) & 0xfff
		data := u16(action)
		match action >> 28 {
			0 {
				previous = if mcu {
					mac_read(rtl_phy_base + reg)
				} else {
					phy_read(reg) or { return false }
				}
				reads++
			}
			1 { previous |= data }
			2 { previous &= data }
			3 {
				if int(reg) > index { return false }
				index -= int(reg)
				continue
			}
			4 {
				if data > 1 { return false }
				mcu = data != 0
			}
			7 { reads = 0 }
			8, 12 {
				value := if action >> 28 == 12 { previous } else { data }
				if mcu {
					if reg == 0x1f {
						rtl_phy_base = u32(value) << 4
					} else {
						mac_write(rtl_phy_base + reg, value)
					}
				} else if !phy_write(reg, value) {
					return false
				}
			}
			9 {
				if reads == int(data) { index++ }
			}
			10 {
				if previous == data { index += int(reg) }
			}
			11 {
				if previous != data { index += int(reg) }
			}
			13 { index += int(reg) }
			14 {
				delayed += u64(data)
				if delayed > 5000 { return false }
				pause_ms(u64(data))
			}
			else { return false }
		}
		index++
		if index > count { return false }
	}
	return phy_write(0x1f, 0)
}
