@[has_globals]
module sched

import proc

const stack_size = u64(0x200000)

const max_running_threads = int(512)

__global (
	scheduler_vector        u8
	scheduler_running_queue [512]&proc.Thread
	kernel_process          &proc.Process
	uart_poll_callback      voidptr // Set by console module for HVF UART polling
)
