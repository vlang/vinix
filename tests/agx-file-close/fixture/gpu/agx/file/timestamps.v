// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm
import drm.gem
import drm.ioctl
import drm.asahi
import gpu.agx.gpu
import gpu.agx.mmu
import memory
import proc
import usercopy

struct TimestampRange {
	offset u64
	size u64
	bad_header bool
	bad_backing bool
}

__global unplugged_timestamp_device &drm.DrmDevice = unsafe { nil }

fn replace_during_timestamp_ioctl() {
	assert unplugged_timestamp_device.registered
	unplugged_timestamp_device.registered = false
	gpu.set_running(false)
	gpu.replace_manager(true)
}

fn invoke_timestamp_bind(dev &drm.DrmDevice, key u64, handle u32, modern bool, expected int) {
	legacy := timestamp_bind(handle, 0x12345678, 0, 0x4000, ioctl.asahi_bind_object_usage_timestamps)
	if modern {
		mut request := asahi.GemBindObject{op: legacy.op, flags: legacy.flags, handle: legacy.handle,
			range: legacy.range, object_handle: legacy.object_handle}
		before := request
		address := unsafe { voidptr(&request) }
		usercopy.configure(u64(address), sizeof(request), -1)
		assert drm.invoke(dev, key, asahi.gem_bind_object, sizeof(request), 3, address) == expected,
			'modern timestamp BIND must use its DRM registration'
		assert request.object_handle == if expected == 0 { u32(1) } else { before.object_handle }
		if expected != 0 { assert request == before }
	} else {
		mut request := legacy
		address := unsafe { voidptr(&request) }
		usercopy.configure(u64(address), sizeof(request), -1)
		assert drm.invoke(dev, key, ioctl.drm_asahi_gem_bind_object, sizeof(request), 3, address) == expected,
			'legacy timestamp BIND must use its DRM registration'
		assert request.object_handle == if expected == 0 { u32(1) } else { legacy.object_handle }
		if expected != 0 { assert request == legacy }
	}
}

fn check_timestamp_registration() {
	proc.enable_owner(true)
	for _ in 0 .. 64 {
		for modern in [false, true]! {
			driver := drm.DrmDriver{ioctls: drm_ioctls(), ioctl_abi: ioctl_abi_handle}
			original := gpu.registration_manager()
			mut device := drm.DrmDevice{driver: unsafe { &driver }, driver_data: voidptr(original)}
			key := u64(0x56000)
			abi := if modern { modern_ioctl_abi } else { legacy_ioctl_abi }
			mut file := get_or_create_file(voidptr(key), &device) or { panic('original file') }
			assert file.select_ioctl_abi(abi) && file.timestamp_objects.len == 0
			bo := gem.create(9500)
			file.objects.add_created(bo)
			maps := gpu.maps()
			unmaps := gpu.unmaps()
			allocations_before := memory.calls()
			unplugged_timestamp_device = unsafe { &device }
			usercopy.before_next_read(replace_during_timestamp_ioctl)
			invoke_timestamp_bind(&device, key, bo.handle, modern, -19)
			assert !device.registered && gpu.maps() == maps && gpu.unmaps() == unmaps
			assert file.timestamp_objects.len == 0 && bo.references == 1 && memory.calls() == allocations_before
			assert voidptr(file.registration_manager) == voidptr(original) && !file.lock.is_held()

			mut replacement := unsafe { gpu.registration_manager() }
			replacement.uat = uat_mgr
			new_device := drm.DrmDevice{driver: unsafe { &driver }, driver_data: voidptr(replacement)}
			new_key := key + 1
			mut new_file := get_or_create_file(voidptr(new_key), &new_device) or { panic('replacement file') }
			assert new_file.select_ioctl_abi(abi)
			new_bo := gem.create(9501)
			new_file.objects.add_created(new_bo)
			invoke_timestamp_bind(&new_device, new_key, new_bo.handle, modern, 0)
			assert gpu.maps() == maps + 1 && new_file.timestamp_objects.len == 1 && new_bo.references == 2
			release_handle(&device, voidptr(key))
			assert gpu.unmaps() == unmaps && new_bo.references == 2
			release_handle(&new_device, voidptr(new_key))
			assert gpu.unmaps() == unmaps + 1 && gem.live() == 0
			memory.assert_released()
			unplugged_timestamp_device = unsafe { nil }
			gpu.replace_manager(false)
			gpu.set_running(true)
		}
	}
	proc.enable_owner(false)
	println('G13 timestamp registration: 128 first BIND races after ioctl admission reject the stale device before mapping and admit the replacement open')
}

