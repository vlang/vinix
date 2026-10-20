// SPDX-License-Identifier: GPL-2.0-or-later
module atlframework

fn array_item(e voidptr, list voidptr, index i32) voidptr {
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{i: index}
        return obj(e, list, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', args)
    }
}
fn menu_items(e voidptr, menu voidptr) voidptr { return get_object(e, menu, c'android/view/VinixMenu', c'items', c'Ljava/util/ArrayList;') }
fn menu_owner(e voidptr, menu voidptr) voidptr { return get_object(e, menu, c'android/view/VinixMenu', c'owner', c'Landroid/app/Activity;') }
fn item_menu(e voidptr, item voidptr) voidptr { return get_object(e, item, c'android/view/VinixMenuItem', c'menu', c'Landroid/view/VinixMenu;') }
fn make_menu(e voidptr, owner voidptr) voidptr {
    menu := new_object(e, c'android/view/VinixMenu', c'()V', unsafe { nil })
    items := new_object(e, c'java/util/ArrayList', c'()V', unsafe { nil })
    put_object(e, menu, c'android/view/VinixMenu', c'items', c'Ljava/util/ArrayList;', items)
    put_object(e, menu, c'android/view/VinixMenu', c'owner', c'Landroid/app/Activity;', owner)
    return menu
}
fn menu_add(e voidptr, menu voidptr, group i32, id i32, order i32, title voidptr) voidptr {
    item := new_object(e, c'android/view/VinixMenuItem', c'()V', unsafe { nil })
    put_object(e, item, c'android/view/VinixMenuItem', c'menu', c'Landroid/view/VinixMenu;', menu)
    put_object(e, item, c'android/view/VinixMenuItem', c'title', c'Ljava/lang/CharSequence;', title)
    put_int(e, item, c'android/view/VinixMenuItem', c'id', id)
    put_int(e, item, c'android/view/VinixMenuItem', c'group', group)
    put_int(e, item, c'android/view/VinixMenuItem', c'order', order)
    put_int(e, item, c'android/view/VinixMenuItem', c'visible', 1)
    put_int(e, item, c'android/view/VinixMenuItem', c'enabled', 1)
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{l: item}
        boolean(e, menu_items(e, menu), c'java/util/ArrayList', c'add', c'(Ljava/lang/Object;)Z', args)
    }
    return item
}
fn menu_add_text(e voidptr, menu voidptr, text voidptr) voidptr { return menu_add(e, menu, 0, 0, 0, text) }
fn menu_add_resource(e voidptr, menu voidptr, group i32, id i32, order i32, resource i32) voidptr {
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{i: resource}
        text := obj(e, menu_owner(e, menu), c'android/content/Context', c'getText', c'(I)Ljava/lang/CharSequence;', args)
        return menu_add(e, menu, group, id, order, text)
    }
}
fn menu_add_one_resource(e voidptr, menu voidptr, resource i32) voidptr { return menu_add_resource(e, menu, 0, 0, 0, resource) }
fn menu_sub(e voidptr, menu voidptr, group i32, id i32, order i32, title voidptr) voidptr {
    item := menu_add(e, menu, group, id, order, title)
    child := make_menu(e, menu_owner(e, menu))
    put_object(e, child, c'android/view/VinixMenu', c'item', c'Landroid/view/VinixMenuItem;', item)
    put_object(e, item, c'android/view/VinixMenuItem', c'submenu', c'Landroid/view/VinixMenu;', child)
    return child
}
fn menu_sub_resource(e voidptr, menu voidptr, group i32, id i32, order i32, resource i32) voidptr {
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{i: resource}
        text := obj(e, menu_owner(e, menu), c'android/content/Context', c'getText', c'(I)Ljava/lang/CharSequence;', args)
        return menu_sub(e, menu, group, id, order, text)
    }
}
fn menu_size(e voidptr, menu voidptr) i32 { return integer(e, menu_items(e, menu), c'java/util/ArrayList', c'size', c'()I', unsafe { nil }) }
fn menu_get(e voidptr, menu voidptr, index i32) voidptr { return array_item(e, menu_items(e, menu), index) }
fn menu_find(e voidptr, menu voidptr, id i32) voidptr {
    count := menu_size(e, menu)
    for index := i32(0); index < count && !pending(e); index++ {
        item := menu_get(e, menu, index)
        if get_int(e, item, c'android/view/VinixMenuItem', c'id') == id { return item }
        child := get_object(e, item, c'android/view/VinixMenuItem', c'submenu', c'Landroid/view/VinixMenu;')
        if child != unsafe { nil } {
            found := menu_find(e, child, id)
            if found != unsafe { nil } { return found }
        }
    }
    return unsafe { nil }
}
fn menu_clear(e voidptr, menu voidptr) { call(e, menu_items(e, menu), c'java/util/ArrayList', c'clear', c'()V', unsafe { nil }) }
fn menu_remove(e voidptr, menu voidptr, id i32) {
    count := menu_size(e, menu)
    for index := i32(0); index < count && !pending(e); index++ {
        item := menu_get(e, menu, index)
        if get_int(e, item, c'android/view/VinixMenuItem', c'id') == id {
            args := [Value{i: index}]!
            obj(e, menu_items(e, menu), c'java/util/ArrayList', c'remove', c'(I)Ljava/lang/Object;', unsafe { &args[0] })
            return
        }
    }
}
fn menu_visible(e voidptr, menu voidptr) u8 {
    count := menu_size(e, menu)
    for index := i32(0); index < count && !pending(e); index++ { if item_visible(e, menu_get(e, menu, index)) != 0 { return 1 } }
    return 0
}
fn menu_group_checkable(e voidptr, menu voidptr, group i32, checkable u8, exclusive u8) {
    count := menu_size(e, menu)
    for index := i32(0); index < count && !pending(e); index++ {
        item := menu_get(e, menu, index)
        if get_int(e, item, c'android/view/VinixMenuItem', c'group') == group {
            put_int(e, item, c'android/view/VinixMenuItem', c'checkable', i32(checkable))
            put_int(e, item, c'android/view/VinixMenuItem', c'exclusive', i32(exclusive))
        }
    }
}
fn menu_group_visible(e voidptr, menu voidptr, group i32, visible u8) {
    count := menu_size(e, menu)
    for index := i32(0); index < count && !pending(e); index++ {
        item := menu_get(e, menu, index)
        if get_int(e, item, c'android/view/VinixMenuItem', c'group') == group { item_set_visible(e, item, visible) }
    }
}
fn menu_intent_options(_e voidptr, _menu voidptr, _group i32, _id i32, _order i32, _caller voidptr, _specifics voidptr, _intent voidptr, _flags i32, _out voidptr) i32 {
    // This isolated APK process has no system application resolver or extra
    // installed intent handlers to contribute to the application's menu.
    return 0
}
fn item_shortcut(e voidptr, item voidptr, numeric u16, alphabetic u16) voidptr {
    put_int(e, item, c'android/view/VinixMenuItem', c'numeric', i32(numeric))
    put_int(e, item, c'android/view/VinixMenuItem', c'alphabetic', i32(alphabetic))
    return item
}
fn menu_sub_item(e voidptr, menu voidptr) voidptr { return get_object(e, menu, c'android/view/VinixMenu', c'item', c'Landroid/view/VinixMenuItem;') }
fn item_id(e voidptr, item voidptr) i32 { return get_int(e, item, c'android/view/VinixMenuItem', c'id') }
fn item_group(e voidptr, item voidptr) i32 { return get_int(e, item, c'android/view/VinixMenuItem', c'group') }
fn item_order(e voidptr, item voidptr) i32 { return get_int(e, item, c'android/view/VinixMenuItem', c'order') }
fn item_title(e voidptr, item voidptr) voidptr { return get_object(e, item, c'android/view/VinixMenuItem', c'title', c'Ljava/lang/CharSequence;') }
fn item_condensed(e voidptr, item voidptr) voidptr {
    title := get_object(e, item, c'android/view/VinixMenuItem', c'condensed', c'Ljava/lang/CharSequence;')
    return if title == unsafe { nil } { item_title(e, item) } else { title }
}
fn item_sub(e voidptr, item voidptr) voidptr { return get_object(e, item, c'android/view/VinixMenuItem', c'submenu', c'Landroid/view/VinixMenu;') }
fn item_has_sub(e voidptr, item voidptr) u8 { return if item_sub(e, item) == unsafe { nil } { 0 } else { 1 } }
fn item_action(e voidptr, item voidptr) voidptr { return get_object(e, item, c'android/view/VinixMenuItem', c'action', c'Landroid/view/View;') }
fn item_set_title(e voidptr, item voidptr, title voidptr) voidptr { put_object(e, item, c'android/view/VinixMenuItem', c'title', c'Ljava/lang/CharSequence;', title); return item }
fn item_set_condensed(e voidptr, item voidptr, title voidptr) voidptr { put_object(e, item, c'android/view/VinixMenuItem', c'condensed', c'Ljava/lang/CharSequence;', title); return item }
fn item_title_resource(e voidptr, item voidptr, resource i32) voidptr {
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{i: resource}
        text := obj(e, menu_owner(e, item_menu(e, item)), c'android/content/Context', c'getText', c'(I)Ljava/lang/CharSequence;', args)
        return item_set_title(e, item, text)
    }
}
fn item_set_action(e voidptr, item voidptr, action voidptr) voidptr { put_object(e, item, c'android/view/VinixMenuItem', c'action', c'Landroid/view/View;', action); return item }
fn item_set_listener(e voidptr, item voidptr, listener voidptr) voidptr { put_object(e, item, c'android/view/VinixMenuItem', c'listener', c'Landroid/view/MenuItem$OnMenuItemClickListener;', listener); return item }
fn item_set_expand_listener(e voidptr, item voidptr, listener voidptr) voidptr { put_object(e, item, c'android/view/VinixMenuItem', c'expandListener', c'Landroid/view/MenuItem$OnActionExpandListener;', listener); return item }
fn item_show_action(e voidptr, item voidptr, value i32) { put_int(e, item, c'android/view/VinixMenuItem', c'showAction', value) }
fn item_set_icon(e voidptr, item voidptr, icon voidptr) voidptr { put_object(e, item, c'android/view/VinixMenuItem', c'icon', c'Landroid/graphics/drawable/Drawable;', icon); return item }
fn item_icon_resource(e voidptr, item voidptr, resource i32) voidptr {
    if resource == 0 { return item_set_icon(e, item, unsafe { nil }) }
    unsafe {
        mut args := &Value(C.alloca(sizeof(Value)))
        args[0] = Value{i: resource}
        icon := obj(e, menu_owner(e, item_menu(e, item)), c'android/content/Context', c'getDrawable', c'(I)Landroid/graphics/drawable/Drawable;', args)
        return item_set_icon(e, item, icon)
    }
}
fn item_expanded(e voidptr, item voidptr) u8 { return u8(get_int(e, item, c'android/view/VinixMenuItem', c'expanded')) }
fn item_expand(e voidptr, item voidptr) u8 {
    action := item_action(e, item)
    if action == unsafe { nil } { return 0 }
    owner := menu_owner(e, item_menu(e, item))
    bar := action_bar(e, owner)
    header := bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;')
    if item_expanded(e, item) == 0 { add_view(e, header, action) }
    put_int(e, item, c'android/view/VinixMenuItem', c'expanded', 1)
    return 1
}
fn item_collapse(e voidptr, item voidptr) u8 {
    action := item_action(e, item)
    if action == unsafe { nil } || item_expanded(e, item) == 0 { return 0 }
    bar := action_bar(e, menu_owner(e, item_menu(e, item)))
    args := [Value{l: action}]!
    call(e, bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;'), c'android/view/ViewGroup', c'removeView', c'(Landroid/view/View;)V', unsafe { &args[0] })
    put_int(e, item, c'android/view/VinixMenuItem', c'expanded', 0)
    return 1
}

fn options_init(e voidptr, activity voidptr) {
    existing := get_object(e, activity, c'android/app/Activity', c'vinixMenu', c'Landroid/view/VinixMenu;')
    if existing != unsafe { nil } { return }
    menu := make_menu(e, activity)
    put_object(e, activity, c'android/app/Activity', c'vinixMenu', c'Landroid/view/VinixMenu;', menu)
    args := [Value{l: menu}]!
    created := boolean(e, activity, c'android/app/Activity', c'onCreateOptionsMenu', c'(Landroid/view/Menu;)Z', unsafe { &args[0] })
    if created == 0 || pending(e) { return }
    boolean(e, activity, c'android/app/Activity', c'onPrepareOptionsMenu', c'(Landroid/view/Menu;)Z', unsafe { &args[0] })
    if pending(e) { return }
    bar := action_bar(e, activity)
    intent := obj(e, activity, c'android/app/Activity', c'getIntent', c'()Landroid/content/Intent;', unsafe { nil })
    action := obj(e, intent, c'android/content/Intent', c'getAction', c'()Ljava/lang/String;', unsafe { nil })
    main := [Value{l: action}]!
    if boolean(e, string_value(e, c'android.intent.action.MAIN'), c'java/lang/String', c'equals', c'(Ljava/lang/Object;)Z', unsafe { &main[0] }) == 0 { up_enabled(e, bar, 1) }
    context := [Value{l: activity}]!
    button := new_object(e, c'android/widget/Button', c'(Landroid/content/Context;)V', unsafe { &context[0] })
    text := [Value{l: string_value(e, c'Menu')}]!
    call(e, button, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &text[0] })
    callback := new_object(e, c'android/view/VinixMenuClick', c'()V', unsafe { nil })
    put_object(e, callback, c'android/view/VinixMenuClick', c'owner', c'Landroid/app/Activity;', activity)
    listener := [Value{l: callback}]!
    call(e, button, c'android/view/View', c'setOnClickListener', c'(Landroid/view/View$OnClickListener;)V', unsafe { &listener[0] })
    add_view(e, bar_field(e, bar, c'vinixHeader', c'Landroid/view/ViewGroup;'), button)
    panel := new_object(e, c'android/widget/LinearLayout', c'(Landroid/content/Context;)V', unsafe { &context[0] })
    vertical := [Value{i: 1}]!
    call(e, panel, c'android/widget/LinearLayout', c'setOrientation', c'(I)V', unsafe { &vertical[0] })
    scroll := new_object(e, c'android/widget/ScrollView', c'(Landroid/content/Context;)V', unsafe { &context[0] })
    add_view(e, scroll, panel)
    bar_put(e, bar, c'vinixMenuPanel', c'Landroid/view/ViewGroup;', panel)
    bar_put(e, bar, c'vinixMenuScroll', c'Landroid/view/View;', scroll)
    params_args := [Value{i: -1}, Value{i: 280}]!
    params := new_object(e, c'android/widget/LinearLayout$LayoutParams', c'(II)V', unsafe { &params_args[0] })
    add := [Value{l: scroll}, Value{i: 1}, Value{l: params}]!
    call(e, bar_field(e, bar, c'vinixRoot', c'Landroid/view/ViewGroup;'), c'android/view/ViewGroup', c'addView', c'(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V', unsafe { &add[0] })
    visibility(e, scroll, false)
}
fn options_prepare(e voidptr, activity voidptr) {
    menu := get_object(e, activity, c'android/app/Activity', c'vinixMenu', c'Landroid/view/VinixMenu;')
    if menu == unsafe { nil } { return }
    args := [Value{l: menu}]!
    boolean(e, activity, c'android/app/Activity', c'onPrepareOptionsMenu', c'(Landroid/view/Menu;)Z', unsafe { &args[0] })
}
fn menu_render(e voidptr, owner voidptr, menu voidptr) {
    bar := action_bar(e, owner)
    panel := bar_field(e, bar, c'vinixMenuPanel', c'Landroid/view/ViewGroup;')
    call(e, panel, c'android/view/ViewGroup', c'removeAllViews', c'()V', unsafe { nil })
    count := menu_size(e, menu)
    for index := i32(0); index < count && !pending(e); index++ {
        item := menu_get(e, menu, index)
        if item_visible(e, item) == 0 { continue }
        context := [Value{l: owner}]!
        button := new_object(e, c'android/widget/Button', c'(Landroid/content/Context;)V', unsafe { &context[0] })
        text := [Value{l: item_title(e, item)}]!
        call(e, button, c'android/widget/TextView', c'setText', c'(Ljava/lang/CharSequence;)V', unsafe { &text[0] })
        enabled := [Value{i: i32(item_enabled(e, item))}]!
        call(e, button, c'android/view/View', c'setEnabled', c'(Z)V', unsafe { &enabled[0] })
        click := new_object(e, c'android/view/VinixMenuClick', c'()V', unsafe { nil })
        put_object(e, click, c'android/view/VinixMenuClick', c'owner', c'Landroid/app/Activity;', owner)
        put_object(e, click, c'android/view/VinixMenuClick', c'item', c'Landroid/view/VinixMenuItem;', item)
        listener := [Value{l: click}]!
        call(e, button, c'android/view/View', c'setOnClickListener', c'(Landroid/view/View$OnClickListener;)V', unsafe { &listener[0] })
        add_view(e, panel, button)
    }
    visibility(e, bar_field(e, bar, c'vinixMenuScroll', c'Landroid/view/View;'), true)
}
fn menu_clicked(e voidptr, callback voidptr, _view voidptr) {
    owner := get_object(e, callback, c'android/view/VinixMenuClick', c'owner', c'Landroid/app/Activity;')
    item := get_object(e, callback, c'android/view/VinixMenuClick', c'item', c'Landroid/view/VinixMenuItem;')
    if item == unsafe { nil } {
        bar := action_bar(e, owner)
        scroll := bar_field(e, bar, c'vinixMenuScroll', c'Landroid/view/View;')
        if integer(e, scroll, c'android/view/View', c'getVisibility', c'()I', unsafe { nil }) == 0 {
            visibility(e, scroll, false)
            return
        }
        options_prepare(e, owner)
        menu_render(e, owner, get_object(e, owner, c'android/app/Activity', c'vinixMenu', c'Landroid/view/VinixMenu;'))
        return
    }
    child := item_sub(e, item)
    if child != unsafe { nil } { menu_render(e, owner, child); return }
    bar := action_bar(e, owner)
    visibility(e, bar_field(e, bar, c'vinixMenuScroll', c'Landroid/view/View;'), false)
    if item_action(e, item) != unsafe { nil } { item_expand(e, item); return }
    listener := get_object(e, item, c'android/view/VinixMenuItem', c'listener', c'Landroid/view/MenuItem$OnMenuItemClickListener;')
    args := [Value{l: item}]!
    handled := if listener == unsafe { nil } { u8(0) } else { boolean(e, listener, c'android/view/MenuItem$OnMenuItemClickListener', c'onMenuItemClick', c'(Landroid/view/MenuItem;)Z', unsafe { &args[0] }) }
    selected := if handled == 0 && !pending(e) { boolean(e, owner, c'android/app/Activity', c'onOptionsItemSelected', c'(Landroid/view/MenuItem;)Z', unsafe { &args[0] }) } else { handled }
    if selected == 0 && !pending(e) && item_id(e, item) == 16908332 { call(e, owner, c'android/app/Activity', c'onBackPressed', c'()V', unsafe { nil }) }
    options_prepare(e, owner)
}

