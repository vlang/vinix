module mmap

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.timer
import proc

pub fn pf_handler(gpr_state &cpulocal.GPRState) ? {
	esr := cpu.read_esr_el1()
	// ESR_EL1 ISS field for data aborts: bits [5:0] = DFSC
	// Permission fault: DFSC = 0b0011xx (0x0C-0x0F)
	dfsc := esr & 0x3f
	if dfsc >= 0x0c && dfsc <= 0x0f {
		addr := cpu.read_far_el1()
		wnr := (esr >> 6) & 1
		current := proc.current_thread()
		previous_interrupt_state := cpu.interrupt_toggle(true)
		resolved := wnr != 0 && addr < higher_half && current != unsafe { nil }
			&& resolve_cow_fault(current.process.pagemap, addr)
		cpu.interrupt_toggle(previous_interrupt_state)
		if resolved {
			return
		}
		// Permission fault — trace details before crashing
		print('PF_PERM: dfsc=0x')
		print(dfsc.hex())
		print(' addr=0x')
		print(addr.hex())
		print(' pc=0x')
		print(gpr_state.pc.hex())
		print(' wnr=')
		println(wnr.str())
		// It was a permission fault (protection violation), crash
		return none
	}

	addr := cpu.read_far_el1()

	// Only user mappings can be paged in here. A fault on a kernel address
	// (HHDM, MMIO aperture, kernel image) has nothing to resolve, and during
	// early boot there is no current thread at all: dereferencing it from the
	// fault path re-faults, recursing until the exception stack is gone, and
	// the report that would have named the real fault never prints. Hand such
	// faults straight back to the caller's fault reporter.
	if addr >= higher_half {
		return none
	}
	mut current_thread := proc.current_thread()
	if current_thread == unsafe { nil } {
		return none
	}

	// Resolve the fault as one exception transaction. In particular, do not
	// enable the scheduler FIQ between finding the backing page and installing
	// its PTE: a file-backed fault on the M1 can outlive a 5 ms quantum, and a
	// context switch from this nested synchronous exception leaves the initial
	// exec handoff unable to make forward progress. The earlier bounded startup
	// trace happened to avoid that race by stopping the timer around each fault.
	// Make that correctness property independent of diagnostics, and give the
	// faulting instruction a fresh quantum in which to retry after the PTE and
	// instruction-cache maintenance are complete.
	fault_timeslice := if current_thread.timeslice != 0 { current_thread.timeslice } else { u64(1) }
	timer.stop()
	defer {
		timer.oneshot(fault_timeslice)
	}

	mut process := current_thread.process
	mut pagemap := process.pagemap

	// A translation fault on a page that is mapped by now raced with a
	// break-before-make update of its descriptor: fork write-protecting it, or
	// a copy-on-write fault resolved on another CPU. Retrying the access is all
	// it needs. Paging the range's page in again would map a page still shared
	// with a fork child writable, behind copy-on-write's back.
	page_in(mut pagemap, addr, dfsc >= 0x04 && dfsc <= 0x07)?
}

// A page about to be mapped executable must reach the instruction cache.
fn sync_new_code_page(page voidptr) {
	cpu.sync_instruction_cache(u64(page) + higher_half, page_size)
}
