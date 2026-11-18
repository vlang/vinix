module file

import drm.asahi
import drm.gem
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
import klock
import memory
import usercopy

fn append_packet(mut bytes []u8, kind u16, data voidptr, size u16, vdm u16, cdm u16) {
	header := asahi.CmdHeader{ cmd_type: kind, size: size, vdm_barrier: vdm, cdm_barrier: cdm }
	unsafe {
		bytes.push_many(voidptr(&header), int(sizeof(header)))
		bytes.push_many(data, int(size))
	}
}

pub fn measure_modern_syncs() {
	$if macos {
		input := output()
		out := output()
		syncobj.replace_fence(input, syncobj.new_fence(1, 1))
		records := [asahi.Sync{ handle: input.handle }, asahi.Sync{ handle: out.handle }]!
		for count in [u32(0), 1]! {
			for _ in 0 .. 20 {
				code, _, _ := submission.stage_packet_syncs(1, unsafe { u64(&records[0]) }, count, count)
				assert code == 0
			}
			for batch in 0 .. 3 {
				before_blocks, before_bytes := live_record_heap()
				for _ in 0 .. 1000 {
					code, inputs, outputs := submission.stage_packet_syncs(1, unsafe { u64(&records[0]) }, count, count)
					assert code == 0 && inputs.count == count && outputs.count == count
				}
				after_blocks, after_bytes := live_record_heap()
				println('modern-sync count=${count} batch=${batch} operations=1000 retained_blocks=${i64(after_blocks) - before_blocks} retained_bytes=${i64(after_bytes) - i64(before_bytes)}')
			}
		}
	} $else {
		panic('malloc-zone retention measurement requires macOS')
	}
}

