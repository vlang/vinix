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
	mut username := ''
	mut new_shell := ''
	mut list_shells := false

	mut idx := 1
	for idx < os.args.len {
		match os.args[idx] {
			'--help' {
				println('Usage: ${os.args[0]} [options] [username]')
				println('')
				println('Change the login shell of a user')
				println('')
				println('Options:')
				println('-s, --shell <shell>  specify login shell')
				println('-l, --list-shells    print list of shells and exit')
				println('--help               display this help')
				println('--version            display version information')
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
					exit(1)
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
		println('${shells_file} could not be read')
		exit(0)
	}
	if list_shells {
		for sh in shells {
			println(sh)
		}
		exit(0)
	}

	// Get the shell.
	if new_shell == '' {
		println('Changing shell for ${username}')
		new_shell = os.input('New shell: ')
	}

	// Check whether the shell is valid.
	if C.access(new_shell.str, access_f_ok | access_r_ok) == 1 {
		println('${new_shell} cannot be found')
	} else if C.access(new_shell.str, access_x_ok) == 1 {
		println('${new_shell} is not executable')
	} else if new_shell !in shells {
		println('${new_shell} is not listed in ${shells_file}')
		println('Please consider adding it.')
	}

	// Change the shell in the passwd file.
	old_shell := os.getenv('SHELL')
	mut passwd_lines := os.read_lines(passwd_file) or {
		println('${passwd_file} could not be read')
		exit(1)
	}
	for i, pswd in passwd_lines {
		if pswd.starts_with(username) {
			passwd_lines[i] = passwd_lines[i].replace(old_shell, new_shell)
		}
	}
	mut new_passwd_file := os.create(passwd_file) or {
		println('${passwd_file} could not be created')
		exit(1)
	}
	for ln in passwd_lines {
		new_passwd_file.writeln(ln) or {
			println('${passwd_file} could not be written')
			exit(1)
		}
	}
	new_passwd_file.close()
	println('Shell changed ${old_shell} -> ${new_shell}')
}