fn timestamp_bind(handle u32, output u32, offset u64, size u64, flags u32) ioctl.DrmAsahiGemBindObject {
	return ioctl.DrmAsahiGemBindObject{
		op: ioctl.asahi_bind_object_op_bind, handle: handle, object_handle: output,
		offset: offset, range: size, flags: flags
	}
}

fn timestamp_unbind(id u32) ioctl.DrmAsahiGemBindObject {
	return ioctl.DrmAsahiGemBindObject{ op: ioctl.asahi_bind_object_op_unbind, object_handle: id }
}

fn expect_timestamp_publication_error(mut file GpuFile, handle u32, code int) {
	legacy := timestamp_bind(handle, 0x12345678, 0, 0x4000, ioctl.asahi_bind_object_usage_timestamps)
	modern := asahi.GemBindObject{op: legacy.op, flags: legacy.flags, handle: handle,
		range: legacy.range, object_handle: legacy.object_handle}
	saved_legacy := legacy
	saved_modern := modern
	assert file.ioctl_gem_bind_object(unsafe { &legacy }) == code && legacy == saved_legacy,
		'legacy timestamp BIND must report the publication failure without an output handle'
	assert file.ioctl_modern_gem_bind_object(unsafe { &modern }) == code && modern == saved_modern,
		'modern timestamp BIND must report the publication failure without an output handle'
	assert !file.lock.is_held()
}

fn check_timestamp_publication_storage() {
	memory.assert_released()
	for cycle in 0 .. 100 {
		mut file := GpuFile{registration_manager: gpu.registration_manager()}
		bo := gem.create(u32(9200 + cycle))
		file.objects.add_created(bo)
		memory.fail_allocations(true)
		before_empty := memory.calls()
		maps_empty := gpu.maps()
		unmaps_empty := gpu.unmaps()
		gpu.fail_timestamp_map(-28)
		expect_timestamp_publication_error(mut file, bo.handle, -28)
		assert memory.calls() == before_empty && gpu.unmaps() == unmaps_empty
		gpu.fail_timestamp_map(0)
		expect_timestamp_publication_error(mut file, bo.handle, -12)
		assert memory.calls() == before_empty + 2 && memory.outstanding() == 0
		assert gpu.maps() == maps_empty + 4 && gpu.unmaps() == unmaps_empty + 2
		assert file.timestamp_objects.len == 0 && bo.references == 1

		memory.fail_allocations(false)
		for index in 0 .. 7 {
			assert bind_capture_buffer(mut file, bo.handle) == u32(index + 1)
		}
		code, old_capture := file.capture_g13_timestamp(asahi.Timestamp{handle: 1}, gpu.registration_manager())
		assert code == 0 && unbind_capture_buffer(mut file, 1) == 0
		memory.fail_allocations(true)
		with_spare := memory.calls()
		assert bind_capture_buffer(mut file, bo.handle) == 1
		assert memory.calls() == with_spare && file.timestamp_objects.len == 8 && file.timestamp_objects.cap == 8
		data := file.timestamp_objects.data
		mut saved := [8]TimestampObject{}
		for index in 0 .. 8 { saved[index] = file.timestamp_objects[index] }
		maps_full := gpu.maps()
		unmaps_full := gpu.unmaps()
		expect_timestamp_publication_error(mut file, bo.handle, -12)
		assert memory.calls() == with_spare + 2 && memory.outstanding() == 1
		assert file.timestamp_objects.data == data && file.timestamp_objects.len == 8 && file.timestamp_objects.cap == 8
		assert gpu.maps() == maps_full + 2 && gpu.unmaps() == unmaps_full + 2 && bo.references == 9
		for index in 0 .. 8 { assert saved[index] == file.timestamp_objects[index] }

		memory.fail_allocations(false)
		assert bind_capture_buffer(mut file, bo.handle) == 8
		assert file.timestamp_objects.data != data && memory.outstanding() == 1
		assert file.timestamp_objects.len == 9 && file.timestamp_objects.cap == 16
		file.release_g13_timestamp(old_capture)
		assert file.timestamp_objects.len == 8 && file.timestamp_objects[0].va == saved[1].va
		assert file.close() && gem.live() == 0
		memory.assert_released()
	}
	println('G13 timestamp publication: 400 allocation refusals, 200 mapping-precedence checks, 100 spare-slot publications and growth retries preserve captures and release all storage')
}

