// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the native desktop IPC descriptors while using private browser libraries.
module main

import os

const runtime_root = '/usr/libexec/vinix-vox/root'

fn main() {
	executable := runtime_root + '/usr/bin/vox'
	if !os.is_file(executable) {
		eprintln('Vox is not installed. Stage its native runtime first.')
		exit(127)
	}
	os.setenv('FONTCONFIG_FILE', runtime_root + '/etc/fonts/vox.conf', true)
	os.setenv('FONTCONFIG_PATH', runtime_root + '/etc/fonts', true)
	os.setenv('FONTCONFIG_SYSROOT', runtime_root, true)
	os.setenv('SSL_CERT_FILE', runtime_root + '/etc/ssl/certs/ca-certificates.crt', true)
	os.setenv('GC_MARKERS', '1', true)
	os.setenv('LD_LIBRARY_PATH', runtime_root + '/usr/lib:' + runtime_root + '/lib', true)
	// Execute the ELF itself so /proc/self/exe remains Vox for script workers.
	os.execvp(executable, os.args[1..]) or {
		eprintln(err)
		exit(1)
	}
}
