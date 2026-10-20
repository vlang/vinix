// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

fn bar_field(e voidptr, bar voidptr, name &char, signature &char) voidptr {
    return get_object(e, bar, c'android/app/ActionBar', name, signature)
}
fn bar_put(e voidptr, bar voidptr, name &char, signature &char, value voidptr) {
    put_object(e, bar, c'android/app/ActionBar', name, signature, value)
}
fn add_view(e voidptr, parent voidptr, child voidptr) {
    args := [Value{l: child}]!
    call(e, parent, c'android/view/ViewGroup', c'addView', c'(Landroid/view/View;)V', unsafe { &args[0] })
}
fn visibility(e voidptr, view voidptr, visible bool) {
    if view == unsafe { nil } { return }
    args := [Value{i: if visible { 0 } else { 8 }}]!
    call(e, view, c'android/view/View', c'setVisibility', c'(I)V', unsafe { &args[0] })
}

fn action_bar(e voidptr, activity voidptr) voidptr {
    mut bar := get_object(e, activity, c'android/app/Activity', c'vinixActionBar', c'Landroid/app/ActionBar;')
    if bar != unsafe { nil } { return bar }
    bar = new_object(e, c'android/app/ActionBar', c'()V', unsafe { nil })
    put_object(e, activity, c'android/app/Activity', c'vinixActionBar', c'Landroid/app/ActionBar;', bar)
    bar_put(e, bar, c'vinixOwner', c'Landroid/app/Activity;', activity)
    put_int(e, bar, c'android/app/ActionBar', c'vinixShowing', 1)
    put_int(e, bar, c'android/app/ActionBar', c'vinixDisplayOptions', 8)
    context_args := [Value{l: activity}]!
    root := new_object(e, c'android/widget/LinearLayout', c'(Landroid/content/Context;)V', unsafe { &context_args[0] })
    header := new_object(e, c'android/widget/LinearLayout', c'(Landroid/content/Context;)V', unsafe { &context_args[0] })
    title := new_object(e, c'android/widget/TextView', c'(Landroid/content/Context;)V', unsafe { &context_args[0] })
    subtitle := new_object(e, c'android/widget/TextView', c'(Landroid/content/Context;)V', unsafe { &context_args[0] })
    vertical := [Value{i: 1}]!
    call(e, root, c'android/widget/LinearLayout', c'setOrientation', c'(I)V', unsafe { &vertical[0] })
    padding := [Value{i: 12}, Value{i: 6}, Value{i: 12}, Value{i: 6}]!
    call(e, header, c'android/view/View', c'setPadding', c'(IIII)V', unsafe { &padding[0] })
    add_view(e, header, title)
    add_view(e, header, subtitle)
    add_view(e, root, header)
    bar_put(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;', header)
    bar_put(e, bar, c'vinixRoot', c'Landroid/view/ViewGroup;', root)
    bar_put(e, bar, c'vinixTitleView', c'Landroid/widget/TextView;', title)
    bar_put(e, bar, c'vinixSubtitleView', c'Landroid/widget/TextView;', subtitle)
    window := obj(e, activity, c'android/app/Activity', c'getWindow', c'()Landroid/view/Window;', unsafe { nil })
    decor := obj(e, window, c'android/view/Window', c'getDecorView', c'()Landroid/view/View;', unsafe { nil })
    zero := [Value{i: 0}]!
    content := obj(e, decor, c'android/view/ViewGroup', c'getChildAt', c'(I)Landroid/view/View;', unsafe { &zero[0] })
    if content != unsafe { nil } {
        remove := [Value{l: content}]!
        call(e, decor, c'android/view/ViewGroup', c'removeView', c'(Landroid/view/View;)V', unsafe { &remove[0] })
        params_args := [Value{i: -1}, Value{i: 0}, Value{f: 1.0}]!
        params := new_object(e, c'android/widget/LinearLayout$LayoutParams', c'(IIF)V', unsafe { &params_args[0] })
        add := [Value{l: content}, Value{l: params}]!
        call(e, root, c'android/view/ViewGroup', c'addView', c'(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V', unsafe { &add[0] })
    }
    add_view(e, decor, root)
    return bar
}

fn set_subtitle(e voidptr, bar voidptr, text voidptr) {
    bar_put(e, bar, c'vinixSubtitle', c'Ljava/lang/CharSequence;', text)
    view := bar_field(e, bar, c'vinixSubtitleView', c'Landroid/widget/TextView;')
    args := [Value{l: text}]!
    call(e, view, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &args[0] })
}
fn set_title(e voidptr, bar voidptr, text voidptr) {
    bar_put(e, bar, c'vinixTitle', c'Ljava/lang/CharSequence;', text)
    view := bar_field(e, bar, c'vinixTitleView', c'Landroid/widget/TextView;')
    args := [Value{l: text}]!
    call(e, view, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &args[0] })
}
fn set_resource_text(e voidptr, bar voidptr, resource i32, subtitle bool) {
    owner := bar_field(e, bar, c'vinixOwner', c'Landroid/app/Activity;')
    argument := Value{i: resource}
    result := obj(e, owner, c'android/content/Context', c'getText', c'(I)Ljava/lang/CharSequence;', unsafe { &argument })
    if subtitle { set_subtitle(e, bar, result) }
    else { set_title(e, bar, result) }
}
fn set_subtitle_resource(e voidptr, bar voidptr, resource i32) { set_resource_text(e, bar, resource, true) }
fn set_title_resource(e voidptr, bar voidptr, resource i32) { set_resource_text(e, bar, resource, false) }
fn get_subtitle(e voidptr, bar voidptr) voidptr { return bar_field(e, bar, c'vinixSubtitle', c'Ljava/lang/CharSequence;') }
fn get_title(e voidptr, bar voidptr) voidptr { return bar_field(e, bar, c'vinixTitle', c'Ljava/lang/CharSequence;') }
fn get_custom(e voidptr, bar voidptr) voidptr { return bar_field(e, bar, c'vinixCustom', c'Landroid/view/View;') }

