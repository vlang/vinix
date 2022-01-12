// main.v: Main file of the chsh utility.
// Copyright (C) 2022 streaksu
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
module main

import os
#include <unistd.h>

fn C.access(name charptr, mode u32) int

const access_f_ok = 1
const access_r_ok = 2
const access_x_ok = 8
const shells_file = '/etc/shells'
const passwd_file = '/etc/passwd'

fn main() {
	// Get command line options, and set defaults.
	mut username    := ''
	mut new_shell   := ''
	mut list_shells := false

	mut idx := 1
	for idx < os.args.len {
		match os.args[idx] {
			'--help' {
				println('Usage: chsh [options] [username]')
				println('')
				println('Change the login shell of a user')
				println('')
				println('Options:')
				println('-s, --shell <shell>  specify login shell')
				println('-l, --list-shells    print list of shells and exit')
				println('-u, --help           display this help')
				println('-v, --version        display version information')
				exit(0)
			}
			'--version' {
				println('chsh from util-vinix')
				exit(0)
			}
			'-s', '--shell' {
				idx++
				if idx < os.args.len {
					new_shell = os.args[idx]
				} else {
					println('-s/--shell argument needs an argument')
					exit(0)
				}
			}
			'-l' {
				list_shells = true
			}
			else {
				username = os.args[idx]
				break
			}
		}
		idx++
	}

	// Get the current user if it was not specified.
	if username == '' {
		username = os.getenv('USER')
	}

	// Get the shell list and print them if requested.
	// TODO: Support comments in the shells file.
	shells := os.read_lines(shells_file) or {
		println('$shells_file could not be read')
		exit(0)
	}
	if list_shells {
		for sh in shells {
			println(sh)
		}
		exit(0)
	}

	// Get the shell.
	if new_shell == "" {
		println("Changing shell for $username")
		new_shell = os.input("New shell: ")
	}

	// Check whether the shell is valid.
	if C.access(new_shell.str, access_f_ok | access_r_ok) == 1 {
		println("$new_shell cannot be found")
	} else if C.access(new_shell.str, access_x_ok) == 1 {
		println("$new_shell is not executable")
	} else if new_shell !in shells {
		println("$new_shell is not listed in $shells_file")
		println("Please consider adding it.")
	}

	// Change the shell in the passwd file.
	old_shell := os.getenv('SHELL')
	mut passwd_lines := os.read_lines(passwd_file) or {
		println('$passwd_file could not be read')
		exit(0)
	}
	for i, pswd in passwd_lines {
		if pswd.starts_with(username) {
			passwd_lines[i] = passwd_lines[i].replace(old_shell, new_shell)
		}
	}
	mut new_passwd_file := os.create(passwd_file) or {
		println('$passwd_file could not be created')
		exit(0)
	}
	for ln in passwd_lines {
		new_passwd_file.writeln(ln) or {
			println('$passwd_file could not be written')
			exit(0)
		}
	}
	new_passwd_file.close()
	println("Shell changed $old_shell -> $new_shell")
}
