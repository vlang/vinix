module initialisation

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.exception
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

	// Configure timer frequency
	cpu_local.timer_freq = cpu.read_cntfrq_el0()

	// The kernel itself uses integer registers only, but EL0 NEON/FP state is
	// architectural thread state and must be switched on every CPU.
	cpu.init_fpu_globals()

	print('smp: CPU ${cpu_local.cpu_number} online!\n')

	katomic.inc(mut &cpu_local.online)

	if cpu_number != 0 {
		// A secondary CPU is fully set up by this point but does not schedule.
		// The loop below waits for scheduler_vector, which only the amd64
		// scheduler ever sets -- this architecture has no interrupt vectors to
		// allocate -- so in practice it parks here for good.
		//
		// That is deliberate for now rather than an oversight left in place.
		// Releasing these CPUs into await() brings up four-way scheduling and
		// userspace then faults: a thread migrated between CPUs either wedges
		// or takes a null dereference in the kernel. Everything needed to
		// release them is in place -- per-CPU VBAR, SP_EL1, MAIR, TTBR1 and
		// TCR, all installed above -- and the scheduler already prefers a
		// thread's own memory node when it picks one. What is missing is
		// whatever the migration path still shares between CPUs, and finding
		// it is its own piece of work.
		//
		// Until then: a thread's pages come from the node of the CPU it runs
		// on, which is this machine's node 0, and mbind(2)/set_mempolicy(2)
		// reach every other node explicitly.
		for katomic.load(&scheduler_vector) == 0 {
			asm volatile aarch64 {
				wfe
				; ; ; memory
			}
		}
		sched.await()
	}
}
