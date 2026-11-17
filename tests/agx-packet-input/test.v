// SPDX-License-Identifier: GPL-2.0-or-later
module main

import drm.asahi
import drm.ioctl
import gpu.agx.command as agxcommand
import gpu.agx.submission
import usercopy

struct Guarded {
mut:
	before [64]u8
	commands [64]submission.Command
	after [64]u8
}

fn append_record(mut bytes []u8, kind u16, data voidptr, size u16, vdm u16, cdm u16) {
	mut header := asahi.CmdHeader{cmd_type: kind, size: size, vdm_barrier: vdm, cdm_barrier: cdm}
	unsafe { bytes.push_many(voidptr(&header), int(sizeof(header))); if size != 0 { bytes.push_many(data, int(size)) } }
}

fn randomize(data voidptr, size int, initial u64) u64 {
	mut seed := initial
	for i in 0 .. size {
		seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
		unsafe { (&u8(data))[i] = u8(seed) }
	}
	return seed
}

fn expect_attachments(actual [16]agxcommand.Attachment, count u32, expected [16]asahi.Attachment, expected_count u32) {
	assert count == expected_count, 'attachment count'
	for i in 0 .. 16 {
		item := actual[i]
		if i < int(count) {
			assert item.address == expected[i].pointer && item.size_bytes == expected[i].size, 'attachment identity'
			assert item.cache_lines == u32((expected[i].size + 127) / 128), 'attachment lines'
			assert item.order == 1, 'attachment exponent'
		} else { assert item == agxcommand.Attachment{}, 'inactive attachment' }
	}
}

fn expect_guards(g &Guarded) {
	assert g.before.all(it == 0xa5) && g.after.all(it == 0x5a), 'output guard'
}

