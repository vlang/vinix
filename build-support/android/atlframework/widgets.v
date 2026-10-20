// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

#include <alloca.h>
fn C.alloca(usize) voidptr

type ArrayLength = fn (voidptr, voidptr) i32
type ArrayObject = fn (voidptr, voidptr, i32) voidptr
type IntRegion = fn (voidptr, voidptr, i32, i32, &i32)
type InstanceOf = fn (voidptr, voidptr, voidptr) u8
type ThrowNew = fn (voidptr, voidptr, &char) i32

fn static_obj(e voidptr, class_name &char, name &char, signature &char, args &Value) voidptr {
    c := cls(e, class_name)
    if c == unsafe { nil } { return unsafe { nil } }
    unsafe {
        m := Member(slot(e, 113))(e, c, name, signature)
        if m == nil { return nil }
        return ObjectCall(slot(e, 116))(e, c, m, args)
    }
}
fn string_value(e voidptr, text &char) voidptr {
    if pending(e) { return unsafe { nil } }
    unsafe { return Lookup(slot(e, 167))(e, text) }
}

fn simple_init(e voidptr, adapter voidptr, layout i32, from voidptr, to voidptr) {
    put_int(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixLayout', layout)
    put_object(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixFrom', c'[Ljava/lang/String;', from)
    put_object(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixTo', c'[I', to)
}
fn simple_new_view(e voidptr, adapter voidptr, context voidptr, _cursor voidptr, parent voidptr) voidptr {
    // JNI returns a local reference, never an alias into its argument vector.
    // Use explicitly bounded stack storage: V otherwise promotes that vector
    // on this pointer-returning path even though JNI never retains it.
    unsafe {
        mut args := &Value(C.alloca(3 * sizeof(Value)))
        args[0] = Value{l: context}
        inflater := static_obj(e, c'android/view/LayoutInflater', c'from', c'(Landroid/content/Context;)Landroid/view/LayoutInflater;', args)
        args[0] = Value{i: get_int(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixLayout')}
        args[1] = Value{l: parent}
        args[2] = Value{i: 0}
        return obj(e, inflater, c'android/view/LayoutInflater', c'inflate', c'(ILandroid/view/ViewGroup;Z)Landroid/view/View;', args)
    }
}
fn simple_set_binder(e voidptr, adapter voidptr, binder voidptr) {
    put_object(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixBinder', c'Landroid/widget/SimpleCursorAdapter$ViewBinder;', binder)
}
fn simple_get_binder(e voidptr, adapter voidptr) voidptr {
    return get_object(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixBinder', c'Landroid/widget/SimpleCursorAdapter$ViewBinder;')
}
fn simple_text(e voidptr, _adapter voidptr, view voidptr, text voidptr) {
    args := [Value{l: text}]!
    call(e, view, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &args[0] })
}
fn simple_bind(e voidptr, adapter voidptr, row voidptr, _context voidptr, cursor voidptr) {
    from := get_object(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixFrom', c'[Ljava/lang/String;')
    to := get_object(e, adapter, c'android/widget/SimpleCursorAdapter', c'vinixTo', c'[I')
    binder := simple_get_binder(e, adapter)
    unsafe {
        count := ArrayLength(slot(e, 171))(e, from)
        destinations := ArrayLength(slot(e, 171))(e, to)
        if count != destinations { throw(e, c'java/lang/IllegalArgumentException', c'from/to column counts differ'); return }
        for index := i32(0); index < count && !pending(e); index++ {
            name := ArrayObject(slot(e, 173))(e, from, index)
            name_args := [Value{l: name}]!
            column := integer(e, cursor, c'android/database/Cursor', c'getColumnIndexOrThrow', c'(Ljava/lang/String;)I', &name_args[0])
            mut id := i32(0)
            IntRegion(slot(e, 203))(e, to, index, 1, &id)
            id_args := [Value{i: id}]!
            view := obj(e, row, c'android/view/View', c'findViewById', c'(I)Landroid/view/View;', &id_args[0])
            if view != nil {
                bind_args := [Value{l: view}, Value{l: cursor}, Value{i: column}]!
                handled := if binder == nil { u8(0) } else { boolean(e, binder, c'android/widget/SimpleCursorAdapter$ViewBinder', c'setViewValue', c'(Landroid/view/View;Landroid/database/Cursor;I)Z', &bind_args[0]) }
                if handled == 0 && !pending(e) {
                    column_args := [Value{i: column}]!
                    text := obj(e, cursor, c'android/database/Cursor', c'getString', c'(I)Ljava/lang/String;', &column_args[0])
                    args := [Value{l: view}, Value{l: text}]!
                    call(e, adapter, c'android/widget/SimpleCursorAdapter', c'setViewText', c'(Landroid/widget/TextView;Ljava/lang/String;)V', &args[0])
                    Drop(slot(e, 23))(e, text)
                }
                Drop(slot(e, 23))(e, view)
            }
            Drop(slot(e, 23))(e, name)
        }
    }
}
fn throw(e voidptr, class_name &char, message &char) {
    c := cls(e, class_name)
    if c != unsafe { nil } { unsafe { ThrowNew(slot(e, 14))(e, c, message) } }
}
fn register_simple_cursor(e voidptr) i32 {
    methods := [
        NativeMethod{c'vinixInit', c'(I[Ljava/lang/String;[I)V', voidptr(simple_init)},
        NativeMethod{c'newView', c'(Landroid/content/Context;Landroid/database/Cursor;Landroid/view/ViewGroup;)Landroid/view/View;', voidptr(simple_new_view)},
        NativeMethod{c'bindView', c'(Landroid/view/View;Landroid/content/Context;Landroid/database/Cursor;)V', voidptr(simple_bind)},
        NativeMethod{c'setViewBinder', c'(Landroid/widget/SimpleCursorAdapter$ViewBinder;)V', voidptr(simple_set_binder)},
        NativeMethod{c'getViewBinder', c'()Landroid/widget/SimpleCursorAdapter$ViewBinder;', voidptr(simple_get_binder)},
        NativeMethod{c'setViewText', c'(Landroid/widget/TextView;Ljava/lang/String;)V', voidptr(simple_text)},
    ]!
    return register(e, c'android/widget/SimpleCursorAdapter', unsafe { &methods[0] }, 6)
}

fn search_edit(e voidptr, search voidptr) voidptr {
    return get_object(e, search, c'android/widget/SearchView', c'vinixEdit', c'Landroid/widget/EditText;')
}
fn search_init(e voidptr, search voidptr, context voidptr) {
    args := [Value{l: context}]!
    edit := new_object(e, c'android/widget/EditText', c'(Landroid/content/Context;)V', unsafe { &args[0] })
    put_object(e, search, c'android/widget/SearchView', c'vinixEdit', c'Landroid/widget/EditText;', edit)
    add_view(e, search, edit)
    callbacks := new_object(e, c'android/widget/VinixSearchCallbacks', c'()V', unsafe { nil })
    put_object(e, callbacks, c'android/widget/VinixSearchCallbacks', c'owner', c'Landroid/widget/SearchView;', search)
    callback_args := [Value{l: callbacks}]!
    call(e, edit, c'android/widget/EditText', c'addTextChangedListener', c'(Landroid/text/TextWatcher;)V', unsafe { &callback_args[0] })
    call(e, edit, c'android/widget/EditText', c'setOnEditorActionListener', c'(Landroid/widget/TextView$OnEditorActionListener;)V', unsafe { &callback_args[0] })
    button := new_object(e, c'android/widget/Button', c'(Landroid/content/Context;)V', unsafe { &args[0] })
    put_object(e, search, c'android/widget/SearchView', c'vinixSubmit', c'Landroid/widget/Button;', button)
    label := [Value{l: string_value(e, c'Search')}]!
    call(e, button, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &label[0] })
    call(e, button, c'android/view/View', c'setOnClickListener', c'(Landroid/view/View$OnClickListener;)V', unsafe { &callback_args[0] })
    add_view(e, search, button)
    visibility(e, button, false)
}
fn search_listener(e voidptr, search voidptr, listener voidptr) {
    put_object(e, search, c'android/widget/SearchView', c'vinixListener', c'Landroid/widget/SearchView$OnQueryTextListener;', listener)
}
fn search_query(e voidptr, search voidptr) voidptr {
    return obj(e, search_edit(e, search), c'android/widget/TextView', c'getText', c'()Ljava/lang/CharSequence;', unsafe { nil })
}
fn search_submit(e voidptr, search voidptr) u8 {
    listener := get_object(e, search, c'android/widget/SearchView', c'vinixListener', c'Landroid/widget/SearchView$OnQueryTextListener;')
    if listener == unsafe { nil } { return 0 }
    query := search_query(e, search)
    text := obj(e, query, c'java/lang/Object', c'toString', c'()Ljava/lang/String;', unsafe { nil })
    args := [Value{l: text}]!
    return boolean(e, listener, c'android/widget/SearchView$OnQueryTextListener', c'onQueryTextSubmit', c'(Ljava/lang/String;)Z', unsafe { &args[0] })
}
fn search_set_query(e voidptr, search voidptr, text voidptr, submit u8) {
    args := [Value{l: text}]!
    call(e, search_edit(e, search), c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &args[0] })
    if submit != 0 { search_submit(e, search) }
}
fn search_ime(e voidptr, search voidptr, options i32) {
    args := [Value{i: options}]!
    call(e, search_edit(e, search), c'android/widget/TextView', c'setImeOptions', c'(I)V', unsafe { &args[0] })
}
fn search_submit_enabled(e voidptr, search voidptr, enabled u8) {
    put_int(e, search, c'android/widget/SearchView', c'vinixSubmitEnabled', i32(enabled))
    visibility(e, get_object(e, search, c'android/widget/SearchView', c'vinixSubmit', c'Landroid/widget/Button;'), enabled != 0)
}
fn search_changed(e voidptr, callback voidptr, _text voidptr) {
    search := get_object(e, callback, c'android/widget/VinixSearchCallbacks', c'owner', c'Landroid/widget/SearchView;')
    listener := get_object(e, search, c'android/widget/SearchView', c'vinixListener', c'Landroid/widget/SearchView$OnQueryTextListener;')
    if listener == unsafe { nil } { return }
    query := search_query(e, search)
    text := obj(e, query, c'java/lang/Object', c'toString', c'()Ljava/lang/String;', unsafe { nil })
    args := [Value{l: text}]!
    boolean(e, listener, c'android/widget/SearchView$OnQueryTextListener', c'onQueryTextChange', c'(Ljava/lang/String;)Z', unsafe { &args[0] })
}
fn search_before(_e voidptr, _callback voidptr, _text voidptr, _start i32, _count i32, _after i32) {}
fn search_during(_e voidptr, _callback voidptr, _text voidptr, _start i32, _before i32, _count i32) {}
fn search_editor(e voidptr, callback voidptr, _view voidptr, _action i32, _event voidptr) u8 {
    return search_submit(e, get_object(e, callback, c'android/widget/VinixSearchCallbacks', c'owner', c'Landroid/widget/SearchView;'))
}
fn search_click(e voidptr, callback voidptr, _view voidptr) {
    search_submit(e, get_object(e, callback, c'android/widget/VinixSearchCallbacks', c'owner', c'Landroid/widget/SearchView;'))
}
fn register_search(e voidptr) i32 {
    methods := [
        NativeMethod{c'vinixInit', c'(Landroid/content/Context;)V', voidptr(search_init)},
        NativeMethod{c'setOnQueryTextListener', c'(Landroid/widget/SearchView$OnQueryTextListener;)V', voidptr(search_listener)},
        NativeMethod{c'getQuery', c'()Ljava/lang/CharSequence;', voidptr(search_query)},
        NativeMethod{c'setQuery', c'(Ljava/lang/CharSequence;Z)V', voidptr(search_set_query)},
        NativeMethod{c'setImeOptions', c'(I)V', voidptr(search_ime)},
        NativeMethod{c'setSubmitButtonEnabled', c'(Z)V', voidptr(search_submit_enabled)},
    ]!
    return register(e, c'android/widget/SearchView', unsafe { &methods[0] }, 6)
}
fn register_search_callbacks(e voidptr) i32 {
    methods := [
        NativeMethod{c'afterTextChanged', c'(Landroid/text/Editable;)V', voidptr(search_changed)},
        NativeMethod{c'beforeTextChanged', c'(Ljava/lang/CharSequence;III)V', voidptr(search_before)},
        NativeMethod{c'onTextChanged', c'(Ljava/lang/CharSequence;III)V', voidptr(search_during)},
        NativeMethod{c'onEditorAction', c'(Landroid/widget/TextView;ILandroid/view/KeyEvent;)Z', voidptr(search_editor)},
        NativeMethod{c'onClick', c'(Landroid/view/View;)V', voidptr(search_click)},
    ]!
    return register(e, c'android/widget/VinixSearchCallbacks', unsafe { &methods[0] }, 5)
}
