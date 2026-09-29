module mmap

import x86.cpu
import x86.cpu.local as cpulocal
import proc

pub fn pf_handler(gpr_state &cpulocal.GPRState) ? {
	// CR2 is read before interrupts go back on. Once they are, the scheduler
	// can switch this thread out, and another one's page fault on this CPU
	// overwrites CR2: the handler then looked up the other thread's address in
	// this thread's page map, found nothing there, and killed it with SIGSEGV
	// for a page that was perfectly mappable.
	addr := cpu.read_cr2()
	if gpr_state.err & 1 != 0 {
		// A write-protection fault on a fork-shared private page is the normal
		// COW path, not a process fault.
		if gpr_state.err & 2 != 0 {
			current := proc.current_thread()
			asm volatile amd64 {
				sti
			}
			resolved := current != unsafe { nil }
				&& resolve_cow_fault(current.process.pagemap, addr)
			asm volatile amd64 {
				cli
			}
			if resolved {
				return
			}
		}
		// It was a protection violation, crash
		return none
	}

	// Only user mappings can be paged in here, and during early boot there is
	// no current thread to page them in for.
	if addr >= higher_half {
		return none
	}
	mut current_thread := proc.current_thread()
	if current_thread == unsafe { nil } {
		return none
	}

	asm volatile amd64 {
		sti
	}
	defer {
		asm volatile amd64 {
			cli
		}
	}

	// A page that is mapped by the time the lock is held was paged in by
	// another thread that faulted on it too; retrying the access is all this
	// one needs.
	mut pagemap := current_thread.process.pagemap
	page_in(mut pagemap, addr, true)?
}

// x86 keeps the instruction cache coherent with stores.
fn sync_new_code_page(_page voidptr) {}
