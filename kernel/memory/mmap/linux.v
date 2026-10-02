// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module mmap

// The Linux VM syscalls that need to reach inside the range bookkeeping:
// mremap, mincore, madvise and brk.

import errno
import krandom
import lib
import memory
import proc
import resource
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

// 960 GiB, which ends the arena 64 GiB short of the stack region. A whole TiB
// reached 0x70000000000 itself, with the stack of every program's first
// thread already mapped at its top: reserving the arena failed for every
// process, brk() reported a break of 0, and allocators went to mmap instead.
// Walking the reservation costs only what is mapped in it (see
// Pagemap.next_present), so fork and exit do not pay for its size.
const brk_arena_size = u64(0xf000000000)

// The break starts at a random page in the first 256 MiB of the arena, a
// different one for each program, as OpenBSD starts it: a heap at the same
// address in every process is one an exploit needs no leak to find.
const brk_aslr_span = u64(0x10000000)

fn random_brk_start() u64 {
	mut random := u64(0)
	if !krandom.fill(voidptr(&random), sizeof(random), true) {
		return brk_arena_base
	}
	return brk_arena_base + (random % (brk_aslr_span / page_size)) * page_size
}

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
	if old_length < old_size || new_length < new_size
		|| old_address > u64(-1) - old_length
		|| (flags & mremap_fixed != 0 && (new_address > u64(-1) - new_length
			|| (new_address < old_address + old_length && new_address + new_length > old_address))) {
		return errno.err, errno.einval
	}

	pagemap.l.acquire()
	source, _, source_file_page := addr2range(pagemap, old_address) or {
		pagemap.l.release()
		return errno.err, errno.efault
	}
	// Restored lock/protection splits can still describe one original mapping.
	// Incompatible pieces or independently created globals cannot be moved as
	// though they had a single resource and policy.
	if !compatible_remap_span_unlocked(pagemap, old_address, old_length, source, source_file_page) {
		pagemap.l.release()
		return errno.err, errno.get()
	}
	if source.immutable {
		pagemap.l.release()
		return errno.err, errno.eperm
	}
	prot := source.prot
	map_flags := source.flags
	// The reserved heap belongs to brk bookkeeping, including its uncommitted
	// tail. Moving or shrinking it would leave the process break naming a
	// different mapping; copying its private flag would also bypass limits.
	if map_flags & map_brk_reservation != 0 {
		pagemap.l.release()
		return errno.err, errno.einval
	}
	// What fork does with the range moves with it, as on Linux.
	inheritance := InheritChange{
		set_dont_fork: true
		dont_fork: source.dont_fork
		set_wipe_on_fork: true
		wipe_on_fork: source.wipe_on_fork
	}
	// A move has to re-establish the mapping against whatever backs it, so the
	// resource and its handle come along, and the file offset is the source
	// range's own offset advanced to wherever inside it the move starts.
	mut global := source.global
	source_resource := global.resource
	source_handle := global.handle
	source_handle_ref := global.handle_ref
	source_handle_unref := global.handle_unref
	// Keep the file/description alive while mmap acquires destination ownership.
	// Driver mapping-range callbacks still run outside the address-space lock.
	mut held_handle := false
	mut held_resource := false
	if map_flags & map_anonymous == 0 {
		if source_handle != unsafe { nil } && source_handle_ref != unsafe { nil } {
			source_handle_ref(source_handle)
			held_handle = true
		} else if source_resource != unsafe { nil } {
			mut retained := source_resource
			resource.retain_resource(mut retained)
			held_resource = true
		}
	}
	defer {
		if held_handle { source_handle_unref(source_handle) }
		else if held_resource {
			mut retained := source_resource
			resource.release_resource(mut retained)
		}
	}
	source_offset := source.offset + i64(old_address - source.base)
	mut source_options := MmapOptions{
		lazy_file: global.lazy_file
		segmented_file: global.segmented_file
		no_write: global.no_write
		no_exec: global.no_exec
		credit_base: old_address
		credit_serial: global.serial
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
		pagemap.l.acquire()
		if !remap_span_unlocked(pagemap, old_address, old_length, source_options.credit_serial, true) {
			pagemap.l.release()
			return errno.err, errno.get()
		}
		if new_length < old_length {
			munmap_unlocked(mut pagemap, voidptr(old_address + new_length), old_length - new_length) or {
				pagemap.l.release()
				return errno.err, errno.get()
			}
		}
		pagemap.l.release()
		return old_address, 0
	}

	if flags & mremap_maymove == 0 {
		// Nothing can be done without permission to relocate.
		return errno.err, errno.enomem
	}

	anonymous := map_flags & map_anonymous != 0

	mut destination_flags := map_flags & ~(map_fixed | map_fixed_noreplace | map_brk_reservation)
	mut destination_hint := voidptr(0)
	if flags & mremap_fixed != 0 {
		destination_flags |= map_fixed
		destination_hint = voidptr(new_address)
	}

	mut destination_offset := i64(0)
	if !anonymous {
		destination_offset = source_offset
	}

	mut destination_serial := u64(0)
	// mmap only writes this synchronous stack output while publishing its VMA.
	source_options.created_serial = unsafe { &destination_serial }
	destination := mmap_with_credit(pagemap, destination_hint, new_length, prot, destination_flags, source_resource, destination_offset, source_handle, source_handle_ref, source_handle_unref, old_length, source_options) or {
		return errno.err, errno.get()
	}
	// Before anything is copied in: a thread forking meanwhile must not hand
	// its child what the range was kept from children for.
	if inheritance.dont_fork || inheritance.wipe_on_fork {
		pagemap.l.acquire()
		if !remap_span_unlocked(pagemap, u64(destination), new_length, destination_serial, true) {
			failure := errno.get()
			pagemap.l.release()
			unmap_created_range(mut pagemap, u64(destination), new_length, destination_serial)
			return errno.err, failure
		}
		set_inheritance_unlocked(mut pagemap, u64(destination), new_length, inheritance) or {
			failure := errno.get()
			pagemap.l.release()
			unmap_created_range(mut pagemap, u64(destination), new_length, destination_serial)
			return errno.err, failure
		}
		pagemap.l.release()
	}

	// Private file pages can contain writes that never reached the backing
	// file. Preserve those just like anonymous pages; shared file pages are
	// still rebuilt against the same resource without copying.
	if anonymous || map_flags & map_shared == 0 {
		carried := if old_length < new_length { old_length } else { new_length }
		if !copy_between_mappings(mut pagemap, u64(destination), old_address, carried,
			source_options.credit_serial, destination_serial, source_file_page) {
			failure := errno.get()
			unmap_created_range(mut pagemap, u64(destination), new_length, destination_serial)
			return errno.err, failure
		}
	}

	pagemap.l.acquire()
	if !remap_span_unlocked(pagemap, old_address, old_length, source_options.credit_serial, true)
		|| !remap_span_unlocked(pagemap, u64(destination), new_length, destination_serial, false) {
		failure := errno.get()
		pagemap.l.release()
		unmap_created_range(mut pagemap, u64(destination), new_length, destination_serial)
		return errno.err, failure
	}
	munmap_unlocked(mut pagemap, voidptr(old_address), old_length) or {
		failure := errno.get()
		pagemap.l.release()
		unmap_created_range(mut pagemap, u64(destination), new_length, destination_serial)
		return errno.err, failure
	}
	pagemap.l.release()

	return u64(destination), 0
}

