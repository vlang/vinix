// SPDX-License-Identifier: GPL-2.0-or-later
module cpu

// Keep exception/entry assembly in V sources as raw GNU PowerPC templates.
// This leaf also exercises module-scope assembly through the C backend.
asm ppc raw {
	".pushsection .text.vinix_ppc_read_pvr,\"ax\"\n"
	".balign 4\n"
	".globl vinix_ppc_read_pvr\n"
	"vinix_ppc_read_pvr:\n"
	"mfspr 3,287\n"
	"blr\n"
	".popsection\n"
}

fn C.vinix_ppc_read_pvr() u32

pub fn read_pvr() u32 {
	return C.vinix_ppc_read_pvr()
}

pub fn read_msr() u32 {
	mut value := u32(0)
	asm volatile ppc raw {
		"mfmsr %[value]"
		; [value] "=r" (value)
	}
	return value
}

pub fn timebase() u64 {
	mut high := u32(0)
	mut low := u32(0)
	mut check := u32(0)
	for {
		asm volatile ppc raw {
			"mftbu %[high]\n\t"
			"mftb %[low]\n\t"
			"mftbu %[check]"
			; [high] "=&r" (high)
			  [low] "=&r" (low)
			  [check] "=r" (check)
		}
		if high == check { return u64(high) << 32 | u64(low) }
	}
	return 0
}

pub fn sync() {
	asm volatile ppc raw {
		"sync"
		; ; ; memory
	}
}

pub fn io_barrier() {
	asm volatile ppc raw {
		"eieio"
		; ; ; memory
	}
}

// Sequentially consistent 32-bit CAS. Return the observed value, including on
// failure. The b constraint excludes r0, which means zero in an address base.
pub fn compare_exchange32(address &u32, expected u32, desired u32) u32 {
	mut old := u32(0)
	asm volatile ppc raw {
		"sync\n\t"
		"1: lwarx %[old],0,%[address]\n\t"
		"cmpw %[old],%[expected]\n\t"
		"bne 2f\n\t"
		"stwcx. %[desired],0,%[address]\n\t"
		"bne- 1b\n\t"
		"2: isync"
		; [old] "=&r" (old)
		; [address] "b" (address)
		  [expected] "r" (expected)
		  [desired] "r" (desired)
		; memory
		  cr0
	}
	return old
}

// Publish freshly written instructions on G4's separate data/instruction caches.
pub fn publish_code(address u32, size u32) {
	if size == 0 || size > 0xffffffff - address { return }
	end := address + size
	mut line := address & ~u32(31)
	for line < end {
		asm volatile ppc raw {
			"dcbf 0,%[line]"
			; ; [line] "b" (line)
			; memory
		}
		if line > 0xffffffff - 32 { break }
		line += 32
	}
	sync()
	line = address & ~u32(31)
	for line < end {
		asm volatile ppc raw {
			"icbi 0,%[line]"
			; ; [line] "b" (line)
			; memory
		}
		if line > 0xffffffff - 32 { break }
		line += 32
	}
	asm volatile ppc raw {
		"sync\n\tisync"
		; ; ; memory
	}
}
