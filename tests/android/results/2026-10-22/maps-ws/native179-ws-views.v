// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsView {
mut:
 font &WsFont
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
	max_lines      i32
	min_lines      i32
	single_line    bool
	checked        bool
	broadcasting   bool
	progress       f32
	indeterminate  bool
	window         &WsNativeWindow
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
		ws_window_release(view.window)
		ws_font_unref(view.font)
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
		text_width := i32(ws_text_width(view.text, view.size, view.font) + 0.999)
		mut width := text_width + view.padding_left + view.padding_right + 6
		mut height := i32(view.size * 1.5) + view.padding_top + view.padding_bottom
		if view.kind == 1 && !view.single_line {
			limit := if u32(width_spec) >> 30 == 0 { width } else { width_spec & 0x3fffffff }
			content_width := limit - view.padding_left - view.padding_right - 6
			layout := ws_text_layout(view.text, view.size, if content_width > 0 { content_width } else { 1 }, view.font)
			mut lines := (&WsTextLayout(layout)).count
			if lines < view.min_lines { lines = view.min_lines }
			if view.max_lines > 0 && lines > view.max_lines { lines = view.max_lines }
			height = i32(view.size * (1.5 + f32(lines - 1) * 1.25)) + view.padding_top + view.padding_bottom
			ws_layout_free(layout)
		}
		if view.kind == 2 {
			width += 24
			height += 16
		}
		if view.kind == 3 {
			if width < 100 { width = 100 }
			height += 12
		}
		if view.kind == 7 || view.kind == 8 {
			width += 30
			if height < 32 { height = 32 }
		}
		if view.kind == 9 {
			width = if view.indeterminate { i32(32) } else { i32(120) }
			height = if view.indeterminate { i32(32) } else { i32(8) }
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
			layout := ws_text_layout(view.text, view.size, width - 6, view.font)
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
	args := [Value{ i: left }, Value{ i: top }, Value{ i: right }, Value{ i: bottom }]!
	call(e, object, c'android/view/View', c'vinixPerformLayout', c'(IIII)V', unsafe { &args[0] })
	// onMeasure/onSizeChanged/onLayout can throw. JNI field lookup then returns
	// zero while the exception is pending; preserve it before reading native state.
	if pending(e) { return }
	view := ws_view(e, object)
	if pending(e) { return }
	if view == unsafe { nil } {
		throw(e, c'java/lang/IllegalStateException', c'View has no native WS state')
		return
	}
	if view.kind == 10 {
		ws_surface_layout(e, object, right - left, bottom - top)
		if pending(e) { return }
	}
	// ATL delegates ScrollView child placement to its display backend.
	if view.kind == 4 {
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

fn ws_draw_background(e voidptr, object voidptr, canvas voidptr) {
	unsafe {
		view := ws_view(e, object)
		width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
		height := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil)
		background := obj(e, object, c'android/view/View', c'getBackground', c'()Landroid/graphics/drawable/Drawable;', nil)
		if background != nil {
			bounds := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: width }, Value{ i: height }]!
			call(e, background, c'android/graphics/drawable/Drawable', c'setBounds', c'(IIII)V', &bounds[0])
			draw := [Value{ l: canvas }]!
			call(e, background, c'android/graphics/drawable/Drawable', c'draw', c'(Landroid/graphics/Canvas;)V', &draw[0])
		}
		if view.background >> 24 != 0 {
			ws_rect(0, 0, f32(width), f32(height), view.background)
		} else if view.kind == 2 && background == nil {
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
		if view.kind == 10 { ws_surface_draw(e, object); return }
		if view.kind == 9 { ws_progress_draw(e, object); return }
		if view.kind == 5 {
			ws_draw_image(e, object)
			return
		}
		if view.kind == 6 {
			width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
			layout := ws_text_layout(view.text, view.size, width - 6, view.font)
			ws_layout_draw(layout, view.color, 3, view.size)
			ws_layout_free(layout)
			return
		}
		if (view.kind < 1 || view.kind > 3) && view.kind != 7 && view.kind != 8 { return }
		width := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
		height := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil)
		if view.kind == 1 {
			content_width := width - view.padding_left - view.padding_right - 6
			layout := ws_text_layout(view.text, view.size, if view.single_line { 0 } else if content_width > 0 { content_width } else { 1 }, view.font)
			gravity := integer(e, object, c'android/widget/TextView', c'getGravity', c'()I', nil)
			alignment := integer(e, object, c'android/view/View', c'getTextAlignment', c'()I', nil)
			mut lines := (&WsTextLayout(layout)).count
			if view.max_lines > 0 && lines > view.max_lines { lines = view.max_lines }
			block_height := view.size * (1.5 + f32(lines - 1) * 1.25)
			available := height - view.padding_top - view.padding_bottom
			extra := if f32(available) > block_height { f32(available) - block_height } else { f32(0) }
			y := f32(view.padding_top) + view.size + if gravity & 0x70 == 0x50 { extra } else if gravity & 0x70 == 0x10 { extra / 2 } else { f32(0) }
			for line := i32(0); line < lines; line++ {
				entry := (&WsTextLayout(layout)).lines[line]
				horizontal := if alignment == 4 { i32(1) } else if alignment == 3 || alignment == 6 { i32(5) } else if alignment == 2 || alignment == 5 { i32(3) } else { gravity & 7 }
				x := f32(view.padding_left + 3) + if horizontal == 1 { (f32(content_width) - entry.width) / 2 } else if horizontal == 5 { f32(content_width) - entry.width } else { f32(0) }
				text := (&WsTextLayout(layout)).text
				end := text[entry.end]
				text[entry.end] = 0
				ws_text(&text[entry.start], x, y + f32(line) * view.size * 1.25, view.size, view.color, view.font)
				text[entry.end] = end
			}
			ws_layout_free(layout)
			return
		}
		text_width := ws_text_width(view.text, view.size, view.font)
		if view.kind == 7 || view.kind == 8 {
			left := f32(view.padding_left + 3)
			top := (f32(height) - 18) / 2
			ws_rect(left, top, left + 18, top + 18, 0xff66736c)
			ws_rect(left + 2, top + 2, left + 16, top + 16, if view.checked { u32(0xff00a884) } else { u32(0xffffffff) })
			if view.checked { ws_rect(left + 6, top + 6, left + 12, top + 12, 0xffffffff) }
		}
		left := if view.kind == 7 || view.kind == 8 {
			f32(view.padding_left + 30)
		} else if view.kind == 2 {
			(f32(width) - text_width) / 2
		} else {
			f32(view.padding_left + 3)
		}
		top := if view.kind == 2 {
			(f32(height) + view.size * 0.65) / 2
		} else {
			f32(view.padding_top) + view.size
		}
		ws_text(view.text, left, top, view.size, view.color, view.font)
		if view.kind == 3 && view.focused {
			ws_rect(left + text_width + 1, top - view.size * 0.8, left + text_width + 2, top + 2, view.color)
		}
	}
}

