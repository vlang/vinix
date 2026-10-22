// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include "stb_truetype.h"

fn C.stbtt_GetFontVMetrics(voidptr, &i32, &i32, &i32)
fn C.stbtt_GetFontBoundingBox(voidptr, &i32, &i32, &i32, &i32)

struct WsFontMetrics {
	top f32
	ascent f32
	descent f32
	bottom f32
	leading f32
}

type WsPutFloat = fn (voidptr, voidptr, voidptr, f32)

fn ws_put_metric_float(e voidptr, metrics voidptr, name &char, value f32) {
	f := field(e, c'android/graphics/Paint$FontMetrics', name, c'F')
	if f != unsafe { nil } { unsafe { WsPutFloat(slot(e, 111))(e, metrics, f, value) } }
}

// Use the same face and pixel-height scale as Canvas text rasterization.
// TrueType y increases upwards; Android metrics increase downwards.
fn ws_paint_metrics(e voidptr, paint voidptr) WsFontMetrics {
	unsafe {
		pointer := get_long(e, paint, c'android/graphics/Paint', c'paint')
		if pointer == 0 || pending(e) { return WsFontMetrics{} }
		native := &WsPaint(pointer)
		info := ws_font_info(native.font)
		if info == nil || native.size == 0 { return WsFontMetrics{} }
		mut ascent, mut descent, mut gap := i32(0), i32(0), i32(0)
		mut left, mut bottom, mut right, mut top := i32(0), i32(0), i32(0), i32(0)
		C.stbtt_GetFontVMetrics(info, &ascent, &descent, &gap)
		C.stbtt_GetFontBoundingBox(info, &left, &bottom, &right, &top)
		scale := C.stbtt_ScaleForPixelHeight(info, native.size)
		return WsFontMetrics{
			top: -f32(top) * scale
			ascent: -f32(ascent) * scale
			descent: -f32(descent) * scale
			bottom: -f32(bottom) * scale
			leading: f32(gap) * scale
		}
	}
}

fn ws_font_metrics(e voidptr, paint voidptr, output voidptr) f32 {
	m := ws_paint_metrics(e, paint)
	if output != unsafe { nil } && !pending(e) {
		ws_put_metric_float(e, output, c'top', m.top)
		ws_put_metric_float(e, output, c'ascent', m.ascent)
		ws_put_metric_float(e, output, c'descent', m.descent)
		ws_put_metric_float(e, output, c'bottom', m.bottom)
		ws_put_metric_float(e, output, c'leading', m.leading)
	}
	return m.descent - m.ascent + m.leading
}

fn ws_font_metrics_int(e voidptr, paint voidptr, output voidptr) i32 {
	m := ws_paint_metrics(e, paint)
	// Android encloses the ink bounds, and rounds the recommended metrics
	// with Java Math.round (ties toward positive infinity, including negatives).
	top, bottom := i32(C.floorf(m.top)), i32(C.ceilf(m.bottom))
	ascent := i32(C.floorf(m.ascent + f32(0.5)))
	descent := i32(C.floorf(m.descent + f32(0.5)))
	leading := i32(C.floorf(m.leading + f32(0.5)))
	if output != unsafe { nil } && !pending(e) {
		put_int(e, output, c'android/graphics/Paint$FontMetricsInt', c'top', top)
		put_int(e, output, c'android/graphics/Paint$FontMetricsInt', c'ascent', ascent)
		put_int(e, output, c'android/graphics/Paint$FontMetricsInt', c'descent', descent)
		put_int(e, output, c'android/graphics/Paint$FontMetricsInt', c'bottom', bottom)
		put_int(e, output, c'android/graphics/Paint$FontMetricsInt', c'leading', leading)
	}
	return descent - ascent + leading
}
