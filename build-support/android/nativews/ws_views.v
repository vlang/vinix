// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsView {
mut:
	kind           i32 // 0 custom/container, 1 label, 2 button, 3 editable, 4 scroll
	text           &char
	hint           &char
	size           f32 = 18
	color          u32 = 0xff202124
	background     u32
	padding_left   i32
	padding_top    i32
	padding_right  i32
	padding_bottom i32
	visible        bool = true
	sensitive      bool = true
	focused        bool
}

fn ws_view(e voidptr, object voidptr) &WsView {
	unsafe { return &WsView(get_long(e, object, c'android/view/View', c'widget'))
	 }
}

fn ws_view_new(kind i32) i64 {
	unsafe {
		view := &WsView(C.malloc(sizeof(WsView)))
		*view = WsView{ kind: kind, text: C.strdup(c''), hint: C.strdup(c'') }
		return i64(view)
	}
}

fn ws_view_free(pointer i64) {
	unsafe {
		if pointer == 0 { return }
		view := &WsView(pointer)
		C.free(view.text)
		C.free(view.hint)
		C.free(view)
	}
}

fn ws_mark() { if ws != unsafe { nil } { ws.dirty = true } }

fn ws_set_text(e voidptr, object voidptr, text voidptr) {
	unsafe {
		view := ws_view(e, object)
		old_length := i32(C.strlen(view.text))
		chars := ws_utf(e, text)
		replacement := C.strdup(chars)
		ws_release(e, text, chars)
		watchers := get_object(e, object, c'android/view/View', c'vinixWsWatchers', c'Ljava/util/ArrayList;')
		count := if watchers == nil {
			i32(0)
		} else {
			integer(e, watchers, c'java/util/ArrayList', c'size', c'()I', nil)
		}
		old_text := ws_string(e, view.text)
		length := i32(C.strlen(replacement))
		args := [Value{ l: old_text }, Value{ i: 0 }, Value{ i: old_length }, Value{ i: length }]!
		for i := i32(0); i < count; i++ {
			call(e, array_item(e, watchers, i), c'android/text/TextWatcher', c'beforeTextChanged', c'(Ljava/lang/CharSequence;III)V', &args[0])
		}
		C.free(view.text)
		view.text = replacement
		if C.getenv(c'VINIX_ANDROID_TRACE_TEXT') != nil {
			C.printf(c'ANDROID-WS-TEXT kind=%d value=%s\n', view.kind, replacement)
		}
		new_text := ws_string(e, replacement)
		next := [Value{ l: new_text }, Value{ i: 0 }, Value{ i: old_length }, Value{ i: length }]!
		for i := i32(0); i < count; i++ {
			call(e, array_item(e, watchers, i), c'android/text/TextWatcher', c'onTextChanged', c'(Ljava/lang/CharSequence;III)V', &next[0])
		}
		editable_args := [Value{ l: new_text }]!
		editable := if count > 0 {
			new_object(e, c'android/text/SpannableStringBuilder', c'(Ljava/lang/CharSequence;)V', &editable_args[0])
		} else {
			nil
		}
		after := [Value{ l: editable }]!
		for i := i32(0); i < count; i++ {
			call(e, array_item(e, watchers, i), c'android/text/TextWatcher', c'afterTextChanged', c'(Landroid/text/Editable;)V', &after[0])
		}
		call(e, object, c'android/view/View', c'requestLayout', c'()V', nil)
		ws_mark()
	}
}

fn ws_watcher(e voidptr, object voidptr, watcher voidptr, remove bool) {
	unsafe {
		list := get_object(e, object, c'android/view/View', c'vinixWsWatchers', c'Ljava/util/ArrayList;')
		mut retained := list
		if retained == nil {
			retained = new_object(e, c'java/util/ArrayList', c'()V', nil)
			put_object(e, object, c'android/view/View', c'vinixWsWatchers', c'Ljava/util/ArrayList;', retained)
		}
		args := [Value{ l: watcher }]!
		boolean(e, retained, c'java/util/ArrayList', if remove { c'remove' } else { c'add' }, c'(Ljava/lang/Object;)Z', &args[0])
	}
}

