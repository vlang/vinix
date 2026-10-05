// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module sched

// The x86 segments a thread brings to a CPU: the three TLS descriptors
// set_thread_area(2) gave it, the LDT modify_ldt(2) gave its process, and the
// selectors it had in FS and GS. A CPU's GDT holds the TLS descriptors of the
// thread it runs, and its LDTR the LDT of that thread's process; the scheduler
// puts them there before it resumes a thread.
//
// Whatever loads a selector a thread had must not fault on one whose
// descriptor has gone since: another thread can take an LDT entry away, and a
// thread can come back on a CPU with a newer LDT. So an LDT is never changed
// once a process has it -- a change is a new LDT -- and a CPU only loads
// another itself, with interrupts off: what it checked a selector against is
// what it goes on loading from. The scheduler checks the frame it resumes;
// the interrupt and syscall exits have a DS or ES load that faults fixed up
// instead (x86/isr), and interrupt_leave() checks the CS and SS an IRETQ is
// about to take (userland.interrupt_return()).

import katomic
import klock
import proc
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import x86.gdt

// Linux's LDT_ENTRIES: an LDT is at most 64 KiB.
pub const ldt_max_entries = u32(8192)

// An LDT, which no one changes once a process has it. Owned by that process.
pub struct Ldt {
pub:
	entries u32
	table   &u64 = unsafe { nil }
}

__global (
	// Guards Process.ldt and each CPU's cpulocal.Local.ldt. A CPU records the
	// LDT it takes from a process before it lets go, so that the thread which
	// replaced that LDT finds every CPU still on it once it holds the lock.
	ldt_lock klock.Lock
)

@[inline]
fn load_pointer(p &voidptr) voidptr {
	return voidptr(katomic.load(unsafe { &u64(p) }))
}

// A selector that always loads, from GDT entries that never change: null, the
// kernel's data segment as the kernel loads it, and the user data and code
// segments with any RPL. All of them have a base of 0. Anything else -- an
// LDT or TLS descriptor, or a selector a VM exit left in a segment register
// -- is checked before it is loaded.
@[inline]
fn fixed_selector(selector u16) bool {
	s := selector & 0xfffc
	return s == 0 || selector == gdt.kernel_data_selector || s == gdt.user_data_selector & 0xfffc
		|| s == gdt.user_code_selector & 0xfffc
}

// Whether `selector` loads into DS, ES, FS or GS for userspace from this CPU's
// GDT and LDT: null, or a present data segment, or readable code segment, of
// privilege 3.
pub fn user_data_selector_ok(selector u16) bool {
	if selector & 0xfffc == 0 {
		return true
	}
	rights := cpu.access_rights(selector)
	if rights & cpu.ar_present == 0 || rights & cpu.ar_code_or_data == 0 {
		return false
	}
	if rights & cpu.ar_code != 0 {
		if rights & cpu.ar_writable == 0 {
			return false
		}
		// Conforming code has no privilege of its own to check.
		if rights & cpu.ar_conforming != 0 {
			return true
		}
	}
	return (rights >> cpu.ar_dpl_shift) & 3 == 3
}

// Whether an IRETQ to `frame`, a userspace one, would be taken: its code and
// stack segments are ones this CPU's GDT and LDT describe for privilege 3, and
// 32-bit code resumes inside its segment. Otherwise the IRETQ faults, in the
// kernel.
pub fn user_frame_segments_ok(frame &cpulocal.GPRState) bool {
	cs := u16(frame.cs)
	ss := u16(frame.ss)
	if cs == gdt.user_code_selector && ss == gdt.user_data_selector {
		return true
	}
	if cs & 3 != 3 || ss & 3 != 3 {
		return false
	}
	code := cpu.access_rights(cs)
	if code & cpu.ar_present == 0 || code & cpu.ar_code_or_data == 0 || code & cpu.ar_code == 0 {
		return false
	}
	if code & cpu.ar_conforming == 0 && (code >> cpu.ar_dpl_shift) & 3 != 3 {
		return false
	}
	if code & cpu.ar_long == 0 {
		limit := cpu.segment_limit(cs) or { return false }
		if frame.rip > u64(limit) {
			return false
		}
	}
	stack := cpu.access_rights(ss)
	return stack & cpu.ar_present != 0 && stack & cpu.ar_code_or_data != 0
		&& stack & cpu.ar_code == 0 && stack & cpu.ar_writable != 0
		&& (stack >> cpu.ar_dpl_shift) & 3 == 3
}

