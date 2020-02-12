module sys

enum FramebufferPixelFormat {
	rgba8888,
	bgra8888,
	argb8888,
	abgr8888,
	rgb888,
	bgr888
}

const (
	CALLBACK_FRAMEBUFFER_ATTACH = 0x2000
	CALLBACK_FRAMEBUFFER_DETACH = 0x2001
)

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

	/*for y := 0; y < fb.height; y++ {
		for x := 0; x < fb.width; x++ {
			fb.plot(u32(x), u32(y), 0x000000)
		}
	}*/
	memset32(fb.addr_virt, 0, fb.width * fb.height)

	printk('Initialized framebuffer ${id}: (mapped ${fb.addr_phys} to ${fb.addr_virt}): ${fb.width}x${fb.height} pitch: ${fb.pitch}')
	emit_callback(CALLBACK_FRAMEBUFFER_ATTACH, voidptr(fb))
}

[inline]
fn (fb &Framebuffer) plot(x, y, color u32) {
	if x < fb.width && y < fb.height {
		memputd(fb.addr_virt, int(y) * int(fb.pitch) / 4 + int(x), color)
	}
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

pub fn (kernel &VKernel) register_framebuffer(framebuffer Framebuffer) &Framebuffer {
	// V compiler is broken
	for i := 0; i < 8; i++ {
		mut fb_val := &kernel.devices.framebuffers[i]

		if fb_val.addr_phys == nullptr {
			// V compiler is broken
			fb_val.addr_phys = framebuffer.addr_phys
			fb_val.addr_virt = framebuffer.addr_virt
			fb_val.width = framebuffer.width
			fb_val.height = framebuffer.height
			fb_val.pitch = framebuffer.pitch
			fb_val.pixel_format = framebuffer.pixel_format

			fb_val.init(i)
			return fb_val
		}
	}

	return &Framebuffer(nullptr)
}
