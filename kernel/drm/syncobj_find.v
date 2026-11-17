// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import drm.syncobj
import proc
import katomic
import sched

fn C.__builtin_alloca(uint) voidptr

struct SyncobjFenceLookup {
	fence &syncobj.DmaFence = unsafe { nil }
	code int
}

// drm_syncobj_find_fence semantics: lookup precedes flags, and FOR_SUBMIT
// waits for availability rather than completion. Published object/fence
// metadata stays retained independently of names. Only the stack capture is
// borrowed, and its defer unlinks it before any return leaves this frame.
fn find_syncobj_fence(owner u64, handle u32, point u64, flags u32) SyncobjFenceLookup {
	object := syncobj.lookup(owner, handle) or { return SyncobjFenceLookup{code: -2} }
	if flags & ~ioctl.drm_syncobj_wait_for_submit != 0 { return SyncobjFenceLookup{code: -22} }
	mut capture := unsafe { &syncobj.TimelineCapture(C.__builtin_alloca(sizeof(syncobj.TimelineCapture))) }
	unsafe { *capture = syncobj.TimelineCapture{} }
	defer { syncobj.release_timeline_capture(capture) }
	if !syncobj.prepare_timeline_capture(object, capture, point,
		flags & ioctl.drm_syncobj_wait_for_submit != 0) { return SyncobjFenceLookup{code: -22} }
	if fence := syncobj.captured_timeline_fence(capture) {
		return SyncobjFenceLookup{fence: if fence == unsafe { nil } { syncobj.shared_timeline_stub() } else { fence }}
	}
	syncobj.arm_timeline_capture(capture)
	submit_started_ns := syncobj.now_ns()
	for {
		if fence := syncobj.captured_timeline_fence(capture) {
			return SyncobjFenceLookup{fence: if fence == unsafe { nil } { syncobj.shared_timeline_stub() } else { fence }}
		}
		if syncobj.now_ns() - submit_started_ns >= u64(5_000_000_000) { return SyncobjFenceLookup{code: -62} }
		waiting_thread := proc.current_thread()
		if katomic.load(&waiting_thread.must_exit) || proc.pending_signals(waiting_thread) & ~waiting_thread.masked_signals != 0 {
			return SyncobjFenceLookup{code: -proc.interrupted_errno}
		}
		sched.reschedule()
	}
	return SyncobjFenceLookup{code: -62}
}
