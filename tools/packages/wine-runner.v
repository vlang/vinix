// SPDX-License-Identifier: GPL-2.0-or-later
// Native SDK entrypoint and Wine child-process bridge; no shell is involved.
module main

import appsdk
import os
import time
import wineadapter

#include <unistd.h>
fn C.execv(&char, &&char) int
#include <fcntl.h>
#define wine_runner_open open
fn C.wine_runner_open(&char, i32) i32

struct WineVariable { name string; value string }

// Opt-in staging path. The outer launcher must still retain its generation
// lease through a qualified descendant barrier. This waits only its two direct
// children; unexpected manager death relies on idle/foreign-server admission
// for later launches, not on retaining the prefix guard after death.
fn owned_wine(prefix &wineadapter.Prefix, data string, client_command []string, server_command []string) !int {
	cwd := C.wine_runner_open(c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if cwd < 0 { return error('cannot capture Wine application working directory') }
	defer { C.close(cwd) }
	mut guard := prefix.acquire_launch(data)!
	defer { guard.close() }
	mut directory := guard.prepare_server_directory(data)!
	defer { directory.close() }
	mut server := directory.start_child(&guard, data, wineadapter.ServerCommand{program: server_command[0], arguments: server_command[1..]})!
	defer { if server.process_id() > 0 { server.terminate() or { eprintln(err) } } }
	mut connection := server.await_connection(&directory, &guard, data, 5000)!
	defer { connection.close() }
	// Snapshot before fork, after override removal and canonical Wine setup.
	mut inherited := os.environ()
	defer { unsafe { for _, value in inherited { value.free() }; inherited.free() } }
	mut environment := []string{cap: inherited.len}
	defer { appsdk.free_values(mut environment) }
	for key, value in inherited { environment << key + '=' + value }
	mut client := connection.start_client_in(&directory, &guard, data, wineadapter.ServerCommand{program: client_command[0], arguments: client_command[1..]}, environment, cwd)!
	defer { if client.process_id() > 0 { client.terminate() or { eprintln(err) } } }
	mut result := 126
	for {
		client.exec_ready()!
		status := client.collect()!
		if status.collected { result = status.code; break }
		time.sleep(10 * time.millisecond)
	}
	// Preserve the application's result independently of server retirement.
	for {
		status := server.collect()!
		if status.collected { break }
		time.sleep(10 * time.millisecond)
	}
	return result
}

fn run_wine() !int {
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
	wineadapter.clear_bridge_overrides(name)!
	if name == 'wine-runner' {
		program := context.app_directory + '/bin/program.exe'
		defer { unsafe { program.free() } }
		if os.args.len < 2 || os.args[1] != program { return error('Wine entrypoint must name its signed application') }
	}
	program := root + if name == 'wineserver' { '/usr/libexec/vinix-wine/wineserver' } else { '/usr/libexec/vinix-wine/wine' }
	identity := root + if name == 'wineserver' { '/usr/bin/wineserver' } else { '/usr/bin/wine' }
	loader := root + '/usr/bin/vinix-wine-musl'
	libraries := root + '/lib:' + root + '/usr/lib:' + root + '/usr/lib/wine/x86_64-unix:' + root + '/usr/lib/pulseaudio'
	dlls := root + '/usr/lib/wine/x86_64-unix:' + builtins
	wine_loader := root + '/usr/bin/wine'
	wine_server := root + '/usr/bin/wineserver'
	fonts := root + '/etc/fonts'
	font_file := fonts + '/fonts.conf'
	defer { unsafe { program.free(); identity.free(); loader.free(); libraries.free(); dlls.free(); wine_loader.free(); wine_server.free(); fonts.free(); font_file.free() } }
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
		// The admitted source-built translator chooses separate RW/RX code
		// mappings itself when W+X is refused, and keeps them private across fork.
		for argument in [translated, '-B', '0x100000000', '-L', root]! { command << argument }
	}
	for argument in [loader, '--library-path', libraries, '--argv0', identity, '--', program]! { command << argument }
	for index in 1 .. os.args.len { command << os.args[index] }
	$if wine_owned_manager ? {
		if name == 'wine-runner' {
			$if amd64 {
				foreground := root + '/usr/libexec/vinix-wine/wineserver'
				defer { unsafe { foreground.free() } }
				server_command := [loader, '--library-path', libraries, '--argv0', wine_server, '--', foreground, '--foreground']
				defer { unsafe { (&array(&server_command)).free() } }
				return owned_wine(&prefix, context.data_directory, command, server_command)
			} $else { return error('owned Wine entrypoint is qualified only for x86_64') }
		}
	}
	mut pointers := []&char{cap: command.len + 1}
	defer { unsafe { pointers.free() } }
	for argument in command { pointers << &char(argument.str) }
	pointers << &char(unsafe { nil })
	prefix.recheck(context.data_directory)!
	C.execv(command[0].str, pointers.data)
	return error('packaged Wine runtime could not be executed')
}

fn main() { code := run_wine() or { eprintln(err); exit(126) }; exit(code) }
