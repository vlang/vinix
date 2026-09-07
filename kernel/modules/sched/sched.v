@[has_globals]
module sched

import proc

const stack_size = u64(0x200000)

// Kernel stacks do not need the two-megabyte reservation used for initial
// userspace stacks. Keeping them small also avoids requiring a large
// physically-contiguous run for every pthread a native runtime creates.
const kernel_stack_size = u64(0x10000)

const max_running_threads = int(512)

__global (
	scheduler_vector        u8
	scheduler_running_queue [512]&proc.Thread
	kernel_process          &proc.Process
	uart_poll_callback      voidptr // Set by console module for HVF UART polling
)