fn register_menu(e voidptr) i32 {
    methods := [
        NativeMethod{c'add', c'(IIILjava/lang/CharSequence;)Landroid/view/MenuItem;', voidptr(menu_add)},
        NativeMethod{c'add', c'(IIII)Landroid/view/MenuItem;', voidptr(menu_add_resource)},
        NativeMethod{c'add', c'(Ljava/lang/CharSequence;)Landroid/view/MenuItem;', voidptr(menu_add_text)},
        NativeMethod{c'add', c'(I)Landroid/view/MenuItem;', voidptr(menu_add_one_resource)},
        NativeMethod{c'addSubMenu', c'(IIILjava/lang/CharSequence;)Landroid/view/SubMenu;', voidptr(menu_sub)},
        NativeMethod{c'addSubMenu', c'(IIII)Landroid/view/SubMenu;', voidptr(menu_sub_resource)},
        NativeMethod{c'getItem', c'(I)Landroid/view/MenuItem;', voidptr(menu_get)},
        NativeMethod{c'getItem', c'()Landroid/view/MenuItem;', voidptr(menu_sub_item)},
        NativeMethod{c'findItem', c'(I)Landroid/view/MenuItem;', voidptr(menu_find)},
        NativeMethod{c'clear', c'()V', voidptr(menu_clear)},
        NativeMethod{c'removeItem', c'(I)V', voidptr(menu_remove)},
        NativeMethod{c'size', c'()I', voidptr(menu_size)},
        NativeMethod{c'hasVisibleItems', c'()Z', voidptr(menu_visible)},
        NativeMethod{c'setGroupCheckable', c'(IZZ)V', voidptr(menu_group_checkable)},
        NativeMethod{c'setGroupVisible', c'(IZ)V', voidptr(menu_group_visible)},
        NativeMethod{c'addIntentOptions', c'(IIILandroid/content/ComponentName;[Landroid/content/Intent;Landroid/content/Intent;I[Landroid/view/MenuItem;)I', voidptr(menu_intent_options)},
    ]!
    return register(e, c'android/view/VinixMenu', unsafe { &methods[0] }, 16)
}
fn register_menu_click(e voidptr) i32 {
    methods := [NativeMethod{c'onClick', c'(Landroid/view/View;)V', voidptr(menu_clicked)}]!
    return register(e, c'android/view/VinixMenuClick', unsafe { &methods[0] }, 1)
}

