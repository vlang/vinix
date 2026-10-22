// SPDX-License-Identifier: Apache-2.0
// Android resource JNI, using ART's independent libandroidfw C ABI.
// Based on AOSP/ATL resource semantics; no display toolkit is involved.
@[translated]
module atlframework

#define _LARGEFILE64_SOURCE
#include "androidfw_c_api.h"
#include <stdlib.h>
#include <string.h>

struct C.ResTable_config {
mut:
	density               u16
	sdkVersion            u16
	mcc                   u16
	mnc                   u16
	orientation           u8
	touchscreen           u8
	keyboard              u8
	navigation            u8
	screenWidth           u16
	screenHeight          u16
	smallestScreenWidthDp u16
	screenWidthDp         u16
	screenHeightDp        u16
	screenLayout          u8
	uiMode                u8
}

struct C.Res_value {
mut:
	dataType u8
	data     u32
}

struct C.ResolvedBag_Entry {
	key    u32
	value  C.Res_value
	cookie i32
}

struct C.ResolvedBag {
	type_spec_flags u32
	entry_count     u32
	entries         &C.ResolvedBag_Entry
}

struct C.resource_name {
	package     &char
	package_len usize
	@type       &char
	type16      &u16
	type_len    usize
	entry       &char
	entry16     &u16
	entry_len   usize
}

fn C.malloc(usize) voidptr
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.strlen(&char) usize
fn C.strdup(&char) &char
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.AssetManager_new() voidptr
fn C.AssetManager_lock(voidptr)
fn C.AssetManager_unlock(voidptr)
fn C.AssetManager_setConfiguration(voidptr, &C.ResTable_config)
fn C.ApkAssets_load(&char, bool) voidptr
fn C.ApkAssets_loadDir(&char) voidptr
fn C.AssetManager_setApkAssets(voidptr, voidptr, usize, bool, bool) bool
fn C.AssetManager_getStringPoolForCookie(voidptr, i32) voidptr
fn C.AssetManager_getResource(voidptr, u32, bool, u16, &C.Res_value, &C.ResTable_config, &u32) i32
fn C.AssetManager_resolveReference(voidptr, i32, &C.Res_value, &C.ResTable_config, &u32, &u32) i32
fn C.AssetManager_newTheme(voidptr) voidptr
fn C.Theme_delete(voidptr)
fn C.Theme_applyStyle(voidptr, u32, bool)
fn C.Theme_getAttribute(voidptr, u32, &C.Res_value, &u32) i32
fn C.Theme_setTo(voidptr, voidptr)
fn C.AssetManager_getResourceId(voidptr, &char, &char, &char) u32
fn C.AssetManager_getResourceName(voidptr, u32, &C.resource_name) u32
fn C.AssetManager_getBag(voidptr, u32) &C.ResolvedBag
fn C.ResStringPool_stringAt(voidptr, usize, &usize) &u16
fn C.AssetManager_openNonAsset(voidptr, &char, i32) voidptr
fn C.Asset_getBuffer(voidptr, bool) voidptr
fn C.Asset_getLength(voidptr) i64
fn C.Asset_getRemainingLength(voidptr) i64
fn C.Asset_read(voidptr, voidptr, usize) isize
fn C.Asset_seek(voidptr, i64, i32) i64
fn C.Asset_delete(voidptr)
fn C.ResXMLTree_new() voidptr
fn C.ResXMLTree_setTo(voidptr, voidptr, usize, bool)
fn C.ResXMLTree_delete(voidptr)
fn C.ResXMLParser_new(voidptr) voidptr
fn C.ResXMLParser_restart(voidptr)
fn C.ResXMLParser_next(voidptr) i32
fn C.ResXMLParser_getElementNameID(voidptr) i32
fn C.ResXMLParser_getStrings(voidptr) voidptr
fn C.ResXMLParser_getAttributeCount(voidptr) usize
fn C.ResXMLParser_getAttributeNameID(voidptr, usize) u32
fn C.ResXMLParser_getAttributeNameResID(voidptr, usize) u32
fn C.ResXMLParser_indexOfAttribute(voidptr, &u16, usize, &u16, usize) isize
fn C.ResXMLParser_getAttributeValueStringID(voidptr, usize) i32
fn C.ResXMLParser_getLineNumber(voidptr) u32
fn C.ResXMLParser_getAttributeDataType(voidptr, usize) i32
fn C.ResXMLParser_getAttributeData(voidptr, usize) i32
fn C.ResXMLParser_indexOfClass(voidptr) isize
fn C.ResXMLParser_indexOfStyle(voidptr) isize
fn C.ResXMLParser_getAttributeValue(voidptr, usize, &C.Res_value)
fn C.ResXMLParser_delete(voidptr)
fn C.ApplyStyle(voidptr, voidptr, i32, i32, &u32, usize, &u32, &u32)
fn C.RetrieveAttributes(voidptr, voidptr, &u32, usize, &u32, &u32) bool
fn C.ResolveAttrs(voidptr, i32, i32, &u32, usize, &u32, usize, &u32, &u32) bool

