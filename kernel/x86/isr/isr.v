@[has_globals]
module isr

import x86.idt
import event
import event.eventstruct
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import memory.mmap
import memory
import katomic
import lib
import userland
import proc

__global (
	int_events [256]eventstruct.Event
)

fn generic_isr(num u32, _ voidptr) {
	apic.lapic_eoi()
	event.trigger(mut int_events[num], false)
}

const exception_names = [
	c'Division by 0',
	c'Debug',
	c'NMI',
	c'Breakpoint',
	c'Overflow',
	c'Bound range exceeded',
	c'Invalid opcode',
	c'Device not available',
	c'Double fault',
	c'???',
	c'Invalid TSS',
	c'Segment not present',
	c'Stack-segment fault',
	c'General protection fault',
	c'Page fault',
	c'???',
	c'x87 exception',
	c'Alignment check',
	c'Machine check',
	c'SIMD exception',
	c'Virtualisation',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'???',
	c'Security',
]!

fn pf_handler(num u32, mut gpr_state cpulocal.GPRState) {
	// Read while interrupts are still off: see mmap.pf_handler().
	fault_addr := cpu.read_cr2()
	if gpr_state.cs & 3 == 0 {
		resume := memory.stack_guard_probe_fixup(gpr_state.rip, fault_addr)
		if resume != 0 { gpr_state.rip = resume; return }
		if memory.kernel_stack_guard(fault_addr) {
			C.vinix_stack_guard_diagnostic(gpr_state.rsp, gpr_state.rip, fault_addr)
			C.vinix_stack_guard_message(c'STACK-GUARD FATAL kernel-stack exhaustion\n')
			C.printf_panic(c'kernel stack guard: address=0x%llx sp=0x%llx\n', fault_addr, gpr_state.rsp)
			lib.kpanic(gpr_state, c'Kernel stack guard')
		}
	}
	exhausted := memory.exhaustions()
	mmap.pf_handler(gpr_state) or {
		if memory.exhaustions() != exhausted && out_of_memory(gpr_state) {
			return
		}
		exception_handler_at(num, mut gpr_state, fault_addr)
	}
}

// The page a fault needed could not be had, for lack of memory rather than of
// a mapping. A process is killed for the memory (userland/oom.v) and the
// access runs again, which is what true asks for; a thread of the process
// killed ends here instead. A fault the kernel took on a process' page has to
// be seen through: when it cannot wait, having interrupts off, or the process
// is the one killed, its page comes out of the reserve.
fn out_of_memory(gpr_state &cpulocal.GPRState) bool {
	user := gpr_state.cs & 3 == 3
	if !user && gpr_state.rflags & cpu.rflags_if == 0 {
		return userland.grant_reserve_page()
	}
	asm volatile amd64 {
		sti
	}
	retry := memory.recover_from_exhaustion(true)
	asm volatile amd64 {
		cli
	}
	if retry {
		return true
	}
	if !user {
		return userland.grant_reserve_page()
	}
	userland.exit_if_killed_for_memory()
	return false
}

fn abort_handler(_num u32, _gpr_state &cpulocal.GPRState) {
	mut aborted := &cpulocal.current().aborted
	katomic.store(mut aborted, true)
	for {
		asm volatile amd64 {
			hlt
		}
	}
}

// asm/int_thunks_asm.S and asm/x86_64/syscall_entry.S: where the way back to
// a thread reloads the DS and ES it had.
fn C.interrupt_exit_load_ds()
fn C.interrupt_exit_load_es()
fn C.syscall_exit_load_ds()
fn C.syscall_exit_load_es()

// A data segment the way back to a thread reloads, which its LDT or TLS
// descriptors no longer describe -- another thread took the entry away, or
// the thread came back on a CPU with a newer LDT -- is loaded null instead,
// as Linux's exception fixup has it. Whether the fault was one of those.
fn fix_segment_reload(num u32, mut gpr_state cpulocal.GPRState) bool {
	// #NP for a descriptor that is not present, #GP for any other.
	if num != 11 && num != 13 {
		return false
	}
	rip := gpr_state.rip
	if rip != u64(voidptr(C.interrupt_exit_load_ds)) && rip != u64(voidptr(C.interrupt_exit_load_es))
		&& rip != u64(voidptr(C.syscall_exit_load_ds))
		&& rip != u64(voidptr(C.syscall_exit_load_es)) {
		return false
	}
	// Each loads the segment from eax: it runs again, with null.
	gpr_state.rax = 0
	return true
}

fn exception_handler(num u32, mut gpr_state cpulocal.GPRState) {
	exception_handler_at(num, mut gpr_state, if num == 14 { cpu.read_cr2() } else { u64(0) })
}

