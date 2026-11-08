// SPDX-License-Identifier: GPL-2.0-or-later
module mmio

pub fn read8(address u32) u8 {
	mut value := u32(0)
	asm volatile ppc raw { "lbz %[value],0(%[address])\neieio" ; [value] "=r" (value) ; [address] "b" (address) ; memory }
	return u8(value)
}

pub fn write8(address u32, value u8) {
	asm volatile ppc raw { "stb %[value],0(%[address])\neieio" ; ; [address] "b" (address) [value] "r" (value) ; memory }
}

pub fn read16(address u32) u16 {
	mut value := u32(0)
	asm volatile ppc raw { "lhbrx %[value],0,%[address]\neieio" ; [value] "=r" (value) ; [address] "b" (address) ; memory }
	return u16(value)
}

pub fn write16(address u32, value u16) {
	asm volatile ppc raw { "sthbrx %[value],0,%[address]\neieio" ; ; [address] "b" (address) [value] "r" (value) ; memory }
}

pub fn read32(address u32) u32 {
	mut value := u32(0)
	asm volatile ppc raw {
		"lwbrx %[value],0,%[address]\neieio"
		; [value] "=r" (value)
		; [address] "b" (address)
		; memory
	}
	return value
}

pub fn write32(address u32, value u32) {
	asm volatile ppc raw {
		"stwbrx %[value],0,%[address]\neieio"
		; ; [address] "b" (address)
		[value] "r" (value)
		; memory
	}
}

pub fn write_be32(address u32, value u32) {
	asm volatile ppc raw {
		"stw %[value],0(%[address])\neieio"
		; ; [address] "b" (address)
		[value] "r" (value)
		; memory
	}
}

pub fn read_be32(address u32) u32 {
	mut value := u32(0)
	asm volatile ppc raw { "lwz %[value],0(%[address])\neieio" ; [value] "=r" (value) ; [address] "b" (address) ; memory }
	return value
}

pub fn write_be16(address u32, value u32) {
	asm volatile ppc raw { "sth %[value],0(%[address])\neieio" ; ; [address] "b" (address) [value] "r" (value) ; memory }
}

pub fn read_be16(address u32) u32 {
	mut value := u32(0)
	asm volatile ppc raw { "lhz %[value],0(%[address])\neieio" ; [value] "=r" (value) ; [address] "b" (address) ; memory }
	return value
}

// DMA descriptors/buffers are cache-line aligned and exclusively owned when
// published. Invalidate only after the device has relinquished ownership.
pub fn publish(address u32, size u32) {
	for at := address & ~u32(31); at < address + size; at += 32 {
		asm volatile ppc raw { "dcbf 0,%[at]" ; ; [at] "b" (at) ; memory }
	}
	asm volatile ppc raw { "sync" ; ; ; memory }
}

pub fn acquire(address u32, size u32) {
	for at := address & ~u32(31); at < address + size; at += 32 {
		asm volatile ppc raw { "dcbi 0,%[at]" ; ; [at] "b" (at) ; memory }
	}
	asm volatile ppc raw { "sync" ; ; ; memory }
}
