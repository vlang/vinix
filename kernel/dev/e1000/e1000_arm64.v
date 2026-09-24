module e1000

import aarch64.cpu
import aarch64.kio
import memory

// The direct map only covers RAM, and as Normal memory; registers need their
// own Device mapping.
fn map_registers(phys u64, length u64) u64 {
	return memory.map_mmio(phys, length)
}

// kio's 32-bit accessors are out-of-line assembly: a plain load or store from
// an address in a register. Anything cleverer the compiler might emit -- a
// store with base writeback, a load pair -- is an access HVF cannot decode.
fn reg_read(offset u64) u32 {
	return kio.mmin32(unsafe { &u32(e1000_regs + offset) })
}

fn reg_write(offset u64, value u32) {
	kio.mmout32(unsafe { &u32(e1000_regs + offset) }, value)
}

// Order the descriptor and buffer accesses against each other and against the
// register writes that hand them to the card. The card is outside the inner
// shareable domain, so this is a full-system barrier.
fn dma_barrier() {
	cpu.dmb_sy()
}