fn compatible_remap_span_unlocked(pagemap &memory.Pagemap, base u64, length u64,
	reference &MmapRangeLocal, first_page u64) bool {
	mut cursor := base
	for cursor < base + length {
		local, _, file_page := addr2range(pagemap, cursor) or { errno.set(errno.efault); return false }
		if local.immutable { errno.set(errno.eperm); return false }
		if local.global != reference.global || local.prot != reference.prot
			|| local.flags != reference.flags || local.cow != reference.cow
			|| local.dont_fork != reference.dont_fork || local.wipe_on_fork != reference.wipe_on_fork
			|| file_page != first_page + (cursor - base) / page_size {
			errno.set(errno.efault)
			return false
		}
		cursor = min_u64(base + length, local.base + local.length)
	}
	return true
}

fn remap_span_unlocked(pagemap &memory.Pagemap, base u64, length u64, serial u64, mutable bool) bool {
	mut cursor := base
	for cursor < base + length {
		local, _, _ := addr2range(pagemap, cursor) or { errno.set(errno.efault); return false }
		if local.global.serial != serial { errno.set(errno.efault); return false }
		if mutable && local.immutable { errno.set(errno.eperm); return false }
		cursor = min_u64(base + length, local.base + local.length)
	}
	return true
}

// Carry resident private pages through the direct map. Missing anonymous pages
// remain zero-filled; missing private file pages keep their lazy file source.
fn copy_between_mappings(mut pagemap memory.Pagemap, destination u64, source u64, length u64,
	source_serial u64, destination_serial u64, source_file_page u64) bool {
	for offset := u64(0); offset < length; offset += page_size {
		if !copy_remapped_page(mut pagemap, destination + offset, source + offset,
			source_serial, destination_serial, source_file_page + offset / page_size) { return false }
	}
	return true
}

