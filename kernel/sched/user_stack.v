// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module sched

// A program's first thread's stack, the same on both architectures: how much
// address space it is given, and how exec lays argv, the environment and the
// auxiliary vector out on it, as Linux lays them out.

import elf
import errno
import krandom
import lib
import memory
import memory.mmap
import proc

// Read back what was written to a new stack, through the direct map. Kept as
// the process' saved_auxv, which is freed when it is replaced and when the
// process is (proc.free_process_memory).
fn read_initial_stack(pagemap &memory.Pagemap, addr u64, length u64) []u8 {
	mut bytes := []u8{len: int(length)} @[freed]
	mut done := u64(0)
	for done < length {
		virt := addr + done
		phys := pagemap.virt2phys(virt) or { break }
		offset := virt & (page_size - 1)
		chunk := if length - done < page_size - offset { length - done } else { page_size - offset }
		unsafe {
			C.memcpy(&bytes[int(done)], voidptr(phys + higher_half + offset), chunk)
		}
		done += chunk
	}
	return bytes
}

// The new address space is not necessarily active during exec. Write its
// initial stack through the direct map, one physical page at a time.
fn write_initial_stack(pagemap &memory.Pagemap, addr u64, src voidptr, length u64) bool {
	mut done := u64(0)
	for done < length {
		virt := addr + done
		// The stack is filled in as it is used; a page not there yet is
		// filled in now.
		phys := pagemap.virt2phys(virt) or {
			mut writable := unsafe { pagemap }
			mmap.populate(mut writable, virt & ~(page_size - 1), page_size) or { return false }
			pagemap.virt2phys(virt) or { return false }
		}
		offset := virt & (page_size - 1)
		chunk := if length - done < page_size - offset { length - done } else { page_size - offset }
		unsafe {
			C.memcpy(voidptr(phys + higher_half + offset), voidptr(u64(src) + done), chunk)
		}
		done += chunk
	}
	return true
}

// The helpers below move `cursor`, the address the stack has grown down to,
// past what they push.
fn push_initial_bytes(pagemap &memory.Pagemap, bottom u64, cursor &u64, src voidptr, length u64) bool {
	if *cursor < bottom || length > *cursor - bottom {
		return false
	}
	unsafe {
		*cursor -= length
	}
	return write_initial_stack(pagemap, *cursor, src, length)
}

fn push_initial_word(pagemap &memory.Pagemap, bottom u64, cursor &u64, value u64) bool {
	return push_initial_bytes(pagemap, bottom, cursor, voidptr(&value), sizeof(u64))
}

fn push_initial_pair(pagemap &memory.Pagemap, bottom u64, cursor &u64, key u64, value u64) bool {
	return push_initial_word(pagemap, bottom, cursor, value)
		&& push_initial_word(pagemap, bottom, cursor, key)
}

// Reserve the first thread's stack below process.thread_stack_top. Answers its
// top and bottom. It is reserved for as far as it may grow: a program may raise
// RLIMIT_STACK while it runs -- gcc raises it to 64 MiB as it starts -- and
// Linux lets the stack grow to the new limit. A limit set below the 8 MiB
// default is kept to.
fn reserve_main_stack(mut process proc.Process, want_elf bool) ?(u64, u64) {
	mut user_stack_size := main_stack_reservation
	stack_limit := proc.soft_limit(process, proc.rlimit_stack)
	if stack_limit != proc.rlim_infinity && stack_limit < default_user_stack_size {
		user_stack_size = lib.align_down(stack_limit, page_size)
	} else if stack_limit != proc.rlim_infinity && stack_limit > user_stack_size {
		user_stack_size = lib.align_down(if stack_limit < max_main_stack_reservation {
			stack_limit
		} else {
			max_main_stack_reservation
		}, page_size)
	}
	if user_stack_size < page_size {
		errno.set(errno.enomem)
		return none
	}

	stack_vma := process.thread_stack_top
	if want_elf {
		process.stack_end = stack_vma
	}
	process.thread_stack_top -= user_stack_size
	stack_bottom_vma := process.thread_stack_top
	process.thread_stack_top -= page_size

	mmap.mmap(process.pagemap, voidptr(stack_bottom_vma), user_stack_size,
		mmap.prot_read | mmap.prot_write, mmap.map_private | mmap.map_anonymous | mmap.map_fixed | mmap.map_stack,
		unsafe { nil }, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }) or { return none }
	// The 8 MiB a stack had are there from the start, as before; only what lies
	// past them is filled in as it is touched. HVF does not always resume a
	// fault taken on an STP or LDP, which is mostly what an arm64 stack is
	// touched with.
	eager := if user_stack_size < default_user_stack_size {
		user_stack_size
	} else {
		default_user_stack_size
	}
	mmap.populate(mut process.pagemap, stack_vma - eager, eager) or { return none }
	return stack_vma, stack_bottom_vma
}