fn item_visible(e voidptr, item voidptr) u8 { return u8(get_int(e, item, c'android/view/VinixMenuItem', c'visible')) }
fn item_set_visible(e voidptr, item voidptr, value u8) voidptr { put_int(e, item, c'android/view/VinixMenuItem', c'visible', i32(value)); return item }

fn item_enabled(e voidptr, item voidptr) u8 { return u8(get_int(e, item, c'android/view/VinixMenuItem', c'enabled')) }
fn item_set_enabled(e voidptr, item voidptr, value u8) voidptr { put_int(e, item, c'android/view/VinixMenuItem', c'enabled', i32(value)); return item }

fn item_checked(e voidptr, item voidptr) u8 { return u8(get_int(e, item, c'android/view/VinixMenuItem', c'checked')) }
fn item_set_checked(e voidptr, item voidptr, value u8) voidptr { put_int(e, item, c'android/view/VinixMenuItem', c'checked', i32(value)); return item }

fn item_checkable(e voidptr, item voidptr) u8 { return u8(get_int(e, item, c'android/view/VinixMenuItem', c'checkable')) }
fn item_set_checkable(e voidptr, item voidptr, value u8) voidptr { put_int(e, item, c'android/view/VinixMenuItem', c'checkable', i32(value)); return item }

