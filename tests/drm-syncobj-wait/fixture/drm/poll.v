// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

import drm.syncobj
import event
import file
import memory
import resource

__global poll_fixture_fence &syncobj.DmaFence = unsafe { nil }
__global poll_fixture_number = -1

fn poll_descriptor(number int) int {
	mut fd := file.fd_from_fdnum(unsafe { nil }, number) or { panic('poll missing descriptor') }
	defer { fd.unref() }
	mut res := fd.handle.resource
	return resource.poll_status(mut res, 0)
}

fn descriptor_generation(number int) u64 {
	mut fd := file.fd_from_fdnum(unsafe { nil }, number) or { panic('generation missing descriptor') }
	defer { fd.unref() }
	mut res := fd.handle.resource
	return event.generation(mut res.event)
}

fn check_no_event_in_retiring_storage(allocation voidptr, size u64) {
	for index in 0 .. wait_fixture_fence_count {
		syncobj.assert_no_fence_event_in_region_for_checks(wait_fixture_fences[index], allocation, size)
	}
}

fn poll_signal_before_lock() { syncobj.signal_error(poll_fixture_fence, -5) }
fn poll_close_before_lock() { file.close(poll_fixture_number) }

pub fn run_sync_file_poll_checks() {
	memory.reset()
	memory.check_before_free(check_no_event_in_retiring_storage)
	syncobj.run_fence_event_primitive_checks()
	mut cases := 0
	for _ in 0 .. 200 {
		source := make_object(0)
		pending := make_fence()
		replacement := make_fence()
		syncobj.replace_fence(source, pending)
		number := export_object(11, source.handle, 1)
		attempts := memory.attempts()
		notifications := event.notifications()
		// Register exactly once despite repeated probes. Poll advertises only IN.
		for _ in 0 .. 16 { assert poll_descriptor(number) == 0; cases++ }
		assert memory.attempts() == attempts && descriptor_generation(number) == 0
		// A replacement's completion must not wake a snapshot of older work.
		syncobj.replace_fence(source, replacement)
		syncobj.signal(replacement)
		assert poll_descriptor(number) == 0; cases++
		assert descriptor_generation(number) == 0 && event.notifications() == notifications
		syncobj.signal_error(pending, -5)
		for _ in 0 .. 16 { assert poll_descriptor(number) == file.pollin; cases++ }
		assert descriptor_generation(number) == 1 && event.notifications() == notifications + 1
		syncobj.assert_fence_events_for_checks(pending, 0)
		syncobj.signal(pending); syncobj.signal_error(pending, -19)
		assert descriptor_generation(number) == 1 && syncobj.get_error(pending) == -5
		file.close(number)
		// Already-completed exports need no subscription and remain readable.
		ready := export_object(11, source.handle, 1)
		assert poll_descriptor(ready) == file.pollin; cases++
		syncobj.assert_fence_events_for_checks(replacement, 0)
		file.close(ready)
		// Distinct descriptors subscribe independently; a duplicate shares its
		// wrapper, node and event until the final reference closes.
		fanout := make_fence(); syncobj.replace_fence(source, fanout)
		mut numbers := [8]int{}
		for index in 0 .. numbers.len {
			numbers[index] = export_object(11, source.handle, 1)
			assert poll_descriptor(numbers[index]) == 0; cases++
		}
		syncobj.assert_fence_events_for_checks(fanout, 8)
		duplicate := file.duplicate(numbers[1])
		assert poll_descriptor(duplicate) == 0; cases++
		syncobj.assert_fence_events_for_checks(fanout, 8)
		file.close(numbers[1]); numbers[1] = duplicate
		for index in [7, 4, 0]! { file.close(numbers[index]); numbers[index] = -1 }
		syncobj.assert_fence_events_for_checks(fanout, 5)
		before := event.notifications()
		syncobj.signal(fanout)
		assert event.notifications() == before + 5
		for number_to_close in numbers {
			if number_to_close < 0 { continue }
			assert poll_descriptor(number_to_close) == file.pollin; cases++
			assert descriptor_generation(number_to_close) == 1
			file.close(number_to_close)
		}
		// Deterministic exact-lock races: completion can win before close, or
		// close can unlink/free its node before completion acquires the lock.
		for order in 0 .. 4 {
			fence := make_fence(); syncobj.replace_fence(source, fence)
			fdnum := export_object(11, source.handle, 1)
			poll_fixture_fence = fence; poll_fixture_number = fdnum
			if order < 2 { assert poll_descriptor(fdnum) == 0; cases++ }
			before_race := event.notifications()
			if order == 0 {
				syncobj.before_fence_lock_for_checks(fence, poll_signal_before_lock)
				file.close(fdnum)
				assert event.notifications() == before_race + 1
			} else if order == 1 {
				syncobj.before_fence_lock_for_checks(fence, poll_close_before_lock)
				syncobj.signal(fence)
				assert event.notifications() == before_race
			} else if order == 2 {
				syncobj.before_fence_lock_for_checks(fence, poll_signal_before_lock)
				assert poll_descriptor(fdnum) == file.pollin; cases++
				assert descriptor_generation(fdnum) == 0
				file.close(fdnum)
			} else {
				// Poll owns a lookup reference while the last installed fd closes.
				syncobj.before_fence_lock_for_checks(fence, poll_close_before_lock)
				assert poll_descriptor(fdnum) == 0; cases++
				syncobj.signal(fence)
				assert event.notifications() == before_race
			}
			syncobj.assert_fence_events_for_checks(fence, 0)
			poll_fixture_fence = unsafe { nil }; poll_fixture_number = -1
		}
		// The export and its subscription survive source namespace teardown.
		orphan := make_fence(); syncobj.replace_fence(source, orphan)
		orphan_fd := export_object(11, source.handle, 1)
		assert poll_descriptor(orphan_fd) == 0; cases++
		syncobj.destroy_owner(11)
		syncobj.signal(orphan)
		assert poll_descriptor(orphan_fd) == file.pollin; cases++
		assert descriptor_generation(orphan_fd) == 1
		file.close(orphan_fd)
		assert file.outstanding() == 0 && memory.outstanding() == 0
		clear(); memory.release_retained_fences(sizeof(syncobj.DmaFence)); memory.reset()
	}
	memory.check_before_free(unsafe { nil })
	println('DRM sync-file poll: ${cases} cases; lazy single registration, completion/error IN readiness, stable snapshots, fanout, duplicate/final close, unlink-before-free hooks and exact-lock signal/close/initial-poll races passed')
}
