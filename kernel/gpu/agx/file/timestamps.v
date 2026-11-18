// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm.asahi
import drm.gem
import gpu.agx.gpu

// The base VA stays reserved while a mapping has captures. Users may reuse
// the name after UNBIND. The retained entry pins GpuFile
// through close(), including the interval before a submission has a VM pin.
struct G13TimestampCapture {
	va u64
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

fn (mut f GpuFile) capture_g13_timestamp(timestamp asahi.Timestamp, manager &gpu.GpuManager) (int, G13TimestampCapture) {
	// Asahi ignores even an overflowing offset when the handle is null.
	if timestamp.handle == 0 { return 0, G13TimestampCapture{} }
	f.lock.acquire()
	defer { f.lock.release() }
	for index in 0 .. f.timestamp_objects.len {
		mut object := &f.timestamp_objects[index]
		if object.id != timestamp.handle || object.detached { continue }
		if voidptr(f.timestamp_manager) != voidptr(manager) { return -19, G13TimestampCapture{} }
		// Lookup precedes offset validation; offsets need not be aligned.
		if timestamp.offset > ~u32(0) - u32(8) { return -22, G13TimestampCapture{} }
		if u64(timestamp.offset) + 8 > object.size { return -34, G13TimestampCapture{} }
		if object.references == ~u64(0) { return -12, G13TimestampCapture{} }
		object.references++
		return 0, G13TimestampCapture{va: object.va, address: object.va + u64(timestamp.offset)}
	}
	return -2, G13TimestampCapture{}
}

fn release_timestamp_object(manager &gpu.GpuManager, object TimestampObject) {
	mut owner := unsafe { manager }
	owner.unmap_g13_timestamp_buffer(object.va, object.size)
	gem.unref(object.obj)
}

// Caller holds file.lock. Timestamp mappings do not depend on a userspace VM
// or the current global manager.
fn (mut f GpuFile) reap_detached_timestamp_objects_locked() {
	for index := f.timestamp_objects.len - 1; index >= 0; index-- {
		object := f.timestamp_objects[index]
		if !object.detached || object.references != 0 { continue }
		release_timestamp_object(f.timestamp_manager, object)
		f.timestamp_objects.delete(index)
	}
}

fn (mut f GpuFile) release_g13_timestamp(capture G13TimestampCapture) {
	if capture.va == 0 { return }
	f.lock.acquire()
	defer { f.lock.release() }
	for index in 0 .. f.timestamp_objects.len {
		if f.timestamp_objects[index].va != capture.va { continue }
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
		f.release_g13_timestamp_pair(mut references, u32(pipe))
	}
}

// Each render engine owns only its own pair. Clear before releasing, since
// detached mapping cleanup can remove the namespace entry on the last owner.
fn (mut f GpuFile) release_g13_timestamp_pair(mut references G13TimestampReferences, pipe u32) {
	if pipe >= 3 { return }
	for phase in 0 .. 2 {
		capture := references.entries[pipe][phase]
		references.entries[pipe][phase] = G13TimestampCapture{}
		f.release_g13_timestamp(capture)
	}
}

// Resolve each lookup in command order, retaining earlier destinations across
// concurrent UNBIND. Any failure releases the prefix and clears owned output.
// Submission staging transfers this owner through pending-job retirement.
fn (mut f GpuFile) capture_g13_timestamps(input [3]asahi.Timestamps, manager &gpu.GpuManager,
	mut references G13TimestampReferences) int {
	for pipe in 0 .. 3 {
		for phase in 0 .. 2 {
			if references.entries[pipe][phase].va != 0 { return -22 }
		}
	}
	for pipe in 0 .. 3 {
		for phase in 0 .. 2 {
			timestamp := if phase == 0 { input[pipe].start } else { input[pipe].end }
			code, capture := f.capture_g13_timestamp(timestamp, manager)
			if code != 0 { f.release_g13_timestamps(mut references); return code }
			references.entries[pipe][phase] = capture
		}
	}
	return 0
}
