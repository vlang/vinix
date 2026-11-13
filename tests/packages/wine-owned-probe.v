// SPDX-License-Identifier: GPL-2.0-or-later
// Direct ordinary-account diagnostic using an unchanged retained Wine closure.
// No new package-signature, sandbox or production-launcher qualification.
module main

import os
import time
import tools.packages.appsdk
import tools.packages.wineadapter
import tools.packages.launchhold

#include <unistd.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/wait.h>
#include <sys/file.h>
#include <sys/prctl.h>
#include <signal.h>
#define owned_wine_open open
#define owned_wine_waitpid waitpid
#include <sys/syscall.h>
#include <sys/socket.h>
#define owned_wine_socket socket
fn C.owned_wine_socket(i32, i32, i32) i32
fn C.owned_wine_open(&char, i32) i32
fn C.owned_wine_waitpid(i32, &i32, i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.getpid() i32
fn C.getppid() i32
fn C.flock(i32, i32) i32
fn C.execv(&char, &&char) i32
fn C.prctl(i32, ...voidptr) i32
fn C.kill(i32, i32) i32
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
	os.mkdir_all(data)!; os.chmod(data, 0o700)!
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
	mut client_directory := app
	mut application := 'bin/program.exe'
	$if wine_owned_cwd ? {
		client_directory = data + '/cwd space'
		application = 'cwd program.exe'
		os.mkdir(client_directory)!
		os.write_file_array(client_directory + '/' + application, cwd_program.to_bytes())!
		os.write_file(client_directory + '/input space.txt', 'captured Windows cwd\n')!
		// A decoy in the prefix detects accidental prefix-relative access.
		os.write_file(prefix.path + '/input space.txt', 'wrong prefix directory\n')!
		mut expected := 'VINIX_CWD_EXPECTED=Z:\\tmp\\vinix-owned-wine\\data\\cwd space'
		$if wine_owned_cwd_wrong ? { expected = 'VINIX_CWD_EXPECTED=Z:\\wrong directory' }
		environment << expected.clone()
	}
	mut guard := prefix.acquire_launch(data)!
	defer { guard.close() }
	mut directory := guard.prepare_server_directory(data)!
	defer { directory.close() }
	println('WINE OWNED DIAGNOSTIC starting foreground server')
	mut server_arguments := ['--library-path', libraries, '--argv0', root + '/usr/bin/wineserver', '--', root + '/usr/libexec/vinix-wine/wineserver', '--foreground']
	$if wine_owned_lease ? { server_arguments << '--persistent=20' }
	mut server := directory.start_child(&guard, data, wineadapter.ServerCommand{program: loader, arguments: server_arguments})!
	defer { if server.process_id() > 0 { server.terminate() or { eprintln('HWTEST FAIL owned server cleanup: ' + err.msg()) } } }
	mut connection := server.await_connection(&directory, &guard, data, 5000)!
	defer { connection.close() }
	println('WINE OWNED SERVER CONNECT PASS')
	// Admit this exact application directory from the retained image separately.
	// Launch relative to it, so success also proves Wine resolves the client's
	// initial relative application path outside the prefix.
	app_fd := C.owned_wine_open(client_directory.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	need(app_fd >= 3, 'cannot capture retained application directory')!
	defer { C.close(app_fd) }
	mut client := connection.start_client_in(&directory, &guard, data, wineadapter.ServerCommand{program: loader, arguments:
		['--library-path', libraries, '--argv0', root + '/usr/bin/wine', '--', root + '/usr/libexec/vinix-wine/wine', application]}, environment, app_fd)!
	defer { if client.process_id() > 0 { client.terminate() or { eprintln('HWTEST FAIL owned client cleanup: ' + err.msg()) } } }
	deadline := time.sys_mono_now() + 90 * time.second
	for {
		client.exec_ready()!
		status := client.collect()!
		if status.collected {
			number := status.code.str()
			println('WINE OWNED DIAGNOSTIC client status=' + number)
			unsafe { number.free() }
			$if wine_owned_cwd_wrong ? {
				need(status.code == 41, 'cwd control failed at wrong Windows API gate')!
				println('WINE WINDOWS CWD CONTROL PASS incorrect expected directory detected')
			} $else {
			need(status.code == 0, 'retained Wine client failed')!
			}
			break
		}
		need(time.sys_mono_now() < deadline, 'retained Wine client timed out')!
		time.sleep(10 * time.millisecond)
	}
	$if wine_owned_lease ? {
		need(!server.collect()!.collected, 'persistent Wine server retired before manager')!
		os.write_file('/tmp/vinix-owned-lease/client-complete.tmp', server.process_id().str() + '\n' + C.getppid().str())!
		os.rename('/tmp/vinix-owned-lease/client-complete.tmp', '/tmp/vinix-owned-lease/client-complete')!
		println('WINE OWNED LEASE MANAGER PASS client=0; leaving live server')
		// Deliberate manager retirement without running its cleanup defers. The
		// non-execing holder must adopt and wait for the still-live Wine server.
		C._exit(37)
	}
	server_deadline := time.sys_mono_now() + 30 * time.second
	for {
		status := server.collect()!
		if status.collected { need(status.code == 0, 'foreground server failed')!; break }
		need(time.sys_mono_now() < server_deadline, 'foreground server did not retire')!
		time.sleep(10 * time.millisecond)
	}
	println('WINE OWNED CLIENT EXEC PASS')
	println('WINE OWNED RELATIVE APPLICATION PASS')
	$if wine_owned_cwd ? {
		$if !wine_owned_cwd_wrong ? {
			need(os.read_file(client_directory + '/parent output.txt')! == 'parent relative write\n', 'parent relative Windows write differs')!
			need(os.read_file(client_directory + '/child output.txt')! == 'child relative write\n', 'child relative Windows write differs')!
		}
		need(!os.exists(prefix.path + '/parent output.txt') && !os.exists(prefix.path + '/child output.txt'), 'Windows output escaped to prefix cwd')!
		println('WINE WINDOWS CWD HOST CHECK PASS outputs confined to requested cwd')
	}
}

fn lease_busy(path string, wanted bool) ! {
	fd := C.owned_wine_open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	need(fd >= 3, 'cannot open independent Wine lease check')!
	defer { C.close(fd) }
	result := C.flock(fd, C.LOCK_EX | C.LOCK_NB)
	if wanted { need(result != 0 && C.errno == C.EAGAIN, 'live Wine lease was not busy')! }
	else { need(result == 0, 'retired Wine lease remained busy')! }
}

fn lease_suite() ! {
	C.alarm(150)
	$if wine_owned_lease_caller_death ? {
		mut enabled := i32(0)
		need(C.prctl(36, voidptr(1), voidptr(0), voidptr(0), voidptr(0)) == 0
			&& C.prctl(37, unsafe { &enabled }, voidptr(0), voidptr(0), voidptr(0)) == 0 && enabled == 1, 'cannot enable observer subreaping')!
	}
	root := '/tmp/vinix-owned-lease'
	os.mkdir(root)!
	lease_path := root + '/lease'
	os.write_file(lease_path, '')!
	lease := C.owned_wine_open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC)
	need(lease >= 3 && C.flock(lease, C.LOCK_SH | C.LOCK_NB) == 0, 'cannot acquire Wine diagnostic lease')!
	caller := C.fork()
	if caller == 0 {
		$if wine_owned_lease_unheld ? {
			// Negative control: no inherited lock and no subreaping holder.
			C.close(lease)
			argv := [c'/sbin/init', c'--lease-manager', &char(unsafe { nil })]!
			C.execv(c'/sbin/init', unsafe { &&char(&argv[0]) }); C._exit(92)
		}
		code := launchhold.run(launchhold.Command{program: '/sbin/init', directory: '/tmp', arguments: ['--lease-manager']}, lease) or {
			eprintln('HWTEST FAIL Wine lease caller: ' + err.msg()); C._exit(93); return
		}
		C.close(lease)
		C._exit(i32(code))
	}
	C.close(lease)
	need(caller > 0, 'cannot fork Wine diagnostic caller')!
	marker := root + '/client-complete'
	deadline := time.sys_mono_now() + 100 * time.second
	for !os.exists(marker) {
		need(time.sys_mono_now() < deadline, 'Wine client completion marker timed out')!
		time.sleep(10 * time.millisecond)
	}
	// Check the lock first so the deliberately unheld control fails here.
	lease_busy(lease_path, true)!
	fields := os.read_file(marker)!.split('\n')
	need(fields.len == 2 && fields[0].int() > 1 && fields[1].int() > 1, 'invalid Wine adoption marker')!
	server_status := '/proc/' + fields[0] + '/status'
	holder := fields[1].int()
	mut adopted := false
	for !adopted {
		text := os.read_file(server_status)!
		mut live := false
		mut parent := 0
		for line in text.split_into_lines() {
			if line.starts_with('PPid:') { parent = line.all_after(':').trim_space().int() }
			if line.starts_with('State:') { live = !line.contains('Z') && !line.contains('X') }
		}
		adopted = parent == holder && live
		need(time.sys_mono_now() < deadline, 'live Wine server was not adopted by holder')!
		if !adopted { time.sleep(time.millisecond) }
	}
	mut status := i32(0)
	need(C.owned_wine_waitpid(caller, &status, C.WNOHANG) == 0, 'Wine holder returned with live adopted server')!
	lease_busy(lease_path, true)!
	println('WINE OWNED LEASE BUSY PASS client gone; live server adopted')
	mut awaited := caller
	$if wine_owned_lease_caller_death ? {
		need(C.kill(caller, C.SIGTERM) == 0, 'cannot terminate Wine lease caller')!
		for {
			waited := C.owned_wine_waitpid(caller, &status, 0)
			if waited < 0 && C.errno == C.EINTR { continue }
			need(waited == caller && status == C.SIGTERM, 'Wine caller signal status differs')!
			break
		}
		// The observer has closed its shared FD; caller death removes its copy.
		// Only the non-execing holder may keep the lease busy now.
		lease_busy(lease_path, true)!
		awaited = i32(holder)
		println('WINE OWNED LEASE CALLER DEATH PASS lease remains busy')
	}
	for {
		waited := C.owned_wine_waitpid(awaited, &status, C.WNOHANG)
		if waited == awaited { need(status == 37 << 8, 'Wine holder lost manager status')!; break }
		need(waited == 0 || (waited < 0 && C.errno == C.EINTR), 'cannot collect Wine caller')!
		need(time.sys_mono_now() < deadline, 'Wine descendants did not retire')!
		time.sleep(10 * time.millisecond)
	}
	lease_busy(lease_path, false)!
	need(!os.exists(server_status), 'Wine server still present after holder return')!
	println('WINE OWNED LEASE PASS manager=37; descendants retired; lease free')
}
fn sandbox_stage() ! {
	data := '/tmp/vinix-owned-wine/data'
	os.mkdir_all(data)!; os.chmod(data, 0o700)!
	os.write_file('/tmp/vinix-owned-sandbox-denied', 'outside diagnostic sandbox')!
	generation := '/var/lib/vinix-packages/generations/1/apps'
	// Match the current Windows + process launch-plan promises and path grants.
	// The retained sandbox additionally unveils the selected program itself rx.
	command := ['/usr/bin/vinix-sandbox', '--uid', '1000', '--gid', '1000',
		'--promises', 'stdio rpath wpath cpath flock exec prot_exec fattr sendfd recvfd proc unix',
		'--unveil', generation + '/org.vinix.wine-win64-probe', 'rx',
		'--unveil', generation + '/org.vinix.wine-runtime', 'rx',
		'--unveil', data, 'rwc', '--', '/sbin/init', '--sandbox-manager']
	mut pointers := []&char{cap: command.len + 1}
	defer { unsafe { pointers.free() } }
	for entry in command { pointers << entry.str }
	pointers << &char(unsafe { nil })
	C.execv(command[0].str, unsafe { &&char(pointers.data) })
	return error('cannot execute retained sandbox')
}