type WsNewString = fn (voidptr, &u16, i32) voidptr
type WsUtf = fn (voidptr, voidptr, voidptr) &char
type WsUtfRelease = fn (voidptr, voidptr, &char)
type WsChars = fn (voidptr, voidptr, voidptr) &u16
type WsCharsRelease = fn (voidptr, voidptr, &u16)
type WsLength = fn (voidptr, voidptr) i32
type WsNewUtf = fn (voidptr, &char) voidptr
type WsArrayGet = fn (voidptr, voidptr, i32) voidptr
type WsArraySet = fn (voidptr, voidptr, i32, voidptr)
type WsIntElements = fn (voidptr, voidptr, voidptr) &u32
type WsIntRelease = fn (voidptr, voidptr, &u32, i32)
type WsPutLong = fn (voidptr, voidptr, voidptr, i64)
type WsByteRegion = fn (voidptr, voidptr, i32, i32, voidptr)
type WsNewArray = fn (voidptr, i32, voidptr, voidptr) voidptr

fn ws_string(e voidptr, text &char) voidptr {
	unsafe { return WsNewUtf(slot(e, 167))(e, text)
	 }
}

fn ws_utf(e voidptr, text voidptr) &char {
	unsafe {
		if text == nil { return c'' }
		return WsUtf(slot(e, 169))(e, text, nil)
	}
}

fn ws_release(e voidptr, text voidptr, data &char) {
	if text != unsafe { nil } { unsafe { WsUtfRelease(slot(e, 170))(e, text, data) } }
}

fn ws_array_len(e voidptr, array voidptr) i32 {
	if array == unsafe { nil } { return 0 }
	unsafe { return WsLength(slot(e, 171))(e, array)
	 }
}

fn ws_put_long(e voidptr, object voidptr, class_name &char, name &char, value i64) {
	unsafe { WsPutLong(slot(e, 110))(e, object, field(e, class_name, name, c'J'), value) }
}

fn ws_manager(e voidptr, object voidptr) voidptr {
	unsafe { return voidptr(get_long(e, object, c'android/content/res/AssetManager', c'mObject'))
	 }
}

fn ws_pool_string(e voidptr, pool voidptr, index i32) voidptr {
	unsafe {
		if pool == nil || index < 0 { return nil }
		length := &usize(C.alloca(sizeof(usize)))
		*length = 0
		chars := &u16(C.ResStringPool_stringAt(pool, usize(index), length))
		if chars == nil { return nil }
		return WsNewString(slot(e, 163))(e, chars, i32(*length))
	}
}

fn ws_resource_init(e voidptr, object voidptr, sdk i32) {
	manager := C.AssetManager_new()
	config := C.ResTable_config{ density: 160, sdkVersion: u16(sdk) }
	C.AssetManager_setConfiguration(manager, &config)
	ws_put_long(e, object, c'android/content/res/AssetManager', c'mObject', i64(manager))
}

fn ws_load_apk_asset(e voidptr, path voidptr) voidptr {
	unsafe {
		if path == nil { return nil }
		text := ws_utf(e, path)
		if text == nil { return nil }
		defer { ws_release(e, path, text) }
		length := C.strlen(text)
		return if length > 0 && text[length - 1] == `/` {
			voidptr(C.ApkAssets_loadDir(text))
		} else {
			voidptr(C.ApkAssets_load(text, false))
		}
	}
}

