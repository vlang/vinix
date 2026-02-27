module lib

import aarch64.cpu.local as cpulocal
import aarch64.cpu

@[noreturn]
pub fn kpanic(gpr_state &cpulocal.GPRState, message charptr) {
	kpanic_lock.acquire()

	cpu.interrupt_toggle(false)

	// TODO: Send IPIs to halt other CPUs once AIC IPI support
	// is available without creating an import cycle (lib -> aic -> exception -> lib)

	cpu_number := if smp_ready { cpulocal.current().cpu_number } else { 0 }

	C.printf_panic(c'\n  *** Vinix KERNEL PANIC on CPU %d ***\n\n', cpu_number)
	C.printf_panic(c'Panic info: %s\n', message)
	if gpr_state != unsafe { nil } {
		C.printf_panic(c'ESR_EL1: 0x%016llx  FAR_EL1: 0x%016llx\n', cpu.read_esr_el1(),
			cpu.read_far_el1())
		C.printf_panic(c'Register dump:\n')
		C.printf_panic(c'PC  (ELR_EL1)=%016llx  PSTATE (SPSR_EL1)=%016llx\n', gpr_state.pc,
			gpr_state.pstate)
		C.printf_panic(c'SP=%016llx   X30(LR)=%016llx\n', gpr_state.sp, gpr_state.x30)
		C.printf_panic(c'X00=%016llx  X01=%016llx  X02=%016llx  X03=%016llx\n', gpr_state.x0,
			gpr_state.x1, gpr_state.x2, gpr_state.x3)
		C.printf_panic(c'X04=%016llx  X05=%016llx  X06=%016llx  X07=%016llx\n', gpr_state.x4,
			gpr_state.x5, gpr_state.x6, gpr_state.x7)
		C.printf_panic(c'X08=%016llx  X09=%016llx  X10=%016llx  X11=%016llx\n', gpr_state.x8,
			gpr_state.x9, gpr_state.x10, gpr_state.x11)
		C.printf_panic(c'X12=%016llx  X13=%016llx  X14=%016llx  X15=%016llx\n', gpr_state.x12,
			gpr_state.x13, gpr_state.x14, gpr_state.x15)
		C.printf_panic(c'X16=%016llx  X17=%016llx  X18=%016llx  X19=%016llx\n', gpr_state.x16,
			gpr_state.x17, gpr_state.x18, gpr_state.x19)
		C.printf_panic(c'X20=%016llx  X21=%016llx  X22=%016llx  X23=%016llx\n', gpr_state.x20,
			gpr_state.x21, gpr_state.x22, gpr_state.x23)
		C.printf_panic(c'X24=%016llx  X25=%016llx  X26=%016llx  X27=%016llx\n', gpr_state.x24,
			gpr_state.x25, gpr_state.x26, gpr_state.x27)
		C.printf_panic(c'X28=%016llx  X29(FP)=%016llx\n', gpr_state.x28, gpr_state.x29)
	}

	for {
		cpu.wfi()
	}

	for {}
}
