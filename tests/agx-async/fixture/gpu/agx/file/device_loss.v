// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module file

import drm.gem
import drm.ioctl
import drm.syncobj
import gpu.agx.gpu
import klock
import memory
import usercopy

__global device_cases = 0
__global loss_state = gpu.State.error
__global loss_file &GpuFile = unsafe { nil }

fn lose_device() {
	mut manager := gpu.get_global_manager() or { panic('manager') }
	assert !manager.lock.is_held() && !loss_file.lock.is_held()
	manager.state = loss_state
}

fn expect_device_refusal(mut file GpuFile, request &ioctl.DrmAsahiSubmit, expected int,
	manager &gpu.GpuManager, output &syncobj.SyncObj, previous &syncobj.DmaFence,
	result &gem.GemObject) {
	before := unsafe { *request }
	code := file.ioctl_submit(request)
	assert code == expected, 'submission device state expected ${expected}, got ${code}'
	assert unsafe { *request } == before
	assert !file.lock.is_held() && !manager.lock.is_held()
	assert_drained(file)
	assert manager.prepares == 0 && manager.callbacks == 0 && manager.admissions == 0 && manager.published.len == 0
	assert voidptr(fence(output)) == voidptr(previous) && result.references == 1
	assert !syncobj.is_signaled(previous) && syncobj.get_error(previous) == 0
	for index := u64(0); index < result.size; index++ {
		assert unsafe { (&u8(result.virt_addr))[index] } == 0xa5
	}
	device_cases++
}

