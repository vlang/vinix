// SPDX-License-Identifier: GPL-2.0-or-later
module mmap

import errno
import lib
import memory
import proc
import stat

const mcl_current = 1
const mcl_future = 2
const mcl_onfault = 4

// Existing mapping ownership pins every installed physical/cache page.
// Locking therefore needs residency and a VMA discard barrier, not another
// allocation or resource reference per locked page. The page map lock guards
// flags and accounting; population never holds it over filesystem callbacks.
fn lockable_range(local &MmapRangeLocal, process &proc.Process) bool {
	if local.flags & map_brk_reservation == 0 || local.prot != prot_none { return true }
	// A committed heap page can be made PROT_NONE by the program. It still
	// differs from the enormous reserve before/after the actual program break.
	return process.pagemap.brk_current > process.pagemap.brk_base && local.base >= process.pagemap.brk_base
		&& local.base + local.length <= lib.align_up(process.pagemap.brk_current, page_size)
}

fn locked_bytes_unlocked(pagemap &memory.Pagemap) u64 {
	mut total := u64(0)
	for pointer in pagemap.mmap_ranges {
		local := unsafe { &MmapRangeLocal(pointer) }
		if local.flags & map_locked != 0 { total += local.length }
	}
	return total
}

pub fn locked_bytes(_pagemap &memory.Pagemap) u64 {
	if _pagemap == unsafe { nil } { return 0 }
	mut pagemap := unsafe { _pagemap }
	pagemap.l.acquire()
	defer { pagemap.l.release() }
	return locked_bytes_unlocked(pagemap)
}

fn locked_overlap_unlocked(pagemap &memory.Pagemap, base u64, length u64) u64 {
	return locked_source_overlap_unlocked(pagemap, base, length, 0)
}

fn locked_source_overlap_unlocked(pagemap &memory.Pagemap, base u64, length u64, serial u64) u64 {
	mut total := u64(0)
	end := base + length
	for pointer in pagemap.mmap_ranges {
		local := unsafe { &MmapRangeLocal(pointer) }
		if local.flags & map_locked == 0 || (serial != 0 && local.global.serial != serial) { continue }
		begin := if base > local.base { base } else { local.base }
		finish := if end < local.base + local.length { end } else { local.base + local.length }
		if finish > begin { total += finish - begin }
	}
	return total
}

fn can_lock_memory(process &proc.Process) bool {
	if proc.current_has_capability(proc.cap_ipc_lock)
		|| proc.soft_limit(process, proc.rlimit_memlock) != 0 { return true }
	errno.set(errno.eperm)
	return false
}

fn lock_limit_allows(process &proc.Process, total u64) bool {
	return proc.current_has_capability(proc.cap_ipc_lock)
		|| total <= lib.align_down(proc.soft_limit(process, proc.rlimit_memlock), page_size)
}

fn lock_span(address u64, length u64) ?(u64, u64) {
	in_page := address % page_size
	if address > u64(-1) - length || length > u64(-1) - in_page
		|| length + in_page > u64(-1) - (page_size - 1) {
		errno.set(errno.einval)
		return none
	}
	base := lib.align_down(address, page_size)
	aligned := lib.align_up(length + in_page, page_size)
	if base > memory.user_address_limit() || aligned > memory.user_address_limit() - base {
		errno.set(errno.enomem)
		return none
	}
	return base, aligned
}

fn supported_lock_pages(local &MmapRangeLocal, begin u64, end u64) bool {
	if local.flags & map_anonymous != 0 { return true }
	global := local.global
	if global.resource == unsafe { nil } || !stat.isreg(global.resource.stat.mode) {
		errno.set(errno.enotsup)
		return false
	}
	for page := begin; page < end; page += page_size {
		if global.segmented_file && !range_page_has_file_data(global, page) { continue }
		offset := u64(local.offset) + page - local.base
		if offset >= u64(global.resource.stat.size) {
			errno.set(errno.enomem)
			return false
		}
	}
	return true
}