fn ws_focus(e voidptr, object voidptr) {
	unsafe {
		if ws.focused != nil {
			ws_view(e, ws.focused).focused = false
			Drop(slot(e, 22))(e, ws.focused)
		}
		ws.focused = WsRef(slot(e, 21))(e, object)
		ws_view(e, object).focused = true
		ws_mark()
	}
}

fn ws_measure(e voidptr, object voidptr, width_spec i32, height_spec i32) {
	unsafe {
		view := ws_view(e, object)
		text_width := i32(ws_text_width(view.text, view.size) + 0.999)
		mut width := text_width + view.padding_left + view.padding_right + 6
		mut height := i32(view.size * 1.5) + view.padding_top + view.padding_bottom
		if view.kind == 2 {
			width += 24
			height += 16
		}
		if view.kind == 3 {
			if width < 100 { width = 100 }
			height += 12
		}
		if view.kind == 5 {
			drawable := obj(e, object, c'android/widget/ImageView', c'getDrawable', c'()Landroid/graphics/drawable/Drawable;', nil)
			width = 48
			height = 48
			if drawable != nil {
				natural_width := integer(e, drawable, c'android/graphics/drawable/Drawable', c'getIntrinsicWidth', c'()I', nil)
				natural_height := integer(e, drawable, c'android/graphics/drawable/Drawable', c'getIntrinsicHeight', c'()I', nil)
				if natural_width > width { width = natural_width }
				if natural_height > height { height = natural_height }
			}
			width += view.padding_left + view.padding_right
			height += view.padding_top + view.padding_bottom
		}
		if view.kind == 6 {
			width = ws.width - 96
			available := width_spec & 0x3fffffff
			if u32(width_spec) >> 30 != 0 && width > available { width = available }
			layout := ws_text_layout(view.text, view.size, width - 6)
			height = i32(f32((&WsTextLayout(layout)).count) * view.size * 1.25) + 12
			if height > ws.height / 2 { height = ws.height / 2 }
			ws_layout_free(layout)
		}
		minimum_width := integer(e, object, c'android/view/View', c'getSuggestedMinimumWidth', c'()I', nil)
		minimum_height := integer(e, object, c'android/view/View', c'getSuggestedMinimumHeight', c'()I', nil)
		if width < minimum_width { width = minimum_width }
		if height < minimum_height { height = minimum_height }
		wmode, hmode := u32(width_spec) >> 30, u32(height_spec) >> 30
		wsize, hsize := width_spec & 0x3fffffff, height_spec & 0x3fffffff
		if wmode == 1 || (wmode == 2 && width > wsize) { width = wsize }
		if hmode == 1 || (hmode == 2 && height > hsize) { height = hsize }
		args := [Value{ i: width }, Value{ i: height }]!
		call(e, object, c'android/view/View', c'setMeasuredDimension', c'(II)V', &args[0])
	}
}

fn ws_layout(e voidptr, object voidptr, left i32, top i32, right i32, bottom i32) {
	args := [Value{ i: right - left }, Value{ i: bottom - top }]!
	call(e, object, c'android/view/View', c'layoutInternal', c'(II)V', unsafe { &args[0] })
	// ATL delegates ScrollView child placement to its display backend.
	if ws_view(e, object).kind == 4 && !pending(e) {
		unsafe {
			zero := [Value{ i: 0 }]!
			child := obj(e, object, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', &zero[0])
			if child != nil {
				width := integer(e, child, c'android/view/View', c'getMeasuredWidth', c'()I', nil)
				height := integer(e, child, c'android/view/View', c'getMeasuredHeight', c'()I', nil)
				bounds := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: width }, Value{ i: height }]!
				call(e, child, c'android/view/View', c'layout', c'(IIII)V', &bounds[0])
			}
		}
	}
	ws_mark()
}