fn check_timestamp_publication_stop() {
	for _ in 0 .. 64 {
		for modern in [false, true]! {
			gpu.available(true)
			gpu.set_running(true)
			mut file := GpuFile{registration_manager: gpu.registration_manager()}
			bo := gem.create(9300)
			file.objects.add_created(bo)
			assert bind_capture_buffer(mut file, bo.handle) == 1
			original := file.timestamp_objects[0]
			before_alloc := memory.calls()
			maps := gpu.maps()
			unmaps := gpu.unmaps()
			stops := gpu.stop_count()
			gpu.stop_after_next_timestamp_map()
			legacy := timestamp_bind(bo.handle, 0x12345678, 0, 0x4000, ioctl.asahi_bind_object_usage_timestamps)
			if modern {
				request := asahi.GemBindObject{op: legacy.op, flags: legacy.flags, handle: legacy.handle,
					range: legacy.range, object_handle: legacy.object_handle}
				before := request
				assert file.ioctl_modern_gem_bind_object(unsafe { &request }) == -19 && request == before
			} else {
				before := legacy
				assert file.ioctl_gem_bind_object(unsafe { &legacy }) == -19 && legacy == before
			}
			assert gpu.stop_count() == stops + 1 && gpu.maps() == maps + 1 && gpu.unmaps() == unmaps + 1
			assert !file.lock.is_held() && !gpu.timestamp_lock_held()
			assert memory.calls() == before_alloc && bo.references == 2 && file.timestamp_objects.len == 1
			assert file.timestamp_objects[0] == original
			assert file.close() && gem.live() == 0 && gpu.unmaps() == unmaps + 2
			memory.assert_released()
		}
	}
	gpu.set_running(true)
	println('G13 timestamp publication: 128 shutdown races after a successful map return ENODEV without publishing a handle and retire only the new mapping')
}

fn check_timestamp_owner_teardown() {
	for _ in 0 .. 64 {
		for modern in [false, true]! {
			gpu.available(true)
			mut file := GpuFile{registration_manager: gpu.registration_manager()}
			mut replacement := GpuFile{}
			old_bo := gem.create(9400)
			new_bo := gem.create(9401)
			file.objects.add_created(old_bo)
			replacement.objects.add_created(new_bo)
			id := bind_capture_buffer(mut file, old_bo.handle)
			closes := bind_capture_buffer(mut file, old_bo.handle)
			captured := bind_capture_buffer(mut file, old_bo.handle)
			original := gpu.registration_manager()
			old_unmaps := original.timestamp_unmaps
			code, capture := file.capture_g13_timestamp(asahi.Timestamp{handle: captured}, original)
			assert code == 0 && capture.va != 0

			gpu.available(false)
			if modern {
				request := asahi.GemBindObject{op: ioctl.asahi_bind_object_op_unbind, object_handle: id}
				before := request
				assert file.ioctl_modern_gem_bind_object(unsafe { &request }) == 0 && request == before
			} else {
				assert unbind_capture_buffer(mut file, id) == 0
			}
			assert file.timestamp_objects.len == 2 && file.timestamp_objects[0].id == closes
			assert old_bo.references == 3 && original.timestamp_unmaps == old_unmaps + 1
			gpu.available(true)
			gpu.replace_manager(true)
			replacement.registration_manager = gpu.registration_manager()
			assert bind_capture_buffer(mut replacement, new_bo.handle) == id
			assert replacement.timestamp_objects[0].va == capture.va
			active := gpu.registration_manager()
			refused, empty := file.capture_g13_timestamp(asahi.Timestamp{handle: captured}, active)
			assert refused == -19 && empty == G13TimestampCapture{} && file.timestamp_objects[1].references == 1
			gpu.set_running(false)
			expect_timestamp_publication_error(mut file, old_bo.handle, -19)
			assert file.timestamp_objects.len == 2 && old_bo.references == 3
			new_unmaps := active.timestamp_unmaps
			assert unbind_capture_buffer(mut file, captured) == 0 && !file.close()
			file.release_g13_timestamp(capture)
			assert old_bo.references == 2 && original.timestamp_unmaps == old_unmaps + 2
			assert active.timestamp_unmaps == new_unmaps && replacement.timestamp_objects[0].va == capture.va

			mut vm := mmu.UatContext{inflight: 1}
			file.vms = [&vm]
			gpu.available(false)
			assert !file.close() && file.timestamp_objects.len == 0 && old_bo.references == 1
			assert original.timestamp_unmaps == old_unmaps + 3 && active.timestamp_unmaps == new_unmaps
			vm.inflight = 0
			assert file.close() && replacement.close() && gem.live() == 0
			assert active.timestamp_unmaps == new_unmaps + 1
			memory.assert_released()
			gpu.replace_manager(false)
			gpu.set_running(true)
			gpu.available(true)
		}
	}
	println('G13 timestamp teardown: 128 lifecycles retire through the original owner across global removal and replacement VA reuse')
}

