module sys

struct VKernel {
mut:
	command_line string
	debug_buffer voidptr
	debug_buffer_size u32
	devices KernelDevices
}

__global kernel VKernel

pub fn kmain() {
	memset(voidptr(&kernel), 0, sizeof(VKernel))

	kernel.init_platform()
	kernel.init_debug()

	banner()
	kernel.parse_bootinfo()

	panic('No init service found.')
}