fn ws_assets(e voidptr, object voidptr, paths voidptr, count i32, target i32) i32 {
	unsafe {
		if count < 0 || count > 4096 || target >= count { return 0 }
		assets := &voidptr(C.alloca(usize(count + 1) * sizeof(voidptr)))
		cookie_paths := WsNewArray(slot(e, 172))(e, count, cls(e, c'java/lang/Object'), nil)
		if cookie_paths == nil { return 0 }
		defer { Drop(slot(e, 23))(e, cookie_paths) }
		// Reject a bad addition before reloading any existing APKs.
		mut addition := voidptr(nil)
		if target >= 0 {
			path := WsArrayGet(slot(e, 173))(e, paths, target)
			addition = ws_load_apk_asset(e, path)
			if path != nil { Drop(slot(e, 23))(e, path) }
			if addition == nil { return 0 }
		}
		mut actual := usize(0)
		mut cookie := i32(0)
		for i := i32(0); i < count; i++ {
			path := WsArrayGet(slot(e, 173))(e, paths, i)
			if path == nil { continue }
			asset := if i == target { addition } else { ws_load_apk_asset(e, path) }
			if asset != nil {
				assets[actual] = asset
				WsArraySet(slot(e, 174))(e, cookie_paths, i32(actual), path)
				actual++
				if i == target { cookie = i32(actual) }
			}
			Drop(slot(e, 23))(e, path)
		}
		if target >= 0 && cookie == 0 { return 0 }
		if !C.AssetManager_setApkAssets(ws_manager(e, object), voidptr(assets), actual, true, true) { return 0 }
		put_object(e, object, c'android/content/res/AssetManager', c'vinixCookiePaths', c'[Ljava/lang/Object;', cookie_paths)
		return cookie
	}
}

fn ws_value(e voidptr, manager voidptr, value &C.Res_value, cookie i32, reference u32, output voidptr) i32 {
	if cookie < 0 { return -1 }
	put_int(e, output, c'android/util/TypedValue', c'type', i32(value.dataType))
	put_int(e, output, c'android/util/TypedValue', c'data', i32(value.data))
	put_int(e, output, c'android/util/TypedValue', c'resourceId', i32(reference))
	put_int(e, output, c'android/util/TypedValue', c'assetCookie', cookie + 1)
	text := if value.dataType == 3 {
		ws_pool_string(e, voidptr(C.AssetManager_getStringPoolForCookie(manager, cookie)), i32(value.data))
	} else {
		unsafe { nil }
	}
	put_object(e, output, c'android/util/TypedValue', c'string', c'Ljava/lang/CharSequence;', text)
	return cookie + 1
}

fn ws_resource(e voidptr, object voidptr, id i32, density i16, output voidptr, resolve u8) i32 {
	manager := ws_manager(e, object)
	C.AssetManager_lock(manager)
	defer { C.AssetManager_unlock(manager) }
	mut value := C.Res_value{}
	mut config := C.ResTable_config{}
	mut flags := u32(0)
	mut reference := u32(id)
	mut cookie := C.AssetManager_getResource(manager, u32(id), false, u16(density), &value, &config, &flags)
	if resolve != 0 && cookie >= 0 {
		cookie = C.AssetManager_resolveReference(manager, cookie, &value, &config, &flags, &reference)
	}
	return ws_value(e, manager, &value, cookie, u32(id), output)
}

fn ws_theme_value(e voidptr, object voidptr, theme i64, id i32, output voidptr, resolve u8) i32 {
	manager := ws_manager(e, object)
	C.AssetManager_lock(manager)
	defer { C.AssetManager_unlock(manager) }
	mut value := C.Res_value{}
	mut config := C.ResTable_config{}
	mut flags := u32(0)
	mut reference := u32(id)
	mut cookie := C.Theme_getAttribute(voidptr(theme), u32(id), &value, &flags)
	if resolve != 0 && cookie >= 0 {
		cookie = C.AssetManager_resolveReference(manager, cookie, &value, &config, &flags, &reference)
	}
	return ws_value(e, manager, &value, cookie, reference, output)
}

fn ws_resource_id(e voidptr, object voidptr, name voidptr, kind voidptr, package voidptr) i32 {
	a, b, c := ws_utf(e, name), ws_utf(e, kind), ws_utf(e, package)
	result := C.AssetManager_getResourceId(ws_manager(e, object), a, b, c)
	ws_release(e, name, a)
	ws_release(e, kind, b)
	ws_release(e, package, c)
	return i32(result)
}

