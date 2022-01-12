// main.v: Main file of the fetch utility.
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

fn C.getlogin() charptr
fn C.gethostname(name charptr, len u64) int

const (
	escape_cyan  = "\e[1;36m"
	escape_blue  = "\e[1;34m"
	escape_reset = "\e[0m"
)

fn main() {
	mut hostname_buffer := [256]byte{}
	if unsafe { C.gethostname(&hostname_buffer[0], 256) } != 0 {
		panic("gethostname() failed!")
	}
	uname_result := os.uname()

	user     := unsafe { cstring_to_vstring(C.getlogin()) }
	hostname := unsafe { (&hostname_buffer[0]).vstring()  }
	os_name  := "${uname_result.sysname} ${uname_result.machine} ${uname_result.version}"
	kernel   := uname_result.sysname
	shell    := os.getenv("SHELL")

	logo_print(r" __          __   ", "")
	logo_print(r" \ \        / //  ", "${user}${escape_blue}@${escape_reset}${hostname}")
	logo_print(r"  \ \      / //   ", "${escape_blue}OS${escape_reset}:     ${os_name}")
	logo_print(r"   \ \    / //    ", "${escape_blue}KERNEL${escape_reset}: ${kernel}")
	logo_print(r"    \ \  / //     ", "${escape_blue}SHELL${escape_reset}:  ${shell}")
	logo_print(r"     \ \/ //      ", "")
	logo_print(r"      \/_//       ", "")
	println("")
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
		print("${c:c}")
	}

	println(message)
}
