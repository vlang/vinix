// SPDX-License-Identifier: GPL-2.0-or-later
// Enumerate the locales present in the manager's loaded resource tables.
@[translated]
module atlframework

#include "androidfw_c_api.h"

fn C.AssetManager_getLocales(voidptr, bool, bool) &&char

type WsLocaleArrayDelete = fn (voidptr)

fn ws_locale_vector_delete(locales &&char, release WsLocaleArrayDelete) {
	unsafe {
		mut index := usize(0)
		for locales[index] != nil {
			C.free(locales[index])
			index++
		}
		// The C API allocates the vector with new[] and its strings with strdup.
		release(voidptr(locales))
	}
}

fn ws_asset_locales(e voidptr, object voidptr) voidptr {
	unsafe {
		if e == nil || pending(e) { return nil }
		manager := ws_manager(e, object)
		if pending(e) { return nil }
		if manager == nil {
			throw(e, c'java/lang/IllegalStateException', c'AssetManager is not initialized')
			return nil
		}
		// libandroidfw already depends on this C++ runtime. Resolve its matching
		// array deallocator before obtaining any owned storage from the C API.
		release := C.dlsym(nil, c'_ZdaPv')
		if release == nil {
			throw(e, c'java/lang/UnsatisfiedLinkError', c'C++ locale array deallocator is unavailable')
			return nil
		}
		ws_resources_enter(manager)
		locales := C.AssetManager_getLocales(manager, false, true)
		ws_resources_leave(manager)
		if locales == nil {
			throw(e, c'java/lang/OutOfMemoryError', c'Cannot enumerate asset locales')
			return nil
		}
		defer { ws_locale_vector_delete(locales, WsLocaleArrayDelete(release)) }
		mut count := usize(0)
		for locales[count] != nil { count++ }
		if count > 0x7fffffff {
			throw(e, c'java/lang/OutOfMemoryError', c'Asset locale array is too large')
			return nil
		}
		// Enumeration returns owned copies. Release both resource locks before
		// entering Java or allocating its independently owned String[] result.
		string_class := cls(e, c'java/lang/String')
		if string_class == nil { return nil }
		if pending(e) {
			Drop(slot(e, 23))(e, string_class)
			return nil
		}
		array := WsNewArray(slot(e, 172))(e, i32(count), string_class, nil)
		Drop(slot(e, 23))(e, string_class)
		if array == nil { return nil }
		mut success := false
		defer { if !success { Drop(slot(e, 23))(e, array) } }
		if pending(e) { return nil }
		for index := usize(0); index < count; index++ {
			text := ws_string(e, locales[index])
			if text == nil { return nil }
			if !pending(e) { WsArraySet(slot(e, 174))(e, array, i32(index), text) }
			Drop(slot(e, 23))(e, text)
			if pending(e) { return nil }
		}
		success = true
		return array
	}
}
