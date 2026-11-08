// SPDX-License-Identifier: GPL-2.0-or-later
module mmu

import powerpc.cpu
import powerpc.hash32
import powerpc.runtime

pub struct Mapping {
pub mut:
	virtual  u32
	physical u32
	writable bool
}

pub struct Space {
pub mut:
	table    u32
	count    u32
	mappings [1024]Mapping
}

pub fn (mut space Space) init(table u32) bool {
	if table == 0 || table & 65535 != 0 { return false }
	space.table = table
	space.count = 0
	runtime.fill(voidptr(table), 0, hash32.bytes)
	return true
}

pub fn (mut space Space) map(address u32, physical u32, writable bool) bool {
	if space.table == 0 || address < 0x40000000 || address >= 0x60000000
		|| (address | physical) & 4095 != 0 || physical == 0 || space.count >= 1024
		|| (writable && address < 0x50000000) {
		return false
	}
	vsid := address >> 28
	mut table := unsafe { &hash32.Pte(space.table) }
	index := hash32.slot(table, vsid, address)
	if index < 0 { return false }
	secondary := u32(index) / 8 != hash32.primary(vsid, address)
	unsafe { table[index].page = physical | 0x180 | if writable { u32(2) } else { u32(3) } }
	cpu.sync()
	unsafe { table[index].tag = hash32.tag(vsid, address, secondary) }
	cpu.sync()
	space.mappings[space.count] = Mapping{address, physical, writable}
	space.count++
	invalidate(address)
	return true
}

pub fn (space &Space) translate(address u32, write bool) u32 {
	page := address & ~u32(4095)
	for i := u32(0); i < space.count; i++ {
		mapping := space.mappings[i]
		if mapping.virtual == page {
			if write && !mapping.writable { return 0 }
			return mapping.physical + (address & 4095)
		}
	}
	return 0
}

pub fn (space &Space) accessible(address u32, size u32, write bool) bool {
	if size > 0xffffffff - address { return false }
	if size == 0 { return true }
	for page := address & ~u32(4095); page <= (address + size - 1) & ~u32(4095); page += 4096 {
		if space.translate(page, write) == 0 { return false }
		if page == 0xfffff000 { break }
	}
	return true
}

pub fn (space &Space) activate() {
	// The kernel runs real-mode; revoke every inherited firmware BAT before
	// enabling relocation in userspace. Hardware hash walking, no high BATs
	// or extended physical addressing. This backend targets the 745x family.
	asm volatile ppc raw {
		"li 0,0\nmtspr 528,0\nmtspr 530,0\nmtspr 532,0\nmtspr 534,0\n"
		"mtspr 536,0\nmtspr 538,0\nmtspr 540,0\nmtspr 542,0\n"
		"mfspr 4,1008\nlis 5,0x0182\nandc 4,4,5\nmtspr 1008,4\n"
		"mtsdr1 %[table]\nsync\nisync"
		; ; [table] "r" (space.table)
		; r0
		  r4
		  r5
		  memory
	}
	for segment := u32(0); segment < 16; segment++ {
		address := segment << 28
		value := 0x20000000 | segment | if segment == 4 { u32(0) } else { u32(0x10000000) }
		asm volatile ppc raw {
			"mtsrin %[value],%[address]"
			; ; [value] "r" (value)
			[address] "r" (address)
			; memory
		}
	}
	// MPC7450UM 2.4.6: real G4 chips do not implement tlbia, even though
	// QEMU accepts it. Invalidate all 64 indices with tlbie instead.
	for index := u32(0); index < 64; index++ { invalidate(index << 12) }
}

fn invalidate(address u32) {
	asm volatile ppc raw {
		"sync\ntlbie %[address]\ntlbsync\nsync\nisync"
		; ; [address] "r" (address)
		; memory
	}
}
