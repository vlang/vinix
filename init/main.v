module main

import os

#include <unistd.h>

fn C.sethostname(name charptr, len u64) int

fn main() {
	println('Vinix Init started')

	os.setenv('HOME', '/root', true)
	os.setenv('TERM', 'linux', true)
	os.setenv('PATH', '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('USER', 'root', true)
	os.setenv('LOGNAME', 'root', true)
	os.setenv('SHELL', '/bin/bash', true)
	os.setenv('MAIL', '/var/mail', true)
	os.setenv('XDG_RUNTIME_DIR', '/run', true)

	os.chdir('/root') or { panic('Could not move to root') }

	// Read hostname from /etc/hostname and pass to the kernel.
	hostname_file := os.read_file('/etc/hostname') or { 'vinix' }
	mut length := u64(0)
	for length < hostname_file.len && hostname_file[length] != `\n` {
		length++
	}
	C.sethostname(hostname_file[..length].str, length)

	for {
		os.system("exec -a '-bash' bash --login")
	}
}