fn check_inputs() {
	mut workspace := submission.PacketWorkspace{}
	mut seed := u64(0x3c5e7a9bcdef1234)
	mut bytes := []u8{cap: 65536}
	mut storage := Guarded{before: [64]u8{init: 0xa5}, after: [64]u8{init: 0x5a}}
	for iteration in 0 .. 256 {
		mut renders := [32]asahi.CmdRender{}
		mut computes := [32]asahi.CmdCompute{}
		mut attachments := [3][16]asahi.Attachment{}
		mut counts := [3]u32{}
		usc := seed
		bytes.clear()
		for i in 0 .. 32 {
			mut render := asahi.CmdRender{}
			mut compute := asahi.CmdCompute{}
			seed = randomize(&render, int(__offsetof(asahi.CmdRender, ts_frag_end_copies)), seed)
			seed = randomize(&compute, int(__offsetof(asahi.CmdCompute, ts_end_copies)), seed)
			render.flags = u32(iteration & 7) | (if iteration & 8 != 0 { asahi.render_dbias_is_int } else { u32(0) })
			render.width_px = u16(1 + (seed & 16383)); render.height_px = u16(1 + ((seed >> 16) & 16383))
			render.layers = u16(1 + ((seed >> 32) & 2047)); render.samples = u8(1 << (i % 3))
			render.utile_width_px = if i % 3 == 0 { u8(16) } else { u8(32) }
			render.utile_height_px = if i % 3 == 2 { u8(32) } else { u8(16) }
			compute.flags = 0
			if i == 0 { compute.sampler_count = ~u32(0) }
			renders[i] = render; computes[i] = compute
			// Replace one engine's state at a time, including empty/zero records.
			engine := i % 3
			counts[engine] = u32((i + iteration) % 17)
			for a in 0 .. int(counts[engine]) {
				attachments[engine][a] = asahi.Attachment{pointer: if a == 0 { u64(0) } else { seed + u64(a) }, size: if a == 0 { u64(0) } else { (seed & 0xffff) + u64(a) }}
			}
			append_record(mut bytes, asahi.set_vertex_attachments + u16(engine), &attachments[engine], u16(counts[engine] * u32(sizeof(asahi.Attachment))), asahi.barrier_none, asahi.barrier_none)
			append_record(mut bytes, asahi.cmd_compute, &compute, u16(sizeof(compute)), u16(i), asahi.barrier_none)
			append_record(mut bytes, asahi.cmd_render, &render, u16(sizeof(render)), asahi.barrier_none, u16(i + 1))
		}
		code, count := submission.decode_packet(bytes.data, u64(bytes.len), usc, mut storage.commands[..], mut workspace)
		assert code == 0 && count == 64, 'mixed packet count'
		for i in 0 .. 32 {
			c := storage.commands[i * 2]
			r := storage.commands[i * 2 + 1]
			assert c.descriptor.cmd_type == ioctl.asahi_cmd_compute, 'compute opcode'
			assert r.descriptor.cmd_type == ioctl.asahi_cmd_render, 'render opcode'
			assert c.descriptor.barriers == [u32(i), ioctl.asahi_barrier_none]!, 'compute barriers'
			assert r.descriptor.barriers == [ioctl.asahi_barrier_none, u32(i + 1)]!, 'render barriers'
			assert c.descriptor.cmd_buffer == 0 && c.descriptor.result_offset == 0 && c.descriptor.result_size == 0
			assert r.descriptor.cmd_buffer == 0 && r.descriptor.result_offset == 0 && r.descriptor.result_size == 0
			expect_compute(&c.compute, &computes[i], usc, i == 31)
			expect_render(&r.render, &renders[i], usc, i == 31)
			assert c.timestamps == [asahi.Timestamps{}, asahi.Timestamps{}, computes[i].ts]!, 'compute timestamp metadata'
			assert r.timestamps == [renders[i].ts_vtx, renders[i].ts_frag, asahi.Timestamps{}]!, 'render timestamp metadata'
			assert c.needs_timestamp_objects() && r.needs_timestamp_objects()
		}
		// Attachment expectations are kept from the wire records, not output.
		mut offset := 0
		counts = [3]u32{}; attachments = [3][16]asahi.Attachment{}
		mut hardware := 0
		for offset < bytes.len {
			mut h := asahi.CmdHeader{}
			unsafe { C.memcpy(&h, &bytes[offset], sizeof(h)) }; offset += int(sizeof(h))
			if h.cmd_type >= asahi.set_vertex_attachments {
				engine := int(h.cmd_type - asahi.set_vertex_attachments)
				counts[engine] = u32(h.size / sizeof(asahi.Attachment))
				unsafe { C.memcpy(&attachments[engine], &bytes[offset], h.size) }
			} else {
				value := storage.commands[hardware]
				if h.cmd_type == asahi.cmd_compute { expect_attachments(value.compute.attachments, value.compute.attachment_count, attachments[2], counts[2]) }
				else {
					expect_attachments(value.render.vertex_attachments, value.render.vertex_attachment_count, attachments[0], counts[0])
					expect_attachments(value.render.fragment_attachments, value.render.fragment_attachment_count, attachments[1], counts[1])
				}
				hardware++
			}
			offset += int(h.size)
		}
		expect_guards(&storage)
		// The staged value owns its bytes after the immutable input is discarded.
		for i in 0 .. bytes.len { bytes[i] = 0xff }
		expect_compute(&storage.commands[0].compute, &computes[0], usc, false)
	}
	unsafe { bytes.free() }
}

