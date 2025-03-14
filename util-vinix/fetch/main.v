module main

import os

#include <unistd.h>

fn C.getlogin() charptr
fn C.gethostname(name charptr, len u64) int

const escape_cyan = '\e[1;36m'
const escape_blue = '\e[1;34m'
const escape_reset = '\e[0m'

fn main() {
	mut idx := 1
	for idx < os.args.len {
		match os.args[idx] {
			'--help' {
				println('Usage: ${os.args[0]} [options]')
				println('')
				println('List system information in a user-friendly format')
				println('')
				println('Options:')
				println('--help    display this help')
				println('--version display version information')
				exit(0)
			}
			'--version' {
				println('fetch from util-vinix')
				exit(0)
			}
			else {
				println("Unexpected argument '${os.args[idx]}'")
				exit(1)
			}
		}
		idx++
	}

	mut hostname_buffer := [256]u8{}
	if unsafe { C.gethostname(&hostname_buffer[0], 256) } != 0 {
		panic('gethostname() failed!')
	}
	uname_result := os.uname()

	user := unsafe { cstring_to_vstring(C.getlogin()) }
	hostname := unsafe { (&hostname_buffer[0]).vstring() }
	os_name := '${uname_result.sysname} ${uname_result.machine} ${uname_result.version}'
	kernel := uname_result.sysname
	shell := os.getenv('SHELL')

	logo_print(r' __          __   ', '')
	logo_print(r' \ \        / //  ', '${user}${escape_blue}@${escape_reset}${hostname}')
	logo_print(r'  \ \      / //   ', '${escape_blue}OS${escape_reset}:     ${os_name}')
	logo_print(r'   \ \    / //    ', '${escape_blue}KERNEL${escape_reset}: ${kernel}')
	logo_print(r'    \ \  / //     ', '${escape_blue}SHELL${escape_reset}:  ${shell}')
	logo_print(r'     \ \/ //      ', '')
	logo_print(r'      \/_//       ', '')
	println('')
}

fn logo_print(logo string, message string) {
	for c in logo {
		match c {
			`_`, `\\` {
				print(escape_cyan)
			}
			`/` {
				print(escape_blue)
			}
			else {
				print(escape_reset)
			}
		}
		print('${c:c}')
	}

	println(message)
}
