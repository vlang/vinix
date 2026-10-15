// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

const root = '/usr/libexec/vinix-emacs/root'

fn main() {
	if !os.is_file('${root}/usr/bin/emacs') {
		eprintln('Emacs is not installed. Stage the Alpine Emacs runtime first.')
		exit(127)
	}
	os.setenv('EMACSDATA', '${root}/usr/share/emacs/30.1/etc', true)
	os.setenv('EMACSDOC', '${root}/usr/share/emacs/30.1/etc', true)
	os.setenv('EMACSLOADPATH', '${root}/usr/share/emacs/30.1/lisp', true)
	libexec := '${root}/usr/lib/emacs/30.1/aarch64-alpine-linux-musl'
	os.setenv('EMACSPATH', libexec, true)
	mut dumps := (os.ls(libexec) or { []string{} }).filter(it.ends_with('.pdmp'))
	if dumps.len != 1 {
		eprintln('Emacs runtime must contain exactly one portable dump.')
		exit(1)
	}
	os.setenv('FONTCONFIG_FILE', '${root}/etc/fonts/fonts.conf', true)
	os.setenv('FONTCONFIG_PATH', '${root}/etc/fonts', true)
	os.setenv('FONTCONFIG_SYSROOT', root, true)
	os.setenv('XLOCALEDIR', '${root}/usr/share/X11/locale', true)
	os.setenv('LC_ALL', 'C.UTF-8', true)
	os.setenv('LD_LIBRARY_PATH', '${root}/usr/lib:${root}/lib', true)
	os.unsetenv('WAYLAND_DISPLAY')
	os.execvp('${root}/lib/ld-musl-aarch64.so.1', ['--library-path',
		'${root}/usr/lib:${root}/lib', '${root}/usr/bin/emacs',
		'--dump-file=${libexec}/${dumps[0]}',
		...os.args[1..]]) or {
		eprintln(err)
		exit(1)
	}
}
