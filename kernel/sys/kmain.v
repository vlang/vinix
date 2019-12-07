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
	kernel = new_vkernel()
	kernel.init_platform()
	kernel.init_debug()
	
	banner()
	kernel.parse_bootinfo()

	panic('No init service found.')
}

fn new_vkernel() VKernel {
	return VKernel{
		command_line: '',
		debug_buffer: null,
		debug_buffer_size: 0,
		devices: KernelDevices {
			framebuffers: [8]Framebuffer,
			fb_mutex: Mutex{},
			debug_sinks: [8]DebugSink,
		}
	}
}