// `selector`, or null if it no longer loads.
@[inline]
fn loadable_selector(selector u16) u16 {
	if fixed_selector(selector) || user_data_selector_ok(selector) {
		return selector
	}
	return 0
}

// Load `ldt`, a &Ldt or nil, on this CPU. Interrupts are off and ldt_lock is
// taken.
fn install_ldt(mut cpu_local cpulocal.Local, ldt voidptr) {
	if ldt == unsafe { nil } {
		cpu.load_ldt(0)
	} else {
		l := unsafe { &Ldt(ldt) }
		gdt.set_ldt(&cpu_local.gdt[0], u64(voidptr(l.table)), u64(l.entries) * 8)
		cpu.load_ldt(gdt.ldt_selector)
	}
	mut loaded := unsafe { &u64(&cpu_local.ldt) }
	katomic.store(mut loaded, u64(ldt))
}

// Make the LDT this CPU has loaded the one `process` has now, or none, and
// record that the CPU runs a thread of `process`. Interrupts are off.
//
// The CPU says whose thread it runs before it looks at the process' LDT, and
// ldt_changed() changes the LDT before it looks at whose threads the CPUs
// run, each a locked store, which orders it before the load that follows: so
// either this sees the new LDT, or ldt_changed() sees this CPU running the
// process and waits for it to take the new one.
fn load_process_ldt(mut cpu_local cpulocal.Local, process &proc.Process) {
	if cpu_local.ldt_process != voidptr(process) {
		mut owner := unsafe { &u64(&cpu_local.ldt_process) }
		katomic.store(mut owner, u64(voidptr(process)))
	}
	want := if unsafe { process == nil } { unsafe { nil } } else { load_pointer(&process.ldt) }
	if want == cpu_local.ldt {
		return
	}
	ldt_lock.acquire()
	install_ldt(mut cpu_local, if unsafe { process == nil } { unsafe { nil } } else { process.ldt })
	ldt_lock.release()
}

// Put `t`'s TLS descriptors in this CPU's GDT and its process' LDT in the
// LDTR, for resuming it, and load null for a DS or ES it goes back to that
// they no longer describe. Interrupts are off.
fn load_segment_tables(mut cpu_local cpulocal.Local, mut t proc.Thread) {
	for i := 0; i < gdt.tls_entry_count; i++ {
		cpu_local.gdt[gdt.tls_first_entry + i] = t.tls[i]
	}
	load_process_ldt(mut cpu_local, t.process)
	t.gpr_state.ds = u64(loadable_selector(u16(t.gpr_state.ds)))
	t.gpr_state.es = u64(loadable_selector(u16(t.gpr_state.es)))
}

// Load the FS and GS selectors `t` had, or null for one whose descriptor has
// gone, and answer the FS and user GS bases it has with them: its own, from
// arch_prctl(2), for a null selector, and otherwise the one the descriptor
// gives, as on Linux. Last before the scheduler sets the FS and GS bases:
// loading a selector replaces its segment's base, and the kernel finds itself
// by GS's. One from an LDT or TLS descriptor is loaded even when it is there
// already, as the descriptor may be another since.
fn load_fs_gs(t &proc.Thread) (u64, u64) {
	fs := loadable_selector(t.fs_selector)
	if fs != cpu.fs_selector() || !fixed_selector(fs) {
		cpu.load_fs_selector(fs)
	}
	fs_base := if fs & 0xfffc == 0 {
		t.fs_base
	} else if fixed_selector(fs) {
		u64(0)
	} else {
		cpu.get_fs_base()
	}
	gs := loadable_selector(t.gs_selector)
	if gs != cpu.gs_selector() || !fixed_selector(gs) {
		cpu.load_gs_selector(gs)
	}
	gs_base := if gs & 0xfffc == 0 {
		t.gs_base
	} else if fixed_selector(gs) {
		u64(0)
	} else {
		cpu.get_gs_base()
	}
	return fs_base, gs_base
}