fn ws_resource_name(e voidptr, object voidptr, id i32, kind i32) voidptr {
	unsafe {
		name := &C.resource_name(C.alloca(sizeof(C.resource_name)))
		C.memset(name, 0, sizeof(C.resource_name))
		if C.AssetManager_getResourceName(ws_manager(e, object), u32(id), name) == 0 { return nil }
		if kind == 0 { return ws_string(e, &char(name.package)) }
		if kind == 1 {
			if name.@type != nil { return ws_string(e, &char(name.@type)) }
			return WsNewString(slot(e, 163))(e, &u16(name.type16), i32(name.type_len))
		}
		if kind == 2 {
			if name.entry != nil { return ws_string(e, &char(name.entry)) }
			return WsNewString(slot(e, 163))(e, &u16(name.entry16), i32(name.entry_len))
		}
		result := ws_resource_name(e, object, id, 0)
		args := &Value(C.alloca(sizeof(Value)))
		args[0] = Value{ l: ws_string(e, c':') }
		result1 := obj(e, result, c'java/lang/String', c'concat', c'(Ljava/lang/String;)Ljava/lang/String;', args)
		args[0] = Value{ l: ws_resource_name(e, object, id, 1) }
		result2 := obj(e, result1, c'java/lang/String', c'concat', c'(Ljava/lang/String;)Ljava/lang/String;', args)
		args[0] = Value{ l: ws_string(e, c'/') }
		result3 := obj(e, result2, c'java/lang/String', c'concat', c'(Ljava/lang/String;)Ljava/lang/String;', args)
		args[0] = Value{ l: ws_resource_name(e, object, id, 2) }
		return obj(e, result3, c'java/lang/String', c'concat', c'(Ljava/lang/String;)Ljava/lang/String;', args)
	}
}

fn ws_bag_value(e voidptr, object voidptr, id i32, key i32, output voidptr) i32 {
	unsafe {
		manager := ws_manager(e, object)
		C.AssetManager_lock(manager)
		defer { C.AssetManager_unlock(manager) }
		bag := &C.ResolvedBag(C.AssetManager_getBag(manager, u32(id)))
		if bag == nil { return -1 }
		for i := u32(0); i < bag.entry_count; i++ {
			entry := bag.entries[i]
			if entry.key != u32(key) { continue }
			mut value := entry.value
			mut config := C.ResTable_config{}
			mut flags := u32(0)
			mut reference := u32(0)
			cookie := C.AssetManager_resolveReference(manager, entry.cookie, &value, &config, &flags, &reference)
			return ws_value(e, manager, &value, cookie, reference, output)
		}
		return -1
	}
}

fn ws_resource_array(e voidptr, object voidptr, id i32, output voidptr, strings bool) voidptr {
	unsafe {
		manager := ws_manager(e, object)
		C.AssetManager_lock(manager)
		defer { C.AssetManager_unlock(manager) }
		bag := &C.ResolvedBag(C.AssetManager_getBag(manager, u32(id)))
		if bag == nil { return nil }
		array := if strings {
			WsNewArray(slot(e, 172))(e, i32(bag.entry_count), cls(e, c'java/lang/String'), nil)
		} else {
			output
		}
		for i := u32(0); i < bag.entry_count; i++ {
			entry := bag.entries[i]
			mut value := entry.value
			mut config := C.ResTable_config{}
			mut flags := u32(0)
			mut reference := u32(0)
			cookie := C.AssetManager_resolveReference(manager, entry.cookie, &value, &config, &flags, &reference)
			if strings {
				text := ws_pool_string(e, voidptr(C.AssetManager_getStringPoolForCookie(manager, cookie)), i32(value.data))
				WsArraySet(slot(e, 174))(e, array, i32(i), text)
				if text != nil { Drop(slot(e, 23))(e, text) }
			} else {
				record := [i32(value.dataType), i32(value.data), cookie + 1, i32(reference),
					i32(flags), i32(config.density), 0]!
				IntRegion(slot(e, 211))(e, array, i32(i * 7), 7, &record[0])
			}
		}
		return array
	}
}

fn ws_open_asset(e voidptr, object voidptr, name voidptr, mode i32) i64 {
	text := ws_utf(e, name)
	asset := C.AssetManager_openNonAsset(ws_manager(e, object), text, mode)
	ws_release(e, name, text)
	return i64(asset)
}

fn ws_open_xml(e voidptr, object voidptr, cookie i32, name voidptr) i64 {
	if cookie != 0 {
		args := [Value{i: cookie}, Value{l: name}]!
		bytes := obj(e, object, c'android/content/res/AssetManager', c'vinixReadXmlAsset', c'(ILjava/lang/String;)[B', &args[0])
		if pending(e) || bytes == unsafe { nil } { return 0 }
		defer { unsafe { Drop(slot(e, 23))(e, bytes) } }
		return ws_xml_create(e, bytes, 0, ws_array_len(e, bytes))
	}
	asset := voidptr(ws_open_asset(e, object, name, 3))
	if asset == unsafe { nil } { return 0 }
	tree := C.ResXMLTree_new()
	C.ResXMLTree_setTo(tree, C.Asset_getBuffer(asset, true), usize(C.Asset_getLength(asset)), true)
	C.Asset_delete(asset)
	return i64(tree)
}

