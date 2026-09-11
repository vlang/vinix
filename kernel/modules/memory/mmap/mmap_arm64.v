module mmap

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import memory
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

	prev := cpu.interrupt_toggle(true)
	defer {
		cpu.interrupt_toggle(prev)
	}

	mut process := current_thread.process
	mut pagemap := process.pagemap

	pagemap.l.acquire()

	mut range_local, memory_page, file_page := addr2range(pagemap, addr) or {
		pagemap.l.release()
		return none
	}

	pagemap.l.release()

	mut page := unsafe { nil }

	if range_local.flags & map_anonymous != 0 {
		page = memory.pmm_alloc(1)
	} else {
		page = range_local.global.resource.mmap(range_local.global.handle, file_page, range_local.flags)
	}

	map_page_in_range(range_local.global, memory_page * page_size, u64(page), range_local.prot) or {
		return none
	}
}
