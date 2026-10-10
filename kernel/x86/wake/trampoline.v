// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The page under 1 MiB a processor starts on, and the page table it climbs
// out of it with.
//
// The boot loader starts this kernel's processors, in long mode, and the
// kernel had no way to start one itself. A suspend to RAM needs one: firmware
// hands the machine back in real mode at an address below 1 MiB, and the
// other processors have to be started again from real mode too. So a few
// pages there are taken out of the allocator before its first allocation
// (memory/lowmem_amd64.v), the code in asm/x86_64/wake_trampoline.S is copied
// to the first of them, and the others hold a page table of the kernel's own
// that maps that one page onto itself -- the instructions between "paging on"
// and "jump to the kernel" run at their low address -- beside the kernel's
// half of the address space, which it shares with every other page table.
//
// The page table is rebuilt for every use (arm()), and the trampoline is told
// each time where to go and on what stack. In between, the page is inert: its
// header names no entry, and a processor that starts there halts.
@[has_globals]
module wake

import memory
import x86.cpu
import x86.msr

fn C.x86_wake_trampoline()
fn C.x86_wake_trampoline_end()

// asm/x86_64/wake_trampoline.S: two words, where the far jumps land in the page.
fn C.x86_wake_protected_offset()
fn C.x86_wake_long_offset()

// The trampoline itself, then a table for each level of the page table: five
// at most, with 57-bit addresses.
pub const low_pages_wanted = u64(8)
const table_pages = u64(5)
const header_offset = u64(8)
const header_magic = u32(0x454b4157)

const msr_efer = u32(0xc0000080)
const efer_lma = u64(1) << 10
const cr4_pae = u64(1) << 5
const cr4_la57 = u64(1) << 12

// asm/x86_64/wake_trampoline.S has the same layout at wake_header.
@[packed]
struct Header {
mut:
	magic              u32
	trace              u32
	cr3                u32
	cr4                u32
	cr0                u32
	reserved           u32
	efer               u64
	entry              u64
	stack              u64
	argument           u64
	protected_offset   u32
	protected_selector u16
	pad0               u16
	long_offset        u32
	long_selector      u16
	pad1               u16
	gdt_limit          u16
	gdt_base           u32
	pad2               u16
}

__global (
	// Physical address of the trampoline page; 0 when there is none.
	x86wake_page u64
	// Why not, for whoever reports it.
	x86wake_unavailable string
)

fn header() &Header {
	return unsafe { &Header(x86wake_page + higher_half + header_offset) }
}

// Copy the trampoline to its page. Called once at boot, after the virtual
// memory is up; false when the machine has no room for it under 1 MiB, in
// which case nothing here can be used and suspend to RAM is not offered.
pub fn install() bool {
	base, pages := memory.low_pages()
	if base == 0 || pages < 1 + table_pages {
		x86wake_unavailable = 'no memory below 1 MiB for the wake-up code'
		return false
	}
	start := u64(voidptr(C.x86_wake_trampoline))
	size := u64(voidptr(C.x86_wake_trampoline_end)) - start
	if size > page_size || !layout_matches() {
		x86wake_unavailable = 'the wake-up code is not laid out as expected'
		return false
	}
	unsafe {
		C.memset(voidptr(base + higher_half), 0, pages * page_size)
		C.memcpy(voidptr(base + higher_half), voidptr(start), size)
	}
	x86wake_page = base
	mut h := header()
	if h.magic != header_magic {
		x86wake_page = 0
		x86wake_unavailable = 'the wake-up code is not laid out as expected'
		return false
	}
	h.protected_offset = u32(base) + unsafe { *&u32(voidptr(C.x86_wake_protected_offset)) }
	h.long_offset = u32(base) + unsafe { *&u32(voidptr(C.x86_wake_long_offset)) }
	// The GDT follows the header and the empty IDT pointer in the page; its
	// limit is assembled in.
	h.gdt_base = u32(base + header_offset + sizeof(Header) + 8)
	C.kprintf(c'wake: real-mode entry at 0x%llx, %llu bytes\n', base, size)
	return true
}

pub fn available() bool {
	return x86wake_page != 0
}

// Why install() failed, for whoever explains that deep sleep is not offered.
pub fn unavailable_reason() string {
	return x86wake_unavailable
}

// The address a processor is to start at: what goes into the FACS waking
// vector, and, as a page number, into a startup IPI.
pub fn entry_address() u64 {
	return x86wake_page
}

fn table(index u64) &u64 {
	return unsafe { &u64(x86wake_page + (1 + index) * page_size + higher_half) }
}

fn table_phys(index u64) u64 {
	return x86wake_page + (1 + index) * page_size
}

// Point the trampoline at `entry`, to be entered with `stack` and `argument`,
// and make its page table. Whoever calls this is the only one using the page:
// processors are started one at a time.
fn arm(entry u64, stack u64, argument u64) {
	levels := if la57 { u64(5) } else { u64(4) }
	for i in 0 .. table_pages {
		unsafe { C.memset(voidptr(table(i)), 0, page_size) }
	}
	// The top level shares the kernel's half with the kernel's own table.
	mut top := table(0)
	kernel_top := unsafe { &u64(u64(kernel_pagemap.top_level) + higher_half) }
	for i in 256 .. 512 {
		unsafe {
			top[i] = kernel_top[i]
		}
	}
	// And one page of the other half: this one, at its own address.
	for level in 0 .. levels - 1 {
		shift := 12 + 9 * (levels - 1 - level)
		mut entries := table(level)
		unsafe {
			entries[(x86wake_page >> shift) & 0x1ff] = table_phys(level + 1) | memory.pte_present | memory.pte_writable
		}
	}
	mut last := table(levels - 1)
	unsafe {
		last[(x86wake_page >> 12) & 0x1ff] = x86wake_page | memory.pte_present | memory.pte_writable
	}

	mut h := header()
	h.cr3 = u32(table_phys(0))
	h.cr4 = u32(cr4_pae | if la57 { cr4_la57 } else { u64(0) })
	// As this processor has them: every processor of the machine runs with
	// the same CR0, and EFER.LMA is the processor's to set.
	h.cr0 = u32(cpu.read_cr0())
	h.efer = msr.rdmsr(msr_efer) & ~efer_lma
	h.stack = stack
	h.argument = argument
	$if wake_trace ? {
		h.trace = 1
	}
	// Last: this is what says the page may be used.
	h.entry = entry
}

// Leave the page as it is between uses.
fn disarm() {
	mut h := header()
	h.entry = 0
	h.stack = 0
	h.argument = 0
}
