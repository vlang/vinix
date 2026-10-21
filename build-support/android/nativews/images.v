// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_draw_image(e voidptr, object voidptr) {
	unsafe {
		view := ws_view(e, object)
		width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil) - view.padding_left - view.padding_right
		height := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil) - view.padding_top - view.padding_bottom
		if width <= 0 || height <= 0 { return }
		drawable := obj(e, object, c'android/widget/ImageView', c'getDrawable', c'()Landroid/graphics/drawable/Drawable;', nil)
		bitmap := get_object(e, object, c'android/widget/ImageView', c'bitmap', c'Landroid/graphics/Bitmap;')
		mut natural_width, mut natural_height := width, height
		if drawable != nil {
			natural_width = integer(e, drawable, c'android/graphics/drawable/Drawable', c'getIntrinsicWidth', c'()I', nil)
			natural_height = integer(e, drawable, c'android/graphics/drawable/Drawable', c'getIntrinsicHeight', c'()I', nil)
		} else if bitmap != nil {
			natural_width = integer(e, bitmap, c'android/graphics/Bitmap', c'getWidth', c'()I', nil)
			natural_height = integer(e, bitmap, c'android/graphics/Bitmap', c'getHeight', c'()I', nil)
		} else {
			return
		}
		if natural_width <= 0 || natural_height <= 0 {
			natural_width = width
			natural_height = height
		}
		scale_type := obj(e, object, c'android/widget/ImageView', c'getScaleType', c'()Landroid/widget/ImageView$ScaleType;', nil)
		mode := integer(e, scale_type, c'java/lang/Enum', c'ordinal', c'()I', nil)
		mut draw_width, mut draw_height := natural_width, natural_height
		if mode == 1 {
			draw_width = width
			draw_height = height
		} else if mode != 0 && mode != 5 {
			a, b := f32(width) / f32(natural_width), f32(height) / f32(natural_height)
			mut scale := if (a < b) != (mode == 6) { a } else { b }
			if mode == 7 && scale > 1 { scale = 1 }
			draw_width = i32(f32(natural_width) * scale)
			draw_height = i32(f32(natural_height) * scale)
		}
		x := view.padding_left + if mode == 2 || mode == 0 {
			i32(0)
		} else if mode == 4 {
			width - draw_width
		} else {
			(width - draw_width) / 2
		}
		y := view.padding_top + if mode == 2 || mode == 0 {
			i32(0)
		} else if mode == 4 {
			height - draw_height
		} else {
			(height - draw_height) / 2
		}
		ws_save()
		ws_translate(f32(x), f32(y))
		if drawable != nil {
			bounds := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: draw_width }, Value{ i: draw_height }]!
			call(e, drawable, c'android/graphics/drawable/Drawable', c'setBounds', c'(IIII)V', &bounds[0])
			args := [Value{ l: ws.canvas }]!
			call(e, drawable, c'android/graphics/drawable/Drawable', c'draw', c'(Landroid/graphics/Canvas;)V', &args[0])
		} else {
			ws_draw_bitmap(get_long(e, bitmap, c'android/graphics/Bitmap', c'texture'), 0, 0, draw_width, draw_height)
		}
		ws_restore()
	}
}
