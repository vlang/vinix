module mmap

import memory
import proc

pub enum PageFault {
	resolved
	beyond_eof
	protection
}

// Page in the page holding `addr` from the mapping it belongs to. With
// `present_is_done`, a page that is mapped by the time the lock is held is left
// as it is.
fn page_in(mut pagemap memory.Pagemap, addr u64, present_is_done bool,
	require_readable bool, fault_access int) ?PageFault {
	pagemap.l.acquire()

	mut range_local, memory_page, file_page := addr2range(pagemap, addr) or {
		pagemap.l.release()
		return none
	}
	if require_readable && (range_local.prot & prot_read == 0 || !page_mapping_has_node(range_local)) {
		pagemap.l.release()
		return none
	}
	if fault_access != 0 && range_local.prot & fault_access == 0 {
		pagemap.l.release()
		return .protection
	}

	if present_is_done {
		if _ := pagemap.virt2phys(memory_page * page_size) {
			pagemap.l.release()
			return .resolved
		}
	}
	source := range_page_source(range_local, memory_page * page_size)

	pagemap.l.release()
	virt := memory_page * page_size
	read_before := proc.current_disk_read_bytes()
	result := fill_range_page(mut pagemap, source, virt, file_page)?
	if result != .resolved { return result }
	proc.account_page_fault(pagemap, proc.current_disk_read_bytes() != read_before)
	note_anonymous_fault(pagemap, source.flags)
	return .resolved
}

// Anonymous memory that is filled in on demand -- a large mapping, or any
// private one of a process in a cgroup -- is committed a page at a time as it
// faults in, so memory.max is checked here, once every 16 committed pages:
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
	if process.faults_since_memory_check < 16 {
		return
	}
	process.faults_since_memory_check = 0
	proc.cgroup_charge_memory(process, 16 * page_size)
}

// Nothing is in the page tables for a page of a mapping that has not been
// touched yet; the fault handler pages it in when userspace first touches it.
// The kernel copying to or from such a page on a process' behalf -- a syscall's
// buffer, a signal set in a binary's read-only data -- has to do the same, or
// the syscall fails with EFAULT on a perfectly good pointer.
fn resolve_missing_page(_pagemap &memory.Pagemap, address u64) bool {
	return resolve_missing_with_access(_pagemap, address, false)
}

fn resolve_missing_with_access(_pagemap &memory.Pagemap, address u64, require_readable bool) bool {
	if address >= higher_half {
		return false
	}
	mut pagemap := unsafe { _pagemap }
	for {
		exhausted := memory.exhaustions()
		result := page_in(mut pagemap, address, true, require_readable, 0) or {
			if out_of_memory_since(exhausted, false) {
				continue
			}
			return false
		}
		return result == .resolved
	}
	return false
}

// Whether what just failed did so for lack of memory -- memory.exhaustions()
// has moved on from `exhausted`, sampled before it -- and is worth trying
// again, a process having been killed for the memory (userland/oom.v). False
// when the calling process is the one killed. For a caller in a syscall; a
// fault taken in userspace is its handler's to retry. `sleepable` is as for
// memory.recover_from_exhaustion(): mmap() filling its own pages holds
// nothing, and the kernel copying for some other syscall cannot tell.
fn out_of_memory_since(exhausted u64, sleepable bool) bool {
	return memory.exhaustions() != exhausted && memory.recover_from_exhaustion(sleepable)
}

// resolve_cow_fault() for the kernel writing to a process' page on its
// behalf: a copy there is no memory for is waited for, as above.
fn resolve_cow_waiting(pagemap &memory.Pagemap, address u64) bool {
	for {
		exhausted := memory.exhaustions()
		if resolve_cow_fault(pagemap, address) {
			return true
		}
		if !out_of_memory_since(exhausted, false) {
			break
		}
	}
	return false
}

fn register_page_in_resolver() {
	memory.register_page_in_resolver(resolve_missing_page)
}