pub fn run_modern_submission_checks() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input := output()
	out := output()
	dependency := syncobj.new_fence(1, 1)
	syncobj.replace_fence(input, dependency)
	mut syncs := [asahi.Sync{ handle: input.handle }, asahi.Sync{ handle: out.handle }]!
	compute := asahi.CmdCompute{ cdm_ctrl_stream_base: 0xdecaf000 }
	render := asahi.CmdRender{ width_px: 64, height_px: 32, layers: 1, samples: 1, utile_width_px: 32, utile_height_px: 32 }
	mut bytes := []u8{}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
	append_packet(mut bytes, asahi.cmd_render, unsafe { &render }, u16(sizeof(render)), asahi.barrier_none, 1)
	mut request := asahi.Submit{
		queue_id:       1
		syncs:          unsafe { u64(&syncs[0]) }
		in_sync_count:  1
		out_sync_count: 1
		cmdbuf:         u64(bytes.data)
		cmdbuf_size:    u32(bytes.len)
	}
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	assert memory.outstanding() == 1 && manager.g13_compute_jobs.len == 1 && manager.g13_render_jobs.len == 1
	assert manager.g13_compute_jobs[0].marker == compute.cdm_ctrl_stream_base
	assert manager.g13_compute_jobs[0].usc_base == 0x120000000
	// The worker must never revisit either userspace packet or scratch storage.
	unsafe { C.memset(bytes.data, 0xff, bytes.len) }
	syncs[0].handle = ~u32(0)
	service_file_work()
	assert manager.published.len == 0
	syncobj.signal(dependency)
	service_file_work()
	assert manager.published == [u32(12), 10]
	manager.finish_render(0)
	service_file_work()
	assert !syncobj.is_signaled(fence(out))
	manager.finish_compute(0)
	service_file_work()
	assert syncobj.is_signaled(fence(out))
	assert_drained(file)
	// Reuse stable host owners so the repeated count isolates native scratch
	// and pending storage, rather than per-case fixture constructor allocations.
	bytes.clear()
	append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
	request = asahi.Submit{ queue_id: 1, cmdbuf: u64(bytes.data), cmdbuf_size: u32(bytes.len) }
	mut cases := 0
	for _ in 0 .. 100 {
		for fail in 0 .. 4 {
			memory.fail_at(fail)
			assert file.ioctl_modern_submit(unsafe { &request }) == -12
			memory.fail_at(-1)
			assert_drained(file)
			cases++
		}
		usercopy.reject(true)
		assert file.ioctl_modern_submit(unsafe { &request }) == -14
		usercopy.reject(false)
		assert_drained(file)
		cases++
		request.queue_id = 99
		request.syncs = 0
		request.in_sync_count = 65
		assert file.ioctl_modern_submit(unsafe { &request }) == -2
		request.queue_id = 1
		request.in_sync_count = 0
		assert_drained(file)
		cases++
		assert file.ioctl_modern_submit(unsafe { &request }) == 0
		assert manager.g13_compute_jobs[0].flush_stamps, 'single compute command must flush stamps'
		service_file_work()
		manager.finish_compute(0)
		service_file_work()
		assert_drained(file)
		cases++
	}
	// Modern 16-byte records are decoded with their own stride and ordering.
	mut invalid := asahi.Sync{ handle: input.handle, timeline_value: 1 }
	request.syncs = unsafe { u64(&invalid) }
	request.in_sync_count = 1
	assert file.ioctl_modern_submit(unsafe { &request }) == -22
	invalid.sync_type = 99
	assert file.ioctl_modern_submit(unsafe { &request }) == -22
	invalid = asahi.Sync{ handle: 0xffffffff }
	assert file.ioctl_modern_submit(unsafe { &request }) == -2
	invalid = asahi.Sync{ handle: input.handle, sync_type: 1, timeline_value: 0 }
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	service_file_work()
	manager.finish_compute(0)
	service_file_work()
	assert_drained(file)
	request.in_sync_count = 0
	request.out_sync_count = 1
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	service_file_work()
	manager.finish_compute(0)
	service_file_work()
	assert syncobj.is_signaled(fence(input))
	assert_drained(file)
	request.syncs = 0
	request.out_sync_count = 0
	request.cmdbuf_size = 0
	assert file.ioctl_modern_submit(unsafe { &request }) == -22
	request.cmdbuf_size = 32
	request.cmdbuf = ~u64(0) - 2
	assert file.ioctl_modern_submit(unsafe { &request }) == -14
	assert_drained(file)
	request.cmdbuf = u64(bytes.data)
	request.cmdbuf_size = u32(bytes.len)
	unsafe { (&asahi.CmdHeader(bytes.data)).cmd_type = 99 }
	assert file.ioctl_modern_submit(unsafe { &request }) == -22
	assert_drained(file)
	unsafe { (&asahi.CmdHeader(bytes.data)).cmd_type = asahi.cmd_compute }
	manager.state = .error
	assert file.ioctl_modern_submit(unsafe { &request }) == -19
	manager.state = .running
	assert_drained(file)
	assert cases == 700
	check_modern_device_status(out)
	check_modern_attachment_barriers(input, out)
	check_modern_timestamp_batch()
	println('AGX modern SUBMIT: real packet-to-scheduler compute/render, 16-byte combined syncs, captured USC base, immutable input, reverse completion and 700 copy/OOM/retry/drain cases pass')
}

