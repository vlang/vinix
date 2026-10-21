// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

type Monitor = fn (voidptr, voidptr) i32

// A persistent handler makes removeCallbacks cancel the same queue entries
// that postDelayed creates. Keep its lifetime owned by the Java View.
fn view_handler(e voidptr, view voidptr) voidptr {
    unsafe {
        if Monitor(slot(e, 217))(e, view) != 0 { return nil }
        mut handler := get_object(e, view, c'android/view/View', c'vinixHandler', c'Landroid/os/Handler;')
        if handler == nil && !pending(e) {
            mut args := &Value(C.alloca(sizeof(Value)))
            args[0] = Value{l: static_obj(e, c'android/os/Looper', c'getMainLooper', c'()Landroid/os/Looper;', nil)}
            handler = new_object(e, c'android/os/Handler', c'(Landroid/os/Looper;)V', args)
            put_object(e, view, c'android/view/View', c'vinixHandler', c'Landroid/os/Handler;', handler)
        }
        Monitor(slot(e, 218))(e, view)
        return handler
    }
}

fn view_post(e voidptr, view voidptr, task voidptr) u8 {
    handler := view_handler(e, view)
    args := [Value{l: task}]!
    return boolean(e, handler, c'android/os/Handler', c'post', c'(Ljava/lang/Runnable;)Z', unsafe { &args[0] })
}

fn view_post_delayed(e voidptr, view voidptr, task voidptr, delay i64) u8 {
    handler := view_handler(e, view)
    args := [Value{l: task}, Value{j: delay}]!
    return boolean(e, handler, c'android/os/Handler', c'postDelayed', c'(Ljava/lang/Runnable;J)Z', unsafe { &args[0] })
}

fn view_remove_callbacks(e voidptr, view voidptr, task voidptr) u8 {
    handler := get_object(e, view, c'android/view/View', c'vinixHandler', c'Landroid/os/Handler;')
    if handler != unsafe { nil } && task != unsafe { nil } {
        args := [Value{l: task}]!
        call(e, handler, c'android/os/Handler', c'removeCallbacks', c'(Ljava/lang/Runnable;)V', unsafe { &args[0] })
    }
    return if pending(e) { u8(0) } else { u8(1) }
}

fn list_item_click(e voidptr, listener voidptr, parent voidptr, view voidptr, position i32, id i64) {
    activity := get_object(e, listener, c'android/app/ListActivity$2', c'this$0', c'Landroid/app/ListActivity;')
    args := [Value{l: parent}, Value{l: view}, Value{i: position}, Value{j: id}]!
    call(e, activity, c'android/app/ListActivity', c'onListItemClick', c'(Landroid/widget/ListView;Landroid/view/View;IJ)V', unsafe { &args[0] })
}

fn view_raw_direction(e voidptr, view voidptr) i32 {
    stored := get_int(e, view, c'android/view/View', c'vinixRawDirection')
    return if stored == 0 { i32(2) } else { stored - 1 }
}

// Resolve on demand so changing an ancestor's direction cannot leave cached
// descendants stale. An unattached inheriting View has no resolved direction.
fn view_resolved_direction(e voidptr, view voidptr) i32 {
    unsafe {
        if FramePush(slot(e, 19))(e, 32) != 0 { return -1 }
        mut current := view
        mut owned := false
        mut result := i32(-1)
        for depth := 0; depth < 256 && !pending(e); depth++ {
            raw := view_raw_direction(e, current)
            if raw == 0 || raw == 1 { result = raw; break }
            if raw == 3 {
                context := obj(e, current, c'android/view/View', c'getContext', c'()Landroid/content/Context;', nil)
                resources := obj(e, context, c'android/content/Context', c'getResources', c'()Landroid/content/res/Resources;', nil)
                config := obj(e, resources, c'android/content/res/Resources', c'getConfiguration', c'()Landroid/content/res/Configuration;', nil)
                result = integer(e, config, c'android/content/res/Configuration', c'getLayoutDirection', c'()I', nil)
                break
            }
            parent := get_object(e, current, c'android/view/View', c'parent', c'Landroid/view/ViewParent;')
            if parent == nil || !instance_of(e, parent, c'android/view/View') { break }
            if owned { Drop(slot(e, 23))(e, current) }
            current = parent
            owned = true
        }
        FramePop(slot(e, 20))(e, nil)
        return result
    }
}

fn view_direction(e voidptr, view voidptr) i32 {
    resolved := view_resolved_direction(e, view)
    return if resolved < 0 { i32(0) } else { resolved }
}