// Preflight all ranges before changing any flag. Internal brk reservation
// tails are not user heap mappings and must not make MCL_CURRENT lock a TiB.
fn preflight_lock_unlocked(pagemap &memory.Pagemap, base u64, length u64, supported bool,
	allow_brk_reservation bool) bool {
	end := base + length
	mut current := base
	for current < end {
		local, _, _ := addr2range(pagemap, current) or { errno.set(errno.enomem); return false }
		if supported && !allow_brk_reservation
			&& !lockable_range(local, proc.current_thread().process) { errno.set(errno.enomem); return false }
		finish := min_u64(end, local.base + local.length)
		if supported && !supported_lock_pages(local, current, finish) { return false }
		current = finish
	}
	return true
}

fn resident_span_unlocked(pagemap &memory.Pagemap, base u64, length u64) bool {
	for page := base; page < base + length; page += page_size {
		if _ := pagemap.virt2phys(page) { continue }
		return false
	}
	return true
}

// Splits keep the existing global's ownership. No physical page or resource
// reference is acquired for a metadata boundary.
fn set_lock_flags_unlocked(mut pagemap memory.Pagemap, base u64, length u64, locked bool) ? {
	end := base + length
	mut current := base
	for current < end {
		mut local, _, _ := addr2range(pagemap, current) or { return }
		finish := min_u64(end, local.base + local.length)
		current = finish
		if (local.flags & map_locked != 0) == locked { continue }
		if base > local.base && finish < local.base + local.length {
			mut piece := new_local_range(unsafe { *local })? @[freed]
			piece.base = finish
			piece.length = local.base + local.length - finish
			piece.offset = local.offset + i64(finish - local.base)
			split_off_unlocked(mut pagemap, local, piece)
		}
		begin := if base > local.base { base } else { local.base }
		mut changed := local
		if begin != local.base || finish - begin != local.length {
			changed = new_local_range(unsafe { *local })? @[freed]
			changed.base = begin
			changed.length = finish - begin
			changed.offset = local.offset + i64(begin - local.base)
			split_off_unlocked(mut pagemap, local, changed)
		}
		if locked { changed.flags |= map_locked } else { changed.flags &= ~map_locked }
	}
}

// Called before MAP_FIXED removes anything, under the address-space lock.
// A moving locked mapping gets credit for the source span still installed.
fn prepare_mapping_lock_unlocked(pagemap &memory.Pagemap, process &proc.Process,
	local &MmapRangeLocal, fixed bool, credit u64, options MmapOptions) bool {
	if local.flags & map_locked == 0 { return true }
	if !can_lock_memory(process) { return false }
	if !supported_lock_pages(local, local.base, local.base + local.length) { return false }
	mut current := locked_bytes_unlocked(pagemap)
	if fixed { current -= locked_overlap_unlocked(pagemap, local.base, local.length) }
	if options.credit_serial != 0 {
		current -= locked_source_overlap_unlocked(pagemap, options.credit_base, credit,
			options.credit_serial)
	}
	if local.length > u64(-1) - current || !lock_limit_allows(process, current + local.length) {
		errno.set(errno.eagain)
		return false
	}
	return true
}

fn lock_range(mut pagemap memory.Pagemap, base u64, length u64, locked bool,
	allow_brk_reservation bool) ? {
	process := proc.current_thread().process
	if locked && !can_lock_memory(process) { return none }
	for _ in 0 .. 3 {
		pagemap.l.acquire()
		if !preflight_lock_unlocked(&pagemap, base, length, locked, allow_brk_reservation) {
			pagemap.l.release()
			return none
		}
		if !locked {
			set_lock_flags_unlocked(mut pagemap, base, length, false) or { pagemap.l.release(); return none }
			pagemap.l.release()
			return
		}
		total := locked_bytes_unlocked(&pagemap) + length - locked_overlap_unlocked(&pagemap, base, length)
		if !lock_limit_allows(process, total) {
			pagemap.l.release()
			errno.set(errno.enomem)
			return none
		}
		pagemap.l.release()
		populate_missing_pages(mut pagemap, base, length, prot_read | prot_write, false) or {
			errno.set(errno.enomem)
			return none
		}
		pagemap.l.acquire()
		if !preflight_lock_unlocked(&pagemap, base, length, true, allow_brk_reservation) {
			pagemap.l.release()
			return none
		}
		if !lock_limit_allows(process, locked_bytes_unlocked(&pagemap) + length
			- locked_overlap_unlocked(&pagemap, base, length)) {
			pagemap.l.release()
			errno.set(errno.enomem)
			return none
		}
		if resident_span_unlocked(&pagemap, base, length) {
			set_lock_flags_unlocked(mut pagemap, base, length, true) or { pagemap.l.release(); return none }
			pagemap.l.release()
			return
		}
		pagemap.l.release()
	}
	errno.set(errno.eagain)
	return none
}

