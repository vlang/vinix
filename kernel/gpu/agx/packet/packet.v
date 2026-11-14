// SPDX-License-Identifier: GPL-2.0-or-later
module packet

// The packaged Asahi flat command protocol. The caller owns an immutable
// kernel copy of the packet for the reader's lifetime. No allocation or
// userspace access occurs here; commands and attachments are stack values.
import drm.asahi

pub struct Attachment {
pub:
	address     u64
	size_bytes  u64
	cache_lines u32
}

pub struct Command {
pub mut:
	header               asahi.CmdHeader
	render               asahi.CmdRender
	compute              asahi.CmdCompute
	vertex_count         u32
	fragment_count       u32
	compute_count        u32
	vertex_attachments   [16]Attachment
	fragment_attachments [16]Attachment
	compute_attachments  [16]Attachment
}

pub struct Info {
pub mut:
	render_count  u32
	compute_count u32
}

pub struct Reader {
mut:
	data              voidptr
	size              u64
	offset            u64
	info              Info
	attachment_counts [3]u32
	attachments       [3][16]Attachment
	failed            bool
}

pub fn reader(data voidptr, size u64) Reader {
	return Reader{ data: data, size: size }
}

pub fn (r &Reader) info() Info { return r.info }

fn (mut r Reader) reject() int {
	r.failed = true
	return -22
}

fn (r &Reader) supported(payload u64, size u64, supported u64) bool {
	if size <= supported { return true }
	bytes := unsafe { &u8(u64(r.data) + payload) }
	for i := supported; i < size; i++ {
		if unsafe { bytes[i] } != 0 { return false }
	}
	return true
}

fn (mut r Reader) read_attachments(kind u32, start u64, size u64) bool {
	stride := u64(sizeof(asahi.Attachment))
	if size % stride != 0 || size / stride > asahi.max_attachments { return false }
	count := u32(size / stride)
	for index := u32(0); index < count; index++ {
		mut item := asahi.Attachment{}
		unsafe { C.memcpy(&item, voidptr(u64(r.data) + start + u64(index) * stride), stride) }
		if item.flags != 0 || item.pad != 0 { return false }
		lines := (item.size >> 7) + if item.size & 127 != 0 { u64(1) } else { u64(0) }
		if lines > u64(~u32(0)) { return false }
		r.attachments[kind][index] = Attachment{ address: item.pointer, size_bytes: item.size, cache_lines: u32(lines) }
	}
	r.attachment_counts[kind] = count
	return true
}

fn valid_render(command &asahi.CmdRender) bool {
	return command.flags & ~asahi.render_supported == 0
		&& command.width_px != 0 && command.width_px <= 16384
		&& command.height_px != 0 && command.height_px <= 16384
		&& command.layers != 0 && command.layers <= 2048
		&& ((command.utile_width_px == 32 && command.utile_height_px == 32)
			|| (command.utile_width_px == 32 && command.utile_height_px == 16)
			|| (command.utile_width_px == 16 && command.utile_height_px == 16))
		&& command.samples in [u8(1), 2, 4]!
}

// Zero means one hardware command, one means end of packet, negative errno
// means invalid. Software attachment records persist until replaced, and do
// not count against the 64-command hardware limit.
pub fn (mut r Reader) next(mut output Command) int {
	if r.failed { return -22 }
	if r.size != 0 && (r.data == unsafe { nil } || r.size - 1 > ~u64(r.data)) { return r.reject() }
	for r.offset < r.size {
		if r.size - r.offset < sizeof(asahi.CmdHeader) { return r.reject() }
		mut header := asahi.CmdHeader{}
		unsafe { C.memcpy(&header, voidptr(u64(r.data) + r.offset), sizeof(asahi.CmdHeader)) }
		start := r.offset + sizeof(asahi.CmdHeader)
		size := u64(header.size)
		if size > r.size - start { return r.reject() }
		r.offset = start + size
		if header.cmd_type >= asahi.set_vertex_attachments && header.cmd_type <= asahi.set_compute_attachments {
			if header.vdm_barrier != asahi.barrier_none || header.cdm_barrier != asahi.barrier_none
				|| !r.read_attachments(u32(header.cmd_type - asahi.set_vertex_attachments), start, size) {
				return r.reject()
			}
			continue
		}
		if (header.vdm_barrier != asahi.barrier_none && u32(header.vdm_barrier) > r.info.render_count)
			|| (header.cdm_barrier != asahi.barrier_none && u32(header.cdm_barrier) > r.info.compute_count)
			|| r.info.render_count + r.info.compute_count >= asahi.max_commands {
			return r.reject()
		}
		output = Command{ header: header }
		match header.cmd_type {
			asahi.cmd_render {
				limit := u64(__offsetof(asahi.CmdRender, ts_frag_end_copies))
				if !r.supported(start, size, limit) { return r.reject() }
				copy_size := if size < limit { size } else { limit }
				unsafe { C.memcpy(&output.render, voidptr(u64(r.data) + start), copy_size) }
				if !valid_render(&output.render) { return r.reject() }
				output.vertex_count = r.attachment_counts[0]
				output.fragment_count = r.attachment_counts[1]
				output.vertex_attachments = r.attachments[0]
				output.fragment_attachments = r.attachments[1]
				r.info.render_count++
			}
			asahi.cmd_compute {
				limit := u64(__offsetof(asahi.CmdCompute, ts_end_copies))
				if !r.supported(start, size, limit) { return r.reject() }
				copy_size := if size < limit { size } else { limit }
				unsafe { C.memcpy(&output.compute, voidptr(u64(r.data) + start), copy_size) }
				if output.compute.flags != 0 { return r.reject() }
				output.compute_count = r.attachment_counts[2]
				output.compute_attachments = r.attachments[2]
				r.info.compute_count++
			}
			else { return r.reject() }
		}
		return 0
	}
	return 1
}

pub fn validate(data voidptr, size u64) (int, Info) {
	mut r := reader(data, size)
	mut command := Command{}
	for {
		result := r.next(mut command)
		if result < 0 { return result, Info{} }
		if result == 1 { break }
	}
	if r.info.render_count + r.info.compute_count == 0 { return -22, Info{} }
	return 0, r.info
}