fn check_submission_device_loss() {
	gpu.reset()
	mut file := new_file()
	mut manager := gpu.get_global_manager() or { panic('manager') }
	input := output(); target := output(); previous := syncobj.new_fence(99, 1)
	dependency := syncobj.new_fence(98, 1)
	syncobj.signal(dependency); syncobj.replace_fence(input, dependency)
	mut bytes := [8192]u8{}
	mut result := gem.GemObject{ size: sizeof(bytes), virt_addr: unsafe { u64(&bytes) } }
	file.objects = Objects{ object: unsafe { &result } }
	compute := ioctl.DrmAsahiCmdCompute{ encoder_ptr: 0x12340000 }
	render := ioctl.DrmAsahiCmdRender{ fb_width: 32, fb_height: 32, layers: 1, utile_width: 32, utile_height: 32, samples: 1 }
	mut commands := [2]ioctl.DrmAsahiCommand{}
	in_sync := ioctl.DrmAsahiSync{ handle: input.handle }
	mut out_sync := ioctl.DrmAsahiSync{ handle: target.handle }
	for _ in 0 .. 200 {
		for state in [gpu.State.error, .stopped, .idle, .starting, .running]! {
			for generation in [gpu.Generation.g13, .g17]! {
				gpu.reset(); manager.hw_config = gpu.Config{ gpu_gen: generation }; manager.state = state
				expected := if state in [.error, .stopped] { -19 }
					else if generation != .g13 || state != .running { -95 } else { 0 }
				assert manager.g13_submission_status() == expected && !manager.lock.is_held(); device_cases++
				for pair in [false, true]! { for results in [false, true]! { for sync in [false, true]! {
					gpu.reset(); manager.hw_config = gpu.Config{ gpu_gen: generation }; manager.state = state
					manager.immediate_complete = true
					unsafe { C.memset(&bytes[0], 0xa5, sizeof(bytes)) }
					syncobj.replace_fence(target, previous)
					commands[0] = ioctl.DrmAsahiCommand{ cmd_type: ioctl.asahi_cmd_compute,
						cmd_buffer: unsafe { u64(&compute) }, cmd_buffer_size: sizeof(compute),
						result_size: if results { u64(sizeof(ioctl.DrmAsahiResultCompute)) } else { 0 },
						barriers: [ioctl.asahi_barrier_none, ioctl.asahi_barrier_none]! }
					commands[1] = ioctl.DrmAsahiCommand{ cmd_type: ioctl.asahi_cmd_render,
						cmd_buffer: unsafe { u64(&render) }, cmd_buffer_size: sizeof(render),
						result_offset: if results { u64(64) } else { 0 },
						result_size: if results { u64(sizeof(ioctl.DrmAsahiResultRender)) } else { 0 },
						barriers: [ioctl.asahi_barrier_none, u32(1)]! }
					request := ioctl.DrmAsahiSubmit{ queue_id: 1, commands: unsafe { u64(&commands[0]) },
						command_count: if pair { 2 } else { 1 }, result_handle: if results { 7 } else { 0 },
						in_syncs: unsafe { u64(&in_sync) }, in_sync_count: if sync { 1 } else { 0 },
						out_syncs: unsafe { u64(&out_sync) }, out_sync_count: 1 }
					memory.fail_at(-1); usercopy.reject(false); usercopy.reset_reads()
					if expected == 0 {
						assert file.ioctl_submit(&request) == 0
						for _ in 0 .. 4 { service_file_work() }
						assert_drained(file)
						assert syncobj.is_signaled(fence(target)) && result.references == 1
						assert !file.lock.is_held() && !manager.lock.is_held(); device_cases++
					} else {
						expect_device_refusal(mut file, &request, expected, manager, target, previous, &result)
						assert memory.attempts() == 1 && usercopy.reads() > 0
					}
					if state !in [.error, .stopped] { continue }
					for failure in 0 .. 6 {
						mut bad := request
						memory.fail_at(if failure == 2 { 0 } else { -1 }); usercopy.reject(failure == 3)
						match failure {
							0 { bad.flags = 1 }
							1 { bad.queue_id = 3 }
							4 { commands[0].flags = 1 }
							5 { out_sync.handle = ~u32(0) }
							else {}
						}
						staging_error := match failure { 1, 5 { -2 } 2 { -12 } 3 { -14 } else { -22 } }
						expect_device_refusal(mut file, &bad, staging_error, manager, target, previous, &result)
						assert memory.attempts() == if failure < 2 { 0 } else { 1 }
						commands[0].flags = 0; out_sync.handle = target.handle
					}
				} } }
			}
		}
		// Detect loss during unlocked copying or immediately before the
		// production state-lock acquisition, without publishing output work.
		for state in [gpu.State.error, .stopped]! { for before_lock in [false, true]! {
			gpu.reset(); syncobj.replace_fence(target, previous)
			unsafe { C.memset(&bytes[0], 0xa5, sizeof(bytes)) }
			memory.fail_at(-1); usercopy.reject(false)
			loss_state = state; loss_file = file
			if before_lock { klock.before_once(unsafe { &manager.lock }, lose_device) }
			else { usercopy.before_once(lose_device) }
			request := ioctl.DrmAsahiSubmit{ queue_id: 1, commands: unsafe { u64(&commands[0]) }, command_count: 1,
				out_syncs: unsafe { u64(&out_sync) }, out_sync_count: 1 }
			expect_device_refusal(mut file, &request, -19, manager, target, previous, &result)
			loss_file = unsafe { nil }
		} }
		gpu.reset(); syncobj.replace_fence(target, previous)
		registration := file.registration_manager
		file.registration_manager = unsafe { nil }
		memory.fail_at(-1); usercopy.reject(false)
		request := ioctl.DrmAsahiSubmit{ queue_id: 1, commands: unsafe { u64(&commands[0]) }, command_count: 1,
			out_syncs: unsafe { u64(&out_sync) }, out_sync_count: 1 }
		assert file.ioctl_submit(&request) == -19
		file.registration_manager = registration
		assert_drained(file); assert voidptr(fence(target)) == voidptr(previous); device_cases++
		assert !syncobj.is_signaled(previous) && !file.lock.is_held() && !manager.lock.is_held() && result.references == 1
	}
	file.objects = Objects{}; gpu.reset()
	println('AGX submission device loss: ${device_cases} checks; locked ENODEV for error/stopped before job/output publication, unsupported/startup controls, compute/render and input/result combinations, unchanged outputs/refs, released staging storage, earlier header/queue/OOM/copy/sync errors, deterministic copy/lock transitions and running completion passed')
}
