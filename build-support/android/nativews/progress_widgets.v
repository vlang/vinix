// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_progress_set(pointer i64, fraction f32) {
	unsafe {
		if pointer == 0 { return }
		(&WsView(pointer)).progress = if fraction != fraction || fraction < 0 { f32(0) } else if fraction > 1 { f32(1) } else { fraction }
	}
	ws_mark()
}

fn ws_progress_indeterminate(e voidptr, object voidptr, value u8) {
	ws_view(e, object).indeterminate = value != 0
	unsafe { PutBoolean(slot(e, 105))(e, object, field(e, c'android/widget/ProgressBar', c'indeterminate', c'Z'), value) }
	ws_mark()
}

fn ws_progress_draw(e voidptr, object voidptr) {
	unsafe {
		view := ws_view(e, object)
		width := f32(integer(e, object, c'android/view/View', c'getWidth', c'()I', nil))
		height := f32(integer(e, object, c'android/view/View', c'getHeight', c'()I', nil))
		if width <= 0 || height <= 0 { return }
		if !view.indeterminate {
			y := (height - 6) / 2
			ws_rect(0, y, width, y + 6, 0xffd8e7e1)
			ws_rect(0, y, width * view.progress, y + 6, 0xff00a884)
			return
		}
		ws.animated = true
		size := if width < height { width } else { height }
		radius := size * 0.35
		paint := &WsPaint(C.alloca(sizeof(WsPaint)))
		*paint = WsPaint{ color: 0xff00a884, stroke: 2 }
		phase := f32(ws_millis() % 1200) / 1200 * 6.2831853
		for i := 0; i < 20; i++ {
			a := phase + f32(i) * 0.2
			b := a + 0.2
			ws_canvas_line(width / 2 + C.cosf(a) * radius, height / 2 + C.sinf(a) * radius,
				width / 2 + C.cosf(b) * radius, height / 2 + C.sinf(b) * radius, i64(paint))
		}
	}
}
