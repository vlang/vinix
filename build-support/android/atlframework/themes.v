// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

fn context_theme(e voidptr, context voidptr) voidptr {
    existing := get_object(e, context, c'android/app/ContextImpl', c'mTheme', c'Landroid/content/res/Resources$Theme;')
    if existing != unsafe { nil } { return existing }
    resources := get_object(e, context, c'android/app/ContextImpl', c'resources', c'Landroid/content/res/Resources;')
    theme := obj(e, resources, c'android/content/res/Resources', c'newTheme', c'()Landroid/content/res/Resources$Theme;', unsafe { nil })
    put_object(e, context, c'android/app/ContextImpl', c'mTheme', c'Landroid/content/res/Resources$Theme;', theme)
    loaded := get_object(e, context, c'android/app/ContextImpl', c'atl_loaded_app', c'Landroid/atl/ATLLoadedApp;')
    sdk := if loaded == unsafe { nil } { i32(7) } else { get_int(e, loaded, c'android/atl/ATLLoadedApp', c'effective_sdk_compat') }
    unsafe {
        mut args := &Value(C.alloca(2 * sizeof(Value)))
        args[0] = Value{i: 0}
        args[1] = Value{i: sdk}
        c := cls(e, c'android/content/res/Resources')
        m := Member(slot(e, 113))(e, c, c'selectDefaultTheme', c'(II)I')
        if m == nil { return nil }
        default_style := IntCall(slot(e, 131))(e, c, m, args)
        args[0] = Value{i: default_style}
        args[1] = Value{i: 1}
        call(e, theme, c'android/content/res/Resources$Theme', c'applyStyle', c'(IZ)V', args)
        style := get_int(e, context, c'android/app/ContextImpl', c'mThemeResource')
        if style != 0 {
            args[0] = Value{i: style}
            call(e, theme, c'android/content/res/Resources$Theme', c'applyStyle', c'(IZ)V', args)
        }
        return theme
    }
}

fn register_theme(e voidptr) i32 {
    methods := [NativeMethod{c'getTheme', c'()Landroid/content/res/Resources$Theme;', voidptr(context_theme)}]!
    return register(e, c'android/app/ContextImpl', unsafe { &methods[0] }, 1)
}
