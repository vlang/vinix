// SPDX-License-Identifier: GPL-2.0-or-later
// Direct ordinary-account diagnostic using an unchanged retained Wine closure.
// No new package-signature, sandbox or lease qualification is claimed here.
module main

import os
import time
import tools.packages.appsdk
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/wait.h>
#define owned_wine_open open
#define owned_wine_waitpid waitpid
fn C.owned_wine_open(&char, i32) i32
fn C.owned_wine_waitpid(i32, &i32, i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.getpid() i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.alarm(u32) u32
fn C._exit(i32)

struct Variable { name string value string }
fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn install(entry string) ! {
	mut split := -1
	for index, byte in entry { if byte == `=` { split = index; break } }
	if split <= 0 { return error('bad diagnostic environment') }
	name := entry[..split]; value := entry[split + 1..]
	defer { unsafe { name.free(); value.free() } }
	if os.setenv(name, value, true) != 0 { return error('cannot install diagnostic environment') }
}
fn suite() ! {
	C.alarm(150)
	data := '/tmp/vinix-owned-wine/data'
	os.mkdir('/tmp/vinix-owned-wine')!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.mkdir(data + '/tmp')!
	generation := '/var/lib/vinix-packages/generations/1/apps'
	runtime := generation + '/org.vinix.wine-runtime'
	app := generation + '/org.vinix.wine-win64-probe'
	root := runtime + '/root'
	builtins := root + '/usr/lib/wine/x86_64-windows'
	permissions := ['process']
	context := appsdk.Context{id: 'org.vinix.wine-win64-probe', version: '1.0.0', architecture: 'x86_64', kind: 'windows',
		generation: 1, repository: 'wine-fixture', public_key: 'b3cb7bb471c40c9afcef3250eb4595bf8fd71e0d21315300340a64ddad14c48a', sequence: 1,
		app_directory: app, data_directory: data, runtime_id: 'org.vinix.wine-runtime', runtime_version: '9.17.1', runtime_directory: runtime, permissions: permissions}
	mut environment := context.environment()!
	defer { appsdk.free_values(mut environment) }
	wineadapter.clear_bridge_overrides('wine-runner')!
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	defer { prefix.close() }
	loader := root + '/usr/bin/vinix-wine-musl'
	libraries := root + '/lib:' + root + '/usr/lib:' + root + '/usr/lib/wine/x86_64-unix:' + root + '/usr/lib/pulseaudio'
	for variable in [Variable{'HOME', data}, Variable{'TMPDIR', data + '/tmp'}, Variable{'PATH', runtime + '/bin'}, Variable{'LANG', 'C.UTF-8'},
		Variable{'WINEARCH', 'win64'}, Variable{'WINEPREFIX', prefix.path}, Variable{'WINEDLLPATH', root + '/usr/lib/wine/x86_64-unix:' + builtins},
		Variable{'WINELOADERNOEXEC', '1'}, Variable{'WINELOADER', root + '/usr/bin/wine'}, Variable{'WINESERVER', root + '/usr/bin/wineserver'},
		Variable{'USER', 'vinix'}, Variable{'LOGNAME', 'vinix'}, Variable{'USERNAME', 'vinix'}, Variable{'TEMP', 'C:\\users\\vinix\\Temp'}, Variable{'TMP', 'C:\\users\\vinix\\Temp'},
		Variable{'FONTCONFIG_PATH', root + '/etc/fonts'}, Variable{'FONTCONFIG_FILE', root + '/etc/fonts/fonts.conf'}, Variable{'FONTCONFIG_SYSROOT', root}]! {
		entry := variable.name + '=' + variable.value
		unsafe { environment.push_many(&entry, 1) }
	}
	for entry in environment { install(entry)! }
	mut guard := prefix.acquire_launch(data)!
	defer { guard.close() }
	mut directory := guard.prepare_server_directory(data)!
	defer { directory.close() }
	println('WINE OWNED DIAGNOSTIC starting foreground server')
	mut server := directory.start_child(&guard, data, wineadapter.ServerCommand{program: loader, arguments:
		['--library-path', libraries, '--argv0', root + '/usr/bin/wineserver', '--', root + '/usr/libexec/vinix-wine/wineserver', '--foreground']})!
	defer { if server.process_id() > 0 { server.terminate() or { eprintln('HWTEST FAIL owned server cleanup: ' + err.msg()) } } }
	mut connection := server.await_connection(&directory, &guard, data, 5000)!
	defer { connection.close() }
	println('WINE OWNED SERVER CONNECT PASS')
	mut client := connection.start_client(&directory, &guard, data, wineadapter.ServerCommand{program: loader, arguments:
		['--library-path', libraries, '--argv0', root + '/usr/bin/wine', '--', root + '/usr/libexec/vinix-wine/wine', app + '/bin/program.exe']}, environment)!
	defer { if client.process_id() > 0 { client.terminate() or { eprintln('HWTEST FAIL owned client cleanup: ' + err.msg()) } } }
	deadline := time.sys_mono_now() + 90 * time.second
	for {
		client.exec_ready()!
		status := client.collect()!
		if status.collected {
			number := status.code.str()
			println('WINE OWNED DIAGNOSTIC client status=' + number)
			unsafe { number.free() }
			need(status.code == 0, 'retained Wine client failed')!
			break
		}
		need(time.sys_mono_now() < deadline, 'retained Wine client timed out')!
		time.sleep(10 * time.millisecond)
	}
	server_deadline := time.sys_mono_now() + 30 * time.second
	for {
		status := server.collect()!
		if status.collected { need(status.code == 0, 'foreground server failed')!; break }
		need(time.sys_mono_now() < server_deadline, 'foreground server did not retire')!
		time.sleep(10 * time.millisecond)
	}
	println('WINE OWNED CLIENT EXEC PASS')
}
fn main() {
	if C.getpid() != 1 { eprintln('requires fixture PID1'); exit(2) }
	fd := C.owned_wine_open(c'/dev/com1', C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		suite() or { eprintln('HWTEST FAIL owned Wine: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.owned_wine_waitpid(pid, &status, 0) != pid || status != 0 {
		eprintln('HWTEST FAIL owned Wine suite'); for { time.sleep(time.second) }
	}
	println('HWTEST PASS owned Wine diagnostic')
	for { time.sleep(time.second) }
}