fn check_modern_attachment_barriers(input &syncobj.SyncObj, out &syncobj.SyncObj) {
	records := [asahi.Sync{handle: input.handle}, asahi.Sync{handle: out.handle}]!
	original := fence(out)
	previous := syncobj.new_fence(106, 1)
	defer { syncobj.replace_fence(out, original) }
	mut packet := []u8{}
	packet.flags |= .noslices
	defer { unsafe { packet.free() } }
	compute := asahi.CmdCompute{}
	render := asahi.CmdRender{width_px: 32, height_px: 32, layers: 1, samples: 1,
		utile_width_px: 32, utile_height_px: 32}
	attachment := asahi.Attachment{pointer: 0x30000, size: 128}
	for prior in u32(0) .. u32(6) {
		for mask in u32(0) .. u32(4) {
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			syncobj.replace_fence(out, previous)
			packet.clear()
			engines := if prior >= 4 { u32(3) } else { prior }
			if engines & 1 != 0 {
				append_packet(mut packet, asahi.cmd_render, unsafe { &render }, u16(sizeof(render)),
					asahi.barrier_none, asahi.barrier_none)
			}
			if engines & 2 != 0 {
				append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
					asahi.barrier_none, asahi.barrier_none)
			}
			if engines != 0 {
				request := asahi.Submit{queue_id: 1, cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len)}
				assert file.ioctl_modern_submit(unsafe { &request }) == 0
				if prior != 5 { service_file_work() } // Include accepted work awaiting publication.
			}
			if prior == 4 {
				manager.finish_compute(0)
				manager.finish_render(0)
				service_file_work()
				assert_drained(file)
			}
			packet.clear()
			append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
				asahi.barrier_none, asahi.barrier_none)
			// Separate software records exercise accumulation in the decoder.
			append_packet(mut packet, asahi.set_vertex_attachments, unsafe { &attachment }, u16(sizeof(attachment)),
				if mask & 1 != 0 { 0 } else { asahi.barrier_none }, asahi.barrier_none)
			append_packet(mut packet, asahi.set_compute_attachments, unsafe { &attachment }, u16(sizeof(attachment)),
				asahi.barrier_none, if mask & 2 != 0 { 0 } else { asahi.barrier_none })
			request := asahi.Submit{queue_id: 1, cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len),
				syncs: unsafe { u64(&records[0]) }, in_sync_count: 1, out_sync_count: 1}
			count := manager.prepares
			sequence := file.g13_queues[0].resources.fence_seqno
			operations := manager.active_operations
			slot_attempts := uat_mgr.acquire_attempts
			code := file.ioctl_modern_submit(unsafe { &request })
			if prior != 4 && engines & mask != 0 {
				assert code == -22 && manager.prepares == count
				assert uat_mgr.acquire_attempts == slot_attempts
				assert manager.active_operations == operations
				assert voidptr(fence(out)) == voidptr(previous)
				assert file.g13_queues[0].resources.fence_seqno == sequence
			} else {
				assert code == 0 && manager.prepares == count + 1
				assert manager.g13_compute_jobs.last().initial_sources == [u32(0), 0]!
				assert file.g13_queues[0].resources.fence_seqno == sequence + 1
				assert voidptr(fence(out)) != voidptr(previous)
			}
			assert manager.capture_pins == 0
			manager.stop()
			service_file_work()
			assert_drained(file)
		}
	}
	println('G13 attachment barriers: 24 modern ioctl cases cover absent, prepared, published and retired prior engines')
}

fn check_modern_device_status(out &syncobj.SyncObj) {
	original := fence(out)
	previous := syncobj.new_fence(105, 1)
	syncobj.replace_fence(out, previous)
	defer { syncobj.replace_fence(out, original) }
	for lost in [false, true]! {
		for mode in 0 .. 9 {
			gpu.reset()
			mut file := new_file()
			mut manager := gpu.get_global_manager() or { panic('manager') }
			if lost { manager.state = .error }
			bad_header := asahi.Submit{flags: 1}
			assert file.ioctl_modern_submit(unsafe { &bad_header }) == -22
			assert manager.submit_globals_refreshes == 0
			record := asahi.Sync{handle: if mode == 7 { u32(0xffffffff) } else { out.handle },
				sync_type: 1, timeline_value: 8}
			header := asahi.CmdHeader{cmd_type: 99, vdm_barrier: asahi.barrier_none,
				cdm_barrier: asahi.barrier_none}
			request := asahi.Submit{
				queue_id: if mode == 8 { u32(99) } else { u32(1) }
				syncs: unsafe { u64(&record) }
				out_sync_count: 1
				cmdbuf: if mode in [0, 3]! { u64(0) } else { unsafe { u64(&header) } }
				cmdbuf_size: match mode { 0 { u32(0) } 1 { u32(1) } else { u32(sizeof(header)) } }
			}
			chains := memory.outstanding_chains()
			memory.fail_at(match mode { 5 { 1 } 6 { 2 } else { -1 } })
			usercopy.reject_at(if mode == 4 { 1 } else { -1 })
			code := file.ioctl_modern_submit(unsafe { &request })
			assert manager.submit_globals_refreshes == 1
			assert code == match mode {
				3, 4 { -14 }
				5 { -12 }
				6 { if lost { -19 } else { -12 } }
				7, 8 { -2 }
				else { if lost { -19 } else { -22 } }
			}
			assert usercopy.reads() == match mode { 8 { 0 } 0, 3, 5, 7 { 1 } else { 2 } }
			assert memory.attempts() == match mode {
				7, 8 { 0 }
				0, 3 { 1 }
				4, 5 { 2 }
				6 { if lost { 2 } else { 3 } }
				else { if lost { 2 } else { 4 } }
			}
			memory.fail_at(-1)
			usercopy.reject_at(-1)
			assert voidptr(fence(out)) == voidptr(previous) && !syncobj.is_signaled(previous)
			assert memory.outstanding_chains() == chains && manager.prepares == 0
			assert file.g13_queues[0].resources.fence_seqno == 0
			assert_drained(file)
		}
	}

	gpu.reset()
	mut file := new_file()
	mut packet := []u8{}
	defer { unsafe { packet.free() } }
	compute := asahi.CmdCompute{}
	append_packet(mut packet, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)),
		asahi.barrier_none, asahi.barrier_none)
	request := asahi.Submit{queue_id: 1, cmdbuf: u64(packet.data), cmdbuf_size: u32(packet.len)}
	usercopy.before_once(stop_after_modern_device_snapshot)
	assert file.ioctl_modern_submit(unsafe { &request }) == -19
	assert_drained(file)
	println('G13 modern device status: 19 ioctl cases preserve staging precedence and recheck loss before preparation')
}