fn main() {
	$if wine_owned_sandbox ? {
		if os.args.len == 2 && os.args[1] == '--sandbox-manager' {
			need(os.getuid() == 1000 && os.geteuid() == 1000, 'sandbox manager requires ordinary account') or { C._exit(94) }
			fd := C.owned_wine_open(c'/tmp/vinix-owned-sandbox-denied', C.O_RDONLY | C.O_CLOEXEC)
			if fd >= 0 || C.errno !in [C.EACCES, C.ENOENT]! { eprintln('HWTEST FAIL owned sandbox: outside file was not denied'); C._exit(95) }
			println('WINE OWNED SANDBOX DENIAL PASS outside file inaccessible')
			C.alarm(15)
			control := C.fork()
			if control == 0 {
				C.owned_wine_socket(C.AF_INET, C.SOCK_STREAM, 0)
				C._exit(97) // Even an ordinary socket error is not pledge proof.
			}
			mut status := i32(0)
			mut waited := i32(-1)
			for {
				waited = if control > 0 { C.owned_wine_waitpid(control, &status, 0) } else { i32(-1) }
				if waited < 0 && control > 0 && C.errno == C.EINTR { continue }
				break
			}
			C.alarm(0)
			if control <= 0 || waited != control || status & 0x7f != C.SIGABRT { eprintln('HWTEST FAIL owned sandbox: internet socket did not trigger pledge SIGABRT'); C._exit(98) }
			println('WINE OWNED SANDBOX PLEDGE PASS internet socket killed with SIGABRT')
			suite() or { eprintln('HWTEST FAIL owned sandbox manager: ' + err.msg()); C._exit(96) }
			C._exit(0)
		}
	}
	$if wine_owned_lease ? {
		if os.args.len == 2 && os.args[1] == '--lease-manager' {
			need(os.getuid() == 1000 && os.geteuid() == 1000, 'Wine manager requires ordinary account') or { C._exit(94) }
			suite() or { eprintln('HWTEST FAIL Wine lease manager: ' + err.msg()); C._exit(95) }
			C._exit(96)
		}
	}
	if C.getpid() != 1 { eprintln('requires fixture PID1'); exit(2) }
	fd := C.owned_wine_open(c'/dev/com1', C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	os.mkdir_all('/tmp') or { panic(err) }; os.chmod('/tmp', 0o1777) or { panic(err) }
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		$if wine_owned_sandbox ? {
			sandbox_stage() or { eprintln('HWTEST FAIL owned sandbox setup: ' + err.msg()); C._exit(91) }
			C._exit(92)
		} $else $if wine_owned_lease ? {
			lease_suite() or { eprintln('HWTEST FAIL owned Wine lease: ' + err.msg()); C._exit(91) }
		} $else {
			suite() or { eprintln('HWTEST FAIL owned Wine: ' + err.msg()); C._exit(91) }
		}
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.owned_wine_waitpid(pid, &status, 0) != pid || status != 0 {
		eprintln('HWTEST FAIL owned Wine suite'); for { time.sleep(time.second) }
	}
	println('HWTEST PASS owned Wine diagnostic')
	for { time.sleep(time.second) }
}
