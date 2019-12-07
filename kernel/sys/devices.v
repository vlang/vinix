module sys

struct KernelDevices {
mut:
	framebuffers [8]sys.Framebuffer
	fb_mutex Mutex
	debug_sinks [8]sys.DebugSink
}