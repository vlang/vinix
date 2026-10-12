module main

import os

#include <unistd.h>

fn C.sethostname(name &char, len usize) i32

fn main() {
	if os.args.len > 1 {
		if os.args.len == 2 && os.args[1] == '--version' {
			println('init from Vinix')
			return
		}
		if os.args.len == 2 && os.args[1] == '--help' {
			println('Usage: ${os.args[0]} [--help|--version]')
			return
		}
		eprintln('Unexpected init arguments')
		exit(1)
	}
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
	mut length := 0
	for length < hostname_file.len && hostname_file[length] != `\n` {
		length++
	}
	unsafe { C.sethostname(&char(hostname_file.str), usize(length)) }

	for {
		os.system("exec -a '-bash' bash --login")
	}
}
