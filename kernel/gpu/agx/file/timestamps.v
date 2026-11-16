// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.gem
import gpu.agx.gpu

// IDs stay reserved while a detached mapping has captures. No pointer into
// the movable namespace array escapes. The retained entry also pins GpuFile
// through close(), including the interval before a submission has a VM pin.
struct G13TimestampCapture {
	id u32
	address u64
}

struct G13TimestampReferences {
mut:
	entries [3][2]G13TimestampCapture // vertex, fragment, compute; start/end
}

fn (references &G13TimestampReferences) addresses(pipe u32) [2]u64 {
	if pipe >= 3 { return [2]u64{} }
	return [references.entries[pipe][0].address, references.entries[pipe][1].address]!
}

fn (mut f GpuFile) capture_g13_timestamp(timestamp asahi.Timestamp) (int, G13TimestampCapture) {
	// Asahi ignores even an overflowing offset when the handle is null.
	if timestamp.handle == 0 { return 0, G13TimestampCapture{} }
	f.lock.acquire()
	defer { f.lock.release() }
	for index in 0 .. f.timestamp_objects.len {
		mut object := &f.timestamp_objects[index]
		if object.id != timestamp.handle || object.detached { continue }
		// Lookup precedes offset validation; offsets need not be aligned.
		if timestamp.offset > ~u32(0) - u32(8) { return -22, G13TimestampCapture{} }
		if u64(timestamp.offset) + 8 > object.size { return -34, G13TimestampCapture{} }
		if object.references == ~u64(0) { return -12, G13TimestampCapture{} }
		object.references++
		return 0, G13TimestampCapture{id: object.id, address: object.va + u64(timestamp.offset)}
	}
	return -2, G13TimestampCapture{}
}

// Caller holds file.lock. Global timestamp mappings do not depend on any
// userspace VM. Missing managers keep their GEM owner and ID for a later retry.
fn (mut f GpuFile) reap_detached_timestamp_objects_locked() {
	manager := gpu.get_global_manager() or { return }
	mut gpu_manager := unsafe { manager }
	for index := f.timestamp_objects.len - 1; index >= 0; index-- {
		object := f.timestamp_objects[index]
		if !object.detached || object.references != 0 { continue }
		gpu_manager.unmap_g13_timestamp_buffer(object.va, object.size)
		gem.unref(object.obj)
		f.timestamp_objects.delete(index)
	}
}

fn (mut f GpuFile) release_g13_timestamp(capture G13TimestampCapture) {
	if capture.id == 0 { return }
	f.lock.acquire()
	defer { f.lock.release() }
	for index in 0 .. f.timestamp_objects.len {
		if f.timestamp_objects[index].id != capture.id { continue }
		assert f.timestamp_objects[index].references != 0
		f.timestamp_objects[index].references--
		f.reap_detached_timestamp_objects_locked()
		return
	}
	assert false, 'missing retained timestamp owner'
}

// Run outside GpuManager.lock, as pending-node retirement does. GPU callbacks
// holding that lock must defer release to the file worker.
fn (mut f GpuFile) release_g13_timestamps(mut references G13TimestampReferences) {
	for pipe in 0 .. 3 {
		for phase in 0 .. 2 {
			capture := references.entries[pipe][phase]
			references.entries[pipe][phase] = G13TimestampCapture{}
			f.release_g13_timestamp(capture)
		}
	}
}

// Resolve each lookup in command order, retaining earlier destinations across
// concurrent UNBIND. Any failure releases the prefix and clears owned output.
// Modern submit must transfer this owner through job retirement before using
// addresses(); the public Mesa 25 ioctl path does not call this helper.
fn (mut f GpuFile) capture_g13_timestamps(input [3]asahi.Timestamps,
	mut references G13TimestampReferences) int {
	for pipe in 0 .. 3 {
		for phase in 0 .. 2 {
			if references.entries[pipe][phase].id != 0 { return -22 }
		}
	}
	for pipe in 0 .. 3 {
		for phase in 0 .. 2 {
			timestamp := if phase == 0 { input[pipe].start } else { input[pipe].end }
			code, capture := f.capture_g13_timestamp(timestamp)
			if code != 0 { f.release_g13_timestamps(mut references); return code }
			references.entries[pipe][phase] = capture
		}
	}
	return 0
}
