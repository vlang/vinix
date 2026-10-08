module mmap

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.timer
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
		// The kernel reached for a page userspace can reach, with PAN set: a
		// path that still follows a user pointer rather than copying through
		// usercopy. An audit names the path once and lets the access through,
		// with PAN clear until the thread goes back to userspace or sleeps, so
		// it sees the first such access of each. This comes before
		// copy-on-write, which would otherwise answer that the page is
		// writable already and retry the access for ever.
		if addr < higher_half && gpr_state.pstate & 0xf != 0 && gpr_state.pstate & cpu.pstate_pan != 0 {
			if !memory.user_guard_auditing() {
				C.kprintf(c'user-access: the kernel %s user address 0x%llx directly, at pc 0x%llx; vinix.user_access=audit reports this and carries on\n',
					if wnr != 0 { c'wrote' } else { c'read' }, addr, gpr_state.pc)
				return none
			}
			report_direct_access(gpr_state, addr, wnr != 0, current)
			unsafe {
				mut state := &cpulocal.GPRState(gpr_state)
				state.pstate &= ~cpu.pstate_pan
			}
			return
		}
		previous_interrupt_state := cpu.interrupt_toggle(true)
		resolved := wnr != 0 && addr < higher_half && current != unsafe { nil }
			&& resolve_cow_fault(current.process.pagemap, addr)
		cpu.interrupt_toggle(previous_interrupt_state)
		if resolved {
			return
		}
		// A protection violation. The caller reports it: as a kernel fault,
		// or to the process as SIGSEGV. Nothing is printed here, because for
		// some programs that signal is routine. A translator write-protects
		// every page it has translated code from and takes this fault on each
		// write to one. Under Wine that was hundreds of console lines a
		// second, each built from strings that nothing freed.
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

	// Resolve the fault as one exception transaction. In particular, do not
	// enable the scheduler FIQ between finding the backing page and installing
	// its PTE: a file-backed fault on the M1 can outlive a 5 ms quantum, and a
	// context switch from this nested synchronous exception leaves the initial
	// exec handoff unable to make forward progress. The earlier bounded startup
	// trace happened to avoid that race by stopping the timer around each fault.
	// Make that correctness property independent of diagnostics, and give the
	// faulting instruction a fresh quantum in which to retry after the PTE and
	// instruction-cache maintenance are complete.
	fault_timeslice := if current_thread.timeslice != 0 { current_thread.timeslice } else { u64(1) }
	timer.stop()
	// A user refault can wait for pending pageout or disk I/O. Keep the
	// preemption timer stopped, but permit device interrupts and explicit
	// event waits. Kernel faults retain their caller's interrupt discipline.
	previous_interrupt_state := cpu.interrupt_state()
	user_fault := gpr_state.pstate & 0xf == 0
	if user_fault { current_thread.user_page_fault = true; cpu.interrupt_toggle(true) }
	defer {
		cpu.interrupt_toggle(previous_interrupt_state)
		if user_fault { current_thread.user_page_fault = false }
		timer.oneshot(fault_timeslice)
	}

	mut process := current_thread.process
	mut pagemap := process.pagemap

	// A translation fault on a page that is mapped by now raced with a
	// break-before-make update of its descriptor: fork write-protecting it, or
	// a copy-on-write fault resolved on another CPU. Retrying the access is all
	// it needs. Paging the range's page in again would map a page still shared
	// with a fork child writable, behind copy-on-write's back.
	page_in(mut pagemap, addr, dfsc >= 0x04 && dfsc <= 0x07)?
}

// One line for each kernel path the audit finds, with the return addresses
// above it: the access itself is often in memcpy or strlen.
fn report_direct_access(gpr_state &cpulocal.GPRState, addr u64, write bool, current &proc.Thread) {
	mut frames := [4]u64{}
	mut frame := gpr_state.x29
	for i in 0 .. 4 {
		if frame < higher_half || frame & 0xf != 0 {
			break
		}
		unsafe {
			frames[i] = *(&u64(frame + 8))
			frame = *(&u64(frame))
		}
	}
	if !memory.user_guard_note(gpr_state.pc * 31 + gpr_state.x30 + frames[0] * 7) {
		return
	}
	name := if current != unsafe { nil } { current.process.name.str } else { c'?' }
	C.kprintf(c'user-access: %s 0x%llx at pc 0x%llx lr 0x%llx < 0x%llx 0x%llx 0x%llx 0x%llx (%s)\n',
		if write { c'wrote' } else { c'read' }, addr, gpr_state.pc, gpr_state.x30, frames[0],
		frames[1], frames[2], frames[3], name)
}

// A page about to be mapped executable must reach the instruction cache.
fn sync_new_code_page(page voidptr) {
	cpu.sync_instruction_cache(u64(page) + higher_half, page_size)
}

// Small private anonymous mappings may wait until their first access.
fn demand_private_anonymous() bool {
	return false
}
