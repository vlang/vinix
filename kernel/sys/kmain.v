module sys

struct VKernel {
mut:
	command_line string
	callback_pool CallbackPool
	devices KernelDevices
	allocator voidptr
}

__global kernel VKernel

pub fn kmain() {
	memset(voidptr(&kernel), 0, sizeof(VKernel))

	kernel.init_platform()
	
	banner()
	kernel.parse_bootinfo()

	panic('No init service found.')
}