// Each call owns at most one independently pinned destination source. All
// physical reads/writes occur under pagemap.l; driver callbacks occur outside.
fn copy_remapped_page(mut pagemap memory.Pagemap, destination u64, source u64,
	source_serial u64, destination_serial u64, source_file_page u64) bool {
	for _ in 0 .. 3 {
		pagemap.l.acquire()
		if !remap_span_unlocked(&pagemap, source, page_size, source_serial, false)
			|| !remap_span_unlocked(&pagemap, destination, page_size, destination_serial, true) {
			pagemap.l.release()
			return false
		}
		_, _, first_page := addr2range(&pagemap, source) or { pagemap.l.release(); errno.set(errno.efault); return false }
		if first_page != source_file_page { pagemap.l.release(); errno.set(errno.efault); return false }
		source_phys := pagemap.virt2phys(source) or { pagemap.l.release(); return true }
		destination_phys := pagemap.virt2phys(destination) or {
			pagemap.l.release()
			populate_missing_pages(mut pagemap, destination, page_size, prot_read | prot_write, false) or {
				errno.set(errno.enomem)
				return false
			}
			continue
		}
		if source_phys == destination_phys { pagemap.l.release(); return true }
		local, _, _ := addr2range(&pagemap, destination) or { pagemap.l.release(); return false }
		mut owner := range_page_source(local, destination)
		pagemap.l.release()
		defer { owner.close() }
		if !owner.prepare() { errno.set(errno.enomem); return false }
		pagemap.l.acquire()
		if !remap_span_unlocked(&pagemap, source, page_size, source_serial, false)
			|| !remap_span_unlocked(&pagemap, destination, page_size, destination_serial, true) {
			pagemap.l.release()
			return false
		}
		current, _, file_page := addr2range(&pagemap, destination) or { pagemap.l.release(); errno.set(errno.efault); return false }
		if current.flags != owner.flags || file_page != owner.file_page
			|| current.generation != owner.local_generation {
			pagemap.l.release()
			errno.set(errno.efault)
			return false
		}
		_, _, from_page := addr2range(&pagemap, source) or { pagemap.l.release(); errno.set(errno.efault); return false }
		if from_page != source_file_page { pagemap.l.release(); errno.set(errno.efault); return false }
		physical := pagemap.virt2phys(destination) or { pagemap.l.release(); errno.set(errno.efault); return false }
		from := pagemap.virt2phys(source) or { pagemap.l.release(); return true }
		// A fork may have made the destination private page shared too.
		mut target := physical
		if current.flags & map_shared == 0 {
			target = unshare_private_page_unlocked(mut pagemap, current, destination,
				physical, current.prot & prot_write != 0) or { pagemap.l.release(); errno.set(errno.enomem); return false }
		}
		unsafe { C.memcpy(voidptr(target + higher_half), voidptr(from + higher_half), page_size) }
		if current.prot & prot_exec != 0 { sync_new_code_page(voidptr(target)) }
		pagemap.l.release()
		if target != physical { owner.give_back_cow(voidptr(physical)) }
		return true
	}
	errno.set(errno.eagain)
	return false
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
// gives back zeroes. Discard whole resident pages so a process can actually
// return memory; a translated guest's partial 4 KiB discard clears only that
// part of its 16 KiB host page. Sparse mappings stay absent.
// Every other advice is a hint with nothing to do.
pub fn syscall_madvise(_ voidptr, address u64, length u64, advice int) (u64, u64) {
	mut process := proc.current_thread().process
	mut pagemap := process.pagemap
	// QEMU's x86 guests discard 4 KiB pages even though Vinix maps 16 KiB
	// host pages. Accept that alignment for the translators and clear only
	// the requested subpage so adjacent guest pages keep their contents.
	guest_page_size := if process.executable_path == '/usr/bin/qemu-x86_64'
		|| process.executable_path == '/usr/bin/qemu-i386' { u64(4096) } else { page_size }
	if advice == madv_dontfork || advice == madv_dofork || advice == madv_wipeonfork
		|| advice == madv_keeponfork {
		return madvise_inheritance(address, length, advice)
	}
	if address % guest_page_size != 0 {
		return errno.err, errno.einval
	}
	if advice != madv_dontneed && advice != madv_free {
		return 0, 0
	}
	if length > u64(-1) - (guest_page_size - 1) {
		return errno.err, errno.einval
	}
	aligned_length := lib.align_up(length, guest_page_size)
	if address > u64(-1) - aligned_length {
		return errno.err, errno.einval
	}

	end := address + aligned_length

	pagemap.l.acquire()
	defer {
		pagemap.l.release()
	}
	if immutable_overlap_unlocked(pagemap, address, aligned_length) {
		return errno.err, errno.eperm
	}
	if locked_overlap_unlocked(pagemap, lib.align_down(address, page_size),
		lib.align_up(address % page_size + aligned_length, page_size)) > 0 {
		return errno.err, errno.einval
	}

	mut virt := address
	for virt < end {
		in_page := virt % page_size
		available := page_size - in_page
		chunk := if end - virt < available { end - virt } else { available }
		local_range, _, file_page := addr2range(pagemap, virt) or {
			virt += chunk
			continue
		}
		// File-page release callbacks temporarily drop pagemap.l. A lock
		// installed while they run must protect each following page too.
		if local_range.flags & map_locked != 0 { return errno.err, errno.einval }
		if advice == madv_dontneed && local_range.flags & map_shared == 0
			&& local_range.global.private_cow && in_page == 0 && chunk == page_size {
			phys := pagemap.virt2phys(virt) or {
				virt += chunk
				continue
			}
			mut global := local_range.global
			global.shadow_pagemap.l.acquire()
			shadow_phys := global.shadow_pagemap.virt2phys(virt) or { u64(0) }
			if shadow_phys == phys {
				pagemap.unmap_page_unlocked(virt) or {
					global.shadow_pagemap.l.release()
					return errno.err, errno.einval
				}
				global.shadow_pagemap.unmap_page_unlocked(virt) or {
					global.shadow_pagemap.l.release()
					return errno.err, errno.einval
				}
				global.shadow_pagemap.l.release()
				source := range_page_source(local_range, virt)
				pagemap.l.release()
				source.give_back(file_page, voidptr(phys))
				source.close()
				pagemap.l.acquire()
				virt += chunk
				continue
			}
			global.shadow_pagemap.l.release()
		}
		if local_range.flags & map_anonymous != 0 && local_range.flags & map_shared == 0 {
			mut phys := pagemap.virt2phys(virt) or {
				virt += chunk
				continue
			}
			if in_page == 0 && chunk == page_size {
				mut global_range := local_range.global
				global_range.shadow_pagemap.l.acquire()
				shadow_phys := global_range.shadow_pagemap.virt2phys(virt) or { u64(0) }
				if shadow_phys == phys {
					pagemap.unmap_page_unlocked(virt) or {
						global_range.shadow_pagemap.l.release()
						return errno.err, errno.einval
					}
					global_range.shadow_pagemap.unmap_page_unlocked(virt) or {
						global_range.shadow_pagemap.l.release()
						return errno.err, errno.einval
					}
					global_range.shadow_pagemap.l.release()
					memory.pmm_free(voidptr(phys), 1)
					virt += chunk
					continue
				}
				global_range.shadow_pagemap.l.release()
			}
			if local_range.cow {
				old_phys := phys
				phys = unshare_private_page_unlocked(mut pagemap, local_range,
					lib.align_down(virt, page_size), phys, false) or { return errno.err, errno.enomem }
				if phys != old_phys { memory.pmm_free(voidptr(old_phys), 1) }
			}
			unsafe {
				C.memset(voidptr(phys + higher_half + in_page), 0, chunk)
			}
		}
		virt += chunk
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
		start := random_brk_start()
		process.brk_base = start
		process.brk_current = start
	}

	if address == 0 || address == process.brk_current {
		return process.brk_current, 0
	}
	if address < process.brk_base || address > brk_arena_base + brk_arena_size {
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
		pagemap.l.acquire()
		if immutable_overlap_unlocked(pagemap, current_page, growth) {
			pagemap.l.release()
			return process.brk_current, 0
		}
		future_locked := pagemap.lock_future
		pagemap.l.release()
		if future_locked {
			lock_range(mut pagemap, current_page, growth, true, true) or {
				return process.brk_current, 0
			}
		}
		mprotect(mut pagemap, voidptr(current_page), wanted_page - current_page, prot_read | prot_write) or {
			if future_locked { lock_range(mut pagemap, current_page, growth, false, true) or {} }
			return process.brk_current, 0
		}
	} else if wanted_page < current_page {
		mut pagemap := process.pagemap
		mprotect(mut pagemap, voidptr(wanted_page), current_page - wanted_page, prot_none) or {
			return process.brk_current, 0
		}
		lock_range(mut pagemap, wanted_page, current_page - wanted_page, false, true) or {}
	}

	process.brk_current = address
	return process.brk_current, 0
}
