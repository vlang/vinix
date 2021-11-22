module main

import os

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

	// FIXME: Doing this instead of the cd bellow causes the system to need
	// 2 spaces instead of one in the login tty
	// ??????????????????
	// os.chdir('/root') or { panic('Could not move to root') }

	for {
		os.system('cd ~ && bash --login')
	}
}
