// SPDX-License-Identifier: GPL-2.0-or-later
import drm.asahi
import gpu.agx.packet

fn append_record(mut bytes []u8, kind u16, data voidptr, size u16, vdm u16, cdm u16) {
	mut header := asahi.CmdHeader{ cmd_type: kind, size: size, vdm_barrier: vdm, cdm_barrier: cdm }
	unsafe {
		bytes.push_many(voidptr(&header), int(sizeof(asahi.CmdHeader)))
		if size != 0 { bytes.push_many(data, int(size)) }
	}
}

fn validate(bytes []u8) int {
	code, _ := packet.validate(bytes.data, u64(bytes.len))
	return code
}

fn main() {
	mut bytes := []u8{}
	mut compute := asahi.CmdCompute{ cdm_ctrl_stream_base: 0x100000 }
	mut render := asahi.CmdRender{
		width_px:        640
		height_px:       480
		layers:          1
		utile_width_px:  32
		utile_height_px: 32
		samples:         1
	}
	mut attachment := asahi.Attachment{ pointer: 0x30000, size: 129 }
	append_record(mut bytes, asahi.set_compute_attachments, &attachment, u16(sizeof(attachment)), asahi.barrier_none, asahi.barrier_none)
	for i := u16(0); i < 32; i++ {
		append_record(mut bytes, asahi.cmd_compute, &compute, u16(sizeof(compute)), i, i)
		append_record(mut bytes, asahi.cmd_render, &render, u16(sizeof(render)), i, i + 1)
	}
	code, info := packet.validate(bytes.data, u64(bytes.len))
	assert code == 0 && info.render_count == 32 && info.compute_count == 32
	mut reader := packet.reader(bytes.data, u64(bytes.len))
	mut command := packet.Command{}
	assert reader.next(mut command) == 0
	assert command.compute_count == 1 && command.compute_attachments[0].cache_lines == 2
	assert command.compute.cdm_ctrl_stream_base == 0x100000
	assert reader.next(mut command) == 0 && command.header.cmd_type == asahi.cmd_render
	assert command.vertex_count == 0 && command.fragment_count == 0
	append_record(mut bytes, asahi.cmd_compute, &compute, u16(sizeof(compute)), 0, 0)
	assert validate(bytes) == -22, '65th hardware command must be rejected'
	bytes.clear()
	// Truncated hardware records are zero extended. The 64-byte compute
	// prefix predates the end-copy and ray-query extension fields.
	append_record(mut bytes, asahi.cmd_compute, &compute, 64, asahi.barrier_none, asahi.barrier_none)
	assert validate(bytes) == 0
	for length in 1 .. 8 {
		assert validate(bytes[..length]) == -22
	}
	mut truncated := bytes.clone()
	truncated.delete_last()
	assert validate(truncated) == -22
	bytes.clear()
	compute.ts_end_copies[0].handle = 1
	append_record(mut bytes, asahi.cmd_compute, &compute, u16(sizeof(compute)), 0, 0)
	assert validate(bytes) == -22, 'unsupported nonzero tail must fail'
	compute.ts_end_copies[0].handle = 0
	bytes.clear()
	append_record(mut bytes, asahi.cmd_compute, &compute, 64, 1, 0)
	assert validate(bytes) == -22, 'a barrier cannot point at future work'
	bytes.clear()
	append_record(mut bytes, 7, unsafe { nil }, 0, asahi.barrier_none, asahi.barrier_none)
	assert validate(bytes) == -22
	bytes.clear()
	append_record(mut bytes, asahi.set_compute_attachments, &attachment, u16(sizeof(attachment)), 0, asahi.barrier_none)
	assert validate(bytes) == -22, 'software records must not request a barrier'
	bytes.clear()
	attachment.flags = 1
	append_record(mut bytes, asahi.set_compute_attachments, &attachment, u16(sizeof(attachment)), asahi.barrier_none, asahi.barrier_none)
	assert validate(bytes) == -22
	bytes.clear()
	attachment.flags = 0
	append_record(mut bytes, asahi.set_compute_attachments, &attachment, u16(sizeof(attachment)), asahi.barrier_none, asahi.barrier_none)
	assert validate(bytes) == -22, 'software records alone cannot submit work'
	// All single-byte corruptions must remain memory safe and terminate.
	append_record(mut bytes, asahi.cmd_compute, &compute, 64, 0, 0)
	for i in 0 .. bytes.len {
		original := bytes[i]
		bytes[i] = 0xff
		_ = validate(bytes)
		bytes[i] = original
	}
	println('Asahi flat packets: 64-command mixed batches, attachments, truncation, barriers and malformed inputs passed')
}
