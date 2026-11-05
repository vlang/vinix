// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Android 9's NetworkManagementService considers activity active when no idle
// timers monitor it. Vinix has no radio-activity idle monitor, so preserve that
// scheduling policy without claiming a link, route, packet or Internet access.
// https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-9.0.0_r1/services/core/java/com/android/server/NetworkManagementService.java
pub fn framework_default_network_active_method() string {
	return '.method public isDefaultNetworkActive()Z
.registers 2
const/4 v0, 0x1
return v0
.end method'
}

// Validate the exact predecessor shape before appending the public virtual
// query. Only the validation view normalizes formatting; every original byte,
// existing method, field, annotation and native declaration is retained.
pub fn framework_default_network_active_source(original string) !string {
	if original.contains('\x00') { return error('textual ConnectivityManager source required') }
	mut classes := []string{}
	mut supers := []string{}
	mut fields := []string{}
	mut headers := []string{}
	mut active := false
	mut annotation := false
	mut sources := 0
	for line in original.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('#') { continue }
		parts := trimmed.fields()
		text := parts.join(' ')
		first := parts[0]
		if first == '.class' || first == '.super' || first == '.field' {
			if active || annotation { return error('ConnectivityManager declaration inside a member') }
			if first == '.class' {
				if classes.len != 0 || supers.len != 0 || fields.len != 0 || headers.len != 0 {
					return error('misplaced or duplicate ConnectivityManager class')
				}
				classes << text
			} else if first == '.super' {
				if classes.len != 1 || supers.len != 0 || fields.len != 0 || headers.len != 0 {
					return error('misplaced or duplicate ConnectivityManager superclass')
				}
				supers << text
			} else {
				if classes.len != 1 || supers.len != 1 {
					return error('ConnectivityManager fields require class metadata')
				}
				// The ordinary writer uses decimal values; DEX disassembly uses
				// hexadecimal. Admit those exact equivalent spellings only in
				// this validation view and retain the original field bytes.
				fields << match text {
					'.field public static final RESTRICT_BACKGROUND_STATUS_DISABLED:I = 1' {
						'.field public static final RESTRICT_BACKGROUND_STATUS_DISABLED:I = 0x1'
					}
					'.field public static final RESTRICT_BACKGROUND_STATUS_ENABLED:I = 3' {
						'.field public static final RESTRICT_BACKGROUND_STATUS_ENABLED:I = 0x3'
					}
					'.field public static final RESTRICT_BACKGROUND_STATUS_WHITELISTED:I = 2' {
						'.field public static final RESTRICT_BACKGROUND_STATUS_WHITELISTED:I = 0x2'
					}
					else { text }
				}
			}
		} else if first == '.method' {
			if active || annotation || classes.len != 1 || supers.len != 1 {
				return error('nested, misplaced or unterminated ConnectivityManager method')
			}
			active = true
			headers << text
		} else if first == '.annotation' {
			if annotation || classes.len != 1 || supers.len != 1 || parts.len != 3
				|| parts[1] !in ['system', 'runtime', 'build']
				|| !parts[2].starts_with('L') || !parts[2].ends_with(';') {
				return error('malformed ConnectivityManager annotation')
			}
			annotation = true
		} else if first == '.end' {
			if parts.len < 2 { return error('malformed ConnectivityManager terminator') }
			if parts[1] == 'method' {
				if text != '.end method' || !active || annotation {
					return error('stray or malformed ConnectivityManager method end')
				}
				active = false
			} else if parts[1] == 'annotation' {
				if text != '.end annotation' || !annotation {
					return error('stray or malformed ConnectivityManager annotation end')
				}
				annotation = false
			} else if !active || annotation {
				return error('unexpected ConnectivityManager terminator')
			}
		} else if first == '.source' {
			if active || annotation || classes.len != 1 || supers.len != 1
				|| sources != 0 || parts.len < 2 {
				return error('unexpected ConnectivityManager source directive')
			}
			sources++
		} else if first.starts_with('.class') || first.starts_with('.super')
			|| first.starts_with('.field') || first.starts_with('.method')
			|| first.starts_with('.annotation') || first.starts_with('.end')
			|| first == '.implements' || parts.contains('.subannotation') {
			return error('unexpected or malformed ConnectivityManager declaration')
		} else if !active && !annotation {
			return error('unexpected top-level ConnectivityManager content')
		}
	}
	expected_fields := [
		'.field public static final RESTRICT_BACKGROUND_STATUS_DISABLED:I = 0x1',
		'.field public static final RESTRICT_BACKGROUND_STATUS_ENABLED:I = 0x3',
		'.field public static final RESTRICT_BACKGROUND_STATUS_WHITELISTED:I = 0x2',
		'.field private static callbacks:Ljava/util/concurrent/ConcurrentHashMap;',
	]
	expected := [
		'.method static constructor <clinit>()V',
		'.method public constructor <init>()V',
		'.method public static vinixCapabilities(I)Landroid/net/NetworkCapabilities;',
		'.method public static vinixLinkProperties(I)Landroid/net/LinkProperties;',
		'.method private vinixRegister(Landroid/net/NetworkRequest;Landroid/net/ConnectivityManager$NetworkCallback;Landroid/os/Handler;)V',
		'.method public static vinixRemove(Landroid/net/ConnectivityManager$NetworkCallback;Landroid/atl/VinixNetworkUpdate;)V',
		'.method public getActiveNetwork()Landroid/net/Network;',
		'.method public getActiveNetworkInfo()Landroid/net/NetworkInfo;',
		'.method public getAllNetworkInfo()[Landroid/net/NetworkInfo;',
		'.method public getAllNetworks()[Landroid/net/Network;',
		'.method public getBackgroundDataSetting()Z',
		'.method public getDefaultProxy()Landroid/net/ProxyInfo;',
		'.method public getLinkProperties(Landroid/net/Network;)Landroid/net/LinkProperties;',
		'.method public getNetworkCapabilities(Landroid/net/Network;)Landroid/net/NetworkCapabilities;',
		'.method public getNetworkInfo(I)Landroid/net/NetworkInfo;',
		'.method public getRestrictBackgroundStatus()I',
		'.method public isActiveNetworkMetered()Z',
		'.method protected native nativeGetNetworkAvailable()Z',
		'.method protected native nativeGetNetworkState()I',
		'.method public registerDefaultNetworkCallback(Landroid/net/ConnectivityManager$NetworkCallback;)V',
		'.method public registerDefaultNetworkCallback(Landroid/net/ConnectivityManager$NetworkCallback;Landroid/os/Handler;)V',
		'.method public registerNetworkCallback(Landroid/net/NetworkRequest;Landroid/net/ConnectivityManager$NetworkCallback;)V',
		'.method public registerNetworkCallback(Landroid/net/NetworkRequest;Landroid/net/ConnectivityManager$NetworkCallback;Landroid/os/Handler;)V',
		'.method public reportNetworkConnectivity(Landroid/net/Network;Z)V',
		'.method public requestNetwork(Landroid/net/NetworkRequest;Landroid/net/ConnectivityManager$NetworkCallback;)V',
		'.method public requestNetwork(Landroid/net/NetworkRequest;Landroid/net/ConnectivityManager$NetworkCallback;Landroid/os/Handler;)V',
		'.method public unregisterNetworkCallback(Landroid/net/ConnectivityManager$NetworkCallback;)V',
		'.method public vinixNetworkState()I',
	]
	if active || annotation || classes != ['.class public Landroid/net/ConnectivityManager;']
		|| supers != ['.super Ljava/lang/Object;']
		|| fields.sorted() != expected_fields.sorted() || headers.sorted() != expected.sorted() {
		return error('exact twenty-eight-method ConnectivityManager predecessor and four fields required')
	}
	return original + '\n' + framework_default_network_active_method() + '\n'
}

fn framework_default_network_active(smali string) ! {
	path := smali + '/android/net/ConnectivityManager.smali'
	patched := framework_default_network_active_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