fn stop_after_modern_device_snapshot() {
	manager := gpu.get_global_manager() or { panic('manager') }
	klock.after_release_once(unsafe { &manager.lock }, stop_before_modern_decode)
}

fn stop_before_modern_decode() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	manager.stop()
}

fn check_modern_timestamp_batch() {
	gpu.reset()
	mut file := new_file()
	mut object := gem.GemObject{}
	add_timestamp(mut file, unsafe { &object })
	mut manager := gpu.get_global_manager() or { panic('manager') }
	mut bytes := []u8{}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	for index in 0 .. 64 {
		ts := asahi.Timestamps{ start: asahi.Timestamp{ handle: 9, offset: u32(index * 32) }, end: asahi.Timestamp{ handle: 9, offset: u32(index * 32 + 8) } }
		if index % 2 == 0 {
			compute := asahi.CmdCompute{ ts: ts }
			append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(__offsetof(asahi.CmdCompute, scs_layout)), 0, 0)
		} else {
			render := asahi.CmdRender{ width_px: 32, height_px: 32, layers: 1, samples: 1, utile_width_px: 32, utile_height_px: 32, ts_vtx: ts, ts_frag: ts }
			// G13 Mesa sends the render prefix before the high resource words.
			append_packet(mut bytes, asahi.cmd_render, unsafe { &render }, u16(__offsetof(asahi.CmdRender, bg_eot_rsrc_spec_hi)), 0, 0)
		}
	}
	request := asahi.Submit{ queue_id: 1, cmdbuf: u64(bytes.data), cmdbuf_size: u32(bytes.len) }
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	assert manager.g13_compute_jobs.len == 32 && manager.g13_render_jobs.len == 32
	assert file.timestamp_objects[0].references == 192
	for index, job in manager.g13_compute_jobs {
		assert job.flush_stamps == (index == 31), 'only the final compute command flushes stamps'
		assert job.timestamps == [u64(0x123456780000) + u64(index * 64),
			u64(0x123456780008) + u64(index * 64)]!
	}
	for index, job in manager.g13_render_jobs {
		assert job.flush_stamps == (index == 31), 'only the final render command flushes stamps'
	}
	detach_timestamp(mut file)
	service_file_work()
	for index := 63; index >= 0; index-- {
		if index % 2 == 0 {
			manager.finish_compute_at(u32(index), 0)
		} else {
			manager.finish_render_at(u32(index), 0)
		}
		service_file_work()
	}
	assert object.references == 0 && manager.timestamp_unmaps == 1 && file.timestamp_objects.len == 0
	assert_drained(file)
	println('AGX modern 64-command ioctl: mixed packets resolve 192 timestamp captures, survive detach and retire in reverse without scratch or VM/queue owners left')
}
