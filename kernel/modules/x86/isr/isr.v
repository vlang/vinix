@[has_globals]
module isr

import x86.idt
import event
import event.eventstruct
import x86.apic
import x86.cpu
import x86.cpu.local as cpulocal
import memory.mmap
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
]

fn pf_handler(num u32, mut gpr_state cpulocal.GPRState) {
	mmap.pf_handler(gpr_state) or { exception_handler(num, mut gpr_state) }
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

fn exception_handler(num u32, mut gpr_state cpulocal.GPRState) {
	if gpr_state.cs == user_code_seg {
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
		// Hardware error codes occupy the low bits; mlibc exposes the vector in
		// the high half as uc_mcontext.gregs[REG_TRAPNO].
		gpr_state.err = (gpr_state.err & u64(0xffffffff)) | (u64(num) << 32)
		fault_addr := if num == 14 { cpu.read_cr2() } else { u64(0) }
		fault_code := match num {
			0 { 1 } // FPE_INTDIV
			1 { 2 } // TRAP_TRACE
			3 { 1 } // TRAP_BRKPT
			14 { if gpr_state.err & 1 != 0 { 2 } else { 1 } } // SEGV_ACCERR / SEGV_MAPERR
			else { 128 } // SI_KERNEL
		}
		userland.sendsig(proc.current_thread(), signal)
		userland.dispatch_a_signal_info(gpr_state, int(signal), fault_code, fault_addr)
		// dispatch_a_signal() switches away when it delivered the exception. If
		// no userspace signal entry exists (or SIGSEGV was blocked), do not retry
		// the same fault forever.
		userland.syscall_exit(unsafe { nil }, 128 + signal)
	} else {
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
