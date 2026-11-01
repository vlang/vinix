// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only JNI bridge. All concurrent manager operations use the production
// adapter; only the pre-worker directory open calls the raw C API directly.
@[translated]
module resourcelockprobe

#define _LARGEFILE64_SOURCE
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "androidfw_c_api.h"
#include "native-ndk.h"

fn C.AAssetManager_fromJava(voidptr, voidptr) voidptr
fn C.AAssetManager_open(voidptr, &char, i32) voidptr
fn C.AAsset_getLength64(voidptr) i64
fn C.AAsset_read(voidptr, voidptr, usize) i32
fn C.AAsset_close(voidptr)
fn C.AssetManager_openDir(voidptr, &char) voidptr
fn C.AssetDir_getFileCount(voidptr) usize
fn C.AssetDir_getFileName(voidptr, i32) &char
fn C.AssetDir_delete(voidptr)
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strcmp(&char, &char) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32

const no_theme_cookie = i32(-2147483648)
const framework_color_attr = i32(0x01010030) // public android.R.attr.colorForeground

struct HeldAssets {
	asset voidptr
	directory voidptr
}

union ProbeValue {
mut:
	l voidptr
	i i32
	j i64
	z u8
}

type ProbeLookup = fn (voidptr, &char) voidptr
type ProbeMember = fn (voidptr, voidptr, &char, &char) voidptr
type ProbeObjectCall = fn (voidptr, voidptr, voidptr, &ProbeValue) voidptr
type ProbeIntCall = fn (voidptr, voidptr, voidptr, &ProbeValue) i32
type ProbeLongCall = fn (voidptr, voidptr, voidptr, &ProbeValue) i64
type ProbeVoidCall = fn (voidptr, voidptr, voidptr, &ProbeValue)
type ProbeIntField = fn (voidptr, voidptr, voidptr) i32
type ProbeArrayLength = fn (voidptr, voidptr) i32
type ProbeDrop = fn (voidptr, voidptr)
type ProbeSame = fn (voidptr, voidptr, voidptr) u8
type ProbePending = fn (voidptr) u8
type ProbeException = fn (voidptr) voidptr
type ProbeClear = fn (voidptr)
type ProbeThrow = fn (voidptr, voidptr) i32
type ProbeThrowNew = fn (voidptr, voidptr, &char) i32

fn probe_slot(e voidptr, index int) voidptr {
	unsafe { return (&voidptr(*(&voidptr(e))))[index] }
}

fn probe_pending(e voidptr) bool {
	unsafe { return ProbePending(probe_slot(e, 228))(e) != 0 }
}

fn probe_member(e voidptr, class voidptr, name &char, signature &char) voidptr {
	unsafe {
		if class == nil || probe_pending(e) { return nil }
		return ProbeMember(probe_slot(e, 33))(e, class, name, signature)
	}
}

fn probe_null(e voidptr) {
	unsafe {
		if probe_pending(e) { return }
		class := ProbeLookup(probe_slot(e, 6))(e, c'java/lang/NullPointerException')
		if class == nil { return }
		ProbeThrowNew(probe_slot(e, 14))(e, class, c'resource-lock probe input')
		ProbeDrop(probe_slot(e, 23))(e, class)
	}
}

fn asset_matches(asset voidptr) bool {
	unsafe {
		if asset == nil { return false }
		mut bytes := [22]u8{}
		return C.AAsset_getLength64(asset) == 21
			&& C.AAsset_read(asset, &bytes[0], 22) == 21
			&& C.memcmp(&bytes[0], c'VINIX-RESOURCE-ASSET\n', 21) == 0
			&& C.AAsset_read(asset, &bytes[0], 1) == 0
	}
}

