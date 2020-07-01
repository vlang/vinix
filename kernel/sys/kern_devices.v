module sys

import sync

struct KernelDevices {
mut:
	framebuffers [8]Framebuffer
	fb_mutex sync.Mutex
}