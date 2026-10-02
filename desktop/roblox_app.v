// SPDX-License-Identifier: GPL-2.0-or-later
// Cordial hosts the unchanged APK through a nested Wayland compositor on Xvfb.
module main

const roblox_surface_width = 1280
const roblox_surface_height = 720

fn roblox_apk_available() bool {
	override := C.getenv(c'VINIX_ROBLOX_APK')
	if override != unsafe { nil } && unsafe { override[0] } != 0 {
		return C.access(override, C.R_OK) == 0
	}
	home_value := C.getenv(c'HOME')
	home := if home_value != unsafe { nil } && unsafe { home_value[0] } != 0 {
		unsafe { cstring_to_vstring(home_value) }
	} else {
		'/root'
	}
	defer { unsafe { home.free() } }
	apk := '${home}/Roblox.apk'
	defer { unsafe { apk.free() } }
	return C.access(&char(apk.str), C.R_OK) == 0
}

fn open_roblox(mut _ Desktop) !NativeApp {
	mut failure := HostedText.none_
	if C.access(c'/usr/bin/run-roblox', C.X_OK) != 0
		|| C.access(c'/usr/bin/run-roblox-client', C.X_OK) != 0
		|| C.access(c'/opt/vinix-roblox-wayland/usr/bin/weston', C.X_OK) != 0 {
		failure = .roblox_missing
	} else if !roblox_apk_available() {
		failure = .roblox_apk_missing
	}
	if failure != .none_ {
		return &HostedX11App{
			surface_width: roblox_surface_width
			surface_height: roblox_surface_height
			icon: 'builtin:gamepad'
			failed: true
			failure: failure
		}
	}
	return open_hosted_x11_app('roblox', '/usr/bin/run-roblox-client', roblox_surface_width,
		roblox_surface_height, 'builtin:gamepad', .roblox_starting, .roblox_missing, .roblox_exited)
}
