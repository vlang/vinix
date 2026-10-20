// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

type GtkGet = fn (voidptr) voidptr
type GtkData = fn (voidptr, &char) voidptr
type GtkInsert = fn (voidptr, voidptr, voidptr)
type GtkBool = fn (voidptr, i32)

fn dialog_custom_view(e voidptr, dialog voidptr, view voidptr) {
    // Keep AlertDialog's label/list/button area. Window.setContentView would
    // replace that entire GTK box, detaching the dismiss buttons.
    put_object(e, dialog, c'android/app/AlertDialog', c'vinixCustomView', c'Landroid/view/View;', view)
    window := obj(e, dialog, c'android/app/Dialog', c'getWindow', c'()Landroid/view/Window;', unsafe { nil })
    decor := obj(e, window, c'android/view/Window', c'getDecorView', c'()Landroid/view/View;', unsafe { nil })
    call(e, decor, c'android/view/ViewGroup', c'removeAllViews', c'()V', unsafe { nil })
    if view == unsafe { nil } { return }
    // Dialog.show measures its Java decor tree. Keep the custom view in that
    // tree as well as GTK's box so it receives a real measure/layout pass.
    add_view(e, decor, view)
    ptr := get_long(e, dialog, c'android/app/Dialog', c'nativePtr')
    widget := get_long(e, decor, c'android/view/View', c'widget')
    if pending(e) { return }
    unsafe {
        get_child := GtkGet(C.dlsym(nil, c'gtk_window_get_child'))
        get_parent := GtkGet(C.dlsym(nil, c'gtk_widget_get_parent'))
        get_data := GtkData(C.dlsym(nil, c'g_object_get_data'))
        insert := GtkInsert(C.dlsym(nil, c'gtk_box_insert_child_after'))
        expand := GtkBool(C.dlsym(nil, c'gtk_widget_set_vexpand'))
        content := get_child(voidptr(ptr))
        wrapper := get_parent(voidptr(widget))
        list := get_data(voidptr(ptr), c'list')
        if get_parent(wrapper) == nil { insert(content, wrapper, list) }
        expand(wrapper, 1)
    }
}

fn dialog_button(e voidptr, dialog voidptr, which i32, text voidptr, listener voidptr) {
    which_args := [Value{i: which}]!
    button := obj(e, dialog, c'android/app/AlertDialog', c'getButton', c'(I)Landroid/widget/Button;', unsafe { &which_args[0] })
    text_args := [Value{l: text}]!
    call(e, button, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &text_args[0] })
    callback := new_object(e, c'android/app/VinixDialogClick', c'()V', unsafe { nil })
    put_object(e, callback, c'android/app/VinixDialogClick', c'dialog', c'Landroid/app/AlertDialog;', dialog)
    put_object(e, callback, c'android/app/VinixDialogClick', c'listener', c'Landroid/content/DialogInterface$OnClickListener;', listener)
    put_int(e, callback, c'android/app/VinixDialogClick', c'which', which)
    args := [Value{l: callback}]!
    call(e, button, c'android/view/View', c'setOnClickListener', c'(Landroid/view/View$OnClickListener;)V', unsafe { &args[0] })
    visibility(e, button, true)
}
fn dialog_clicked(e voidptr, callback voidptr, _view voidptr) {
    dialog := get_object(e, callback, c'android/app/VinixDialogClick', c'dialog', c'Landroid/app/AlertDialog;')
    listener := get_object(e, callback, c'android/app/VinixDialogClick', c'listener', c'Landroid/content/DialogInterface$OnClickListener;')
    if listener != unsafe { nil } {
        args := [Value{l: dialog}, Value{i: get_int(e, callback, c'android/app/VinixDialogClick', c'which')}]!
        call(e, listener, c'android/content/DialogInterface$OnClickListener', c'onClick', c'(Landroid/content/DialogInterface;I)V', unsafe { &args[0] })
    }
    call(e, dialog, c'android/app/Dialog', c'dismiss', c'()V', unsafe { nil })
}
fn dialog_builder_view(e voidptr, builder voidptr, view voidptr) voidptr {
    unsafe {
        dialog := get_object(e, builder, c'android/app/AlertDialog$Builder', c'dialog', c'Landroid/app/AlertDialog;')
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{l: view}
        call(e, dialog, c'android/app/AlertDialog', c'setView', c'(Landroid/view/View;)V', args)
        return builder
    }
}
fn dialog_builder_context(e voidptr, builder voidptr) voidptr {
    dialog := get_object(e, builder, c'android/app/AlertDialog$Builder', c'dialog', c'Landroid/app/AlertDialog;')
    return obj(e, dialog, c'android/app/Dialog', c'getContext', c'()Landroid/content/Context;', unsafe { nil })
}
fn dialog_find_view(e voidptr, dialog voidptr, id i32) voidptr {
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{i: id}
        custom := get_object(e, dialog, c'android/app/AlertDialog', c'vinixCustomView', c'Landroid/view/View;')
        if custom != nil {
            found := obj(e, custom, c'android/view/View', c'findViewById', c'(I)Landroid/view/View;', args)
            if found != nil || pending(e) { return found }
        }
        window := obj(e, dialog, c'android/app/Dialog', c'getWindow', c'()Landroid/view/Window;', nil)
        return obj(e, window, c'android/view/Window', c'findViewById', c'(I)Landroid/view/View;', args)
    }
}

fn dialog_native_close(e voidptr, dialog voidptr, ptr i64) {
    // GtkWindow.close emits close-request, whose ATL handler calls dismiss
    // again and destroys the window. Android Dialog objects can be shown
    // repeatedly; hiding avoids recursion and preserves their input widgets.
    args := [Value{i: 0}]!
    call(e, dialog, c'android/app/Dialog', c'setCanceledOnTouchOutside', c'(Z)V', unsafe { &args[0] })
    if !pending(e) { unsafe { GtkBool(C.dlsym(nil, c'gtk_widget_set_visible'))(voidptr(ptr), 0) } }
}
fn register_dialog_native(e voidptr) i32 {
    methods := [NativeMethod{c'nativeClose', c'(J)V', voidptr(dialog_native_close)}]!
    return register(e, c'android/app/Dialog', unsafe { &methods[0] }, 1)
}
fn register_dialog(e voidptr) i32 {
    methods := [
        NativeMethod{c'setButton', c'(ILjava/lang/CharSequence;Landroid/content/DialogInterface$OnClickListener;)V', voidptr(dialog_button)},
        NativeMethod{c'setView', c'(Landroid/view/View;)V', voidptr(dialog_custom_view)},
        NativeMethod{c'findViewById', c'(I)Landroid/view/View;', voidptr(dialog_find_view)},
    ]!
    return register(e, c'android/app/AlertDialog', unsafe { &methods[0] }, 3)
}
fn register_dialog_builder(e voidptr) i32 {
    methods := [
        NativeMethod{c'setView', c'(Landroid/view/View;)Landroid/app/AlertDialog$Builder;', voidptr(dialog_builder_view)},
        NativeMethod{c'getContext', c'()Landroid/content/Context;', voidptr(dialog_builder_context)},
    ]!
    return register(e, c'android/app/AlertDialog$Builder', unsafe { &methods[0] }, 2)
}
fn register_dialog_click(e voidptr) i32 {
    methods := [
        NativeMethod{c'onClick', c'(Landroid/view/View;)V', voidptr(dialog_clicked)},
    ]!
    return register(e, c'android/app/VinixDialogClick', unsafe { &methods[0] }, 1)
}
