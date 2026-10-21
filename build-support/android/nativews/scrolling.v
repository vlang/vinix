// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_scroll_limit(e voidptr, view voidptr, vertical bool) i32 {
	unsafe {
		size := integer(e, view, c'android/view/View', if vertical { c'getHeight' } else { c'getWidth' }, c'()I', nil)
		mut range := integer(e, view, c'android/view/View', if vertical { c'computeVerticalScrollRange' } else { c'computeHorizontalScrollRange' }, c'()I', nil)
		if ws_view(e, view).kind == 4 {
			zero := [Value{ i: 0 }]!
			child := obj(e, view, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', &zero[0])
			if child != nil { range = integer(e, child, c'android/view/View', if vertical { c'getBottom' } else { c'getRight' }, c'()I', nil) }
		}
		return if range > size { range - size } else { i32(0) }
	}
}

fn ws_can_scroll(e voidptr, view voidptr, direction i32, vertical bool) u8 {
	limit := ws_scroll_limit(e, view, vertical)
	position := get_int(e, view, c'android/view/View', if vertical { c'scrollY' } else { c'scrollX' })
	return u8(if direction < 0 { position > 0 } else { position < limit })
}

fn ws_scroll_to(e voidptr, view voidptr, requested_x i32, requested_y i32) {
	x_limit, y_limit := ws_scroll_limit(e, view, false), ws_scroll_limit(e, view, true)
	x := if requested_x < 0 { i32(0) } else if requested_x > x_limit { x_limit } else { requested_x }
	y := if requested_y < 0 { i32(0) } else if requested_y > y_limit { y_limit } else { requested_y }
	old_x, old_y := get_int(e, view, c'android/view/View', c'scrollX'), get_int(e, view, c'android/view/View', c'scrollY')
	if old_x == x && old_y == y { return }
	put_int(e, view, c'android/view/View', c'scrollX', x)
	put_int(e, view, c'android/view/View', c'scrollY', y)
	args := [Value{ i: x }, Value{ i: y }, Value{ i: old_x }, Value{ i: old_y }]!
	call(e, view, c'android/view/View', c'onScrollChanged', c'(IIII)V', unsafe { &args[0] })
	ws_mark()
}

fn ws_wheel(e voidptr, leaf voidptr, value i32) {
	if value == 0 { return }
	direction := if value > 0 { i32(-1) } else { i32(1) }
	unsafe {
		mut view := leaf
		for depth := 0; depth < 64 && view != nil && !pending(e); depth++ {
			if ws_can_scroll(e, view, direction, true) != 0 {
				delta := if value > 1000 { i32(-40000) } else if value < -1000 { i32(40000) } else { -value * 40 }
				args := [Value{ i: 0 }, Value{ i: delta }]!
				call(e, view, c'android/view/View', c'scrollBy', c'(II)V', &args[0])
				ws_mark()
				return
			}
			parent := obj(e, view, c'android/view/View', c'getParent', c'()Landroid/view/ViewParent;', nil)
			if parent == nil || !instance_of(e, parent, c'android/view/View') { return }
			view = parent
		}
	}
}
