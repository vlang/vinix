// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module mmap

// The Linux VM syscalls that need to reach inside the range bookkeeping:
// mremap, mincore, madvise and brk.

import errno
import lib
import memory
import proc
import usercopy

// mremap(2) flags.
pub const mremap_maymove = 1

pub const mremap_fixed = 2

// madvise(2) advice values we act on. Everything else is a hint we can ignore.
const madv_dontneed = 4

const madv_free = 8

// The program break lives in its own arena, well clear of the thread stacks at
// 0x70000000000 and the anonymous mmap region at 0x80000000000.
// How many pages mincore answers for between copy-outs.
const mincore_chunk = 512

const brk_arena_base = u64(0x60000000000)

const brk_arena_size = u64(0x10000000000)

// ── mremap ───────────────────────────────────────────────────────────────────

// mremap(old_address, old_size, new_size, flags, new_address).
//
// Growing in place is not attempted: a range's pages are handed out by mmap()
// up front and the global range that owns them is sized once, so extending one
// would mean rebuilding it. With MREMAP_MAYMOVE — which is what every libc
// realloc passes — a fresh mapping is made, the contents are carried over and
// the old range is dropped, which is a move Linux is equally free to make.
pub fn syscall_mremap(_ voidptr, old_address u64, old_size u64, new_size u64, flags u64, new_address u64) (u64, u64) {
	mut process := proc.current_thread().process
	mut pagemap := process.pagemap

	if old_address % page_size != 0 || new_size == 0 {
		return errno.err, errno.einval
	}
	if flags & ~u64(mremap_maymove | mremap_fixed) != 0 {
		return errno.err, errno.einval
	}
	if flags & mremap_fixed != 0 {
		if flags & mremap_maymove == 0 || new_address % page_size != 0 {
			return errno.err, errno.einval
		}
	}

	old_length := lib.align_up(old_size, page_size)
	new_length := lib.align_up(new_size, page_size)

	pagemap.l.acquire()
	source, _, _ := addr2range(pagemap, old_address) or {
		pagemap.l.release()
		return errno.err, errno.efault
	}
	// Only a mapping we can describe in full can be moved.
	if old_address + old_length > source.base + source.length {
		pagemap.l.release()
		return errno.err, errno.efault
	}
	prot := source.prot
	map_flags := source.flags
	// A move has to re-establish the mapping against whatever backs it, so the
	// resource and its handle come along, and the file offset is the source
	// range's own offset advanced to wherever inside it the move starts.
	mut global := source.global
	source_resource := global.resource
	source_handle := global.handle
	source_handle_ref := global.handle_ref
	source_handle_unref := global.handle_unref
	source_offset := source.offset + i64(old_address - source.base)
	mut source_options := MmapOptions{
		lazy_file: global.lazy_file
		segmented_file: global.segmented_file
	}
	if global.segmented_file {
		source_relative := old_address - global.base
		data_begin := global.file_data_start
		data_end := data_begin + global.file_data_length
		move_end := source_relative + new_length
		overlap_begin := if data_begin > source_relative { data_begin } else { source_relative }
		overlap_end := if data_end < move_end { data_end } else { move_end }
		if overlap_end > overlap_begin {
			source_options.file_data_start = overlap_begin - source_relative
			source_options.file_data_length = overlap_end - overlap_begin
		}
	}
	pagemap.l.release()

	// Shrinking, or asking for what is already there, needs no new mapping.
	if new_length <= old_length && flags & mremap_fixed == 0 {
		if new_length < old_length {
			munmap(mut pagemap, voidptr(old_address + new_length), old_length - new_length) or {
				return errno.err, errno.get()
			}
		}
		return old_address, 0
	}

	if flags & mremap_maymove == 0 {
		// Nothing can be done without permission to relocate.
		return errno.err, errno.enomem
	}

	anonymous := map_flags & map_anonymous != 0

	mut destination_flags := map_flags
	mut destination_hint := voidptr(0)
	if flags & mremap_fixed != 0 {
		destination_flags |= map_fixed
		destination_hint = voidptr(new_address)
	}

	mut destination_offset := i64(0)
	if !anonymous {
		destination_offset = source_offset
	}

	destination := mmap_with_credit(pagemap, destination_hint, new_length, prot, destination_flags, source_resource, destination_offset, source_handle, source_handle_ref, source_handle_unref, old_length, source_options) or {
		return errno.err, errno.get()
	}

	// Only anonymous pages have to be carried over by hand. A file mapping is
	// rebuilt at the same offset against the same resource, so it comes back
	// holding the same pages, and copying would be writing them onto
	// themselves.
	if anonymous {
		carried := if old_length < new_length { old_length } else { new_length }
		if !copy_between_mappings(pagemap, u64(destination), old_address, carried) {
			munmap(mut pagemap, destination, new_length) or {}
			return errno.err, errno.efault
		}
	}

	munmap(mut pagemap, voidptr(old_address), old_length) or {}

	return u64(destination), 0
}

// Move page contents through the direct map, so neither address has to be
// touched with the user's own mapping active.
fn copy_between_mappings(pagemap &memory.Pagemap, destination u64, source u64, length u64) bool {
	for offset := u64(0); offset < length; offset += page_size {
		source_phys := pagemap.virt2phys(source + offset) or { return false }
		destination_phys := pagemap.virt2phys(destination + offset) or { return false }
		unsafe {
			C.memcpy(voidptr(destination_phys + higher_half), voidptr(source_phys + higher_half), page_size)
		}
	}
	return true
}