fn save_fs_gs(mut t proc.Thread) {
	t.fs_selector = cpu.fs_selector()
	t.gs_selector = cpu.gs_selector()
}

// Give the calling thread TLS descriptor `index` and this CPU's GDT with it,
// for set_thread_area(2). A selector for it the thread has in FS or GS is
// loaded again, as Linux does, for the base the descriptor now gives, or
// null if the descriptor is gone. DS and ES are loaded again on the way out
// of the syscall.
pub fn set_tls_descriptor(index int, descriptor u64) {
	mut t := proc.current_thread()
	ints := cpu.interrupt_toggle(false)
	mut cpu_local := cpulocal.current()
	t.tls[index] = descriptor
	cpu_local.gdt[gdt.tls_first_entry + index] = descriptor
	selector := u16((gdt.tls_first_entry + index) << 3)
	fs := cpu.fs_selector()
	if fs & 0xfffc == selector {
		cpu.load_fs_selector(loadable_selector(fs))
	}
	gs := cpu.gs_selector()
	if gs & 0xfffc == selector {
		cpu.load_user_gs_selector(loadable_selector(gs))
	}
	cpu.interrupt_toggle(ints)
}

// Give `process` `ldt`, with a locked store; see load_process_ldt(). ldt_lock
// is taken.
fn publish_ldt(mut process proc.Process, ldt voidptr) {
	mut slot := unsafe { &u64(&process.ldt) }
	katomic.store(mut slot, u64(ldt))
}

// A new LDT of `entries` entries, all empty.
fn new_ldt(entries u32) ?&Ldt {
	size := u64(entries) * 8
	table := unsafe { &u64(malloc(size)) }
	if table == unsafe { nil } {
		return none
	}
	unsafe { C.memset(table, 0, size) }
	ldt := &Ldt{
		entries: entries
		table:   table
	} @[freed]
	return ldt
}

fn free_ldt(ldt voidptr) {
	l := unsafe { &Ldt(ldt) }
	unsafe {
		free(voidptr(l.table))
		free(voidptr(l))
	}
}

// A copy of the LDT `process` has, with `entries` entries at least, returned
// with ldt_lock taken, so that the LDT copied is still the process' when the
// caller puts the copy in its place. Also the LDT copied, or nil for none.
// None, with the lock let go, when there is nothing to copy and nothing asked
// for, or for want of memory.
fn copy_process_ldt(process &proc.Process, entries u32) ?(&Ldt, voidptr) {
	for {
		// Sized under the lock, as the LDT may be freed as soon as it is let
		// go; made without it, as the scheduler takes it; and checked with it
		// that the LDT to copy still fits.
		ldt_lock.acquire()
		mut wanted := entries
		if process.ldt != unsafe { nil } {
			current := unsafe { &Ldt(process.ldt) }
			if current.entries > wanted {
				wanted = current.entries
			}
		}
		ldt_lock.release()
		if wanted == 0 {
			return none
		}
		mut ldt := new_ldt(wanted)?
		ldt_lock.acquire()
		from := process.ldt
		if from == unsafe { nil } {
			return ldt, from
		}
		old := unsafe { &Ldt(from) }
		if old.entries <= wanted {
			unsafe { C.memcpy(ldt.table, old.table, u64(old.entries) * 8) }
			return ldt, from
		}
		ldt_lock.release()
		free_ldt(voidptr(ldt))
	}
	return none
}

