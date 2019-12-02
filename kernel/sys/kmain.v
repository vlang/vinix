module sys

import mm

struct VKernel {
	command_line string
}

__global kernel VKernel

pub fn kmain() {
	kernel = VKernel{}
	
	banner()
	kernel.parse_bootinfo()

	mm.paging_init()

	panic('No init service found.')
}