fn ws_asset_read(e voidptr, asset i64, bytes voidptr, offset i64, length i64) i32 {
	if offset < 0 || length < 0 || offset + length > i64(ws_array_len(e, bytes)) { return -1 }
	buffer := C.malloc(usize(length))
	defer { C.free(buffer) }
	count := C.Asset_read(voidptr(asset), buffer, usize(length))
	if count > 0 {
		unsafe { WsByteRegion(slot(e, 208))(e, bytes, i32(offset), i32(count), buffer) }
	}
	// AssetInputStream maps the native zero-byte EOF to Java's -1 itself.
	return i32(count)
}

fn ws_xml_next(parser i64) i32 {
	for {
		code := C.ResXMLParser_next(voidptr(parser))
		if code == -1 || code == 0 || code == 1 { return code }
		if code >= 0x102 && code <= 0x104 { return code - 0x100 }
	}
	return -1
}

fn ws_xml_create(e voidptr, bytes voidptr, offset i32, length i32) i64 {
	if offset < 0 || length < 0 || i64(offset) + i64(length) > ws_array_len(e, bytes) { return 0 }
	storage := C.malloc(usize(length))
	defer { C.free(storage) }
	unsafe { WsByteRegion(slot(e, 200))(e, bytes, offset, length, storage) }
	tree := C.ResXMLTree_new()
	C.ResXMLTree_setTo(tree, storage, usize(length), true)
	return i64(tree)
}

fn ws_xml_index(e voidptr, parser i64, namespace voidptr, name voidptr) i32 {
	unsafe {
		ns := if namespace == nil { &u16(nil) } else { WsChars(slot(e, 165))(e, namespace, nil) }
		nslen := if namespace == nil { i32(0) } else { WsLength(slot(e, 164))(e, namespace) }
		nm := WsChars(slot(e, 165))(e, name, nil)
		nmlen := WsLength(slot(e, 164))(e, name)
		result := C.ResXMLParser_indexOfAttribute(voidptr(parser), ns, usize(nslen), nm, usize(nmlen))
		if namespace != nil { WsCharsRelease(slot(e, 166))(e, namespace, ns) }
		WsCharsRelease(slot(e, 166))(e, name, nm)
		return i32(result)
	}
}

fn ws_apply_style(e voidptr, theme i64, parser i64, attr i32, style i32, array voidptr, count i32, values i64, indices i64) {
	unsafe {
		attrs := WsIntElements(slot(e, 187))(e, array, nil)
		C.ApplyStyle(voidptr(theme), voidptr(parser), attr, style, attrs, usize(count), &u32(values), &u32(indices))
		WsIntRelease(slot(e, 195))(e, array, attrs, 2)
	}
}

fn ws_retrieve(e voidptr, object voidptr, parser i64, array voidptr, count i32, values i64, indices i64) u8 {
	unsafe {
		attrs := WsIntElements(slot(e, 187))(e, array, nil)
		result := C.RetrieveAttributes(ws_manager(e, object), voidptr(parser), attrs, usize(count), &u32(values), &u32(indices))
		WsIntRelease(slot(e, 195))(e, array, attrs, 2)
		return u8(result)
	}
}

fn ws_resolve_attrs(e voidptr, theme i64, attr i32, style i32, values voidptr, attrs voidptr, output voidptr, indices voidptr) u8 {
	unsafe {
		a := WsIntElements(slot(e, 187))(e, attrs, nil)
		v := if values == nil { &u32(nil) } else { WsIntElements(slot(e, 187))(e, values, nil) }
		o := WsIntElements(slot(e, 187))(e, output, nil)
		ix := if indices == nil { &u32(nil) } else { WsIntElements(slot(e, 187))(e, indices, nil) }
		result := C.ResolveAttrs(voidptr(theme), attr, style, v, usize(ws_array_len(e, values)), a, usize(ws_array_len(e, attrs)), o, ix)
		if ix != nil { WsIntRelease(slot(e, 195))(e, indices, ix, 0) }
		WsIntRelease(slot(e, 195))(e, output, o, 0)
		if v != nil { WsIntRelease(slot(e, 195))(e, values, v, 2) }
		WsIntRelease(slot(e, 195))(e, attrs, a, 2)
		return u8(result)
	}
}
