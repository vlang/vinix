@[has_globals]
module rtl8169

import devcore

#include <stdio.h>
#flag -Dkprintf=printf

fn C.kprintf(format &char, ...int) int

__global (
	regs        [256]u8
	phy         [32768]u16
	mac         [32768]u16
	ephy        [32]u16
	eri         [256]u32
	fail_port   u64 = 0xffff
	stuck_reset bool
	phy_writes  int
	tx_kicks    int
)

fn map_registers(phys u64, length u64) u64 { return phys }

fn read8(port u64) u8 { return regs[port] }

fn read16(port u64) u16 { return u16(read8(port)) | u16(read8(port + 1)) << 8 }

fn read32(port u64) u32 { return u32(read16(port)) | u32(read16(port + 2)) << 16 }

fn write8(port u64, value u8) {
	if port == 0x38 && value == 0x40 { tx_kicks++ }
	if port == 0x37 && value == 0x0c {
		assert devcore.last_command & 4 != 0
		assert read32(0xe4) != 0 && read32(0x20) != 0
	}
	regs[port] = if port == 0x37 && value & 0x10 != 0 && !stuck_reset { u8(0) } else { value }
}

fn write16(port u64, value u16) {
	if port == 0x3e {
		regs[port] &= ~u8(value)
		regs[port + 1] &= ~u8(value >> 8)
		return
	}
	regs[port] = u8(value)
	regs[port + 1] = u8(value >> 8)
}

fn raw_write32(port u64, value u32) {
	write16(port, u16(value))
	write16(port + 2, u16(value >> 16))
}

fn write32(port u64, command u32) {
	if port == fail_port {
		raw_write32(port, if command & 0x80000000 != 0 { command } else { u32(0) })
		return
	}
	address := (command >> 15) & 0xffff
	index := address / 2
	if port == 0xb8 || port == 0xb0 {
		if command & 0x80000000 != 0 {
			if port == 0xb8 {
				phy[index] = if index == 0xa400 / 2 {
					u16(command) & ~u16(0x8000)
				} else {
					u16(command)
				}
				phy_writes++
			} else {
				mac[index] = u16(command)
			}
			raw_write32(port, 0)
		} else {
			value := if port == 0xb8 { phy[index] } else { mac[index] }
			raw_write32(port, 0x80000000 | u32(value))
		}
	} else if port == 0x80 {
		reg := (command >> 16) & 31
		if command & 0x80000000 != 0 {
			ephy[reg] = u16(command)
			raw_write32(port, 0)
		} else {
			raw_write32(port, 0x80000000 | u32(ephy[reg]))
		}
	} else if port == 0x74 {
		reg := (command & 0xfff) / 4
		if command & 0x80000000 != 0 {
			eri[reg] = read32(0x70)
			raw_write32(port, 0)
		} else {
			raw_write32(0x70, eri[reg])
			raw_write32(port, 0x80000000)
		}
	} else {
		raw_write32(port, command)
	}
}

fn dma_barrier() {}

fn descriptor_status(address u64) u32 { return unsafe { *&u32(address) } }

fn set_descriptor_status(address u64, value u32) {
	unsafe { *&u32(address) = value }
}
