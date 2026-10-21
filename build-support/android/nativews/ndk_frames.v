// SPDX-License-Identifier: GPL-2.0-or-later
// One-shot NDK frame callbacks dispatched by the native WS main Looper.
@[translated]
module atlframework

type WsFrameFunction = fn (i64, voidptr)

struct WsFrame {
mut:
	next &WsFrame
	callback WsFrameFunction
	data voidptr
	due i64
}

struct WsChoreographer {
mut:
	mutex C.pthread_mutex_t
	frames &WsFrame
}

__global ws_choreographer &WsChoreographer

fn ws_frames_init() bool {
	unsafe {
		ws_choreographer = &WsChoreographer(C.calloc(1, sizeof(WsChoreographer)))
		return ws_choreographer != nil && C.pthread_mutex_init(&ws_choreographer.mutex, nil) == 0
	}
}

@[export: 'AChoreographer_getInstance']
pub fn ws_frames_instance() &WsChoreographer {
	unsafe {
		if ws == nil || usize(C.pthread_self()) != ws.main_thread { return nil }
		return ws_choreographer
	}
}

@[export: 'AChoreographer_postFrameCallbackDelayed64']
pub fn ws_frames_post_delayed(choreographer &WsChoreographer, callback WsFrameFunction, data voidptr, delay u32) {
	unsafe {
		if choreographer == nil || voidptr(callback) == nil { return }
		frame := &WsFrame(C.calloc(1, sizeof(WsFrame)))
		if frame == nil { return }
		frame.callback = callback
		frame.data = data
		frame.due = ws_millis() + i64(delay)
		C.pthread_mutex_lock(&choreographer.mutex)
		frame.next = choreographer.frames
		choreographer.frames = frame
		C.pthread_mutex_unlock(&choreographer.mutex)
	}
}

@[export: 'AChoreographer_postFrameCallback64']
pub fn ws_frames_post(choreographer &WsChoreographer, callback WsFrameFunction, data voidptr) {
	ws_frames_post_delayed(choreographer, callback, data, 0)
}

fn ws_frames_dispatch() {
	unsafe {
		choreographer := ws_choreographer
		mut now := WsTimespec{}
		C.clock_gettime(1, voidptr(&now))
		nanos := now.seconds * 1000000000 + now.nanos
		C.pthread_mutex_lock(&choreographer.mutex)
		mut link := &choreographer.frames
		mut ready := &WsFrame(nil)
		for *link != nil {
			frame := *link
			if frame.due > nanos / 1000000 { link = &frame.next; continue }
			*link = frame.next
			frame.next = ready
			ready = frame
		}
		C.pthread_mutex_unlock(&choreographer.mutex)
		// Detach before calling: callbacks may schedule the following frame.
		for ready != nil {
			frame := ready
			ready = frame.next
			frame.callback(nanos, frame.data)
			C.free(frame)
		}
	}
}
