// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsBoolField = fn (voidptr, voidptr, voidptr) u8
type WsApplicationException = fn (voidptr) voidptr
type WsApplicationClear = fn (voidptr)
type WsApplicationThrow = fn (voidptr, voidptr) i32

// The primary Activity and lazily started companion services share this path.
// The object monitor serializes startup, with reentry on the main thread
// allowed while providers or Application.onCreate are initializing.
fn ws_ensure_application(e voidptr, loaded voidptr) {
	unsafe {
		if Monitor(slot(e, 217))(e, loaded) != 0 { return }
		defer { Monitor(slot(e, 218))(e, loaded) }
		state := get_int(e, loaded, c'android/atl/ATLLoadedApp', c'vinixApplicationState')
		if state > 0 { return }
		if state < 0 {
			throw(e, c'java/lang/IllegalStateException', c'Application initialization previously failed')
			return
		}
		main := static_obj(e, c'android/os/Looper', c'getMainLooper', c'()Landroid/os/Looper;', nil)
		current := static_obj(e, c'android/os/Looper', c'myLooper', c'()Landroid/os/Looper;', nil)
		if Same(slot(e, 24))(e, main, current) == 0 {
			throw(e, c'java/lang/IllegalStateException', c'Application must start on the main thread')
			return
		}
		put_int(e, loaded, c'android/atl/ATLLoadedApp', c'vinixApplicationState', 1)
		pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
		application := obj(e, loaded, c'android/atl/ATLLoadedApp', c'getApplication', c'()Landroid/app/Application;', nil)
		if !pending(e) { ws_install_providers(e, loaded, pkg, application) }
		if !pending(e) { call(e, application, c'android/app/Application', c'onCreate', c'()V', nil) }
		if pending(e) {
			// JNI field writes require clearing a pending exception. Preserve the
			// original cause and prevent retries against a partially started app.
			failure := WsApplicationException(slot(e, 15))(e)
			WsApplicationClear(slot(e, 17))(e)
			put_int(e, loaded, c'android/atl/ATLLoadedApp', c'vinixApplicationState', -1)
			WsApplicationThrow(slot(e, 13))(e, failure)
			return
		}
		put_int(e, loaded, c'android/atl/ATLLoadedApp', c'vinixApplicationState', 2)
	}
}

fn ws_enabled(e voidptr, info voidptr) bool {
	f := field(e, c'android/content/pm/ComponentInfo', c'enabled', c'Z')
	if f == unsafe { nil } { return false }
	return unsafe { WsBoolField(slot(e, 96))(e, info, f) != 0 }
}

// Providers run on the main thread after Application attachment and before
// Application.onCreate. Keep instances in the framework's GC-owned resolver
// registry, and let initialization exceptions abort startup with their cause.
fn ws_install_providers(e voidptr, loaded voidptr, pkg voidptr, application voidptr) {
	unsafe {
		args := &Value(C.alloca(2 * sizeof(Value)))
		list := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'providers', c'Ljava/util/ArrayList;')
		count := integer(e, list, c'java/util/ArrayList', c'size', c'()I', nil)
		if pending(e) { return }
		if count > 512 {
			throw(e, c'java/lang/IllegalStateException', c'Too many content providers')
			return
		}
		mut providers := [512]voidptr{}
		mut orders := [512]i32{}
		mut size := i32(0)
		app_info := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'applicationInfo', c'Landroid/content/pm/ApplicationInfo;')
		mut process := get_object(e, app_info, c'android/content/pm/ApplicationInfo', c'processName', c'Ljava/lang/String;')
		if process == nil {
			process = get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'packageName', c'Ljava/lang/String;')
			put_object(e, app_info, c'android/content/pm/ApplicationInfo', c'processName', c'Ljava/lang/String;', process)
		}
		for i := i32(0); i < count && !pending(e); i++ {
			args[0] = Value{ i: i }
			provider := obj(e, list, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', args)
			info := get_object(e, provider, c'android/content/pm/PackageParser$Provider', c'info', c'Landroid/content/pm/ProviderInfo;')
			Drop(slot(e, 23))(e, provider)
			if !ws_enabled(e, info) {
				Drop(slot(e, 23))(e, info)
				continue
			}
			requested := get_object(e, info, c'android/content/pm/ComponentInfo', c'processName', c'Ljava/lang/String;')
			mut same_process := true
			if requested != nil && process != nil {
				args[0] = Value{ l: process }
				same_process = boolean(e, requested, c'java/lang/String', c'equals', c'(Ljava/lang/Object;)Z', args) != 0
			}
			if requested != nil { Drop(slot(e, 23))(e, requested) }
			if !same_process {
				Drop(slot(e, 23))(e, info)
				continue
			}
			order := get_int(e, info, c'android/content/pm/ProviderInfo', c'initOrder')
			mut at := size
			for at > 0 && orders[at - 1] < order {
				providers[at] = providers[at - 1]
				orders[at] = orders[at - 1]
				at--
			}
			providers[at] = info
			orders[at] = order
			size++
		}
		if pending(e) { return }
		registry_class := cls(e, c'android/content/ContentProvider')
		registry_field := Member(slot(e, 144))(e, registry_class, c'atl_providers', c'Ljava/util/HashMap;')
		registry := ObjectField(slot(e, 145))(e, registry_class, registry_field)
		for i := i32(0); i < size && !pending(e); i++ {
			push_frame(e)
			info := providers[i]
			name := get_object(e, info, c'android/content/pm/PackageItemInfo', c'name', c'Ljava/lang/String;')
			text := ws_utf(e, name)
			C.printf(c'ANDROID-WS-PROVIDER %s order=%d\n', text, orders[i])
			ws_release(e, name, text)
			args[0] = Value{ l: name }
			class := obj(e, loaded, c'android/atl/ATLLoadedApp', c'loadClass', c'(Ljava/lang/String;)Ljava/lang/Class;', args)
			provider := obj(e, class, c'java/lang/Class', c'newInstance', c'()Ljava/lang/Object;', nil)
			if pending(e) { pop_frame(e); return }
			args[0] = Value{ l: provider }
			wrapper := new_object(e, c'android/atl/ATLProvider', c'(Landroid/content/ContentProvider;)V', args)
			authority := get_object(e, info, c'android/content/pm/ProviderInfo', c'authority', c'Ljava/lang/String;')
			args[0] = Value{ l: ws_string(e, c';') }
			names := obj(e, authority, c'java/lang/String', c'split', c'(Ljava/lang/String;)[Ljava/lang/String;', args)
			for n := i32(0); n < ws_array_len(e, names) && !pending(e); n++ {
				key := WsArrayGet(slot(e, 173))(e, names, n)
				args[0] = Value{ l: key }
				args[1] = Value{ l: wrapper }
				obj(e, registry, c'java/util/HashMap', c'put', c'(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', args)
				Drop(slot(e, 23))(e, key)
			}
			args[0] = Value{ l: application }
			args[1] = Value{ l: info }
			call(e, provider, c'android/content/ContentProvider', c'attachInfo', c'(Landroid/content/Context;Landroid/content/pm/ProviderInfo;)V', args)
			pop_frame(e)
		}
	}
}