fn set_custom(e voidptr, bar voidptr, view voidptr) {
    header := bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;')
    old := get_custom(e, bar)
    if old != unsafe { nil } {
        args := [Value{l: old}]!
        call(e, header, c'android/view/ViewGroup', c'removeView', c'(Landroid/view/View;)V', unsafe { &args[0] })
    }
    bar_put(e, bar, c'vinixCustom', c'Landroid/view/View;', view)
    if view != unsafe { nil } {
        add_view(e, header, view)
        visibility(e, view, get_int(e, bar, c'android/app/ActionBar', c'vinixDisplayOptions') & 16 != 0)
    }
}
fn set_custom_resource(e voidptr, bar voidptr, resource i32) {
    owner := bar_field(e, bar, c'vinixOwner', c'Landroid/app/Activity;')
    inflater := obj(e, owner, c'android/app/Activity', c'getLayoutInflater', c'()Landroid/view/LayoutInflater;', unsafe { nil })
    args := [Value{i: resource}, Value{l: bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;')}, Value{i: 0}]!
    view := obj(e, inflater, c'android/view/LayoutInflater', c'inflate', c'(ILandroid/view/ViewGroup;Z)Landroid/view/View;', unsafe { &args[0] })
    set_custom(e, bar, view)
}
fn display_options(e voidptr, bar voidptr, options i32) {
    put_int(e, bar, c'android/app/ActionBar', c'vinixDisplayOptions', options)
    visibility(e, get_custom(e, bar), options & 16 != 0)
    visibility(e, bar_field(e, bar, c'vinixTitleView', c'Landroid/widget/TextView;'), options & 8 != 0)
    visibility(e, bar_field(e, bar, c'vinixSubtitleView', c'Landroid/widget/TextView;'), options & 8 != 0)
}
fn display_options_mask(e voidptr, bar voidptr, options i32, mask i32) {
    current := get_int(e, bar, c'android/app/ActionBar', c'vinixDisplayOptions')
    display_options(e, bar, (current & ~mask) | (options & mask))
}
fn custom_enabled(e voidptr, bar voidptr, enabled u8) { display_options_mask(e, bar, if enabled != 0 { 16 } else { 0 }, 16) }
fn title_enabled(e voidptr, bar voidptr, enabled u8) { display_options_mask(e, bar, if enabled != 0 { 8 } else { 0 }, 8) }
fn up_enabled(e voidptr, bar voidptr, enabled u8) {
    display_options_mask(e, bar, if enabled != 0 { 4 } else { 0 }, 4)
    mut button := bar_field(e, bar, c'vinixBack', c'Landroid/view/View;')
    if button == unsafe { nil } && enabled != 0 {
        owner := bar_field(e, bar, c'vinixOwner', c'Landroid/app/Activity;')
        args := [Value{l: owner}]!
        button = new_object(e, c'android/widget/Button', c'(Landroid/content/Context;)V', unsafe { &args[0] })
        text := [Value{l: string_value(e, c'Back')}]!
        call(e, button, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &text[0] })
        item := new_object(e, c'android/view/VinixMenuItem', c'()V', unsafe { nil })
        put_int(e, item, c'android/view/VinixMenuItem', c'id', 16908332)
        callback := new_object(e, c'android/view/VinixMenuClick', c'()V', unsafe { nil })
        put_object(e, callback, c'android/view/VinixMenuClick', c'owner', c'Landroid/app/Activity;', owner)
        put_object(e, callback, c'android/view/VinixMenuClick', c'item', c'Landroid/view/VinixMenuItem;', item)
        listener := [Value{l: callback}]!
        call(e, button, c'android/view/View', c'setOnClickListener', c'(Landroid/view/View$OnClickListener;)V', unsafe { &listener[0] })
        add_view(e, bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;'), button)
        bar_put(e, bar, c'vinixBack', c'Landroid/view/View;', button)
    }
    visibility(e, button, enabled != 0)
}
fn get_options(e voidptr, bar voidptr) i32 { return get_int(e, bar, c'android/app/ActionBar', c'vinixDisplayOptions') }
fn hide(e voidptr, bar voidptr) {
    put_int(e, bar, c'android/app/ActionBar', c'vinixShowing', 0)
    visibility(e, bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;'), false)
}
fn show(e voidptr, bar voidptr) {
    put_int(e, bar, c'android/app/ActionBar', c'vinixShowing', 1)
    visibility(e, bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;'), true)
}
fn showing(e voidptr, bar voidptr) u8 { return u8(get_int(e, bar, c'android/app/ActionBar', c'vinixShowing')) }

fn register_action_bar(e voidptr) i32 {
    methods := [
        NativeMethod{c'setSubtitle', c'(Ljava/lang/CharSequence;)V', voidptr(set_subtitle)},
        NativeMethod{c'setSubtitle', c'(I)V', voidptr(set_subtitle_resource)},
        NativeMethod{c'getSubtitle', c'()Ljava/lang/CharSequence;', voidptr(get_subtitle)},
        NativeMethod{c'setTitle', c'(Ljava/lang/CharSequence;)V', voidptr(set_title)},
        NativeMethod{c'setTitle', c'(I)V', voidptr(set_title_resource)},
        NativeMethod{c'getTitle', c'()Ljava/lang/CharSequence;', voidptr(get_title)},
        NativeMethod{c'setCustomView', c'(I)V', voidptr(set_custom_resource)},
        NativeMethod{c'setCustomView', c'(Landroid/view/View;)V', voidptr(set_custom)},
        NativeMethod{c'getCustomView', c'()Landroid/view/View;', voidptr(get_custom)},
        NativeMethod{c'setDisplayShowCustomEnabled', c'(Z)V', voidptr(custom_enabled)},
        NativeMethod{c'setDisplayShowTitleEnabled', c'(Z)V', voidptr(title_enabled)},
        NativeMethod{c'setDisplayHomeAsUpEnabled', c'(Z)V', voidptr(up_enabled)},
        NativeMethod{c'setDisplayOptions', c'(I)V', voidptr(display_options)},
        NativeMethod{c'setDisplayOptions', c'(II)V', voidptr(display_options_mask)},
        NativeMethod{c'getDisplayOptions', c'()I', voidptr(get_options)},
        NativeMethod{c'hide', c'()V', voidptr(hide)},
        NativeMethod{c'show', c'()V', voidptr(show)},
        NativeMethod{c'isShowing', c'()Z', voidptr(showing)},
    ]!
    return register(e, c'android/app/ActionBar', unsafe { &methods[0] }, 18)
}
