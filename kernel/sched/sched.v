@[has_globals]
module sched

import klock
import proc

// Guarded x86 task stacks; CPU interrupt/idle stacks retain their own size.
const stack_size = u64(0x40000)

// Match the default RLIMIT_STACK exposed to userspace. Large self-hosted
// compilers such as a TCC-built V can legitimately need more than 2 MiB while
// translating a full application.
const default_user_stack_size = u64(0x800000)

// How much address space a program's first thread gets for its stack, unless
// RLIMIT_STACK says more, up to the most it is given.
const main_stack_reservation = u64(256) << 20

const max_main_stack_reservation = u64(4) << 30

// ARM64 kernel stacks do not need the larger userspace reservation. Keeping
// them small also avoids requiring a large
// physically-contiguous run for every pthread a native runtime creates.
const kernel_stack_size = u64(0x10000)

__global (
	scheduler_vector        u8
	// Legacy Linux I/O reservation lock. Runnable membership is per Thread,
	// and selection uses the CPU's own queue lock.
	scheduler_queue_lock klock.Lock
	kernel_process          &proc.Process
	uart_poll_callback      voidptr // Set by console module for HVF UART polling
	// Published by initialise() once the run queue and the kernel process exist.
	// A secondary CPU waits for this before it enters await(): until then there
	// is no kernel_process for it to switch to and no queue to read.
	scheduler_ready = false
)
