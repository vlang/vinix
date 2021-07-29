module isr

import idt
import event
import event.eventstruct
import apic
import cpu.local as cpulocal
import syscall
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
	event.trigger(int_events[num], true)
}

const exception_names = [
    charptr(c'Division by 0'),
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
    c'Security'
]

fn ud_handler(num u32, _gpr_state &cpulocal.GPRState) {
	mut gpr_state := unsafe { _gpr_state }
	insn := &u16(gpr_state.rip)
	if unsafe { insn[0] } == 0x340f {
		// This is sysenter
		gpr_state.rip += 2
		syscall.ud_entry(gpr_state)
	} else {
		exception_handler(num, gpr_state)
	}
}

fn pf_handler(num u32, gpr_state &cpulocal.GPRState) {
	mmap.pf_handler(gpr_state) or {
		exception_handler(num, gpr_state)
	}
}

fn abort_handler() {
	katomic.store(cpulocal.current().aborted, true)
	for {
		asm volatile amd64 { hlt }
	}
}

fn exception_handler(num u32, gpr_state &cpulocal.GPRState) {
	if gpr_state.cs == 0x4b {
		mut signal := byte(0)

		match num {
			13, 14 {
				signal = userland.sigsegv
			}
			else {
				lib.kpanic(gpr_state, exception_names[num])
			}
		}

		userland.sendsig(proc.current_thread(), signal)
		userland.dispatch_a_signal(gpr_state)
		userland.syscall_exit(voidptr(0), 128 + signal)
	} else {
		lib.kpanic(gpr_state, exception_names[num])
	}
}

__global (
	abort_vector = byte(0)
)

pub fn initialise() {
	for i := u16(0); i < 32; i++ {
		idt.register_handler(i, interrupt_thunks[i])
		match i {
			6 { // Invalid opcode
				interrupt_table[i] = voidptr(ud_handler)
				idt.set_ist(i, 2)
			}
			14 { // Page fault
				interrupt_table[i] = voidptr(pf_handler)
				idt.set_ist(i, 3)
			}
			else {
				interrupt_table[i] = voidptr(exception_handler)
			}
		}
	}

	for i := u16(32); i < 256; i++ {
		idt.register_handler(i, interrupt_thunks[i])
		interrupt_table[i] = voidptr(generic_isr)
	}

	abort_vector = idt.allocate_vector()
	idt.register_handler(abort_vector, voidptr(abort_handler))
	idt.set_ist(abort_vector, 4)
}
