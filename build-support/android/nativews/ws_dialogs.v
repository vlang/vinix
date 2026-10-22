// SPDX-License-Identifier: GPL-2.0-or-later
// Dialogs are Android view trees composed within the application's WS surface.
@[translated]
module atlframework

fn ws_dialog_decor(e voidptr, dialog voidptr) voidptr {
	window := obj(e, dialog, c'android/app/Dialog', c'getWindow', c'()Landroid/view/Window;', unsafe { nil })
	return obj(e, window, c'android/view/Window', c'getDecorView', c'()Landroid/view/View;', unsafe { nil })
}

fn ws_dialog_node(e voidptr, dialog voidptr, index i32) voidptr {
	unsafe {
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{ i: 0 }
		root := obj(e, ws_dialog_decor(e, dialog), c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', args)
		args[0] = Value{ i: index }
		return obj(e, root, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', args)
	}
}

fn ws_dialog_construct(e voidptr, dialog voidptr) {
	unsafe {
		context := obj(e, dialog, c'android/app/Dialog', c'getContext', c'()Landroid/content/Context;', nil)
		args := [Value{ l: context }]!
		root := new_object(e, c'android/widget/LinearLayout', c'(Landroid/content/Context;)V', &args[0])
		title := new_object(e, c'android/widget/TextView', c'(Landroid/content/Context;)V', &args[0])
		message := new_object(e, c'android/widget/TextView', c'(Landroid/content/Context;)V', &args[0])
		custom := new_object(e, c'android/widget/FrameLayout', c'(Landroid/content/Context;)V', &args[0])
		buttons := new_object(e, c'android/widget/LinearLayout', c'(Landroid/content/Context;)V', &args[0])
		vertical := [Value{ i: 1 }]!
		call(e, root, c'android/widget/LinearLayout', c'setOrientation', c'(I)V', &vertical[0])
		padding := [Value{ i: 16 }, Value{ i: 16 }, Value{ i: 16 }, Value{ i: 16 }]!
		call(e, root, c'android/view/View', c'setPadding', c'(IIII)V', &padding[0])
		add_view(e, root, title)
		add_view(e, root, message)
		add_view(e, root, custom)
		add_view(e, root, buttons)
		array := get_object(e, dialog, c'android/app/AlertDialog', c'buttons', c'[Landroid/widget/Button;')
		for i := i32(0); i < 3; i++ { add_view(e, buttons, WsArrayGet(slot(e, 173))(e, array, i)) }
		content := [Value{ l: root }]!
		call(e, dialog, c'android/app/Dialog', c'setContentView', c'(Landroid/view/View;)V', &content[0])
		visibility(e, title, false)
		visibility(e, message, false)
	}
}

fn ws_dialog_text(e voidptr, dialog voidptr, index i32, text voidptr) {
	if !instance_of(e, dialog, c'android/app/AlertDialog') { return }
	node := ws_dialog_node(e, dialog, index)
	args := [Value{ l: text }]!
	call(e, node, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &args[0] })
	visibility(e, node, text != unsafe { nil })
	ws_mark()
}

fn ws_dialog_set_view(e voidptr, dialog voidptr, view voidptr) {
	put_object(e, dialog, c'android/app/AlertDialog', c'vinixCustomView', c'Landroid/view/View;', view)
	holder := ws_dialog_node(e, dialog, 2)
	call(e, holder, c'android/view/ViewGroup', c'removeAllViews', c'()V', unsafe { nil })
	if view != unsafe { nil } { add_view(e, holder, view) }
	ws_mark()
}

fn ws_dialog_show(e voidptr, dialog voidptr) {
	unsafe {
		if ws.dialog != nil { Drop(slot(e, 22))(e, ws.dialog) }
		ws.dialog = WsRef(slot(e, 21))(e, dialog)
		ws_mark()
	}
}

fn ws_dialog_close(e voidptr, dialog voidptr) {
	unsafe {
		if ws.dialog != nil && Same(slot(e, 24))(e, dialog, ws.dialog) != 0 {
			ws_detach_view(e, ws_dialog_decor(e, dialog))
			Drop(slot(e, 22))(e, ws.dialog)
			ws.dialog = nil
			if ws.focused != nil {
				Drop(slot(e, 22))(e, ws.focused)
				ws.focused = nil
			}
			ws_mark()
		}
	}
}

fn ws_render_dialog(e voidptr) {
	unsafe {
		decor := ws_dialog_decor(e, ws.dialog)
		window := obj(e, ws.dialog, c'android/app/Dialog', c'getWindow', c'()Landroid/view/Window;', nil)
		ws_attach_window(e, window, decor)
		if pending(e) { return }
		measure := [Value{ i: i32(u32(ws.width - 32) + 0x80000000) },
			Value{ i: i32(u32(ws.height - 32) + 0x80000000) }]!
		call(e, decor, c'android/view/View', c'measure', c'(II)V', &measure[0])
		width := integer(e, decor, c'android/view/View', c'getMeasuredWidth', c'()I', nil)
		height := integer(e, decor, c'android/view/View', c'getMeasuredHeight', c'()I', nil)
		ws.dialog_x = (ws.width - width) / 2
		ws.dialog_y = (ws.height - height) / 2
		ws.dialog_width = width
		ws.dialog_height = height
		layout := [Value{ i: 0 }, Value{ i: 0 }, Value{ i: width }, Value{ i: height }]!
		call(e, decor, c'android/view/View', c'layout', c'(IIII)V', &layout[0])
		ws_rect(0, 0, f32(ws.width), f32(ws.height), 0x66000000)
		ws_save()
		ws_translate(f32(ws.dialog_x), f32(ws.dialog_y))
		ws_clip(0, 0, f32(width), f32(height))
		ws_rect(0, 0, f32(width), f32(height), 0xfffafafa)
		args := [Value{ l: ws.canvas }]!
		call(e, decor, c'android/view/View', c'vinixDrawLayer', c'(Landroid/graphics/Canvas;)V', &args[0])
		ws_restore()
	}
}