// `cr2` is the faulting address of a page fault, read on entry.
fn exception_handler_at(num u32, mut gpr_state cpulocal.GPRState, cr2 u64) {
	// Userspace is any code segment of privilege 3: an LDT can give a process
	// others than the GDT's.
	if gpr_state.cs & 3 == 3 {
		mut signal := u8(0)

		match num {
			0, 16, 19 {
				signal = userland.sigfpe
			}
			1, 3 {
				signal = userland.sigtrap
			}
			4, 5, 10, 11, 12, 13, 14 {
				signal = userland.sigsegv
			}
			6 {
				signal = userland.sigill
			}
			17 {
				signal = userland.sigbus
			}
			else {
				lib.kpanic(gpr_state, exception_names[num])
			}
		}

		// Preserve both pieces of x86 exception state in the existing frame.
		// Hardware error codes occupy the low bits and the vector the high half;
		// the signal frame hands them out as uc_mcontext's REG_ERR and
		// REG_TRAPNO.
		gpr_state.err = (gpr_state.err & u64(0xffffffff)) | (u64(num) << 32)
		fault_addr := if num == 14 { cr2 } else { u64(0) }
		fault_code := match num {
			0 { 1 } // FPE_INTDIV
			1 { 2 } // TRAP_TRACE
			3 { 1 } // TRAP_BRKPT
			14 { if gpr_state.err & 1 != 0 { 2 } else { 1 } } // SEGV_ACCERR / SEGV_MAPERR
			else { 128 } // SI_KERNEL
		}
		// A CPU exception arrives with interrupts off, and everything past this
		// point -- sendsig's scheduler enqueue, fatal exit's own printf,
		// dequeue_and_die's cross-CPU work -- can spin on a klock.Lock.
		// test_and_acquire() restores whatever the ambient interrupt state
		// already was on a failed attempt (see klock_amd64.v), so a lock held by
		// another CPU right now spins this one forever with interrupts
		// permanently off: it can never take the IPI that would let the holder
		// make progress and release it. mmap_amd64.v's own pf_handler already
		// re-enables interrupts before this kind of work for the demand-paging
		// and COW fault paths; this was missing the same `sti` for the same
		// class of user-mode fault.
		//
		// Being preempted or blocking from here on is safe because this
		// handler is running on the faulting thread's own stack: its
		// kernel_stack through tss.rsp0 (set per thread by scheduler_isr), or
		// its pf_stack through ist3 when reached from pf_handler. The
		// fatal exit path below can block in yield(true), for example on
		// writeback while closing files, exactly as a syscall would.
		asm volatile amd64 {
			sti
		}
		userland.sendsig(proc.current_thread(), signal)
		userland.dispatch_a_signal_info(gpr_state, int(signal), fault_code, fault_addr)
		// dispatch_a_signal() switches away when it delivered the exception. A
		// fault nothing handles -- no handler, or the signal blocked -- cannot
		// be retried: the process dies of the signal, as on arm64 and Linux.
		userland.exit_with_fatal_signal(signal)
	} else {
		if fix_segment_reload(num, mut gpr_state) {
			return
		}
		lib.kpanic(gpr_state, exception_names[num])
	}
}

__global (
	abort_vector = u8(0)
)

fn C.interrupt_thunks()

pub fn initialise() {
	thunks := unsafe { &u64(voidptr(C.interrupt_thunks)) }

	for i := u16(0); i < 32; i++ {
		match i {
			8 { // Dedicated double-fault stack, independent of IST3.
				unsafe { idt.register_handler(i, voidptr(thunks[i]), 2, 0x8e) }
				interrupt_table[i] = voidptr(exception_handler)
			}
			14 { // Page fault
				unsafe { idt.register_handler(i, voidptr(thunks[i]), 3, 0x8e) }
				interrupt_table[i] = voidptr(pf_handler)
			}
			3 { // User-mode INT3 breakpoint
				unsafe { idt.register_handler(i, voidptr(thunks[i]), 0, 0xee) }
				interrupt_table[i] = voidptr(exception_handler)
			}
			else {
				unsafe { idt.register_handler(i, voidptr(thunks[i]), 0, 0x8e) }
				interrupt_table[i] = voidptr(exception_handler)
			}
		}
	}

	for i := u16(32); i < 256; i++ {
		unsafe { idt.register_handler(i, voidptr(thunks[i]), 0, 0x8e) }
		interrupt_table[i] = voidptr(generic_isr)
	}

	abort_vector = idt.allocate_vector()
	unsafe { idt.register_handler(abort_vector, voidptr(thunks[abort_vector]), 4, 0x8e) }
	interrupt_table[abort_vector] = voidptr(abort_handler)
}
