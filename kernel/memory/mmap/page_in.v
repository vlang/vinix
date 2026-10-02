module mmap

import memory
import proc

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
	generation := range_local.generation
	executable := range_local.prot & prot_exec != 0

	pagemap.l.release()

	virt := memory_page * page_size
	page := if flags & map_anonymous != 0 {
		acquire_anonymous_page()
	} else {
		acquire_range_page(range_local, virt, file_page)
	} or {
		return none
	}
	if executable {
		sync_new_code_page(page)
	}

	install_range_page(mut pagemap, range_local, generation, virt, file_page, page, flags)?
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
