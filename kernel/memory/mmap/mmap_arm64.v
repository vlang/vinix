module mmap

import aarch64.cpu
import aarch64.cpu.local as cpulocal
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

	mut process := current_thread.process
	mut pagemap := process.pagemap
	trace_gpu := process.executable_path == '/usr/bin/vinix-desktop-gpu'
	mut trace_sequence := u64(0)
	mut trace_this_fault := false
	if trace_gpu {
		pid := u64(process.pid)
		if gpu_desktop_fault_pid != pid {
			gpu_desktop_fault_pid = pid
			gpu_desktop_fault_count = 0
		}
		trace_sequence = gpu_desktop_fault_count
		gpu_desktop_fault_count++
		trace_this_fault = trace_sequence < 32
		if trace_this_fault {
			println('exec[gpu]: page fault #${trace_sequence} begin addr=0x${addr:x} pc=0x${gpr_state.pc:x} esr=0x${esr:x}')
			println('exec[gpu]: page fault #${trace_sequence} retaining exception interrupt mask during traced resolution')
		}
	}

	// Normally a demand fault may be preempted while it obtains and installs
	// the backing page. The bounded GPU-exec trace above is deliberately slow:
	// every line also redraws the framebuffer, so the first three vector lines
	// consume the freshly armed 5 ms slice. Enabling FIQs here then dispatches
	// the expired scheduler timer before the first page-fault checkpoint and
	// makes the diagnostic itself look like a fault-handler hang on the M1.
	// Keep the exception entry mask for traced faults. The pending timer is
	// delivered as soon as the vector restores EL0, after the PTE and cache
	// maintenance are complete; ordinary untraced faults remain preemptible.
	prev := cpu.interrupt_toggle(!trace_this_fault)
	defer {
		cpu.interrupt_toggle(prev)
	}

	if trace_this_fault {
		println('exec[gpu]: page fault #${trace_sequence} acquiring page-map lock')
	}
	pagemap.l.acquire()
	if trace_this_fault {
		println('exec[gpu]: page fault #${trace_sequence} page-map lock acquired')
	}

	mut range_local, memory_page, file_page := addr2range(pagemap, addr) or {
		if trace_this_fault {
			println('exec[gpu]: page fault #${trace_sequence} ERROR address has no range')
		}
		pagemap.l.release()
		return none
	}

	pagemap.l.release()
	if trace_this_fault {
		println('exec[gpu]: page fault #${trace_sequence} range found; acquiring backing page')
	}

	virt := memory_page * page_size
	page := acquire_range_page(range_local, virt, file_page) or {
		if trace_this_fault {
			println('exec[gpu]: page fault #${trace_sequence} ERROR acquiring backing page')
		}
		return none
	}
	if trace_this_fault {
		println('exec[gpu]: page fault #${trace_sequence} backing page acquired')
	}
	if range_local.prot & prot_exec != 0 {
		if trace_this_fault {
			println('exec[gpu]: page fault #${trace_sequence} synchronizing instruction cache')
		}
		cpu.sync_instruction_cache(u64(page) + higher_half, page_size)
		if trace_this_fault {
			println('exec[gpu]: page fault #${trace_sequence} instruction cache synchronized')
		}
	}
	if trace_this_fault {
		println('exec[gpu]: page fault #${trace_sequence} installing PTE')
	}

	map_page_in_range(range_local.global, virt, u64(page), range_local.prot) or {
		if trace_this_fault {
			println('exec[gpu]: page fault #${trace_sequence} ERROR installing PTE')
		}
		release_range_page(range_local.global, virt, file_page, page, range_local.flags)
		return none
	}
	if trace_this_fault {
		println('exec[gpu]: page fault #${trace_sequence} resolved')
	}
}
