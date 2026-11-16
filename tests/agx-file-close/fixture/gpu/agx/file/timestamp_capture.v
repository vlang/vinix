// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.gem
import drm.ioctl
import gpu.agx.gpu
import klock

fn bind_capture_buffer(mut file GpuFile, handle u32) u32 {
	mut bind := ioctl.DrmAsahiGemBindObject{op: ioctl.asahi_bind_object_op_bind,
		flags: ioctl.asahi_bind_object_usage_timestamps, handle: handle, range: 0x4000}
	assert file.ioctl_gem_bind_object(unsafe { &bind }) == 0
	return bind.object_handle
}

fn unbind_capture_buffer(mut file GpuFile, id u32) int {
	mut unbind := ioctl.DrmAsahiGemBindObject{op: ioctl.asahi_bind_object_op_unbind, object_handle: id}
	return file.ioctl_gem_bind_object(unsafe { &unbind })
}

__global timestamp_race_file &GpuFile = unsafe { nil }
__global timestamp_race_id u32
__global timestamp_race_step int

fn remove_between_timestamp_lookups() {
	if timestamp_race_step == 0 {
		timestamp_race_step++
		klock.before_once(unsafe { &timestamp_race_file.lock }, remove_between_timestamp_lookups)
		return
	}
	assert timestamp_race_step == 1
	timestamp_race_step++
	assert unbind_capture_buffer(mut timestamp_race_file, timestamp_race_id) == 0
}

