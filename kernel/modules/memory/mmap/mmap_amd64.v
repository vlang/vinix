module mmap

import x86.cpu
import x86.cpu.local as cpulocal
import memory
import proc

pub fn pf_handler(gpr_state &cpulocal.GPRState) ? {
	if gpr_state.err & 1 != 0 {
		// A write-protection fault on a fork-shared private page is the normal
		// COW path, not a process fault.
		if gpr_state.err & 2 != 0 {
			current := proc.current_thread()
			asm volatile amd64 {
				sti
			}
			resolved := current != unsafe { nil }
				&& resolve_cow_fault(current.process.pagemap, cpu.read_cr2())
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

	mut current_thread := proc.current_thread()

	asm volatile amd64 {
		sti
	}
	defer {
		asm volatile amd64 {
			cli
		}
	}

	mut process := current_thread.process
	mut pagemap := process.pagemap

	addr := cpu.read_cr2()

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
