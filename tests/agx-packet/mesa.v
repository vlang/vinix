// SPDX-License-Identifier: GPL-2.0-or-later
// Compile against the pinned Mesa include/drm-uapi directory with -cflags -I.
import drm.asahi
import gpu.agx.packet

#include "asahi_drm.h"

struct C.drm_asahi_cmd_header {
	cmd_type    u16
	size        u16
	vdm_barrier u16
	cdm_barrier u16
}

struct C.drm_asahi_cmd_render {
	vdm_ctrl_stream_base u64
	width_px            u16
	height_px           u16
	layers              u16
	utile_width_px      u8
	utile_height_px     u8
	samples             u8
	bg_eot_rsrc_spec_hi u32
}

struct C.drm_asahi_cmd_compute {
	cdm_ctrl_stream_base u64
}

struct C.drm_asahi_cmd_render_with_prior {
	legacy    C.drm_asahi_cmd_render
	prior_vdm u64
}

fn append_mesa_command(mut bytes []u8, kind u16, size u16, data voidptr) {
	// Honeykrisp's serialized G13 queue uses zero barriers for both engines.
	header := C.drm_asahi_cmd_header{cmd_type: kind, size: size}
	unsafe {
		bytes.push_many(voidptr(&header), int(sizeof(header)))
		bytes.push_many(data, int(size))
	}
}

fn main() {
	assert sizeof(C.drm_asahi_cmd_header) == sizeof(asahi.CmdHeader)
	render_size := u16(__offsetof(C.drm_asahi_cmd_render, bg_eot_rsrc_spec_hi))
	compute_size := u16(sizeof(C.drm_asahi_cmd_compute))
	assert render_size == __offsetof(asahi.CmdRender, bg_eot_rsrc_spec_hi)
	assert compute_size == __offsetof(asahi.CmdCompute, scs_layout)
	assert u16(C.DRM_ASAHI_CMD_RENDER) == asahi.cmd_render
	assert u16(C.DRM_ASAHI_CMD_COMPUTE) == asahi.cmd_compute
	render := C.drm_asahi_cmd_render{vdm_ctrl_stream_base: 0x4000, width_px: 640,
		height_px: 480, layers: 1, utile_width_px: 32, utile_height_px: 32, samples: 1}
	compute := C.drm_asahi_cmd_compute{cdm_ctrl_stream_base: 0x8000}
	mut bytes := []u8{}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	append_mesa_command(mut bytes, asahi.cmd_compute, compute_size, unsafe { &compute })
	append_mesa_command(mut bytes, asahi.cmd_render, render_size, unsafe { &render })
	mut reader := packet.reader(bytes.data, u64(bytes.len))
	mut command := packet.Command{}
	assert reader.next(mut command) == 0 && command.compute.cdm_ctrl_stream_base == 0x8000
	assert reader.next(mut command) == 0 && command.render.vdm_ctrl_stream_base == 0x4000
	assert command.render.width_px == 640 && command.render.height_px == 480
	assert reader.next(mut command) == 1
	extended := C.drm_asahi_cmd_render_with_prior{legacy: render, prior_vdm: 1}
	bytes.clear()
	append_mesa_command(mut bytes, asahi.cmd_render, u16(sizeof(extended)), unsafe { &extended })
	unsupported, _ := packet.validate(bytes.data, u64(bytes.len))
	assert unsupported == -22
	println('Mesa G13 packet prefixes accepted: render ${render_size} bytes, compute ${compute_size} bytes. Nonzero historical render dependency refused.')
}