fn ws_draw_background(e voidptr, object voidptr) {
	unsafe {
		view := ws_view(e, object)
		width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
		height := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil)
		background := obj(e, object, c'android/view/View', c'getBackground', c'()Landroid/graphics/drawable/Drawable;', nil)
		if background != nil {
			bounds := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: width }, Value{ i: height }]!
			call(e, background, c'android/graphics/drawable/Drawable', c'setBounds', c'(IIII)V', &bounds[0])
			draw := [Value{ l: ws.canvas }]!
			call(e, background, c'android/graphics/drawable/Drawable', c'draw', c'(Landroid/graphics/Canvas;)V', &draw[0])
		}
		if view.background >> 24 != 0 {
			ws_rect(0, 0, f32(width), f32(height), view.background)
		} else if view.kind == 2 {
			ws_rect(2, 2, f32(width - 2), f32(height - 2), if view.sensitive {
				u32(0xffe4e7ec)
			} else {
				u32(0xfff2f3f5)
			})
			ws_rect(2, f32(height - 3), f32(width - 2), f32(height - 2), 0xffb6bcc5)
		}
		if view.kind == 3 {
			ws_rect(0, f32(height - 2), f32(width), f32(height), if view.focused {
				u32(0xff377bd1)
			} else {
				u32(0xffa0a7b0)
			})
		}
	}
}

fn ws_draw_content(e voidptr, object voidptr) {
	unsafe {
		view := ws_view(e, object)
		if view.kind == 5 {
			ws_draw_image(e, object)
			return
		}
		if view.kind == 6 {
			width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
			layout := ws_text_layout(view.text, view.size, width - 6)
			ws_layout_draw(layout, view.color, 3, view.size)
			ws_layout_free(layout)
			return
		}
		if view.kind < 1 || view.kind > 3 { return }
		width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
		height := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil)
		text_width := ws_text_width(view.text, view.size)
		left := if view.kind == 2 {
			(f32(width) - text_width) / 2
		} else {
			f32(view.padding_left + 3)
		}
		top := if view.kind == 2 {
			(f32(height) + view.size * 0.65) / 2
		} else {
			f32(view.padding_top) + view.size
		}
		ws_text(view.text, left, top, view.size, view.color)
		if view.kind == 3 && view.focused {
			ws_rect(left + text_width + 1, top - view.size * 0.8, left + text_width + 2, top + 2, view.color)
		}
	}
}

