module initialisation

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.exception
import aarch64.gic
import limine
import memory
import katomic
import sched

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

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

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
		sched.await()
	}
}