fn check_timestamp_bindings() {
	page := u64(0x4000)
	mut cases := 0
	for cycle in 0 .. 200 {
		gpu.available(true); gpu.set_running(true); gpu.fail_timestamp_map(0)
		mut file := GpuFile{registration_manager: gpu.registration_manager()}
		file.timestamp_objects.flags |= .noslices
		mut foreign := GpuFile{}
		shared := gem.create(u32(1000 + cycle * 4))
		mut private := gem.create(shared.handle + 1)
		private.vm_private_identity = 123
		file.objects.add_created(shared); file.objects.add_created(private)
		for span in [TimestampRange{ size: page }, TimestampRange{ offset: page, size: page },
			TimestampRange{ offset: 3 * page, size: page }, TimestampRange{ bad_backing: true },
			TimestampRange{ offset: 4 * page, bad_backing: true },
			TimestampRange{ offset: 4 * page, size: page, bad_backing: true },
			TimestampRange{ offset: ~u64(0) - page + 1, size: page, bad_header: true },
			TimestampRange{ offset: ~u64(0) - page + 1, size: 2 * page, bad_header: true },
			TimestampRange{ offset: 1, size: page, bad_header: true },
			TimestampRange{ size: 1, bad_header: true },
			TimestampRange{ offset: page, size: ~u64(0) - page + 1, bad_header: true }]! {
			for handle in [shared.handle, private.handle, u32(0), u32(7777)]! {
				for output in [u32(0), u32(1), ~u32(0)]! {
					for flags in [ioctl.asahi_bind_object_usage_timestamps, u32(0), u32(3)]! {
						for available in [false, true]! {
							gpu.set_running(available)
							mut request := timestamp_bind(handle, output, span.offset, span.size, flags)
							before := request; maps := gpu.maps(); unmaps := gpu.unmaps(); lookups := gpu.lookups()
							bad_header := span.bad_header || flags != ioctl.asahi_bind_object_usage_timestamps
							missing := handle != shared.handle && handle != private.handle
							bad_backing := span.bad_backing || handle == private.handle
							expected := if bad_header { -22 } else if missing { -2 }
								else if bad_backing { -22 } else if !available { -19 } else { 0 }
							result := file.ioctl_gem_bind_object(unsafe { &request })
							assert result == expected, 'timestamp BIND expected ${expected}, got ${result}'
							assert !file.lock.is_held()
							assert private.references == 1
							assert gpu.lookups() == lookups
							assert gpu.maps() == maps + if expected == 0 { 1 } else { 0 }
							assert gpu.unmaps() == unmaps
							cases++
							if expected != 0 {
								assert request == before && file.timestamp_objects.len == 0 && shared.references == 1
								continue
							}
							id := request.object_handle
							mut wanted := before; wanted.object_handle = id
							assert id != 0 && request == wanted && file.timestamp_objects.len == 1 && shared.references == 2
							assert file.timestamp_objects[0].size == span.size && voidptr(file.timestamp_objects[0].obj) == voidptr(shared)
							// The original owner remains usable without a global manager.
							gpu.available(false)
							mut remove := timestamp_unbind(id)
							saved := remove
							assert file.ioctl_gem_bind_object(unsafe { &remove }) == 0 && remove == saved
							assert !file.lock.is_held() && shared.references == 1 && file.timestamp_objects.len == 0
							assert gpu.unmaps() == unmaps + 1; cases++
							for missing_id in [u32(0), id, ~u32(0)]! {
								mut absent := timestamp_unbind(missing_id)
								at_lookup := gpu.lookups(); saved_absent := absent
								assert file.ioctl_gem_bind_object(unsafe { &absent }) == -2 && absent == saved_absent
								assert gpu.lookups() == at_lookup && !file.lock.is_held()
								assert shared.references == 1 && file.timestamp_objects.len == 0; cases++
							}
							at_lookup := gpu.lookups()
							assert foreign.ioctl_gem_bind_object(unsafe { &remove }) == -2 && remove == saved
							assert gpu.lookups() == at_lookup && !foreign.lock.is_held() && shared.references == 1; cases++
							for invalid in 0 .. 7 {
								mut bad := remove
								match invalid {
									0 { bad.extensions = 1 }
									1 { bad.pad = 1 }
									2 { bad.vm_id = 1 }
									3 { bad.flags = 1 }
									4 { bad.handle = shared.handle }
									5 { bad.offset = page }
									else { bad.range = page }
								}
								bad_before := bad; at_bad_lookup := gpu.lookups()
								assert file.ioctl_gem_bind_object(unsafe { &bad }) == -22 && bad == bad_before
								assert gpu.lookups() == at_bad_lookup && !file.lock.is_held() && shared.references == 1; cases++
							}
							gpu.available(true)
							assert file.ioctl_gem_bind_object(unsafe { &remove }) == -2 && remove == saved
							assert shared.references == 1 && gpu.unmaps() == unmaps + 1 && !file.lock.is_held(); cases++
						}
					}
				}
			}
		}
		gpu.available(true)
		gpu.set_running(true)
		for invalid in 0 .. 4 {
			mut bad := timestamp_bind(shared.handle, ~u32(0), 0, page, ioctl.asahi_bind_object_usage_timestamps)
			match invalid { 0 { bad.extensions = 1 } 1 { bad.pad = 1 } 2 { bad.vm_id = 1 } else { bad.op = ~u32(0) } }
			before := bad; maps := gpu.maps(); lookups := gpu.lookups()
			assert file.ioctl_gem_bind_object(unsafe { &bad }) == -22 && bad == before
			assert gpu.maps() == maps && gpu.lookups() == lookups && shared.references == 1 && !file.lock.is_held(); cases++
		}
		for map_error in [-12, -16, -19, -28]! {
			gpu.fail_timestamp_map(map_error)
			request := timestamp_bind(shared.handle, ~u32(0), 0, page, ioctl.asahi_bind_object_usage_timestamps)
			saved := request
			maps := gpu.maps(); unmaps := gpu.unmaps()
			assert file.ioctl_gem_bind_object(unsafe { &request }) == map_error && request == saved
			modern := asahi.GemBindObject{
				op: request.op, flags: request.flags, handle: request.handle,
				range: request.range, object_handle: request.object_handle
			}
			saved_modern := modern
			assert file.ioctl_modern_gem_bind_object(unsafe { &modern }) == map_error && modern == saved_modern
			assert shared.references == 1 && file.timestamp_objects.len == 0 && gpu.maps() == maps + 2 && gpu.unmaps() == unmaps
			assert !file.lock.is_held(); cases += 2
		}
		gpu.fail_timestamp_map(0)
		// The output field can name a live mapping without replacing it.
		mut first := timestamp_bind(shared.handle, u32(7), 0, page, ioctl.asahi_bind_object_usage_timestamps)
		assert file.ioctl_gem_bind_object(unsafe { &first }) == 0 && first.object_handle == 1; cases++
		mut second := timestamp_bind(shared.handle, first.object_handle, page, page, ioctl.asahi_bind_object_usage_timestamps)
		assert file.ioctl_gem_bind_object(unsafe { &second }) == 0 && second.object_handle == 2; cases++
		assert file.timestamp_objects.len == 2 && shared.references == 3
		mut remove := timestamp_unbind(first.object_handle)
		assert file.ioctl_gem_bind_object(unsafe { &remove }) == 0 && file.timestamp_objects.len == 1 && shared.references == 2; cases++
		assert file.timestamp_objects[0].id == second.object_handle
		mut reused := asahi.GemBindObject{op: first.op, flags: first.flags, handle: first.handle,
			range: first.range, object_handle: second.object_handle}
		assert file.ioctl_modern_gem_bind_object(unsafe { &reused }) == 0
		assert reused.object_handle == 1, 'BIND must reuse the lowest free name'
		assert file.timestamp_objects[0].id == reused.object_handle && file.timestamp_objects[1].id == second.object_handle
		assert file.timestamp_objects.len == 2 && shared.references == 3; cases++
		unmaps_before_close := gpu.unmaps()
		assert file.close() && foreign.close() && gem.live() == 0
		assert gpu.unmaps() == unmaps_before_close + 2
	}
	println('AGX timestamp object validation: ${cases} ioctl checks; output-only bind handles, checked overflow before BO lookup, empty-range lookup precedence, private/bounds refusal, ENOMEM, EBUSY, ENODEV and ENOSPC under both ABIs, missing/zero/foreign unbind names, original owner cleanup, header precedence, lowest-free name reuse, sibling preservation and final release passed')
}