pub fn syscall_mlock(_ voidptr, address u64, length u64) (u64, u64) {
	base, aligned := lock_span(address, length) or { return errno.err, errno.get() }
	mut pagemap := proc.current_thread().process.pagemap
	lock_range(mut pagemap, base, aligned, true, false) or { return errno.err, errno.get() }
	return 0, 0
}

pub fn syscall_munlock(_ voidptr, address u64, length u64) (u64, u64) {
	base, aligned := lock_span(address, length) or { return errno.err, errno.get() }
	mut pagemap := proc.current_thread().process.pagemap
	lock_range(mut pagemap, base, aligned, false, false) or { return errno.err, errno.get() }
	return 0, 0
}

pub fn syscall_mlock2(context voidptr, address u64, length u64, flags int) (u64, u64) {
	if flags & ~1 != 0 { return errno.err, errno.einval }
	if flags & 1 != 0 { return errno.err, errno.enotsup }
	return syscall_mlock(context, address, length)
}

pub fn syscall_mlockall(_ voidptr, flags int) (u64, u64) {
	if flags & ~7 != 0 || flags & (mcl_current | mcl_future) == 0 { return errno.err, errno.einval }
	if flags & mcl_onfault != 0 { return errno.err, errno.enotsup }
	process := proc.current_thread().process
	if !can_lock_memory(process) { return errno.err, errno.get() }
	mut pagemap := process.pagemap
	if flags & mcl_current == 0 {
		pagemap.l.acquire()
		pagemap.lock_future = true
		pagemap.l.release()
		return 0, 0
	}
	for _ in 0 .. 3 {
		pagemap.l.acquire()
		mut total := u64(0)
		for pointer in pagemap.mmap_ranges {
			local := unsafe { &MmapRangeLocal(pointer) }
			if !lockable_range(local, process) { continue }
			if !supported_lock_pages(local, local.base, local.base + local.length) {
				pagemap.l.release()
				return errno.err, errno.get()
			}
			total += local.length
		}
		if !lock_limit_allows(process, total) {
			pagemap.l.release()
			return errno.err, errno.enomem
		}
		pagemap.l.release()
		mut cursor := u64(0)
		for {
			pagemap.l.acquire()
			mut local := range_lower_bound(pagemap, cursor)
			for local != unsafe { nil } && !lockable_range(local, process) {
				local = range_lower_bound(pagemap, local.base + local.length)
			}
			if local == unsafe { nil } { pagemap.l.release(); break }
			base := local.base
			length := local.length
			cursor = base + length
			pagemap.l.release()
			populate_missing_pages(mut pagemap, base, length, prot_read | prot_write, false) or {
				return errno.err, errno.enomem
			}
		}
		pagemap.l.acquire()
		mut resident := true
		total = 0
		for pointer in pagemap.mmap_ranges {
			local := unsafe { &MmapRangeLocal(pointer) }
			if !lockable_range(local, process) { continue }
			if !supported_lock_pages(local, local.base, local.base + local.length) {
				pagemap.l.release()
				return errno.err, errno.get()
			}
			total += local.length
			if !resident_span_unlocked(pagemap, local.base, local.length) { resident = false }
		}
		if !lock_limit_allows(process, total) {
			pagemap.l.release()
			return errno.err, errno.enomem
		}
		if resident {
			for pointer in pagemap.mmap_ranges {
				mut local := unsafe { &MmapRangeLocal(pointer) }
				if lockable_range(local, process) { local.flags |= map_locked }
			}
			pagemap.lock_future = flags & mcl_future != 0
			pagemap.l.release()
			return 0, 0
		}
		pagemap.l.release()
	}
	return errno.err, errno.eagain
}

pub fn syscall_munlockall(_ voidptr) (u64, u64) {
	mut pagemap := proc.current_thread().process.pagemap
	pagemap.l.acquire()
	for pointer in pagemap.mmap_ranges {
		mut local := unsafe { &MmapRangeLocal(pointer) }
		local.flags &= ~map_locked
	}
	pagemap.lock_future = false
	pagemap.l.release()
	return 0, 0
}