// Lay out what a program finds on its stack when it starts: argc, argv, the
// environment, the auxiliary vector and the strings they point at, below
// `stack_vma`. Answers the stack pointer to start the thread with; fails with
// E2BIG when it does not fit above `stack_bottom_vma`.
fn build_initial_stack(mut process proc.Process, stack_vma u64, stack_bottom_vma u64, argv []string, envp []string, auxval &elf.Auxval) ?u64 {
	// The strings go in as Linux lays them out: argv[0] lowest, each one after
	// the last, the environment above the arguments. Programs count on it.
	// libuv, in every node process, takes the room for a process title to run
	// from argv[0] to the end of the last argument; pushed in the other order
	// that came out negative, a huge size unsigned, and setting process.title
	// cleared memory up past the top of the stack.
	mut cursor := stack_vma
	mut env_strings := []u64{len: envp.len} @[freed]
	mut arg_strings := []u64{len: argv.len} @[freed]
	defer {
		unsafe {
			env_strings.free()
			arg_strings.free()
		}
	}
	for i := envp.len - 1; i >= 0; i-- {
		if !push_initial_bytes(process.pagemap, stack_bottom_vma, unsafe { &cursor }, voidptr(envp[i].str),
			u64(envp[i].len) + 1) {
			errno.set(errno.e2big)
			return none
		}
		env_strings[i] = cursor
	}
	for i := argv.len - 1; i >= 0; i-- {
		if !push_initial_bytes(process.pagemap, stack_bottom_vma, unsafe { &cursor }, voidptr(argv[i].str),
			u64(argv[i].len) + 1) {
			errno.set(errno.e2big)
			return none
		}
		arg_strings[i] = cursor
	}
	cursor &= ~u64(0xf)
	if (argv.len + envp.len + 1) & 1 != 0 {
		cursor -= sizeof(u64)
	}
	// Linux libcs take their stack canary and pointer guard from AT_RANDOM.
	mut random_bytes := [16]u8{}
	if !krandom.fill(voidptr(&random_bytes[0]), 16, true) {
		unsafe { C.memset(voidptr(&random_bytes[0]), 0, 16) }
	}
	if !push_initial_bytes(process.pagemap, stack_bottom_vma, unsafe { &cursor }, voidptr(&random_bytes[0]),
		16) {
		errno.set(errno.e2big)
		return none
	}
	random_vma := cursor
	hwcap, hwcap2 := user_hwcaps()

	// Auxiliary vector (NULL-terminated), with the CPU features userspace can
	// use; see user_hwcaps().
	auxv_top := cursor
	if !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, 0, 0)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_secure,
			if proc.secure_loader_required(process) { u64(1) } else { u64(0) })
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_hwcap2, hwcap2)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_hwcap, hwcap)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_random, random_vma)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_pagesz, page_size)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_uid, u64(process.uid))
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_euid, u64(process.euid))
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_gid, u64(process.gid))
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_egid, u64(process.egid))
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_entry, auxval.at_entry)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_phdr, auxval.at_phdr)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_phent, auxval.at_phent)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_phnum, auxval.at_phnum)
		|| !push_initial_pair(process.pagemap, stack_bottom_vma, unsafe { &cursor }, elf.at_base, auxval.at_base)
		|| !push_initial_word(process.pagemap, stack_bottom_vma, unsafe { &cursor }, 0) {
		errno.set(errno.e2big)
		return none
	}
	// Kept for /proc/<pid>/auxv, which is where Go's x/sys/cpu looks for the
	// CPU's features before it tries reading them from the CPU.
	auxv_start := cursor + sizeof(u64)
	unsafe { process.saved_auxv.free() }
	process.saved_auxv = read_initial_stack(process.pagemap, auxv_start, auxv_top - auxv_start)
	if cursor < stack_bottom_vma || u64(envp.len) * sizeof(u64) > cursor - stack_bottom_vma {
		errno.set(errno.e2big)
		return none
	}
	cursor -= u64(envp.len) * sizeof(u64)
	for i in 0 .. envp.len {
		pointer := env_strings[i]
		if !write_initial_stack(process.pagemap, cursor + u64(i) * sizeof(u64), voidptr(&pointer),
			sizeof(u64)) {
			return none
		}
	}
	if !push_initial_word(process.pagemap, stack_bottom_vma, unsafe { &cursor }, 0) {
		errno.set(errno.e2big)
		return none
	}
	if cursor < stack_bottom_vma || u64(argv.len) * sizeof(u64) > cursor - stack_bottom_vma {
		errno.set(errno.e2big)
		return none
	}
	cursor -= u64(argv.len) * sizeof(u64)
	for i in 0 .. argv.len {
		pointer := arg_strings[i]
		if !write_initial_stack(process.pagemap, cursor + u64(i) * sizeof(u64), voidptr(&pointer),
			sizeof(u64)) {
			return none
		}
	}
	if !push_initial_word(process.pagemap, stack_bottom_vma, unsafe { &cursor }, u64(argv.len)) {
		errno.set(errno.e2big)
		return none
	}
	return cursor
}
