module initialisation

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.exception
import aarch64.gic
import limine
import memory
import katomic
import sched

// Turn PAN on for this CPU, where the command line and the CPU allow it: see
// memory/user_guard.v.
pub fn enable_user_guard(announce bool) {
	if memory.user_guard_requested() == memory.user_guard_off {
		memory.disable_execute_only()
		return
	}
	if !cpu.has_pan() {
		memory.disable_execute_only()
		memory.user_guard_unsupported()
		return
	}
	// Apple hardware runs the kernel at EL2. PAN works the same way there, but
	// it has only been run at EL1, under QEMU: at EL2 it is for the command
	// line to turn on.
	if cpu.read_currentel() == 2 {
		memory.user_guard_untested()
		if memory.user_guard_requested() == memory.user_guard_off {
			memory.disable_execute_only()
			return
		}
	}
	cpu.enable_pan()
	if !cpu.has_epan() { memory.disable_execute_only() }
	if announce {
		println(if memory.user_guard_auditing() {
			'security: PAN enabled, auditing'
		} else {
			'security: PAN enabled'
		})
	}
}

pub fn initialise(smp_info &limine.LimineSMPInfo) {
	mut cpu_local := unsafe { &cpulocal.Local(smp_info.extra_argument) }
	cpu_number := cpu_local.cpu_number

	// Set TPIDR_EL1 to cpu_number for per-CPU data access
	cpu.write_tpidr_el1(cpu_number)

	// Limine deliberately leaves VBAR undefined on every CPU, and leaves SP_EL1
	// undefined too. The BSP installs both during early exception setup; APs
	// enter here directly from Limine's parked trampoline and must install them
	// themselves before a scheduled EL0 thread can take an exception.
	exception.initialise_secondary(cpu_number)

	cpu.enable_el0_cache_access()
	cpu.enable_el0_virtual_counter()

	// The kernel's page tables and memory attributes. TTBR1, MAIR and TCR are
	// per-CPU registers that the BSP's vmm_init only wrote for itself, so a CPU
	// that only switched TTBR0 kept translating the higher half through the
	// bootloader's tables.
	memory.vmm_activate_on_cpu()
	exception.install_guarded_stack(cpu_number)
	sched.prepare_cpu_stacks(cpu_number)

	enable_user_guard(cpu_number == 0)

	// This CPU's own half of the interrupt controller. Without it the CPU takes
	// no interrupts at all, which means its scheduler timer never fires, which
	// means a thread busy in userspace on it is never taken off: no timeslice,
	// no affinity change, and nothing more urgent able to take the CPU.
	//
	// It has to come after the page tables above, not before: the redistributor
	// is device memory, and reaching it through the bootloader's mapping gets it
	// accessed as ordinary memory, by an instruction a hypervisor is then unable
	// to decode the access from.
	if cpu_number != 0 && gic.is_initialised() {
		gic.initialise_secondary(cpu_number)
	}

	// Configure timer frequency
	cpu_local.timer_freq = cpu.read_cntfrq_el0()

	// The kernel itself uses integer registers only, but EL0 NEON/FP state is
	// architectural thread state and must be switched on every CPU.
	cpu.init_fpu_globals()

	C.kprintf(c'smp: CPU %llu online!\n', u64(cpu_local.cpu_number))

	katomic.inc(mut &cpu_local.online)

	if cpu_number != 0 {
		// Into the scheduler. This used to wait on scheduler_vector, which only
		// the amd64 scheduler ever sets -- this architecture allocates no
		// interrupt vectors -- so every CPU but the first spun here for the life
		// of the machine and never ran a thread.
		for !katomic.load(&scheduler_ready) {
			asm volatile aarch64 {
				wfe
				; ; ; memory
			}
		}
		sched.enter_idle()
	}
}
