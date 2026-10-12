// SPDX-License-Identifier: GPL-2.0-or-later
module rtl8169

import memory
import x86.kio

fn map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys + length <= u64(0x100000000) {
		return phys + hhdm
	}
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | u64(0x18)
	for page := phys & ~u64(0xfff); page < phys + length; page += 0x1000 {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

fn read8(offset u64) u8 { return kio.mmin[u8](unsafe { &u8(rtl_regs + offset) }) }

fn read16(offset u64) u16 { return kio.mmin[u16](unsafe { &u16(rtl_regs + offset) }) }

fn read32(offset u64) u32 { return kio.mmin[u32](unsafe { &u32(rtl_regs + offset) }) }

fn write8(offset u64, value u8) { kio.mmout[u8](unsafe { &u8(rtl_regs + offset) }, value) }

fn write16(offset u64, value u16) { kio.mmout[u16](unsafe { &u16(rtl_regs + offset) }, value) }

fn write32(offset u64, value u32) { kio.mmout[u32](unsafe { &u32(rtl_regs + offset) }, value) }

fn descriptor_status(address u64) u32 { return kio.mmin[u32](unsafe { &u32(address) }) }

fn set_descriptor_status(address u64, value u32) { kio.mmout[u32](unsafe { &u32(address) }, value) }

fn dma_barrier() {
	asm volatile amd64 {
		mfence
		; ; ; memory
	}
}
