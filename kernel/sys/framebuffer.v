module sys

enum FramebufferPixelFormat {
	rgba8888,
	bgra8888,
	argb8888,
	abgr8888,
	rgb888,
	bgr888
}

pub struct Framebuffer {
mut:
	addr_phys voidptr
	addr_virt voidptr
	width u32
	height u32
	pitch u32
	pixel_format FramebufferPixelFormat
}

fn (fb mut Framebuffer) init(id int) {
	fb.addr_virt = phys_to_virtual(fb.addr_phys)
	printk('Initialized framebuffer ${id}: (mapped ${fb.addr_phys} to ${fb.addr_virt}): ${fb.width}x${fb.height} pitch: ${fb.pitch}')
}

[inline]
pub fn new_framebuffer(addr_phys voidptr, width u32, height u32, pitch u32, pixel_format FramebufferPixelFormat) Framebuffer {
	return Framebuffer {
		addr_phys: addr_phys,
		addr_virt: nullptr,
		width: width,
		height: height,
		pitch: pitch,
		pixel_format: pixel_format,
	}
}

pub fn (kernel &VKernel) register_framebuffer(framebuffer Framebuffer) {
	fb_list := &kernel.devices.framebuffers
	for i := 0; i < 8; i++ {
		mut fb_val := fb_list[i]

		if fb_val.addr_phys == nullptr {
			// V sucks, we need to copy the fields manually...
			fb_val.addr_phys = framebuffer.addr_phys
			fb_val.addr_virt = framebuffer.addr_virt
			fb_val.width = framebuffer.width
			fb_val.height = framebuffer.height
			fb_val.pitch = framebuffer.pitch
			fb_val.pixel_format = framebuffer.pixel_format

			fb_val.init(i)
			break
		}
	}
}
