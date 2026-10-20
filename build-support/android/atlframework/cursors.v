// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

fn cursor_list(e voidptr, activity voidptr) voidptr {
    mut list := get_object(e, activity, c'android/app/Activity', c'vinixCursors', c'Ljava/util/ArrayList;')
    if list == unsafe { nil } {
        list = new_object(e, c'java/util/ArrayList', c'()V', unsafe { nil })
        put_object(e, activity, c'android/app/Activity', c'vinixCursors', c'Ljava/util/ArrayList;', list)
    }
    return list
}

fn managed_index(e voidptr, list voidptr, cursor voidptr) i32 {
    count := integer(e, list, c'java/util/ArrayList', c'size', c'()I', unsafe { nil })
    for index := i32(0); index < count && !pending(e); index++ {
        args := [Value{i: index}]!
        item := obj(e, list, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', unsafe { &args[0] })
        unsafe {
            same := Same(slot(e, 24))(e, item, cursor)
            Drop(slot(e, 23))(e, item)
            if same != 0 { return index }
        }
    }
    return -1
}

fn manage_cursor(e voidptr, activity voidptr, cursor voidptr) {
    if cursor == unsafe { nil } { return }
    list := cursor_list(e, activity)
    args := [Value{l: cursor}]!
    if managed_index(e, list, cursor) < 0 {
        boolean(e, list, c'java/util/ArrayList', c'add', c'(Ljava/lang/Object;)Z', unsafe { &args[0] })
    }
}

fn unmanage_cursor(e voidptr, activity voidptr, cursor voidptr) {
    list := get_object(e, activity, c'android/app/Activity', c'vinixCursors', c'Ljava/util/ArrayList;')
    if list != unsafe { nil } {
        index := managed_index(e, list, cursor)
        if index >= 0 {
            args := [Value{i: index}]!
            removed := obj(e, list, c'java/util/ArrayList', c'remove', c'(I)Ljava/lang/Object;', unsafe { &args[0] })
            unsafe { Drop(slot(e, 23))(e, removed) }
        }
    }
}

fn update_cursors(e voidptr, activity voidptr, operation i32) {
    list := get_object(e, activity, c'android/app/Activity', c'vinixCursors', c'Ljava/util/ArrayList;')
    if list == unsafe { nil } { return }
    count := integer(e, list, c'java/util/ArrayList', c'size', c'()I', unsafe { nil })
    for index := 0; index < count && !pending(e); index++ {
        args := [Value{i: i32(index)}]!
        cursor := obj(e, list, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', unsafe { &args[0] })
        if operation == 0 {
            call(e, cursor, c'android/database/Cursor', c'deactivate', c'()V', unsafe { nil })
        } else if operation == 1 {
            boolean(e, cursor, c'android/database/Cursor', c'requery', c'()Z', unsafe { nil })
        } else {
            call(e, cursor, c'android/database/Cursor', c'close', c'()V', unsafe { nil })
        }
        unsafe { Drop(slot(e, 23))(e, cursor) }
    }
    if operation == 2 { call(e, list, c'java/util/ArrayList', c'clear', c'()V', unsafe { nil }) }
}

fn activity_stop(e voidptr, activity voidptr) {
    call(e, activity, c'android/app/Activity', c'vinixOriginalOnStop', c'()V', unsafe { nil })
    update_cursors(e, activity, 0)
    put_int(e, activity, c'android/app/Activity', c'vinixCursorsStopped', 1)
}
fn activity_start(e voidptr, activity voidptr) {
    if get_int(e, activity, c'android/app/Activity', c'vinixCursorsStopped') != 0 {
        update_cursors(e, activity, 1)
        put_int(e, activity, c'android/app/Activity', c'vinixCursorsStopped', 0)
    }
    call(e, activity, c'android/app/Activity', c'vinixOriginalOnStart', c'()V', unsafe { nil })
    options_init(e, activity)
}
fn activity_destroy(e voidptr, activity voidptr) {
    update_cursors(e, activity, 2)
    call(e, activity, c'android/app/Activity', c'vinixOriginalOnDestroy', c'()V', unsafe { nil })
}

fn create_main_activity(e voidptr, _class voidptr, name voidptr, window i64, uri voidptr) voidptr {
    unsafe {
        mut args := &Value(C.alloca(3 * sizeof(Value)))
        args[0] = Value{l: name}
        args[1] = Value{j: window}
        args[2] = Value{l: uri}
        activity := static_obj(e, c'android/app/Activity', c'vinixOriginalCreateMainActivity', c'(Ljava/lang/String;JLjava/lang/String;)Landroid/app/Activity;', args)
        if activity == nil || pending(e) { return activity }
        if uri == nil {
            intent := obj(e, activity, c'android/app/Activity', c'getIntent', c'()Landroid/content/Intent;', nil)
            args[0] = Value{l: string_value(e, c'android.intent.action.MAIN')}
            obj(e, intent, c'android/content/Intent', c'setAction', c'(Ljava/lang/String;)Landroid/content/Intent;', args)
            args[0] = Value{l: string_value(e, c'android.intent.category.LAUNCHER')}
            obj(e, intent, c'android/content/Intent', c'addCategory', c'(Ljava/lang/String;)Landroid/content/Intent;', args)
        }
        return activity
    }
}

fn register_activity(e voidptr) i32 {
    methods := [
        NativeMethod{c'getActionBar', c'()Landroid/app/ActionBar;', voidptr(action_bar)},
        NativeMethod{c'startManagingCursor', c'(Landroid/database/Cursor;)V', voidptr(manage_cursor)},
        NativeMethod{c'stopManagingCursor', c'(Landroid/database/Cursor;)V', voidptr(unmanage_cursor)},
        NativeMethod{c'onStart', c'()V', voidptr(activity_start)},
        NativeMethod{c'onStop', c'()V', voidptr(activity_stop)},
        NativeMethod{c'onDestroy', c'()V', voidptr(activity_destroy)},
        NativeMethod{c'createMainActivity', c'(Ljava/lang/String;JLjava/lang/String;)Landroid/app/Activity;', voidptr(create_main_activity)},
        NativeMethod{c'invalidateOptionsMenu', c'()V', voidptr(options_prepare)},
        NativeMethod{c'recreate', c'()V', voidptr(activity_recreate)},
        NativeMethod{c'onRestoreInstanceState', c'(Landroid/os/Bundle;)V', voidptr(activity_restore)},
        NativeMethod{c'vinixDispatchCreate', c'(Landroid/os/Bundle;)V', voidptr(dispatch_create)},
        NativeMethod{c'vinixDispatchPostCreate', c'(Landroid/os/Bundle;)V', voidptr(dispatch_post_create)},
        NativeMethod{c'vinixDispatchStart', c'()V', voidptr(dispatch_start)},
    ]!
    return register(e, c'android/app/Activity', unsafe { &methods[0] }, 13)
}
