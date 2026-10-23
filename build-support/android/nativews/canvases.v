// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsDrawState {
mut:
	width      i32
	height     i32
	pixels     &u32
	bitmap     i64
	transform  WsTransform
	transforms [64]WsTransform
	save_count i32
	clips      [64]WsClipQuad
}

__global ws_draw_key u32
__global ws_root_draw &WsDrawState

fn ws_draw_init() bool {
	unsafe {
		if C.pthread_key_create(&ws_draw_key, nil) != 0 { return false }
		ws_root_draw = &WsDrawState(C.calloc(1, sizeof(WsDrawState)))
		return ws_root_draw != nil
	}
}

fn ws_draw_state() &WsDrawState {
	unsafe {
		state := &WsDrawState(C.pthread_getspecific(ws_draw_key))
		return if state == nil { ws_root_draw } else { state }
	}
}

// Each Canvas owns its matrix/clip stack and holds its pixel storage alive.
// Selection is scoped to a JNI call and thread-local: a worker painting into
// a Bitmap cannot redirect the desktop's main-thread drawing.
fn ws_canvas_enter(e voidptr, canvas voidptr, snapshot i64) voidptr {
	unsafe {
		previous := C.pthread_getspecific(ws_draw_key)
		if snapshot == 1 {
			C.pthread_setspecific(ws_draw_key, ws_root_draw)
			return previous
		}
		mut state := &WsDrawState(get_long(e, canvas, c'android/atl/GskCanvas', c'vinixDrawState'))
		if pending(e) { return previous }
		if state == nil {
			state = &WsDrawState(C.calloc(1, sizeof(WsDrawState)))
			if state == nil {
				throw(e, c'java/lang/OutOfMemoryError', c'Canvas state')
				return previous
			}
			f := field(e, c'android/atl/GskCanvas', c'vinixDrawState', c'J')
			WsPutLong(slot(e, 110))(e, canvas, f, i64(state))
		}
		if state.bitmap != snapshot || state.width == 0 {
			ws_path_clip_release(state, nil)
			ws_bitmap_unref(state.bitmap)
			state.bitmap = ws_bitmap_ref(snapshot)
			state.width = if snapshot == 0 { i32(0) } else { (&WsBitmap(snapshot)).width }
			state.height = if snapshot == 0 { i32(0) } else { (&WsBitmap(snapshot)).height }
			state.transform = WsTransform{ right: state.width, bottom: state.height }
			state.save_count = 0
		}
		C.pthread_setspecific(ws_draw_key, state)
		return previous
	}
}

fn ws_canvas_leave(previous voidptr) {
	C.pthread_setspecific(ws_draw_key, previous)
}

fn ws_canvas_free(e voidptr, canvas voidptr) {
	unsafe {
		state := &WsDrawState(get_long(e, canvas, c'android/atl/GskCanvas', c'vinixDrawState'))
		if state == nil { return }
		f := field(e, c'android/atl/GskCanvas', c'vinixDrawState', c'J')
		WsPutLong(slot(e, 110))(e, canvas, f, 0)
		ws_path_clip_release(state, nil)
		ws_bitmap_unref(state.bitmap)
		C.free(state)
	}
}
