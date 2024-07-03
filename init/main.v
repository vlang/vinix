// main.v: Vinix's init process.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module main

import os
#include <unistd.h>

fn C.sethostname(name charptr, len u64) int

fn main(){
	println('Vinix Init started')
	os.setenv('TERM', 'linux', true)
	os.setenv('PATH', '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('MAIL', '/var/mail', true)
	os.setenv('XDG_RUNTIME_DIR', '/run', true)

	// Read hostname from /etc/hostname and pass to the kernel.
	hostname_file := os.read_file('/etc/hostname') or { 'vinix' }
	mut length := u64(0)
	for length < hostname_file.len && hostname_file[length] != `\n` {
		length++
	}
	C.sethostname(hostname_file[..length].str, length)

	for {
		name := os.input("${os.hostname() or {"Vinix"}} name:")
		pass := os.input("Password for ${name}:")
		passwd := os.read_lines("/etc/passwd")!
		for line in passwd{
			split_line := line.split(":")
			if split_line[0] == name{
				if split_line[1] == pass{
					os.setenv('HOME', split_line[5], true)
					os.setenv('SHELL', split_line[6], true)
					os.setenv('PATH', '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
					os.setenv('USER', '${name}', true)
					os.setenv('LOGNAME', '${name}', true)

					os.chdir(os.getenv("HOME")) or { panic("Could not move to user's home.") }
					os.system(os.getenv("SHELL"))

					break
				}
			}
		}

	}
}
