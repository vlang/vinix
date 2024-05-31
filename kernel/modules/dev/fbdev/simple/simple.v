// simple.v: Driver for simple framebuffers.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module simple

import dev.fbdev.api

pub struct SimpleFBConfig {
pub mut:
	physical_address u64
	width            u32
	height           u32
	stride           u32
	bits_per_pixel   u32
	red              api.FBBitfield
	green            api.FBBitfield
	blue             api.FBBitfield
	transp           api.FBBitfield
}

__global (
	simplefb_driver      = api.FramebufferDriver{
		name: 'simplefb'
		init: simple_init
		register_device: unsafe { nil }
	}
	simplefb_initialized = false
	simplefb_pending_cnt = u32(0)
	simplefb_pending     [8]SimpleFBConfig
)

pub fn get_driver() &api.FramebufferDriver {
	return &simplefb_driver
}

fn simple_init() {
	for i := 0; i < simplefb_pending_cnt; i++ {
		do_register(&simplefb_pending[i])
	}

	simplefb_initialized = true
	simplefb_pending_cnt = 0

	println('simplefb: initialized')
}

fn do_register(config &SimpleFBConfig) {
	info := api.FramebufferInfo{
		base: voidptr(config.physical_address)
		size: config.stride * config.height
		driver: &simplefb_driver
		fixed: api.FBFixScreenInfo{
			id: [16]u8{}
			smem_start: 0
			smem_len: config.stride * config.height
			@type: api.fb_type_packed_pixels
			type_aux: 0
			visual: api.fb_visual_truecolor
			xpanstep: 0
			ypanstep: 0
			ywrapstep: 0
			line_length: config.stride
			mmio_start: 0
			mmio_len: 0
			accel: 0
		}
		variable: api.FBVarScreenInfo{
			xres: config.width
			yres: config.height
			xres_virtual: config.width
			yres_virtual: config.height
			xoffset: 0
			yoffset: 0
			bits_per_pixel: config.bits_per_pixel
			grayscale: 0
			red: config.red
			green: config.green
			blue: config.blue
			transp: config.transp
			nonstd: 0
			activate: api.fb_activate_now
			height: 0
			width: 0
			accel_flags: 0
			pixclock: 0
			left_margin: 0
			right_margin: 0
			upper_margin: 0
			lower_margin: 0
			hsync_len: 0
			vsync_len: 0
			sync: 0
			vmode: api.fb_vmode_noninterlaced
			rotate: 0
			reserved: [4]u32{}
		}
	}

	simplefb_driver.register_device(info) or {
		print('simplefb: failed to register framebuffer device: $err.msg()')
	}
}

pub fn register_simple_framebuffer(config SimpleFBConfig) {
	if !simplefb_initialized {
		if simplefb_pending_cnt >= 8 {
			print('simplefb: too many pending framebuffers')
			return
		}

		simplefb_pending[simplefb_pending_cnt] = config
		simplefb_pending_cnt++
		return
	}

	do_register(&config)
}