// Set entry `index` of the calling process' LDT to `descriptor`, for
// modify_ldt(2): in a new LDT with the change, which this CPU loads at once
// and the CPUs running the process' other threads once the scheduler has been
// through them. False for want of memory.
pub fn set_ldt_entry(index u32, descriptor u64) bool {
	mut process := proc.current_thread().process
	mut ldt, old := copy_process_ldt(process, index + 1) or { return false }
	unsafe {
		ldt.table[index] = descriptor
	}
	publish_ldt(mut process, voidptr(ldt))
	ldt_lock.release()
	ldt_changed(process, old)
	return true
}

// Copy up to `size` bytes of the calling process' LDT to `buf`: how many it
// had, or -1 when it has none.
pub fn read_ldt(buf voidptr, size u64) i64 {
	process := proc.current_thread().process
	ldt_lock.acquire()
	if process.ldt == unsafe { nil } {
		ldt_lock.release()
		return -1
	}
	l := unsafe { &Ldt(process.ldt) }
	mut length := u64(l.entries) * 8
	if length > size {
		length = size
	}
	unsafe { C.memcpy(buf, l.table, length) }
	ldt_lock.release()
	return i64(length)
}

// Give `child`, which has not run yet, a copy of `parent`'s LDT, as fork(2)
// does. False for want of memory.
pub fn copy_ldt(parent &proc.Process, mut child proc.Process) bool {
	if load_pointer(&parent.ldt) == unsafe { nil } {
		return true
	}
	ldt, from := copy_process_ldt(parent, 0) or {
		// Nothing to copy any more, or no memory for the copy.
		return load_pointer(&parent.ldt) == unsafe { nil }
	}
	ldt_lock.release()
	if from == unsafe { nil } {
		free_ldt(voidptr(ldt))
		return true
	}
	child.ldt = voidptr(ldt)
	return true
}

// Free the LDT of `process`, which never ran: no CPU has loaded it.
pub fn discard_ldt(mut process proc.Process) {
	if process.ldt != unsafe { nil } {
		free_ldt(process.ldt)
		process.ldt = unsafe { nil }
	}
}

// Take `process`' LDT away for good, for execve(2) and exit, once the
// process has no other thread left.
pub fn drop_ldt(mut process proc.Process) {
	if load_pointer(&process.ldt) == unsafe { nil } {
		return
	}
	ldt_lock.acquire()
	old := process.ldt
	publish_ldt(mut process, unsafe { nil })
	ldt_lock.release()
	ldt_changed(process, old)
}

// After `process`' LDT has changed from `old`: load the one it has now on
// this CPU, and wait until every CPU running another of its threads has it
// too, as Linux's modify_ldt(2) does, and until none has `old` loaded, which
// is then freed. Each CPU is sent through the scheduler, which loads the LDT
// of the thread it goes on with, or none when it goes idle.
fn ldt_changed(process &proc.Process, old voidptr) {
	ints := cpu.interrupt_toggle(false)
	mut cpu_local := cpulocal.current()
	load_process_ldt(mut cpu_local, process)
	cpu.interrupt_toggle(ints)

	for cpu_entry in cpu_locals {
		mut kicked := false
		for {
			loaded := load_pointer(&cpu_entry.ldt)
			stale := (old != unsafe { nil } && loaded == old)
				|| (load_pointer(&cpu_entry.ldt_process) == voidptr(process)
				&& loaded != load_pointer(&process.ldt))
			if !stale {
				break
			}
			if !kicked {
				apic.lapic_send_ipi(u8(cpu_entry.lapic_id), scheduler_vector)
				kicked = true
			}
			answer_tlb_shootdown()
			asm volatile amd64 {
				pause
				; ; ; memory
			}
		}
	}
	if old != unsafe { nil } {
		free_ldt(old)
	}
}
