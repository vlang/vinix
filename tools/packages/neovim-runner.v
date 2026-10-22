// SPDX-License-Identifier: GPL-2.0-or-later
// The signed manifest supplies these fixed paths before user arguments.
module main

import os

#include <unistd.h>
fn C.execv(&char, &&char) int

fn run_neovim() ! {
	if os.args.len < 3 { return error('usage: vinix-neovim-runner RUNTIME_DATA APPLICATION [ARGS...]') }
	for index in 1 .. 3 {
		path := os.args[index]
		if !path.starts_with('/') || path.contains('\x00') {
			return error('Neovim launch requires ordinary absolute packaged paths')
		}
		info := os.lstat(path)!
		if (index == 1 && info.get_filetype() != .directory)
			|| (index == 2 && (info.get_filetype() != .regular || info.mode & 0o111 == 0)) {
			return error('Neovim launch requires ordinary absolute packaged paths')
		}
	}
	// The sealed manifest supplies runtime data. Execute the static editor
	// directly so its terminal UI can self-spawn using /proc/self/exe.
	os.setenv('VIMRUNTIME', os.args[1], true)
	os.unsetenv('VIM')
	mut argv := []&char{cap: os.args.len - 1}
	defer { unsafe { argv.free() } }
	for argument in os.args[2..] { argv << &char(argument.str) }
	argv << &char(unsafe { nil })
	C.execv(os.args[2].str, argv.data)
	return error('packaged Neovim could not be executed')
}

fn main() { run_neovim() or { eprintln(err); exit(126) } }
