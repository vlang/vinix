module file

import drm.asahi
import drm.gem
import drm.syncobj
import gpu.agx.gpu
import gpu.agx.submission
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
	assert file.ioctl_modern_submit(unsafe { &request }) == -95
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
	check_modern_timestamp_batch()
	println('AGX modern SUBMIT: real packet-to-scheduler compute/render, 16-byte combined syncs, captured USC base, immutable input, reverse completion and 700 copy/OOM/retry/drain cases pass')
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
			append_packet(mut bytes, asahi.cmd_compute, unsafe { &compute }, u16(sizeof(compute)), asahi.barrier_none, asahi.barrier_none)
		} else {
			render := asahi.CmdRender{ width_px: 32, height_px: 32, layers: 1, samples: 1, utile_width_px: 32, utile_height_px: 32, ts_vtx: ts, ts_frag: ts }
			append_packet(mut bytes, asahi.cmd_render, unsafe { &render }, u16(sizeof(render)), asahi.barrier_none, asahi.barrier_none)
		}
	}
	request := asahi.Submit{ queue_id: 1, cmdbuf: u64(bytes.data), cmdbuf_size: u32(bytes.len) }
	assert file.ioctl_modern_submit(unsafe { &request }) == 0
	assert manager.g13_compute_jobs.len == 32 && manager.g13_render_jobs.len == 32
	assert file.timestamp_objects[0].references == 192
	for index, job in manager.g13_compute_jobs {
		assert job.timestamps == [u64(0x123456780000) + u64(index * 64),
			u64(0x123456780008) + u64(index * 64)]!
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