fn view_can_resolve_direction(e voidptr, view voidptr) u8 {
    return u8(view_resolved_direction(e, view) >= 0 && !pending(e))
}

fn view_set_direction(e voidptr, view voidptr, direction i32) {
    if direction < 0 || direction > 3 {
        throw(e, c'java/lang/IllegalArgumentException', c'Invalid layout direction')
        return
    }
    put_int(e, view, c'android/view/View', c'vinixRawDirection', direction + 1)
    params := get_object(e, view, c'android/view/View', c'layout_params', c'Landroid/view/ViewGroup$LayoutParams;')
    if params != unsafe { nil } {
        args := [Value{i: view_direction(e, view)}]!
        call(e, params, c'android/view/ViewGroup$LayoutParams', c'resolveLayoutDirection', c'(I)V', unsafe { &args[0] })
    }
    call(e, view, c'android/view/View', c'requestLayout', c'()V', unsafe { nil })
    call(e, view, c'android/view/View', c'invalidate', c'()V', unsafe { nil })
}

fn register_view(e voidptr) i32 {
    methods := [
        NativeMethod{c'post', c'(Ljava/lang/Runnable;)Z', voidptr(view_post)},
        NativeMethod{c'postDelayed', c'(Ljava/lang/Runnable;J)Z', voidptr(view_post_delayed)},
        NativeMethod{c'removeCallbacks', c'(Ljava/lang/Runnable;)Z', voidptr(view_remove_callbacks)},
        NativeMethod{c'getLayoutDirection', c'()I', voidptr(view_direction)},
        NativeMethod{c'getRawLayoutDirection', c'()I', voidptr(view_raw_direction)},
        NativeMethod{c'setLayoutDirection', c'(I)V', voidptr(view_set_direction)},
        NativeMethod{c'canResolveLayoutDirection', c'()Z', voidptr(view_can_resolve_direction)},
        NativeMethod{c'isLayoutDirectionResolved', c'()Z', voidptr(view_can_resolve_direction)},
    ]!
    return register(e, c'android/view/View', unsafe { &methods[0] }, 8)
}

fn register_list_click(e voidptr) i32 {
    methods := [NativeMethod{c'onItemClick', c'(Landroid/widget/AdapterView;Landroid/view/View;IJ)V', voidptr(list_item_click)}]!
    return register(e, c'android/app/ListActivity$2', unsafe { &methods[0] }, 1)
}

type GtkAdjustmentGet = fn (voidptr) f64
type GtkAdjustmentSet = fn (voidptr, f64)

fn scroll_position(e voidptr, view voidptr, horizontal bool) i32 {
    widget := get_long(e, view, c'android/view/View', c'widget')
    if pending(e) { return 0 }
    unsafe {
        getter := if horizontal { &char(c'gtk_scrolled_window_get_hadjustment') } else { &char(c'gtk_scrolled_window_get_vadjustment') }
        adjustment := GtkGet(C.dlsym(nil, getter))(voidptr(widget))
        return i32(GtkAdjustmentGet(C.dlsym(nil, c'gtk_adjustment_get_value'))(adjustment))
    }
}
fn scroll_x(e voidptr, view voidptr) i32 { return scroll_position(e, view, true) }
fn scroll_y(e voidptr, view voidptr) i32 { return scroll_position(e, view, false) }
fn scroll_to(e voidptr, view voidptr, x i32, y i32) {
    widget := get_long(e, view, c'android/view/View', c'widget')
    if pending(e) { return }
    unsafe {
        horizontal := GtkGet(C.dlsym(nil, c'gtk_scrolled_window_get_hadjustment'))(voidptr(widget))
        vertical := GtkGet(C.dlsym(nil, c'gtk_scrolled_window_get_vadjustment'))(voidptr(widget))
        set := GtkAdjustmentSet(C.dlsym(nil, c'gtk_adjustment_set_value'))
        set(horizontal, f64(x))
        set(vertical, f64(y))
    }
    put_int(e, view, c'android/view/View', c'scrollX', scroll_x(e, view))
    put_int(e, view, c'android/view/View', c'scrollY', scroll_y(e, view))
}
fn register_scroll(e voidptr) i32 {
    methods := [
        NativeMethod{c'scrollTo', c'(II)V', voidptr(scroll_to)},
        NativeMethod{c'smoothScrollTo', c'(II)V', voidptr(scroll_to)},
    ]!
    return register(e, c'android/widget/ScrollView', unsafe { &methods[0] }, 2)
}