fn check_timestamp_captures() {
	mut validation_cases := 0
	mut ownership_cases := 0
	for cycle in 0 .. 64 {
		gpu.available(true); gpu.set_running(true); gpu.fail_timestamp_map(false)
		mut file := GpuFile{}
		mut foreign := GpuFile{}
		file.timestamp_objects.flags |= .noslices
		foreign.timestamp_objects.flags |= .noslices
		object := gem.create(u32(8000 + cycle))
		file.objects.add_created(object)
		id := bind_capture_buffer(mut file, object.handle)
		base := file.timestamp_objects[0].va
		for handle in [u32(0), id, id + 20] {
			for offset in [u32(0), 1, 7, 8, 0x3ff8, 0x3ff9, 0x4000, 0x4001, 0xfffffff7, 0xfffffff8, ~u32(0)] {
				request := asahi.Timestamp{handle: handle, offset: offset}
				code, capture := file.capture_g13_timestamp(request)
				// Independent cases specify Asahi's precedence and range boundary.
				expected := if handle == 0 { 0 } else if handle != id { -2 }
					else if offset >= 0xfffffff8 { -22 } else if offset > 0x3ff8 { -34 } else { 0 }
				assert code == expected, 'timestamp lookup/overflow/range precedence'
				if code == 0 && handle != 0 {
					assert capture.id == id && capture.address == base + u64(offset), 'timestamp byte address'
					assert file.timestamp_objects[0].references == 1
					file.release_g13_timestamp(capture)
				} else { assert capture == G13TimestampCapture{} }
				assert file.timestamp_objects[0].references == 0 && object.references == 2
				validation_cases++
			}
		}
		foreign_code, _ := foreign.capture_g13_timestamp(asahi.Timestamp{handle: id})
		assert foreign_code == -2, 'timestamp names are file-local'
		validation_cases++
		// Duplicate destinations retain independent references and allow bytes
		// without eight-byte alignment. Their GEM mapping owner remains singular.
		input := [asahi.Timestamps{start: asahi.Timestamp{handle: id, offset: 1}, end: asahi.Timestamp{handle: id, offset: 9}},
			asahi.Timestamps{start: asahi.Timestamp{handle: id, offset: 17}, end: asahi.Timestamp{handle: id, offset: 25}},
			asahi.Timestamps{start: asahi.Timestamp{handle: id, offset: 33}, end: asahi.Timestamp{handle: id, offset: 41}}]!
		mut retained := G13TimestampReferences{}
		assert file.capture_g13_timestamps(input, mut retained) == 0
		assert file.timestamp_objects[0].references == 6 && object.references == 2, 'six timestamp captures'
		assert retained.addresses(0) == [base + 1, base + 9]!
		assert retained.addresses(1) == [base + 17, base + 25]!
		assert retained.addresses(2) == [base + 33, base + 41]!
		assert retained.addresses(3) == [2]u64{}
		assert file.capture_g13_timestamps(input, mut retained) == -22 && file.timestamp_objects[0].references == 6, 'cannot overwrite owned references'
		before := gpu.unmaps()
		assert unbind_capture_buffer(mut file, id) == 0
		assert file.timestamp_objects.len == 1 && file.timestamp_objects[0].detached && object.references == 2 && gpu.unmaps() == before, 'UNBIND must retain captured mapping'
		assert unbind_capture_buffer(mut file, id) == -2, 'detached timestamp is absent'
		file_map[u64(0x52000 + cycle)] = unsafe { &file }
		reap_open_detached_g13_queues()
		file_map.delete(u64(0x52000 + cycle))
		assert file.timestamp_objects.len == 1 && file.timestamp_objects[0].references == 6 && gpu.unmaps() == before, 'worker cannot reap a captured timestamp'
		missing_code, _ := file.capture_g13_timestamp(asahi.Timestamp{handle: id})
		assert missing_code == -2 && retained.addresses(2)[1] == base + 41, 'captured timestamp survives namespace removal'
		assert !file.close() && object.references == 2 && !file.lock.is_held(), 'capture pins file before VM pin'
		file.next_timestamp_id = id
		file.lock.acquire()
		reserved := file.allocate_timestamp_id_locked() or { panic('timestamp ID') }
		file.lock.release()
		assert reserved != id, 'captured ID remains reserved'
		// Force namespace growth/movement while captures store scalar identities.
		for _ in 0 .. 20 { _ = bind_capture_buffer(mut file, object.handle) }
		assert retained.addresses(0)[0] == base + 1
		gpu.available(false)
		file.release_g13_timestamps(mut retained)
		assert retained == G13TimestampReferences{} && file.timestamp_objects[0].references == 0
		assert file.timestamp_objects.len == 21 && object.references == 22 && gpu.unmaps() == before, 'missing manager retains detached owner'
		assert !file.close() && object.references == 22, 'close cannot drop mapped backing without manager'
		gpu.available(true)
		file_map[u64(0x51000 + cycle)] = unsafe { &file }
		reap_open_detached_g13_queues()
		file_map.delete(u64(0x51000 + cycle))
		assert file.timestamp_objects.len == 20 && object.references == 21 && gpu.unmaps() == before + 1, 'worker retries detached timestamp cleanup'
		assert file.close() && foreign.close() && gem.live() == 0
		ownership_cases++
	}
	// Rollback each possible prefix, including duplicate references to one map.
	for failed in 0 .. 6 {
		gpu.available(true)
		mut file := GpuFile{}
		object := gem.create(u32(9000 + failed)); file.objects.add_created(object)
		id := bind_capture_buffer(mut file, object.handle)
		mut input := [3]asahi.Timestamps{}
		for index in 0 .. 6 {
			timestamp := asahi.Timestamp{handle: if index == failed { id + 1 } else { id }}
			if index % 2 == 0 { input[index / 2].start = timestamp } else { input[index / 2].end = timestamp }
		}
		mut references := G13TimestampReferences{}
		assert file.capture_g13_timestamps(input, mut references) == -2, 'partial lookup failure'
		assert references == G13TimestampReferences{} && file.timestamp_objects[0].references == 0 && object.references == 2, 'partial capture rollback'
		assert file.close() && gem.live() == 0
	}
	// UNBIND between the first and second individual lookup must retain the
	// first capture, reject the second, then release the failed prefix once.
	mut raced := GpuFile{}
	object := gem.create(9100); raced.objects.add_created(object)
	id := bind_capture_buffer(mut raced, object.handle)
	mut references := G13TimestampReferences{}
	timestamp_race_file = unsafe { &raced }; timestamp_race_id = id; timestamp_race_step = 0
	klock.before_once(unsafe { &raced.lock }, remove_between_timestamp_lookups)
	before := gpu.unmaps()
	input := [asahi.Timestamps{start: asahi.Timestamp{handle: id}, end: asahi.Timestamp{handle: id}}, asahi.Timestamps{}, asahi.Timestamps{}]!
	assert raced.capture_g13_timestamps(input, mut references) == -2
	assert timestamp_race_step == 2 && references == G13TimestampReferences{} && raced.timestamp_objects.len == 0
	assert object.references == 1 && gpu.unmaps() == before + 1, 'racing prefix releases exactly once'
	timestamp_race_file = unsafe { nil }
	assert raced.close() && gem.live() == 0
	println('G13 timestamp capture: ${validation_cases} validation cases, ${ownership_cases} retained mapping lifecycles, six rollback prefixes and inter-lookup UNBIND passed')
}
