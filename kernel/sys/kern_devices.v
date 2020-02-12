module sys

import sync

struct KernelDevices {
mut:
	framebuffers [8]sys.Framebuffer
	fb_mutex sync.Mutex
	debug_sinks [8]sys.DebugSink
}