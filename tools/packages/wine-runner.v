// SPDX-License-Identifier: GPL-2.0-or-later
// Native SDK entrypoint and Wine child-process bridge; no shell is involved.
module main

import appsdk
import os
import wineadapter

#include <unistd.h>
fn C.execv(&char, &&char) int

struct WineVariable { name string; value string }

fn run_wine() ! {
	mut context := appsdk.load()!
	defer { context.close() }
	if context.kind != 'windows' || context.runtime_id == '' || !context.declares('process') {
		return error('Wine requires a Windows SDK context, explicit runtime and process permission')
	}
	$if arm64 {
		if context.architecture != 'aarch64' { return error('Wine adapter architecture differs') }
	} $else $if amd64 {
		if context.architecture != 'x86_64' { return error('Wine adapter architecture differs') }
	} $else { return error('Wine adapter host architecture is unsupported') }
	root := context.runtime_directory + '/root'
	builtins := root + '/usr/lib/wine/x86_64-windows'
	defer { unsafe { root.free(); builtins.free() } }
	mut prefix := wineadapter.prepare_prefix(context.data_directory, builtins)!
	defer { prefix.close() }
	name := os.base(os.args[0])
	defer { unsafe { name.free() } }
	if name !in ['wine-runner', 'wine64', 'wineserver'] { return error('unknown Wine adapter mode') }
	if name == 'wine-runner' {
		program := context.app_directory + '/bin/program.exe'
		defer { unsafe { program.free() } }
		if os.args.len < 2 || os.args[1] != program { return error('Wine entrypoint must name its signed application') }
	}
	program := root + if name == 'wineserver' { '/usr/bin/wineserver' } else { '/usr/bin/wine' }
	loader := root + '/lib/ld-musl-x86_64.so.1'
	libraries := root + '/lib:' + root + '/usr/lib:' + root + '/usr/lib/wine/x86_64-unix:' + root + '/usr/lib/pulseaudio'
	dlls := root + '/usr/lib/wine/x86_64-unix:' + builtins
	wine_loader := context.runtime_directory + '/bin/wine64'
	wine_server := context.runtime_directory + '/bin/wineserver'
	fonts := root + '/etc/fonts'
	font_file := fonts + '/fonts.conf'
	defer { unsafe { program.free(); loader.free(); libraries.free(); dlls.free(); wine_loader.free(); wine_server.free(); fonts.free(); font_file.free() } }
	for key in ['LD_LIBRARY_PATH', 'LD_PRELOAD', 'QEMU_LD_PREFIX', 'QEMU_SET_ENV', 'QEMU_UNSET_ENV', 'VINIX_ALLOW_WX', 'WINEDLLOVERRIDES', 'WINEDEBUG']! { os.unsetenv(key) }
	for variable in [WineVariable{'WINEARCH', 'win64'}, WineVariable{'WINEPREFIX', prefix.path}, WineVariable{'WINEDLLPATH', dlls},
		WineVariable{'WINELOADERNOEXEC', '1'}, WineVariable{'WINELOADER', wine_loader}, WineVariable{'WINESERVER', wine_server},
		WineVariable{'USER', 'vinix'}, WineVariable{'LOGNAME', 'vinix'}, WineVariable{'USERNAME', 'vinix'},
		WineVariable{'TEMP', 'C:\\users\\vinix\\Temp'}, WineVariable{'TMP', 'C:\\users\\vinix\\Temp'},
		WineVariable{'FONTCONFIG_PATH', fonts}, WineVariable{'FONTCONFIG_FILE', font_file}, WineVariable{'FONTCONFIG_SYSROOT', root}]! {
		os.setenv(variable.name, variable.value, true)
	}
	mut command := []string{cap: os.args.len + 20}
	unsafe { command.flags |= .noslices }
	defer { unsafe { (&array(&command)).free() } }
	mut translated := ''
	defer { unsafe { translated.free() } }
	$if arm64 {
		translated = context.runtime_directory + '/bin/qemu-x86_64'
		// The exact admitted translator forces separate RW/RX code mappings.
		// Its Linux-user CLI does not implement a -split-wx switch.
		for argument in [translated, '-B', '0x100000000', '-L', root]! { command << argument }
	}
	for argument in [loader, '--library-path', libraries, '--argv0', program, '--', program]! { command << argument }
	for index in 1 .. os.args.len { command << os.args[index] }
	mut pointers := []&char{cap: command.len + 1}
	defer { unsafe { pointers.free() } }
	for argument in command { pointers << &char(argument.str) }
	pointers << &char(unsafe { nil })
	prefix.recheck(context.data_directory)!
	C.execv(command[0].str, pointers.data)
	return error('packaged Wine runtime could not be executed')
}

fn main() { run_wine() or { eprintln(err); exit(126) } }