fn ws_draw_children(e voidptr, object voidptr) {
	unsafe {
		// ViewGroup's Java native_drawContent is empty; WebView is a leaf
		// ViewGroup whose content belongs to this renderer.
		if ws_view(e, object).kind == 6 { ws_draw_content(e, object) }
		ws_save()
		if ws_view(e, object).kind == 4 {
			ws_translate(-f32(get_int(e, object, c'android/view/View', c'scrollX')), -f32(get_int(e, object, c'android/view/View', c'scrollY')))
		}
		count := integer(e, object, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
		for i := i32(0); i < count; i++ {
			push_frame(e)
			args := [Value{ i: i }]!
			child := obj(e, object, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', &args[0])
			if child != nil && integer(e, child, c'android/view/View', c'getVisibility', c'()I', nil) == 0 {
				left := integer(e, child, c'android/view/View', c'getLeft', c'()I', nil)
				top := integer(e, child, c'android/view/View', c'getTop', c'()I', nil)
				width := integer(e, child, c'android/view/View', c'getWidth', c'()I', nil)
				height := integer(e, child, c'android/view/View', c'getHeight', c'()I', nil)
				ws_save()
				ws_translate(f32(left), f32(top))
				ws_clip(0, 0, f32(width), f32(height))
				draw_args := [Value{ l: ws.canvas }]!
				call(e, child, c'android/view/View', c'draw', c'(Landroid/graphics/Canvas;)V', &draw_args[0])
				ws_restore()
			}
			pop_frame(e)
			if pending(e) {
				ws_restore()
				return
			}
		}
		ws_restore()
	}
}

fn ws_render(e voidptr) {
	unsafe {
		surface := ws.surface
		target := C.__atomic_load_n(&surface.active, 2) ^ 1
		if C.__atomic_load_n(&surface.reader, 2) == target { return }
		previous := C.pthread_getspecific(ws_draw_key)
		C.pthread_setspecific(ws_draw_key, ws_root_draw)
		defer { ws_canvas_leave(previous) }
		ws_root_draw.width = ws.width
		ws_root_draw.height = ws.height
		ws_root_draw.pixels = &u32(usize(surface) + 48 + usize(target) * usize(surface.buffer_size))
		ws_root_draw.transform = WsTransform{ right: ws.width, bottom: ws.height }
		ws_root_draw.save_count = 0
		for i := i32(0); i < ws.width * ws.height; i++ { ws_root_draw.pixels[i] = 0xfffafafa }
		decor := activity_decor(e, ws.activity)
		measure := [Value{ i: ws.width | 0x40000000 }, Value{ i: ws.height | 0x40000000 }]!
		call(e, decor, c'android/view/View', c'measure', c'(II)V', &measure[0])
		layout := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: ws.width }, Value{ i: ws.height }]!
		call(e, decor, c'android/view/View', c'layout', c'(IIII)V', &layout[0])
		if C.getenv(c'VINIX_ANDROID_TRACE_TREE') != nil { ws_debug_tree(e, decor, 0) }
		args := [Value{ l: ws.canvas }]!
		call(e, decor, c'android/view/View', c'draw', c'(Landroid/graphics/Canvas;)V', &args[0])
		if ws.dialog != nil && !pending(e) { ws_render_dialog(e) }
		surface.sequence++
		C.__atomic_store_n(&surface.active, target, 3)
		ws.dirty = false
	}
}