fn register_menu_item(e voidptr) i32 {
    methods := [
        NativeMethod{c'isVisible', c'()Z', voidptr(item_visible)},
        NativeMethod{c'setVisible', c'(Z)Landroid/view/MenuItem;', voidptr(item_set_visible)},
        NativeMethod{c'isEnabled', c'()Z', voidptr(item_enabled)},
        NativeMethod{c'setEnabled', c'(Z)Landroid/view/MenuItem;', voidptr(item_set_enabled)},
        NativeMethod{c'isChecked', c'()Z', voidptr(item_checked)},
        NativeMethod{c'setChecked', c'(Z)Landroid/view/MenuItem;', voidptr(item_set_checked)},
        NativeMethod{c'isCheckable', c'()Z', voidptr(item_checkable)},
        NativeMethod{c'setCheckable', c'(Z)Landroid/view/MenuItem;', voidptr(item_set_checkable)},
        NativeMethod{c'getItemId', c'()I', voidptr(item_id)},
        NativeMethod{c'getGroupId', c'()I', voidptr(item_group)},
        NativeMethod{c'getOrder', c'()I', voidptr(item_order)},
        NativeMethod{c'getTitle', c'()Ljava/lang/CharSequence;', voidptr(item_title)},
        NativeMethod{c'getTitleCondensed', c'()Ljava/lang/CharSequence;', voidptr(item_condensed)},
        NativeMethod{c'setTitle', c'(Ljava/lang/CharSequence;)Landroid/view/MenuItem;', voidptr(item_set_title)},
        NativeMethod{c'setTitle', c'(I)Landroid/view/MenuItem;', voidptr(item_title_resource)},
        NativeMethod{c'setTitleCondensed', c'(Ljava/lang/CharSequence;)Landroid/view/MenuItem;', voidptr(item_set_condensed)},
        NativeMethod{c'setIcon', c'(I)Landroid/view/MenuItem;', voidptr(item_icon_resource)},
        NativeMethod{c'setIcon', c'(Landroid/graphics/drawable/Drawable;)Landroid/view/MenuItem;', voidptr(item_set_icon)},
        NativeMethod{c'setShowAsAction', c'(I)V', voidptr(item_show_action)},
        NativeMethod{c'setOnMenuItemClickListener', c'(Landroid/view/MenuItem$OnMenuItemClickListener;)Landroid/view/MenuItem;', voidptr(item_set_listener)},
        NativeMethod{c'setActionView', c'(Landroid/view/View;)Landroid/view/MenuItem;', voidptr(item_set_action)},
        NativeMethod{c'getActionView', c'()Landroid/view/View;', voidptr(item_action)},
        NativeMethod{c'getSubMenu', c'()Landroid/view/SubMenu;', voidptr(item_sub)},
        NativeMethod{c'hasSubMenu', c'()Z', voidptr(item_has_sub)},
        NativeMethod{c'setOnActionExpandListener', c'(Landroid/view/MenuItem$OnActionExpandListener;)Landroid/view/MenuItem;', voidptr(item_set_expand_listener)},
        NativeMethod{c'expandActionView', c'()Z', voidptr(item_expand)},
        NativeMethod{c'collapseActionView', c'()Z', voidptr(item_collapse)},
        NativeMethod{c'isActionViewExpanded', c'()Z', voidptr(item_expanded)},
        NativeMethod{c'setShortcut', c'(CC)Landroid/view/MenuItem;', voidptr(item_shortcut)},
    ]!
    return register(e, c'android/view/VinixMenuItem', unsafe { &methods[0] }, 29)
}