fn check_failures() {
	mut workspace := submission.PacketWorkspace{}
	mut storage := Guarded{before: [64]u8{init: 0xa5}, after: [64]u8{init: 0x5a}}
	mut bytes := []u8{}
	mut compute := asahi.CmdCompute{}
	mut render := asahi.CmdRender{width_px: 1, height_px: 16384, layers: 2048, samples: 4, utile_width_px: 32, utile_height_px: 32}
	code0, count0 := submission.decode_packet(unsafe { nil }, 0, 0, mut storage.commands[..], mut workspace)
	assert code0 == -22 && count0 == 0
	mut oversized := [65]submission.Command{}
	oversized_code, oversized_count := submission.decode_packet(unsafe { nil }, 0, 0, mut oversized[..], mut workspace)
	assert oversized_code == -22 && oversized_count == 0
	for _ in 0 .. 2 { append_record(mut bytes, asahi.cmd_compute, &compute, 64, 0, 0) }
	capacity_code, capacity_count := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..1], mut workspace)
	assert capacity_code == -22 && capacity_count == 0 && storage.commands[1] == submission.Command{}, 'capacity cannot expose or overwrite prefix'
	for kind in [asahi.cmd_compute, asahi.cmd_render] {
		bytes.clear()
		append_record(mut bytes, kind, if kind == asahi.cmd_compute { voidptr(&compute) } else { voidptr(&render) }, if kind == asahi.cmd_compute { u16(64) } else { u16(__offsetof(asahi.CmdRender, ts_vtx)) }, 0, 0)
		// The final record can be a software command with no payload. The
		// preceding hardware command still flushes its engine's stamps.
		hardware_size := bytes.len
		append_record(mut bytes, asahi.set_compute_attachments, unsafe { nil }, 0, asahi.barrier_none, asahi.barrier_none)
		code, count := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..1], mut workspace)
		assert code == 0 && count == 1 && !storage.commands[0].needs_timestamp_objects(), 'short zero-extended record'
		assert storage.commands[0].compute.flush_stamps == (kind == asahi.cmd_compute), 'single compute flush'
		assert storage.commands[0].render.flush_stamps == (kind == asahi.cmd_render), 'single render flush'
		for size in 0 .. bytes.len {
			if size == hardware_size { continue }
			error_code, error_count := submission.decode_packet(bytes.data, u64(size), 0, mut storage.commands[..], mut workspace)
			assert error_code == -22 && error_count == 0, 'truncated packet'
		}
		for _ in 0 .. 65 { append_record(mut bytes, asahi.cmd_compute, &compute, 64, 0, 0) }
		for capacity in [0, 1, 63, 64] {
			error_code, error_count := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..capacity], mut workspace)
			assert error_code == -22 && error_count == 0, 'failed packet has no usable prefix'
		}
	}
	compute.ts.start.offset = ~u32(0)
	bytes.clear(); append_record(mut bytes, asahi.cmd_compute, &compute, 64, 0, 0)
	code1, count1 := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..], mut workspace)
	assert code1 == 0 && count1 == 1 && !storage.commands[0].needs_timestamp_objects(), 'null timestamp handle ignores offset'
	compute.ts.end.handle = 1; compute.ts.end.offset = ~u32(0)
	bytes.clear(); append_record(mut bytes, asahi.cmd_compute, &compute, 64, 0, 0)
	code2, count2 := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..], mut workspace)
	assert code2 == 0 && count2 == 1 && storage.commands[0].needs_timestamp_objects(), 'defer object bounds to resolver'
	for kind in [u16(9), asahi.cmd_compute, asahi.cmd_render] {
		bytes.clear(); compute.flags = 1; render.flags = ~u32(0)
		append_record(mut bytes, kind, if kind == asahi.cmd_render { voidptr(&render) } else { voidptr(&compute) }, if kind == asahi.cmd_render { u16(sizeof(render)) } else { u16(sizeof(compute)) }, 0, 0)
		error_code, error_count := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..], mut workspace)
		assert error_code == -22 && error_count == 0, 'invalid opcode/flags'
	}
	compute.flags = 0; compute.ts_end_copies[0].handle = 1
	bytes.clear(); append_record(mut bytes, asahi.cmd_compute, &compute, u16(sizeof(compute)), 0, 0)
	tail_code, tail_count := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..], mut workspace)
	assert tail_code == -22 && tail_count == 0, 'unsupported nonzero extension'
	bytes.clear(); append_record(mut bytes, asahi.set_compute_attachments, unsafe { nil }, 0, asahi.barrier_none, asahi.barrier_none)
	software_code, software_count := submission.decode_packet(bytes.data, u64(bytes.len), 0, mut storage.commands[..], mut workspace)
	assert software_code == -22 && software_count == 0, 'software-only packet'
	expect_guards(&storage)
	unsafe { bytes.free() }
}

fn main() {
	check_inputs(); check_failures()
	assert usercopy.reads() == 0, 'packet adapter must not access userspace'
	println('packet input: 16384 hardware commands; all scalar fields, attachments, barriers, timestamp metadata and failure bounds pass')
}
