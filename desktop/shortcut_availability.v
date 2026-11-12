// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn shortcut_executable(path string) bool {
	return C.access(&char(path.str), C.X_OK) == 0
}

fn shortcut_readable(path string) bool {
	return C.access(&char(path.str), C.R_OK) == 0
}

fn shortcut_hosted(command string) bool {
	return shortcut_executable('/usr/bin/Xvfb') && shortcut_executable(command)
}

fn shortcut_readable_setting(key &char, fallback string) bool {
	value := C.getenv(key)
	if value != unsafe { nil } && unsafe { value[0] } != 0 {
		return C.access(value, C.R_OK) == 0
	}
	return shortcut_readable(fallback)
}

// The multicall desktop contains adapters even when their applications are
// absent. Probe the actual payload, rather than its vinix-* multicall alias.
// Keep catalog indices and the saved order intact when an app is uninstalled.
fn (factory &AppFactory) shortcut_available() bool {
	if factory.standalone {
		path := '/usr/bin/${factory.process_name}'
		defer { unsafe { path.free() } }
		return shortcut_executable(path)
	}
	return match factory.process_name {
		'vinix-firefox' {
			shortcut_hosted('/usr/bin/run-firefox') && (shortcut_executable('/usr/lib/firefox-esr/firefox-esr') || shortcut_executable('/usr/lib/firefox/firefox'))
		}
		'vinix-chromium' {
			shortcut_hosted('/usr/bin/run-chromium') && shortcut_executable('/usr/lib/chromium/chrome')
		}
		'vinix-minecraft' { shortcut_hosted('/usr/bin/minecraft') }
		'vinix-wine-calculator' {
			shortcut_hosted('/usr/bin/calculator') && shortcut_executable('/usr/libexec/vinix-x86_64/root/usr/bin/wine') && shortcut_readable('/usr/share/wine/vinix-calculator.exe')
		}
		'vinix-wine-notepad' {
			shortcut_hosted('/usr/bin/notepad') && shortcut_executable('/usr/libexec/vinix-x86_64/root/usr/bin/wine')
		}
		'vinix-wine-word2013' {
			shortcut_hosted('/usr/bin/word2013') && shortcut_executable('/usr/libexec/vinix-x86_64/root/usr/bin/wine') && (shortcut_readable('/root/.wine-word2013-x86_64/drive_c/Program Files/Microsoft Office 15/root/office15/WINWORD.EXE') || shortcut_readable('/root/.wine-word2013-x86_64/drive_c/Program Files/Microsoft Office/Office15/WINWORD.EXE'))
		}
		'vinix-blender' {
			shortcut_executable(blender_native_executable) && shortcut_readable(blender_data_directory)
		}
		'vinix-obs' { shortcut_hosted('/usr/bin/run-obs') && shortcut_executable('/usr/bin/obs') }
		'vinix-gimp' {
			shortcut_hosted('/usr/bin/run-gimp') && shortcut_executable('/usr/bin/gimp')
		}
		'vinix-libreoffice' {
			shortcut_hosted('/usr/bin/run-libreoffice') && shortcut_executable('/usr/lib/libreoffice/program/soffice.bin')
		}
		'vinix-doom' {
			shortcut_hosted('/usr/bin/run-doom') && shortcut_executable('/usr/bin/chocolate-doom') && shortcut_readable('/usr/share/games/doom/doom1.wad')
		}
		'vinix-qemu-window' {
			shortcut_hosted('/usr/bin/vinix-qemu-desktop') && shortcut_readable_setting(c'VINIX_QEMU_DESKTOP_IMAGE', '/root/vinix-inner-desktop.img')
		}
		'vinix-steam' {
			shortcut_hosted('/usr/bin/steam-hosted') && shortcut_executable('/usr/bin/steam')
		}
		'vinix-opengothic' {
			shortcut_hosted('/usr/bin/run-opengothic') && shortcut_readable('/usr/share/games/gothic2/_work/Data')
		}
		'vinix-android-calculator' {
			shortcut_executable('/usr/bin/run-android-calculator') && shortcut_executable('/usr/bin/run-android') && shortcut_readable('/usr/share/vinix/android/Arity-1.1.apk')
		}
		'vinix-roblox' {
			shortcut_hosted('/usr/bin/run-roblox-client') && shortcut_executable('/usr/bin/run-roblox') && shortcut_executable('/usr/bin/run-android') && roblox_apk_available()
		}
		'vinix-dota2' {
			shortcut_hosted('/usr/bin/run-dota2') && shortcut_executable('/usr/share/games/dota2/game/bin/linuxsteamrt64/dota2')
		}
		'vinix-zed' {
			shortcut_hosted('/usr/bin/run-zed') && (shortcut_executable('/usr/libexec/vinix-zed/root/usr/libexec/zed-editor') || shortcut_executable('/opt/vinix-apps/zed/zed.app/libexec/zed-editor'))
		}
		'vinix-emacs' {
			shortcut_hosted('/usr/bin/run-emacs') && shortcut_executable('/usr/libexec/vinix-emacs/root/usr/bin/emacs')
		}
		else { true } // Native utilities are implemented in the desktop itself.
	}
}

// Convert a compact on-screen slot to the persistent catalog-order slot.
fn (d &Desktop) shortcut_order_slot_for_visible_slot(visible_slot int) int {
	if visible_slot < 0 {
		return -1
	}
	mut visible := 0
	mut last := -1
	for slot in 0 .. available_apps.len {
		index := d.shortcut_app_at_slot(slot)
		if index < 0 || !available_apps[index].shortcut_available() { continue }
		last = slot
		if visible == visible_slot { return slot }
		visible++
	}
	return last
}
