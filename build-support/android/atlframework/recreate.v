// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

type SetupHandles = fn (voidptr)
type StaticVoidCall = fn (voidptr, voidptr, voidptr, &Value)
type PutBoolean = fn (voidptr, voidptr, voidptr, u8)

// The pinned ATL cache starts with these four JNI handles. Validate every
// original method before replacing its lifecycle dispatch entry points.
struct ActivityHandles {
mut:
    class voidptr
    create voidptr
    post_create voidptr
    start voidptr
}

@[export: 'set_up_handle_cache']
pub fn setup_handles(e voidptr) {
    unsafe {
        next := SetupHandles(C.dlsym(voidptr(usize(-1)), c'set_up_handle_cache'))
        if voidptr(next) == nil {
            throw(e, c'java/lang/IllegalStateException', c'ATL Activity handle-cache initializer is unavailable')
            return
        }
        next(e)
        if pending(e) { return }
        mut cache := &ActivityHandles(C.dlsym(nil, c'handle_cache'))
        if cache == nil || cache.create != method(e, c'android/app/Activity', c'onCreate', c'(Landroid/os/Bundle;)V') || cache.post_create != method(e, c'android/app/Activity', c'onPostCreate', c'(Landroid/os/Bundle;)V') || cache.start != method(e, c'android/app/Activity', c'onStart', c'()V') {
            throw(e, c'java/lang/IllegalStateException', c'ATL Activity handle cache ABI differs from the pinned source')
            return
        }
        cache.create = method(e, c'android/app/Activity', c'vinixDispatchCreate', c'(Landroid/os/Bundle;)V')
        cache.post_create = method(e, c'android/app/Activity', c'vinixDispatchPostCreate', c'(Landroid/os/Bundle;)V')
        cache.start = method(e, c'android/app/Activity', c'vinixDispatchStart', c'()V')
    }
}

fn instance_of(e voidptr, object voidptr, class_name &char) bool {
    c := cls(e, class_name)
    if c == unsafe { nil } { return false }
    unsafe {
        result := InstanceOf(slot(e, 32))(e, object, c) != 0
        Drop(slot(e, 23))(e, c)
        return result
    }
}

