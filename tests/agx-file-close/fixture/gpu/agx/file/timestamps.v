// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.gem
import drm.ioctl
import gpu.agx.gpu

struct TimestampRange {
	offset u64
	size u64
	bad_header bool
	bad_backing bool
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

fn check_timestamp_bindings() {
	page := u64(0x4000)
	mut cases := 0
	for cycle in 0 .. 200 {
		gpu.available(true); gpu.set_running(true); gpu.fail_timestamp_map(false)
		mut file := GpuFile{}
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
							gpu.available(available)
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
							assert gpu.lookups() == lookups + if !bad_header && !missing && !bad_backing { 1 } else { 0 }
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
							// A found owner remains installed when its manager is absent.
							gpu.available(false)
							mut remove := timestamp_unbind(id)
							saved := remove
							assert file.ioctl_gem_bind_object(unsafe { &remove }) == -19 && remove == saved
							assert !file.lock.is_held() && shared.references == 2 && file.timestamp_objects.len == 1
							assert gpu.unmaps() == unmaps; cases++
							for missing_id in [u32(0), if id == ~u32(0) { id - 1 } else { ~u32(0) }]! {
								mut absent := timestamp_unbind(missing_id)
								at_lookup := gpu.lookups(); saved_absent := absent
								assert file.ioctl_gem_bind_object(unsafe { &absent }) == -2 && absent == saved_absent
								assert gpu.lookups() == at_lookup && !file.lock.is_held()
								assert shared.references == 2 && file.timestamp_objects.len == 1; cases++
							}
							at_lookup := gpu.lookups()
							assert foreign.ioctl_gem_bind_object(unsafe { &remove }) == -2 && remove == saved
							assert gpu.lookups() == at_lookup && !foreign.lock.is_held() && shared.references == 2; cases++
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
								assert gpu.lookups() == at_bad_lookup && !file.lock.is_held() && shared.references == 2; cases++
							}
							gpu.available(true)
							assert file.ioctl_gem_bind_object(unsafe { &remove }) == 0 && remove == saved
							assert shared.references == 1 && file.timestamp_objects.len == 0 && gpu.unmaps() == unmaps + 1
							assert !file.lock.is_held(); cases++
							assert file.ioctl_gem_bind_object(unsafe { &remove }) == -2 && remove == saved
							assert shared.references == 1 && gpu.unmaps() == unmaps + 1 && !file.lock.is_held(); cases++
						}
					}
				}
			}
		}
		gpu.available(true)
		for invalid in 0 .. 4 {
			mut bad := timestamp_bind(shared.handle, ~u32(0), 0, page, ioctl.asahi_bind_object_usage_timestamps)
			match invalid { 0 { bad.extensions = 1 } 1 { bad.pad = 1 } 2 { bad.vm_id = 1 } else { bad.op = ~u32(0) } }
			before := bad; maps := gpu.maps(); lookups := gpu.lookups()
			assert file.ioctl_gem_bind_object(unsafe { &bad }) == -22 && bad == before
			assert gpu.maps() == maps && gpu.lookups() == lookups && shared.references == 1 && !file.lock.is_held(); cases++
		}
		gpu.fail_timestamp_map(true)
		mut oom := timestamp_bind(shared.handle, ~u32(0), 0, page, ioctl.asahi_bind_object_usage_timestamps)
		before_oom := oom; maps := gpu.maps(); unmaps := gpu.unmaps()
		assert file.ioctl_gem_bind_object(unsafe { &oom }) == -12 && oom == before_oom
		assert shared.references == 1 && file.timestamp_objects.len == 0 && gpu.maps() == maps + 1 && gpu.unmaps() == unmaps
		assert !file.lock.is_held(); cases++
		gpu.fail_timestamp_map(false)
		// The output field can name a live mapping without replacing it.
		file.next_timestamp_id = ~u32(0)
		mut first := timestamp_bind(shared.handle, u32(7), 0, page, ioctl.asahi_bind_object_usage_timestamps)
		assert file.ioctl_gem_bind_object(unsafe { &first }) == 0 && first.object_handle == ~u32(0); cases++
		mut second := timestamp_bind(shared.handle, first.object_handle, page, page, ioctl.asahi_bind_object_usage_timestamps)
		assert file.ioctl_gem_bind_object(unsafe { &second }) == 0 && second.object_handle == 1; cases++
		assert file.timestamp_objects.len == 2 && shared.references == 3
		mut remove := timestamp_unbind(first.object_handle)
		assert file.ioctl_gem_bind_object(unsafe { &remove }) == 0 && file.timestamp_objects.len == 1 && shared.references == 2; cases++
		assert file.timestamp_objects[0].id == second.object_handle
		unmaps_before_close := gpu.unmaps()
		assert file.close() && foreign.close() && gem.live() == 0
		assert gpu.unmaps() == unmaps_before_close + 1
	}
	println('AGX timestamp object validation: ${cases} ioctl checks; output-only bind handles, checked overflow before BO lookup, empty-range lookup precedence, private/bounds refusal, map OOM, missing/zero/foreign unbind names, retained unavailable-manager owners, header precedence, ID wrap, sibling preservation and final release passed')
}
