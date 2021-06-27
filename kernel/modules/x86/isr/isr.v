[manualfree] module isr

import idt
import event
import event.eventstruct
import apic
import cpu.local as cpulocal
import cpu
import syscall
import memory.mmap
import katomic
import lib

__global (
	int_events [256]eventstruct.Event
)

fn generic_isr(num u32, _ voidptr) {
	apic.lapic_eoi()
	event.trigger(int_events[num])
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
	C.printf(c'\n%s on CPU %d\n',
			 exception_names[num], cpulocal.current().cpu_number)
	C.printf(c'Error code: 0x%016llx\n', gpr_state.err)
	C.printf(c'Register dump:\n')
	C.printf(c'CS:RIP=%04llx:%016llx\n', gpr_state.cs, gpr_state.rip)
	C.printf(c'SS:RSP=%04llx:%016llx\n', gpr_state.ss, gpr_state.rsp)
	C.printf(c'RFLAGS=%08llx       CR2=%016llx\n', gpr_state.rflags, cpu.read_cr2())
	C.printf(c'RAX=%016llx  RBX=%016llx  RCX=%016llx  RDX=%016llx\n',
			 gpr_state.rax, gpr_state.rbx, gpr_state.rcx, gpr_state.rdx)
	C.printf(c'RSI=%016llx  RDI=%016llx  RBP=%016llx  RSP=%016llx\n',
			 gpr_state.rsi, gpr_state.rdi, gpr_state.rbp, gpr_state.rsp)
	C.printf(c'R08=%016llx  R09=%016llx  R10=%016llx  R11=%016llx\n',
			 gpr_state.r8, gpr_state.r9, gpr_state.r10, gpr_state.r11)
	C.printf(c'R12=%016llx  R13=%016llx  R14=%016llx  R15=%016llx\n',
			 gpr_state.r12, gpr_state.r13, gpr_state.r14, gpr_state.r15)
	lib.kpanic(c'Unhandled exception')
}

__global (
	abort_vector = u8(0)
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