// Called once before workers start. The returned holder owns both handles.
@[export: 'Java_org_vinix_bootstrap_Main_nativeHold']
pub fn native_hold(e voidptr, class voidptr, java_assets voidptr) i64 {
	unsafe {
		if java_assets == nil || probe_pending(e) { return 0 }
		manager := C.AAssetManager_fromJava(e, java_assets)
		if manager == nil || probe_pending(e) { return 0 }
		asset := C.AAssetManager_open(manager, c'proof/alpha.txt', 2)
		if asset == nil { return 0 }
		directory := C.AssetManager_openDir(manager, c'proof')
		if directory == nil { C.AAsset_close(asset); return 0 }
		held := &HeldAssets(C.malloc(sizeof(HeldAssets)))
		if held == nil {
			C.AssetDir_delete(directory)
			C.AAsset_close(asset)
			return 0
		}
		*held = HeldAssets{asset: asset, directory: directory}
		return i64(held)
	}
}

// Called exactly once after every worker has joined, even when a worker fails.
@[export: 'Java_org_vinix_bootstrap_Main_nativeHeldClose']
pub fn native_held_close(e voidptr, class voidptr, handle i64) u8 {
	unsafe {
		if handle == 0 { return 0 }
		held := &HeldAssets(voidptr(handle))
		defer {
			if held.directory != nil { C.AssetDir_delete(held.directory) }
			if held.asset != nil { C.AAsset_close(held.asset) }
			C.free(held)
		}
		asset_valid := asset_matches(held.asset)
		if held.directory == nil || C.AssetDir_getFileCount(held.directory) != 2 { return 0 }
		first := &char(C.AssetDir_getFileName(held.directory, 0))
		second := &char(C.AssetDir_getFileName(held.directory, 1))
		if first == nil || second == nil { return 0 }
		directory_valid := (C.strcmp(first, c'alpha.txt') == 0 && C.strcmp(second, c'beta.txt') == 0)
			|| (C.strcmp(first, c'beta.txt') == 0 && C.strcmp(second, c'alpha.txt') == 0)
		return u8(asset_valid && directory_valid)
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeProbe']
pub fn native_probe(e voidptr, class voidptr, java_assets voidptr) u8 {
	unsafe {
		if java_assets == nil || probe_pending(e) { return 0 }
		manager := C.AAssetManager_fromJava(e, java_assets)
		if manager == nil || probe_pending(e) { return 0 }
		// AAssetManager_open enters the production adapter's resource locks.
		asset := C.AAssetManager_open(manager, c'proof/alpha.txt', 2)
		if asset == nil { return 0 }
		defer { C.AAsset_close(asset) }
		return u8(asset_matches(asset))
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeReplace']
pub fn native_replace(e voidptr, class voidptr, java_assets voidptr, paths voidptr) {
	unsafe {
		if probe_pending(e) { return }
		if java_assets == nil || paths == nil { probe_null(e); return }
		manager_class := ProbeLookup(probe_slot(e, 6))(e, c'android/content/res/AssetManager')
		if manager_class == nil { return }
		defer { ProbeDrop(probe_slot(e, 23))(e, manager_class) }
		replace := probe_member(e, manager_class, c'native_setApkAssets', c'([Ljava/lang/Object;I)V')
		if replace == nil { return }
		count := ProbeArrayLength(probe_slot(e, 171))(e, paths)
		if probe_pending(e) { return }
		args := [ProbeValue{l: paths}, ProbeValue{i: count}]!
		// Invoke JNI -> Java native -> production ws_assets; never bypass locks.
		ProbeVoidCall(probe_slot(e, 63))(e, java_assets, replace, &args[0])
	}
}

// Run all deletes with no exception pending, then restore the original failure
// (or the first cleanup failure). No handle is abandoned after a failed check.
fn themes_close(e voidptr, first voidptr, second voidptr, remove voidptr, themes [3]i64) {
	unsafe {
		mut failure := ProbeException(probe_slot(e, 15))(e)
		if failure != nil { ProbeClear(probe_slot(e, 17))(e) }
		for index, theme in themes {
			if theme == 0 { continue }
			owner := if index == 2 { second } else { first }
			args := [ProbeValue{j: theme}]!
			ProbeVoidCall(probe_slot(e, 63))(e, owner, remove, &args[0])
			next := ProbeException(probe_slot(e, 15))(e)
			if next != nil {
				ProbeClear(probe_slot(e, 17))(e)
				if failure == nil { failure = next }
				else { ProbeDrop(probe_slot(e, 23))(e, next) }
			}
		}
		if failure != nil {
			ProbeThrow(probe_slot(e, 13))(e, failure)
			ProbeDrop(probe_slot(e, 23))(e, failure)
		}
	}
}

// One fixed-size, failure-only line per nativeThemes invocation. An unavailable
// cookie is INT32_MIN; unavailable TypedValue fields are type=-1/data=0. fflush
// preserves the checkpoint even if the Java exception path terminates early.
fn theme_failure_expected(phase &char, cookie i32, kind i32, data u32, pending bool, expected i32) bool {
	unsafe {
		C.printf(c'RESOURCE-LOCKS-THEME-DIAGNOSTIC phase=%s cookie=%d expected_present=%d type=0x%08x data=0x%08x pending=%d\n',
			phase, cookie, expected, u32(kind), data, i32(pending))
		C.fflush(nil)
	}
	return false
}

fn theme_failure(phase &char, cookie i32, kind i32, data u32, pending bool) bool {
	return theme_failure_expected(phase, cookie, kind, data, pending, -1)
}

fn theme_matches(e voidptr, owner voidptr, load voidptr, theme i64, attr i32, value voidptr,
	type_field voidptr, data_field voidptr, present bool, phase &char) bool {
	unsafe {
		args := [ProbeValue{j: theme}, ProbeValue{i: attr}, ProbeValue{l: value}, ProbeValue{z: 1}]!
		cookie := ProbeIntCall(probe_slot(e, 51))(e, owner, load, &args[0])
		if probe_pending(e) { return theme_failure_expected(phase, no_theme_cookie, -1, 0, true, i32(present)) }
		// The returned cookie determines presence. Do not interpret stale output
		// fields after an absent lookup, or call field accessors with an exception.
		if !present && cookie < 0 { return true }
		if cookie < 0 { return theme_failure_expected(phase, cookie, -1, 0, false, i32(present)) }
		kind := ProbeIntField(probe_slot(e, 100))(e, value, type_field)
		if probe_pending(e) { return theme_failure_expected(phase, cookie, -1, 0, true, i32(present)) }
		data := ProbeIntField(probe_slot(e, 100))(e, value, data_field)
		if probe_pending(e) { return theme_failure_expected(phase, cookie, -1, 0, true, i32(present)) }
		if present && kind == 0x1c && u32(data) == u32(0xff123456) { return true }
		return theme_failure_expected(phase, cookie, kind, u32(data), false, i32(present))
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeThemes']
pub fn native_themes(e voidptr, class voidptr, first voidptr, second voidptr, style i32, attr i32) u8 {
	unsafe {
		if probe_pending(e) { theme_failure(c'entry', no_theme_cookie, -1, 0, true); return 0 }
		if first == nil || second == nil {
			probe_null(e)
			theme_failure(c'null-owner', no_theme_cookie, -1, 0, probe_pending(e))
			return 0
		}
		if ProbeSame(probe_slot(e, 24))(e, first, second) != 0 {
			theme_failure(c'identical-owners', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		manager_class := ProbeLookup(probe_slot(e, 6))(e, c'android/content/res/AssetManager')
		if manager_class == nil {
			theme_failure(c'manager-class', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		defer { ProbeDrop(probe_slot(e, 23))(e, manager_class) }
		create := probe_member(e, manager_class, c'newTheme', c'()J')
		remove := probe_member(e, manager_class, c'deleteTheme', c'(J)V')
		apply := probe_member(e, manager_class, c'applyThemeStyle', c'(JIZ)V')
		copy := probe_member(e, manager_class, c'copyTheme', c'(JJ)V')
		load := probe_member(e, manager_class, c'loadThemeAttributeValue', c'(JILandroid/util/TypedValue;Z)I')
		if create == nil || remove == nil || apply == nil || copy == nil || load == nil {
			theme_failure(c'manager-methods', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		value_class := ProbeLookup(probe_slot(e, 6))(e, c'android/util/TypedValue')
		if value_class == nil {
			theme_failure(c'value-class', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		defer { ProbeDrop(probe_slot(e, 23))(e, value_class) }
		constructor := probe_member(e, value_class, c'<init>', c'()V')
		if constructor == nil {
			theme_failure(c'value-constructor', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		type_field := ProbeMember(probe_slot(e, 94))(e, value_class, c'type', c'I')
		if type_field == nil || probe_pending(e) {
			theme_failure(c'value-type-field', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		data_field := ProbeMember(probe_slot(e, 94))(e, value_class, c'data', c'I')
		if data_field == nil || probe_pending(e) {
			theme_failure(c'value-data-field', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		value := ProbeObjectCall(probe_slot(e, 30))(e, value_class, constructor, nil)
		if value == nil || probe_pending(e) {
			theme_failure(c'value-allocation', no_theme_cookie, -1, 0, probe_pending(e)); return 0
		}
		defer { ProbeDrop(probe_slot(e, 23))(e, value) }
		mut themes := [i64(0), i64(0), i64(0)]!
		defer { themes_close(e, first, second, remove, themes) }
		for index in 0 .. 3 {
			owner := if index == 2 { second } else { first }
			themes[index] = ProbeLongCall(probe_slot(e, 54))(e, owner, create, nil)
			if themes[index] == 0 || probe_pending(e) {
				phase := if index == 0 { c'new-A0' } else if index == 1 { c'new-A1' } else { c'new-B2' }
				theme_failure(phase, no_theme_cookie, -1, 0, probe_pending(e)); return 0
			}
		}
		// Each copy has a fresh-empty destination control. The retained C API
		// remaps app attributes across owners only for shared ApkAssets objects;
		// a public framework key with a literal color has no such prerequisite.
		if !theme_matches(e, first, load, themes[1], attr, value, type_field, data_field, false, c'blank-app-A1')
			|| !theme_matches(e, second, load, themes[2], framework_color_attr, value, type_field, data_field, false, c'blank-framework-B2') { return 0 }
		apply_args := [ProbeValue{j: themes[0]}, ProbeValue{i: style}, ProbeValue{z: 1}]!
		ProbeVoidCall(probe_slot(e, 63))(e, first, apply, &apply_args[0])
		if probe_pending(e) { theme_failure(c'apply-call', no_theme_cookie, -1, 0, true); return 0 }
		if !theme_matches(e, first, load, themes[0], attr, value, type_field, data_field, true, c'applied-app-A0')
			|| !theme_matches(e, first, load, themes[0], framework_color_attr, value, type_field, data_field, true, c'applied-framework-A0') { return 0 }
		same_args := [ProbeValue{j: themes[1]}, ProbeValue{j: themes[0]}]!
		ProbeVoidCall(probe_slot(e, 63))(e, first, copy, &same_args[0])
		if probe_pending(e) { theme_failure(c'same-copy-call', no_theme_cookie, -1, 0, true); return 0 }
		if !theme_matches(e, first, load, themes[1], attr, value, type_field, data_field, true, c'same-app-A1')
			|| !theme_matches(e, first, load, themes[1], framework_color_attr, value, type_field, data_field, true, c'same-framework-A1') { return 0 }
		cross_args := [ProbeValue{j: themes[2]}, ProbeValue{j: themes[1]}]!
		ProbeVoidCall(probe_slot(e, 63))(e, second, copy, &cross_args[0])
		if probe_pending(e) { theme_failure(c'cross-copy-call', no_theme_cookie, -1, 0, true); return 0 }
		return u8(theme_matches(e, second, load, themes[2], framework_color_attr, value, type_field, data_field, true, c'cross-framework-B2'))
	}
}
