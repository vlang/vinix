// SPDX-License-Identifier: GPL-2.0-or-later
module file

import gpu.agx.submission
import memory

// Fallible, bounded storage, owned by the submit caller until registration.
// Pending nodes borrow it during preparation and own it after acceptance.
struct G13SubmissionTimestamps {
mut:
	entries &G13TimestampReferences = unsafe { nil }
	count u32
}

fn (timestamps G13SubmissionTimestamps) addresses(command u32, pipe u32) [2]u64 {
	if command >= timestamps.count { return [2]u64{} }
	return unsafe { timestamps.entries[command].addresses(pipe) }
}

// Consume one owner exactly once. The scalar header is copied so cleanup
// never takes an escaping address of a caller's stack-local owner.
fn (mut f GpuFile) release_g13_submission_timestamps(timestamps G13SubmissionTimestamps) {
	for index := u32(0); index < timestamps.count; index++ {
		unsafe { f.release_g13_timestamps(mut timestamps.entries[index]) }
	}
	if timestamps.entries != unsafe { nil } { memory.free(voidptr(timestamps.entries)) }
}

fn (mut f GpuFile) new_g13_submission_timestamps(commands []submission.Command) (int, G13SubmissionTimestamps) {
	if commands.len == 0 || commands.len > int(submission.max_commands) { return -22, G13SubmissionTimestamps{} }
	mut requested := false
	for index in 0 .. commands.len {
		if commands[index].needs_timestamp_objects() { requested = true; break }
	}
	// Preserve the legacy allocation/failure order when no lookup is needed.
	if !requested { return 0, G13SubmissionTimestamps{} }
	storage := memory.malloc_packed_fallible(u64(commands.len) * sizeof(G13TimestampReferences)) @[freed]
	if storage == unsafe { nil } { return -12, G13SubmissionTimestamps{} }
	timestamps := G13SubmissionTimestamps{entries: unsafe { &G13TimestampReferences(storage) }, count: u32(commands.len)}
	for index := u32(0); index < timestamps.count; index++ {
		unsafe { timestamps.entries[index] = G13TimestampReferences{} }
	}
	for index := u32(0); index < timestamps.count; index++ {
		code := unsafe { f.capture_g13_timestamps(commands[index].timestamps, mut timestamps.entries[index]) }
		if code != 0 { f.release_g13_submission_timestamps(timestamps); return code, G13SubmissionTimestamps{} }
	}
	return 0, timestamps
}
