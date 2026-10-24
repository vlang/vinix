// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

fn ws_checked(e voidptr, object voidptr, checked bool) {
	view := ws_view(e, object)
	if view.checked == checked { return }
	view.checked = checked
	ws_mark()
	call(e, object, c'android/view/View', c'refreshDrawableState', c'()V', unsafe { nil })
	if pending(e) { return }
	if view.broadcasting { return }
	listener := get_object(e, object, c'android/widget/CompoundButton', c'vinixWsCheckedListener', c'Landroid/widget/CompoundButton$OnCheckedChangeListener;')
	if listener == unsafe { nil } { return }
	view.broadcasting = true
	defer { view.broadcasting = false }
	args := [Value{ l: object }, Value{ i: i32(checked) }]!
	call(e, listener, c'android/widget/CompoundButton$OnCheckedChangeListener', c'onCheckedChanged',
		c'(Landroid/widget/CompoundButton;Z)V', unsafe { &args[0] })
}

fn ws_check_listener(e voidptr, object voidptr, listener voidptr) {
	put_object(e, object, c'android/widget/CompoundButton', c'vinixWsCheckedListener',
		c'Landroid/widget/CompoundButton$OnCheckedChangeListener;', listener)
}

fn ws_set_sequence(e voidptr, object voidptr, sequence voidptr) {
	text := if sequence == unsafe { nil } { unsafe { nil } } else {
		obj(e, sequence, c'java/lang/Object', c'toString', c'()Ljava/lang/String;', unsafe { nil })
	}
	if !pending(e) { ws_set_text(e, object, text) }
}