fn ws_draw_children(e voidptr, object voidptr, canvas voidptr) {
	unsafe {
		// ViewGroup's Java native_drawContent is empty; WebView is a leaf
		// ViewGroup whose content belongs to this renderer.
		if ws_view(e, object).kind == 6 { ws_draw_content(e, object) }
		ws_save()
		ws_translate(-f32(get_int(e, object, c'android/view/View', c'scrollX')), -f32(get_int(e, object, c'android/view/View', c'scrollY')))
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
				ws_translate(f32(left) + ws_view_translation(e, child, c'translationX'), f32(top) + ws_view_translation(e, child, c'translationY'))
				ws_clip(0, 0, f32(width), f32(height))
				draw_args := [Value{ l: canvas }]!
				call(e, child, c'android/view/View', c'vinixDrawLayer', c'(Landroid/graphics/Canvas;)V', &draw_args[0])
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

// dispatchOnPreDraw returns cancellation, the inverse of onPreDraw's result.
// Keep the old front buffer until a later traversal accepts the frame.
fn ws_dispatch_traversal(e voidptr, window voidptr) bool {
	observer := get_object(e, window, c'android/view/Window', c'view_tree_observer', c'Landroid/view/ViewTreeObserver;')
	if pending(e) { return false }
	if observer == unsafe { nil } { return true }
	call(e, observer, c'android/view/ViewTreeObserver', c'dispatchOnGlobalLayout', c'()V', unsafe { nil })
	if pending(e) { return false }
	cancel := boolean(e, observer, c'android/view/ViewTreeObserver', c'dispatchOnPreDraw', c'()Z', unsafe { nil })
	if pending(e) { return false }
	if cancel != 0 {
		ws.dirty = true
		return false
	}
	call(e, observer, c'android/view/ViewTreeObserver', c'dispatchOnDraw', c'()V', unsafe { nil })
	return !pending(e)
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
		ws.animated = false
		for i := i32(0); i < ws.width * ws.height; i++ { ws_root_draw.pixels[i] = 0xfffafafa }
		decor := activity_decor(e, ws.activity)
		window := obj(e, ws.activity, c'android/app/Activity', c'getWindow', c'()Landroid/view/Window;', nil)
		ws_attach_window(e, window, decor)
		if pending(e) { return }
		measure := [Value{ i: ws.width | 0x40000000 }, Value{ i: ws.height | 0x40000000 }]!
		call(e, decor, c'android/view/View', c'measure', c'(II)V', &measure[0])
		if pending(e) { return }
		layout := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: ws.width }, Value{ i: ws.height }]!
		call(e, decor, c'android/view/View', c'layout', c'(IIII)V', &layout[0])
		if pending(e) { return }
		// Layout itself marks the window dirty. Preserve subsequent invalidations
		// from observers and drawing so they request another traversal.
		ws.dirty = false
		if !ws_dispatch_traversal(e, window) { return }
		ws_trace_tree(e, decor)
		args := [Value{ l: ws.canvas }]!
		call(e, decor, c'android/view/View', c'vinixDrawLayer', c'(Landroid/graphics/Canvas;)V', &args[0])
		if pending(e) { return }
		if ws.dialog != nil && !ws_render_dialog(e) { return }
		surface.sequence++
		C.__atomic_store_n(&surface.active, target, 3)
		ws.animation_last = ws_millis()
	}
}

