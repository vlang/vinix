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

	mut process := current_thread.process
	mut pagemap := process.pagemap
	prev := cpu.interrupt_toggle(true)
	defer {
		cpu.interrupt_toggle(prev)
	}

	// A translation fault on a page that is mapped by now raced with a
	// break-before-make update of its descriptor: fork write-protecting it, or
	// a copy-on-write fault resolved on another CPU. Retrying the access is all
	// it needs. Paging the range's page in again would map a page still shared
	// with a fork child writable, behind copy-on-write's back.
	page_in(mut pagemap, addr, dfsc >= 0x04 && dfsc <= 0x07)?
}

// Page in the page holding `addr` from the mapping it belongs to. With
// `present_is_done`, a page that is mapped by the time the lock is held is left
// as it is.
fn page_in(mut pagemap memory.Pagemap, addr u64, present_is_done bool) ? {
	pagemap.l.acquire()

	mut range_local, memory_page, file_page := addr2range(pagemap, addr) or {
		pagemap.l.release()
		return none
	}

	if present_is_done {
		if _ := pagemap.virt2phys(memory_page * page_size) {
			pagemap.l.release()
			return
		}
	}
	flags := range_local.flags
	executable := range_local.prot & prot_exec != 0

	pagemap.l.release()

	virt := memory_page * page_size
	page := acquire_range_page(range_local, virt, file_page) or {
		return none
	}
	if executable {
		cpu.sync_instruction_cache(u64(page) + higher_half, page_size)
	}

	install_range_page(mut pagemap, range_local, virt, file_page, page, flags)?
	note_anonymous_fault(pagemap, flags)
}

// Anonymous memory that is filled in on demand -- a large mapping, or any
// private one of a process in a cgroup -- is committed a page at a time as it
// faults in, so memory.max is checked here, once every 256 pages (1 MiB):
// often enough to catch a runaway allocation early, rarely enough that
// counting the group's memory stays off the fault path's cost.
fn note_anonymous_fault(pagemap &memory.Pagemap, flags int) {
	if flags & map_anonymous == 0 {
		return
	}
	mut process := proc.current_thread().process
	if unsafe { process == nil } || process.cgroup_account == unsafe { nil }
		|| voidptr(process.pagemap) != voidptr(pagemap) {
		return
	}
	process.faults_since_memory_check++
	if process.faults_since_memory_check < 256 {
		return
	}
	process.faults_since_memory_check = 0
	proc.cgroup_charge_memory(process, 256 * page_size)
}

// Nothing is in the page tables for a page of a mapping that has not been
// touched yet; the fault handler pages it in when userspace first touches it.
// The kernel copying to or from such a page on a process' behalf -- a syscall's
// buffer, a signal set in a binary's read-only data -- has to do the same, or
// the syscall fails with EFAULT on a perfectly good pointer.
fn resolve_missing_page(_pagemap &memory.Pagemap, address u64) bool {
	if address >= higher_half {
		return false
	}
	mut pagemap := unsafe { _pagemap }
	page_in(mut pagemap, address, true) or { return false }
	return true
}

fn register_page_in_resolver() {
	memory.register_page_in_resolver(resolve_missing_page)
}