// ── mincore ──────────────────────────────────────────────────────────────────

// mincore(addr, length, vec): one byte per page, bit 0 set when the page is
// resident. mmap() populates a range up front, so this reports what the page
// tables actually hold rather than a guess.
pub fn syscall_mincore(_ voidptr, address u64, length u64, vec u64) (u64, u64) {
	mut process := proc.current_thread().process
	mut pagemap := process.pagemap

	if address % page_size != 0 {
		return errno.err, errno.einval
	}

	pages := lib.div_roundup(length, page_size)
	if pages == 0 {
		return 0, 0
	}

	// Linux reports ENOMEM when the range is not fully mapped, and callers use
	// that to probe for holes, so the whole span is checked before anything is
	// written back.
	pagemap.l.acquire()
	for i := u64(0); i < pages; i++ {
		addr2range(pagemap, address + i * page_size) or {
			pagemap.l.release()
			return errno.err, errno.enomem
		}
	}
	pagemap.l.release()

	// The answers are gathered a chunk at a time and copied out with the
	// pagemap lock dropped: copy_to_user takes that same lock to walk the
	// caller's tables, and it is not a reentrant one.
	mut chunk := [mincore_chunk]u8{}
	for done := u64(0); done < pages;  {
		mut count := pages - done
		if count > u64(mincore_chunk) {
			count = u64(mincore_chunk)
		}

		pagemap.l.acquire()
		for i := u64(0); i < count; i++ {
			mut resident := u8(0)
			if _ := pagemap.virt2phys(address + (done + i) * page_size) {
				resident = 1
			}
			chunk[i] = resident
		}
		pagemap.l.release()

		if !usercopy.copy_to_user(vec + done, voidptr(&chunk[0]), count) {
			return errno.err, errno.efault
		}
		done += count
	}

	return 0, 0
}

// ── madvise ──────────────────────────────────────────────────────────────────

// madvise(addr, length, advice).
//
// MADV_DONTNEED and MADV_FREE promise that the next read of an anonymous page
// gives back zeroes. Resident pages are zeroed in place; sparse large mappings
// stay absent and the fault path supplies a fresh zeroed page on first access.
// Every other advice is a hint with nothing to do.
pub fn syscall_madvise(_ voidptr, address u64, length u64, advice int) (u64, u64) {
	if address % page_size != 0 {
		return errno.err, errno.einval
	}
	if advice != madv_dontneed && advice != madv_free {
		return 0, 0
	}

	mut process := proc.current_thread().process
	mut pagemap := process.pagemap

	pages := lib.div_roundup(length, page_size)

	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}

	for i := u64(0); i < pages; i++ {
		virt := address + i * page_size
		local_range, _, _ := addr2range(pagemap, virt) or { continue }
		if local_range.flags & map_anonymous == 0 || local_range.flags & map_shared != 0 {
			continue
		}
		phys := pagemap.virt2phys(virt) or { continue }
		unsafe {
			C.memset(voidptr(phys + higher_half), 0, page_size)
		}
	}

	return 0, 0
}

// ── brk ──────────────────────────────────────────────────────────────────────

// brk(addr). brk(0) reports the current break; anything else moves it and
// reports where it ended up, which is the old value when the move fails.
pub fn syscall_brk(_ voidptr, address u64) (u64, u64) {
	mut process := proc.current_thread().process

	if process.brk_base == 0 {
		// Reserve the arena once and commit pages with mprotect as the break
		// grows. Building the heap from adjacent MAP_FIXED mappings exposed
		// separate backing ranges to libc and corrupted QEMU's allocator under
		// repeated growth. A single stable reservation also prevents unrelated
		// mappings from occupying future heap pages.
		mut pagemap := process.pagemap
		mmap(pagemap, voidptr(brk_arena_base), brk_arena_size, prot_none, map_anonymous | map_private | map_fixed_noreplace | map_brk_reservation, unsafe { nil }, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }) or {
			return 0, 0
		}
		process.brk_base = brk_arena_base
		process.brk_current = brk_arena_base
	}

	if address == 0 || address == process.brk_current {
		return process.brk_current, 0
	}
	if address < process.brk_base || address > process.brk_base + brk_arena_size {
		return process.brk_current, 0
	}
	requested_data := address - process.brk_base
	if !proc.limit_allows(process, proc.rlimit_data, requested_data) {
		return process.brk_current, 0
	}

	current_page := lib.align_up(process.brk_current, page_size)
	wanted_page := lib.align_up(address, page_size)

	if wanted_page > current_page {
		current_as := address_space_bytes(process.pagemap, process)
		growth := wanted_page - current_page
		if growth > u64(-1) - current_as
			|| !proc.limit_allows(process, proc.rlimit_as, current_as + growth) {
			return process.brk_current, 0
		}
		mut pagemap := process.pagemap
		mprotect(mut pagemap, voidptr(current_page), wanted_page - current_page, prot_read | prot_write) or {
			return process.brk_current, 0
		}
	} else if wanted_page < current_page {
		mut pagemap := process.pagemap
		mprotect(mut pagemap, voidptr(wanted_page), current_page - wanted_page, prot_none) or {
			return process.brk_current, 0
		}
	}

	process.brk_current = address
	return process.brk_current, 0
}
