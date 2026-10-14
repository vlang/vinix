// SPDX-License-Identifier: GPL-2.0-or-later
// Native ARM64 Alpine Zed launcher; its private libraries never replace the desktop's.
module main

import os
import display

const zed_root = '/usr/libexec/vinix-zed/root'

fn main() {
	display.ensure_refresh(os.getenv('DISPLAY')) or {
		eprintln('Zed display setup: ${err}')
		exit(1)
	}
	home := os.getenv_opt('HOME') or { '/root' }
	runtime := os.getenv_opt('XDG_RUNTIME_DIR') or { '${home}/.cache/zed-runtime' }
	for directory in ['${home}/.config', '${home}/.cache', '${home}/.local/share', runtime] {
		os.mkdir_all(directory) or {
			eprintln(err)
			exit(1)
		}
	}
	os.chmod(runtime, 0o700) or {
		eprintln(err)
		exit(1)
	}
	os.setenv('XDG_CONFIG_HOME', '${home}/.config', true)
	os.setenv('XDG_CACHE_HOME', '${home}/.cache', true)
	os.setenv('XDG_DATA_HOME', '${home}/.local/share', true)
	os.setenv('XDG_RUNTIME_DIR', runtime, true)
	os.setenv('FONTCONFIG_FILE', '${zed_root}/etc/fonts/fonts.conf', true)
	os.setenv('FONTCONFIG_PATH', '${zed_root}/etc/fonts', true)
	os.setenv('FONTCONFIG_SYSROOT', zed_root, true)
	os.setenv('XKB_CONFIG_ROOT', '${zed_root}/usr/share/X11/xkb', true)
	os.setenv('XLOCALEDIR', '${zed_root}/usr/share/X11/locale', true)
	os.setenv('LC_ALL', 'en_US.UTF-8', true)
	os.setenv('LD_LIBRARY_PATH', '${zed_root}/usr/lib:${zed_root}/lib', true)
	os.setenv('VK_ICD_FILENAMES', '${zed_root}/usr/share/vulkan/icd.d/lvp_icd.aarch64.json', true)
	os.setenv('LIBGL_ALWAYS_SOFTWARE', '1', true)
	os.setenv('PATH', '${zed_root}/usr/bin:/usr/bin:/bin', true)
	os.unsetenv('WAYLAND_DISPLAY')
	loader := '${zed_root}/lib/ld-musl-aarch64.so.1'
	executable := '${zed_root}/usr/libexec/zed-editor'
	if !os.is_file(executable) {
		eprintln('Zed is not installed. Stage the Alpine Zed runtime first.')
		exit(127)
	}
	os.execvp(loader, ['--library-path', '${zed_root}/usr/lib:${zed_root}/lib', executable,
		...os.args[1..]]) or {
		eprintln(err)
		exit(1)
	}
}