fn view_text_state(e voidptr, view voidptr, states voidptr, restore bool) {
    if view == unsafe { nil } || pending(e) { return }
    unsafe {
        if FramePush(slot(e, 19))(e, 32) != 0 { return }
        mut args := &Value(C.alloca(2 * sizeof(Value)))
        if instance_of(e, view, c'android/widget/EditText') {
            id := integer(e, view, c'android/view/View', c'getId', c'()I', nil)
            if id > 0 {
                args[0] = Value{i: id}
                if restore {
                    text := obj(e, states, c'android/util/SparseArray', c'get', c'(I)Ljava/lang/Object;', args)
                    if text != nil {
                        args[0] = Value{l: text}
                        call(e, view, c'android/widget/EditText', c'setText', c'(Ljava/lang/CharSequence;)V', args)
                    }
                } else {
                    editable := obj(e, view, c'android/widget/TextView', c'getText', c'()Ljava/lang/CharSequence;', nil)
                    text := obj(e, editable, c'java/lang/Object', c'toString', c'()Ljava/lang/String;', nil)
                    args[1] = Value{l: text}
                    call(e, states, c'android/util/SparseArray', c'put', c'(ILjava/lang/Object;)V', args)
                }
            }
        }
        if instance_of(e, view, c'android/view/ViewGroup') {
            count := integer(e, view, c'android/view/ViewGroup', c'getChildCount', c'()I', nil)
            for index := i32(0); index < count && !pending(e); index++ {
                args[0] = Value{i: index}
                child := obj(e, view, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', args)
                view_text_state(e, child, states, restore)
                Drop(slot(e, 23))(e, child)
            }
        }
        FramePop(slot(e, 20))(e, nil)
    }
}

fn activity_decor(e voidptr, activity voidptr) voidptr {
    window := obj(e, activity, c'android/app/Activity', c'getWindow', c'()Landroid/view/Window;', unsafe { nil })
    return obj(e, window, c'android/view/Window', c'getDecorView', c'()Landroid/view/View;', unsafe { nil })
}
fn activity_restore(e voidptr, activity voidptr, _bundle voidptr) {
    views := get_object(e, activity, c'android/app/Activity', c'vinixSavedViews', c'Landroid/util/SparseArray;')
    if views != unsafe { nil } { view_text_state(e, activity_decor(e, activity), views, true) }
}
fn dispatch_create(e voidptr, activity voidptr, incoming voidptr) {
    saved := get_object(e, activity, c'android/app/Activity', c'vinixSavedState', c'Landroid/os/Bundle;')
    args := [Value{l: if saved == unsafe { nil } { incoming } else { saved }}]!
    call(e, activity, c'android/app/Activity', c'onCreate', c'(Landroid/os/Bundle;)V', unsafe { &args[0] })
}
fn dispatch_post_create(e voidptr, activity voidptr, _incoming voidptr) {
    put_int(e, activity, c'android/app/Activity', c'vinixPostCreatePending', 1)
}
fn dispatch_start(e voidptr, activity voidptr) {
    call(e, activity, c'android/app/Activity', c'onStart', c'()V', unsafe { nil })
    saved := get_object(e, activity, c'android/app/Activity', c'vinixSavedState', c'Landroid/os/Bundle;')
    args := [Value{l: saved}]!
    if saved != unsafe { nil } { call(e, activity, c'android/app/Activity', c'onRestoreInstanceState', c'(Landroid/os/Bundle;)V', unsafe { &args[0] }) }
    if get_int(e, activity, c'android/app/Activity', c'vinixPostCreatePending') != 0 {
        call(e, activity, c'android/app/Activity', c'onPostCreate', c'(Landroid/os/Bundle;)V', unsafe { &args[0] })
        put_int(e, activity, c'android/app/Activity', c'vinixPostCreatePending', 0)
    }
    put_object(e, activity, c'android/app/Activity', c'vinixSavedState', c'Landroid/os/Bundle;', unsafe { nil })
    put_object(e, activity, c'android/app/Activity', c'vinixSavedViews', c'Landroid/util/SparseArray;', unsafe { nil })
}

fn activity_recreate(e voidptr, activity voidptr) {
    bundle := new_object(e, c'android/os/Bundle', c'()V', unsafe { nil })
    args := [Value{l: bundle}]!
    call(e, activity, c'android/app/Activity', c'onSaveInstanceState', c'(Landroid/os/Bundle;)V', unsafe { &args[0] })
    views := new_object(e, c'android/util/SparseArray', c'()V', unsafe { nil })
    view_text_state(e, activity_decor(e, activity), views, false)
    class := unsafe { GetObjectClass(slot(e, 31))(e, activity) }
    name := obj(e, class, c'java/lang/Class', c'getName', c'()Ljava/lang/String;', unsafe { nil })
    window := obj(e, activity, c'android/app/Activity', c'getWindow', c'()Landroid/view/Window;', unsafe { nil })
    intent := obj(e, activity, c'android/app/Activity', c'getIntent', c'()Landroid/content/Intent;', unsafe { nil })
    create_args := [Value{l: name}, Value{j: get_long(e, window, c'android/view/Window', c'native_window')}, Value{l: intent}]!
    next := static_obj(e, c'android/app/Activity', c'internalCreateActivity', c'(Ljava/lang/String;JLandroid/content/Intent;)Landroid/app/Activity;', unsafe { &create_args[0] })
    if pending(e) || next == unsafe { nil } { return }
    put_object(e, next, c'android/app/Activity', c'vinixSavedState', c'Landroid/os/Bundle;', bundle)
    put_object(e, next, c'android/app/Activity', c'vinixSavedViews', c'Landroid/util/SparseArray;', views)
    put_object(e, next, c'android/app/Activity', c'resultActivity', c'Landroid/app/Activity;', get_object(e, activity, c'android/app/Activity', c'resultActivity', c'Landroid/app/Activity;'))
    put_int(e, next, c'android/app/Activity', c'resultRequestCode', get_int(e, activity, c'android/app/Activity', c'resultRequestCode'))
    task := new_object(e, c'android/app/VinixRecreate', c'()V', unsafe { nil })
    put_object(e, task, c'android/app/VinixRecreate', c'old', c'Landroid/app/Activity;', activity)
    put_object(e, task, c'android/app/VinixRecreate', c'next', c'Landroid/app/Activity;', next)
    looper := static_obj(e, c'android/os/Looper', c'getMainLooper', c'()Landroid/os/Looper;', unsafe { nil })
    looper_args := [Value{l: looper}]!
    handler := new_object(e, c'android/os/Handler', c'(Landroid/os/Looper;)V', unsafe { &looper_args[0] })
    task_args := [Value{l: task}]!
    if boolean(e, handler, c'android/os/Handler', c'post', c'(Ljava/lang/Runnable;)Z', unsafe { &task_args[0] }) != 0 {
        f := field(e, c'android/app/Activity', c'finishing', c'Z')
        unsafe { PutBoolean(slot(e, 105))(e, activity, f, 1) }
    }
}
fn recreate_run(e voidptr, task voidptr) {
    old := get_object(e, task, c'android/app/VinixRecreate', c'old', c'Landroid/app/Activity;')
    next := get_object(e, task, c'android/app/VinixRecreate', c'next', c'Landroid/app/Activity;')
    finish_args := [Value{j: 0}]!
    call(e, old, c'android/app/Activity', c'nativeFinish', c'(J)V', unsafe { &finish_args[0] })
    c := cls(e, c'android/app/Activity')
    if c == unsafe { nil } { return }
    unsafe {
        m := Member(slot(e, 113))(e, c, c'nativeStartActivity', c'(Landroid/app/Activity;)V')
        args := [Value{l: next}]!
        if m != nil { StaticVoidCall(slot(e, 143))(e, c, m, &args[0]) }
    }
    put_object(e, task, c'android/app/VinixRecreate', c'old', c'Landroid/app/Activity;', unsafe { nil })
    put_object(e, task, c'android/app/VinixRecreate', c'next', c'Landroid/app/Activity;', unsafe { nil })
}
type GetObjectClass = fn (voidptr, voidptr) voidptr

fn register_recreate(e voidptr) i32 {
    methods := [NativeMethod{c'run', c'()V', voidptr(recreate_run)}]!
    return register(e, c'android/app/VinixRecreate', unsafe { &methods[0] }, 1)
}