fn ws_debug_tree(e voidptr, view voidptr, depth i32) {
	unsafe {
		if pending(e) || depth > 16 { return }
		class_object := WsRef(slot(e, 31))(e, view)
		name := obj(e, class_object, c'java/lang/Class', c'getName', c'()Ljava/lang/String;', nil)
		chars := ws_utf(e, name)
		C.printf(c'ANDROID-WS-TREE depth=%d class=%s rect=%d,%d,%d,%d visible=%d\n', depth, chars, get_int(e, view, c'android/view/View', c'left'), get_int(e, view, c'android/view/View', c'top'), get_int(e, view, c'android/view/View', c'right'), get_int(e, view, c'android/view/View', c'bottom'), integer(e, view, c'android/view/View', c'getVisibility', c'()I', nil))
		if instance_of(e, view, c'android/view/SurfaceView') {
			native := ws_view(e, view)
			C.printf(c'ANDROID-WS-SURFACE kind=%d window=%p\n', native.kind, native.window)
			ws_dump_surface(e, view)
		}
		if C.strcmp(chars, c'nvv') == 0 {
			C.printf(c'ANDROID-WS-ANIMATION-STATE millis=%ld\n', ws_millis())
			ws_surface_fields_count = 0
			ws_dump_surface_fields(e, view)
		}
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

fn ws_view_translation(e voidptr, view voidptr, name &char) f32 {
	unsafe { return WsFloatField(slot(e, 102))(e, view, field(e, c'android/view/View', name, c'F')) }
}

fn ws_hit(e voidptr, view voidptr, x f32, y f32, depth i32) voidptr {
	unsafe {
		if depth > 64 { return nil }
		if instance_of(e, view, c'android/view/ViewGroup') {
			hit_x := x + f32(get_int(e, view, c'android/view/View', c'scrollX'))
			hit_y := y + f32(get_int(e, view, c'android/view/View', c'scrollY'))
			count := integer(e, view, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
			for i := count - 1; i >= 0; i-- {
				args := &Value(C.alloca(sizeof(Value)))
				args[0] = Value{ i: i }
				child := obj(e, view, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', args)
				if integer(e, child, c'android/view/View', c'getVisibility', c'()I', nil) != 0 {
					continue
				}
				tx, ty := ws_view_translation(e, child, c'translationX'), ws_view_translation(e, child, c'translationY')
				left, top := f32(integer(e, child, c'android/view/View', c'getLeft', c'()I', nil)) + tx, f32(integer(e, child, c'android/view/View', c'getTop', c'()I', nil)) + ty
				right, bottom := f32(integer(e, child, c'android/view/View', c'getRight', c'()I', nil)) + tx, f32(integer(e, child, c'android/view/View', c'getBottom', c'()I', nil)) + ty
				if hit_x >= left && hit_x < right && hit_y >= top && hit_y < bottom {
					return ws_hit(e, child, hit_x - left, hit_y - top, depth + 1)
				}
			}
		}
		return WsRef(slot(e, 25))(e, view)
	}
}

struct WsPoint {
	x f32
	y f32
}

type WsLongCall = fn (voidptr, voidptr, voidptr, &Value) i64

fn ws_local_point(e voidptr, view voidptr, x i32, y i32) WsPoint {
	unsafe {
		mut local_x := f32(x - if ws.dialog == nil { i32(0) } else { ws.dialog_x })
		mut local_y := f32(y - if ws.dialog == nil { i32(0) } else { ws.dialog_y })
		mut node := view
		for depth := 0; depth < 64 && node != nil; depth++ {
			local_x -= f32(integer(e, node, c'android/view/View', c'getLeft', c'()I', nil)) + ws_view_translation(e, node, c'translationX')
			local_y -= f32(integer(e, node, c'android/view/View', c'getTop', c'()I', nil)) + ws_view_translation(e, node, c'translationY')
			parent := obj(e, node, c'android/view/View', c'getParent', c'()Landroid/view/ViewParent;', nil)
			if parent == nil || !instance_of(e, parent, c'android/view/View') { break }
			local_x += f32(get_int(e, parent, c'android/view/View', c'scrollX'))
			local_y += f32(get_int(e, parent, c'android/view/View', c'scrollY'))
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
		ws_put_long(e, event, c'android/view/MotionEvent', c'vinixDownTime', ws.press_time)
		args[0] = Value{ l: event }
		return boolean(e, target, c'android/view/View', c'dispatchTouchEvent', c'(Landroid/view/MotionEvent;)Z', args)
	}
}

fn ws_pointer(e voidptr, event &WsEvent) {
	unsafe {
		if event.kind == 1 || event.kind == 3 {
			if ws.pressed == nil { return }
			ws_motion(e, ws.pressed, if event.kind == 1 { 2 } else { 1 }, event.x, event.y)
			if event.kind == 3 {
				Drop(slot(e, 22))(e, ws.pressed)
				ws.pressed = nil
			}
			ws_mark()
			return
		}
		if event.kind != 2 && event.kind != 5 { return }
		if ws.dialog != nil && (event.x < ws.dialog_x || event.y < ws.dialog_y || event.x >= ws.dialog_x + ws.dialog_width || event.y >= ws.dialog_y + ws.dialog_height) {
			return
		}
		root := if ws.dialog == nil {
			activity_decor(e, ws.activity)
		} else {
			ws_dialog_decor(e, ws.dialog)
		}
		target := ws_hit(e, root, f32(event.x - if ws.dialog == nil { 0 } else { ws.dialog_x }), f32(event.y - if ws.dialog == nil {
			0
		} else {
			ws.dialog_y
		}), 0)
		if target == nil { return }
		if event.kind == 5 { ws_wheel(e, target, event.value); return }
		if ws.pressed != nil {
			ws_motion(e, ws.pressed, 3, event.x, event.y)
			Drop(slot(e, 22))(e, ws.pressed)
			ws.pressed = nil
		}
		ws.press_time = ws_millis()
		if ws_motion(e, root, 0, event.x, event.y) != 0 {
			ws.pressed = WsRef(slot(e, 21))(e, root)
		}
		ws_mark()
	}
}

fn ws_insert_text(e voidptr, bytes &u8, length u32) {
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

fn ws_keys(e voidptr, bytes &u8, length u32) {
	unsafe {
		if length > 4096 { return }
		newline := [u8(10)]!
		mut start := u32(0)
		for i := u32(0); i < length; i++ {
			if bytes[i] != 10 && bytes[i] != 13 { continue }
			if bytes[i] == 10 && i > 0 && bytes[i - 1] == 13 {
				start = i + 1
				continue
			}
			if i > start { ws_insert_text(e, &bytes[start], i - start) }
			start = i + 1
			if ws.focused == nil || pending(e) { return }
			view := ws_view(e, ws.focused)
			if view.kind != 3 { return }
			args := [Value{ i: i32(view.single_line) }]!
			if boolean(e, ws.focused, c'android/widget/TextView', c'vinixEditorEnter', c'(Z)Z', &args[0]) == 0 && !pending(e) {
				ws_insert_text(e, &newline[0], 1)
			}
		}
		if start < length && !pending(e) { ws_insert_text(e, &bytes[start], length - start) }
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