fn ws_debug_tree(e voidptr, view voidptr, depth i32) {
	unsafe {
		if pending(e) || depth > 16 { return }
		class_object := WsRef(slot(e, 31))(e, view)
		name := obj(e, class_object, c'java/lang/Class', c'getName', c'()Ljava/lang/String;', nil)
		chars := ws_utf(e, name)
		C.printf(c'ANDROID-WS-TREE depth=%d class=%s rect=%d,%d,%d,%d visible=%d\n', depth, chars, get_int(e, view, c'android/view/View', c'left'), get_int(e, view, c'android/view/View', c'top'), get_int(e, view, c'android/view/View', c'right'), get_int(e, view, c'android/view/View', c'bottom'), integer(e, view, c'android/view/View', c'getVisibility', c'()I', nil))
		ws_release(e, name, chars)
		if instance_of(e, view, c'android/view/ViewGroup') {
			count := integer(e, view, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
			for i := i32(0); i < count; i++ {
				push_frame(e)
				args := [Value{ i: i }]!
				child := obj(e, view, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', &args[0])
				ws_debug_tree(e, child, depth + 1)
				pop_frame(e)
			}
		}
	}
}

fn ws_hit(e voidptr, view voidptr, x i32, y i32, depth i32) voidptr {
	unsafe {
		if depth > 64 { return nil }
		if instance_of(e, view, c'android/view/ViewGroup') {
			hit_x := x + if ws_view(e, view).kind == 4 {
				get_int(e, view, c'android/view/View', c'scrollX')
			} else {
				i32(0)
			}
			hit_y := y + if ws_view(e, view).kind == 4 {
				get_int(e, view, c'android/view/View', c'scrollY')
			} else {
				i32(0)
			}
			count := integer(e, view, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
			for i := count - 1; i >= 0; i-- {
				args := &Value(C.alloca(sizeof(Value)))
				args[0] = Value{ i: i }
				child := obj(e, view, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', args)
				if integer(e, child, c'android/view/View', c'getVisibility', c'()I', nil) != 0 {
					continue
				}
				left, top := integer(e, child, c'android/view/View', c'getLeft', c'()I', nil), integer(e, child, c'android/view/View', c'getTop', c'()I', nil)
				right, bottom := integer(e, child, c'android/view/View', c'getRight', c'()I', nil), integer(e, child, c'android/view/View', c'getBottom', c'()I', nil)
				if hit_x >= left && hit_x < right && hit_y >= top && hit_y < bottom {
					return ws_hit(e, child, hit_x - left, hit_y - top, depth + 1)
				}
			}
		}
		return WsRef(slot(e, 25))(e, view)
	}
}

struct WsPoint {
	x i32
	y i32
}

type WsLongCall = fn (voidptr, voidptr, voidptr, &Value) i64

fn ws_local_point(e voidptr, view voidptr, x i32, y i32) WsPoint {
	unsafe {
		mut local_x := x - if ws.dialog == nil { i32(0) } else { ws.dialog_x }
		mut local_y := y - if ws.dialog == nil { i32(0) } else { ws.dialog_y }
		mut node := view
		for depth := 0; depth < 64 && node != nil; depth++ {
			local_x -= integer(e, node, c'android/view/View', c'getLeft', c'()I', nil)
			local_y -= integer(e, node, c'android/view/View', c'getTop', c'()I', nil)
			parent := obj(e, node, c'android/view/View', c'getParent', c'()Landroid/view/ViewParent;', nil)
			if parent == nil || !instance_of(e, parent, c'android/view/View') { break }
			if ws_view(e, parent).kind == 4 {
				local_x += get_int(e, parent, c'android/view/View', c'scrollX')
				local_y += get_int(e, parent, c'android/view/View', c'scrollY')
			}
			node = parent
		}
		return WsPoint{local_x, local_y}
	}
}

fn ws_motion(e voidptr, target voidptr, action i32, x i32, y i32) u8 {
	unsafe {
		point := ws_local_point(e, target, x, y)
		args := &Value(C.alloca(7 * sizeof(Value)))
		args[0] = Value{ i: 0x1002 }
		args[1] = Value{ i: action }
		args[2] = Value{ j: ws_millis() }
		args[3] = Value{ f: f32(point.x) }
		args[4] = Value{ f: f32(point.y) }
		args[5] = Value{ f: f32(x) }
		args[6] = Value{ f: f32(y) }
		event := new_object(e, c'android/view/MotionEvent', c'(IIJFFFF)V', args)
		args[0] = Value{ l: event }
		args[1] = Value{ i: 1 }
		return boolean(e, target, c'android/view/View', c'onTouchEventInternal', c'(Landroid/view/MotionEvent;Z)Z', args)
	}
}

fn ws_list_activate(e voidptr, leaf voidptr) {
	unsafe {
		mut row := leaf
		for depth := 0; depth < 64; depth++ {
			parent := obj(e, row, c'android/view/View', c'getParent', c'()Landroid/view/ViewParent;', nil)
			if parent == nil || !instance_of(e, parent, c'android/view/View') { return }
			if instance_of(e, parent, c'android/widget/ListView') {
				count := integer(e, parent, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
				for i := i32(0); i < count; i++ {
					args := [Value{ i: i }]!
					child := obj(e, parent, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', &args[0])
					if Same(slot(e, 24))(e, child, row) == 0 { continue }
					position := integer(e, parent, c'android/widget/AdapterView', c'getFirstVisiblePosition', c'()I', nil) + i
					id_args := [Value{ i: position }]!
					id_method := method(e, c'android/widget/AdapterView', c'getItemIdAtPosition', c'(I)J')
					if id_method == nil { return }
					id := WsLongCall(slot(e, 54))(e, parent, id_method, &id_args[0])
					click := [Value{ l: row }, Value{ i: position }, Value{ j: id }]!
					boolean(e, parent, c'android/widget/AdapterView', c'performItemClick', c'(Landroid/view/View;IJ)Z', &click[0])
					return
				}
				return
			}
			row = parent
		}
	}
}

fn ws_pointer(e voidptr, event &WsEvent) {
	unsafe {
		if event.kind != 2 && event.kind != 3 { return }
		if ws.dialog != nil && (event.x < ws.dialog_x || event.y < ws.dialog_y || event.x >= ws.dialog_x + ws.dialog_width || event.y >= ws.dialog_y + ws.dialog_height) {
			return
		}
		root := if ws.dialog == nil {
			activity_decor(e, ws.activity)
		} else {
			ws_dialog_decor(e, ws.dialog)
		}
		target := ws_hit(e, root, event.x - if ws.dialog == nil { 0 } else { ws.dialog_x }, event.y - if ws.dialog == nil {
			0
		} else {
			ws.dialog_y
		}, 0)
		if target == nil { return }
		if !ws_view(e, target).sensitive { return }
		if event.kind == 2 {
			if ws.pressed != nil { Drop(slot(e, 22))(e, ws.pressed) }
			ws.pressed = WsRef(slot(e, 21))(e, target)
			if ws_view(e, target).kind == 3 { ws_focus(e, target) }
			ws_motion(e, target, 0, event.x, event.y)
		} else if ws.pressed != nil {
			if Same(slot(e, 24))(e, ws.pressed, target) != 0 && ws_motion(e, target, 1, event.x, event.y) == 0 {
				ws_list_activate(e, target)
			}
			Drop(slot(e, 22))(e, ws.pressed)
			ws.pressed = nil
		}
		ws_mark()
	}
}

fn ws_keys(e voidptr, bytes &u8, length u32) {
	unsafe {
		if ws.focused == nil || length > 4096 { return }
		view := ws_view(e, ws.focused)
		if view.kind != 3 { return }
		old := usize(C.strlen(view.text))
		buffer := &char(C.malloc(old + usize(length) + 1))
		defer { C.free(buffer) }
		C.memcpy(buffer, view.text, old)
		mut used := old
		for i := u32(0); i < length; i++ {
			if bytes[i] == 8 || bytes[i] == 127 {
				if used > 0 {
					used--
					for used > 0 && u8(buffer[used]) & 0xc0 == 0x80 { used-- }
				}
			} else if bytes[i] >= 32 || bytes[i] == 10 || bytes[i] == 13 {
				buffer[used] = char(if bytes[i] == 13 { u8(10) } else { bytes[i] })
				used++
			}
		}
		buffer[used] = 0
		ws_set_text(e, ws.focused, ws_string(e, buffer))
	}
}

fn ws_input(e voidptr) {
	if ws.input < 0 { return }
	mut descriptor := WsPoll{ fd: ws.input, events: 1 }
	if C.poll(voidptr(&descriptor), 1, 0) <= 0 { return }
	mut event := WsEvent{}
	count := C.read(ws.input, &event, sizeof(WsEvent))
	if count == 0 {
		ws.running = false
		return
	}
	if count != i64(sizeof(WsEvent)) || event.magic != 0x31494e56 || event.length > 4096 {
		ws.running = false
		return
	}
	if event.kind == 4 {
		unsafe {
			bytes := &u8(C.alloca(4096))
			mut read := usize(0)
			for read < usize(event.length) {
				n := C.read(ws.input, &bytes[read], usize(event.length) - read)
				if n <= 0 {
					ws.running = false
					return
				}
				read += usize(n)
			}
			ws_keys(e, bytes, event.length)
		}
	} else {
		ws_pointer(e, &event)
	}
}
