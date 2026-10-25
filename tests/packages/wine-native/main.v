// SPDX-License-Identifier: GPL-2.0-or-later
// A native ordinary-account execution of signed Wine and a real Win64 PE.
module main

import os
import time
import tools.packages.pkgcore

#include <fcntl.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <grp.h>

fn C.dup2(int, int) int
fn C.flock(int, int) int
fn C.setgroups(usize, voidptr) int
fn C.setresgid(u32, u32, u32) int
fn C.setresuid(u32, u32, u32) int
fn C.execv(&char, &&char) int

const application = 'org.vinix.wine-win64-probe'
const data = '/home/alex/.local/share/vinix-apps/' + application

fn nonblocking(fd int) ! {
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 { return error('cannot read child pipe flags') }
	if C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
		return error('cannot make child pipe nonblocking')
	}
	current := C.fcntl(fd, C.F_GETFL)
	if current < 0 || current & C.O_NONBLOCK == 0 {
		return error('child pipe did not retain nonblocking mode')
	}
}

fn smoke_child() {
	if os.args.len != 5 { exit(125) }
	os.unsetenv('VINIX_ALLOW_WX')
	if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0 || C.setresuid(1000, 1000, 1000) != 0 {
		exit(124)
	}
	if os.getuid() != 1000 || os.geteuid() != 1000 || os.getgid() != 1000 || os.getegid() != 1000 {
		exit(123)
	}
	args := [os.args[2], '-B', '0x100000000', '-L', os.args[3], os.args[4], 'true']!
	mut pointers := unsafe { [8]&char{} }
	for index, argument in args { pointers[index] = &char(argument.str) }
	C.execv(args[0].str, &pointers[0])
	exit(122)
}

fn native_loader_child() {
	if os.args.len != 7 { exit(125) }
	os.unsetenv('VINIX_ALLOW_WX')
	os.setenv('WINEDLLPATH', os.args[6], true)
	if C.setgroups(0, unsafe { nil }) != 0 || C.setresgid(1000, 1000, 1000) != 0 || C.setresuid(1000, 1000, 1000) != 0 {
		exit(124)
	}
	args := [os.args[2], '--library-path', os.args[3], '--argv0', os.args[4], '--', os.args[5],
		'--version']!
	mut pointers := unsafe { [10]&char{} }
	for index, argument in args { pointers[index] = &char(argument.str) }
	C.execv(args[0].str, &pointers[0])
	exit(122)
}

fn native_loader_smoke(generation string) ! {
	root := generation + '/apps/org.vinix.wine-runtime/root'
	loader := root + '/usr/bin/vinix-wine-musl'
	libraries := root + '/lib:' + root + '/usr/lib:' + root + '/usr/lib/wine/x86_64-unix:' + root + '/usr/lib/pulseaudio'
	wine := root + '/usr/libexec/vinix-wine/wine'
	identity := root + '/usr/bin/wine'
	dlls := root + '/usr/lib/wine/x86_64-unix:' + root + '/usr/lib/wine/x86_64-windows'
	defer {
		unsafe {
			root.free()
			loader.free()
			libraries.free()
			wine.free()
			identity.free()
			dlls.free()
		}
	}
	mut child := os.new_process('/sbin/init')
	defer {
		if child.is_alive() {
			child.signal_kill()
			child.wait()
		}
		child.close()
	}
	child.set_args(['--native-loader-smoke', loader, libraries, identity, wine, dlls])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	fd := child.stdio_fd[1]
	nonblocking(fd)!
	deadline := time.sys_mono_now() + 15 * time.second
	mut output := []u8{cap: 65536}
	defer { unsafe { output.free() } }
	mut buffer := [4096]u8{}
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count > 0 {
			if output.len + int(count) > 65536 {
				return error('native loader smoke output exceeded bound')
			}
			for index in 0 .. int(count) { output << buffer[index] }
		}
		if !child.is_alive() { break }
		if time.sys_mono_now() > deadline { return error('native loader smoke timed out') }
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count <= 0 { break }
		if output.len + int(count) > 65536 {
			return error('native loader smoke output exceeded bound')
		}
		for index in 0 .. int(count) { output << buffer[index] }
	}
	status := child.code.str()
	defer { unsafe { status.free() } }
	println('HWTEST INFO Wine ordinary loader version status=' + status)
	text := unsafe { tos(output.data, output.len) }
	println(text)
	if child.code != 0 || !text.contains('wine-9.17') {
		return error('ordinary native Wine loader version failed')
	}
}

fn smoke_status(qemu string, root string) !int {
	mut child := os.new_process('/sbin/init')
	defer {
		if child.is_alive() {
			child.signal_kill()
			child.wait()
		}
		child.close()
	}
	child.set_args(['--translator-smoke', qemu, root, '/usr/libexec/wine-qualification/busybox'])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	fd := child.stdio_fd[1]
	nonblocking(fd)!
	deadline := time.sys_mono_now() + 15 * time.second
	mut total := 0
	mut buffer := [4096]u8{}
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count > 0 {
			total += int(count)
			if total > 65536 { return error('translator smoke output exceeded bound') }
			print(unsafe { tos(&buffer[0], int(count)) })
		}
		if !child.is_alive() { break }
		if time.sys_mono_now() > deadline { return error('translator smoke timed out') }
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count <= 0 { break }
		total += int(count)
		if total > 65536 { return error('translator smoke output exceeded bound') }
		print(unsafe { tos(&buffer[0], int(count)) })
	}
	return child.code
}

fn translator_smoke(generation string) ! {
	runtime := generation + '/apps/org.vinix.wine-runtime'
	root := runtime + '/root'
	patched := runtime + '/bin/qemu-x86_64'
	defer {
		unsafe {
			runtime.free()
			root.free()
			patched.free()
		}
	}
	control := smoke_status('/usr/libexec/wine-qualification/qemu-original', root)!
	if control == 0 || control in [122, 123, 124, 125] {
		return error('ordinary default-RWX translator control did not fail at execution')
	}
	if smoke_status(patched, root)! != 0 {
		return error('ordinary split-WX translator could not run real x86 BusyBox true')
	}
	println('HWTEST INFO Wine translated BusyBox true ordinary split-WX control PASS')
}

fn command(arguments []string, input string) !string {
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	if child.code != 0 { return error('Wine qualification command failed: ' + output) }
	return output
}

fn ordinary_status(pid string) ! {
	text := os.read_file('/proc/' + pid + '/status')!
	defer { unsafe { text.free() } }
	lines := text.split_into_lines()
	defer { unsafe { lines.free() } }
	mut credentials := 0
	for line in lines {
		if line.starts_with('Uid:') || line.starts_with('Gid:') {
			fields := line.fields()
			defer { unsafe { fields.free() } }
			if fields.len != 5 { return error('unexpected process credentials') }
			for index in 1 .. fields.len {
				if fields[index] != '1000' {
					return error('Wine process retained privileged credentials')
				}
			}
			credentials++
		}
	}
	if credentials != 2 { return error('Wine process credentials were missing or duplicated') }
}

fn observe(generation string) ![]string {
	mut found := []string{}
	mut client := false
	mut server := false
	names := os.ls('/proc')!
	defer { unsafe { names.free() } }
	for name in names {
		if name == '' || name[0] < `0` || name[0] > `9` { continue }
		text := os.read_file('/proc/' + name + '/cmdline') or { continue }
		defer { unsafe { text.free() } }
		if text.contains(generation + '/apps/org.vinix.wine-runtime/root/usr/libexec/vinix-wine/wine') {
			ordinary_status(name)!
			client = client || text.contains('/usr/libexec/vinix-wine/wine\x00')
			server = server || text.contains('/usr/libexec/vinix-wine/wineserver\x00')
			found << name.clone()
		}
	}
	if !client || !server {
		return error('actual ordinary Wine client/server process pair was not observed')
	}
	return found
}

fn socket_check() ! {
	prefix := data + '/wine'
	for directory in [data, prefix, prefix + '/.wine-1000'] {
		st := os.lstat(directory)!
		if st.get_filetype() != .directory || st.uid != 1000 || st.gid != 1000 || st.mode & 0o777 != 0o700 {
			return error('Wine private prefix/server parent has unsafe ownership or mode')
		}
	}
	names := os.ls(prefix + '/.wine-1000')!
	defer { unsafe { names.free() } }
	if names.len != 1 || !names[0].starts_with('server-') {
		return error('Wine did not use one prefix-bound server directory')
	}
	server := prefix + '/.wine-1000/' + names[0]
	defer { unsafe { server.free() } }
	st := os.lstat(server)!
	if st.get_filetype() != .directory || st.uid != 1000 || st.gid != 1000 || st.mode & 0o777 != 0o700 {
		return error('Wine server directory is not private')
	}
	socket := os.lstat(server + '/socket')!
	if socket.get_filetype() != .socket || socket.uid != 1000 || socket.gid != 1000 {
		return error('Wine server socket owner differs')
	}
	if os.exists('/tmp/.wine-1000') {
		return error('Wine escaped its private prefix into global tmp')
	}
}

// These probes run only after the real signed launch has already failed. They
// preserve its SDK context, identity, unveil paths and promises, and substitute
// an explicit diagnostic command. They cannot satisfy a PASS gate.
fn diagnostic_command(plan pkgcore.Launch, arguments []string, label string) ! {
	mut child := os.new_process(plan.program)
	mut reaped := false
	defer {
		if !reaped && child.pid > 0 && child.is_alive() {
			child.signal_kill()
			child.wait()
		}
		child.close()
	}
	child.set_work_folder(plan.directory)
	child.set_args(arguments)
	child.set_redirect_stdio_merged()
	println('HWTEST DIAGNOSTIC Wine begin ' + label)
	child.run()
	if child.pid <= 0 { return error('diagnostic process did not start: ' + label) }
	println('HWTEST DIAGNOSTIC Wine spawned ' + label)
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	fd := child.stdio_fd[1]
	nonblocking(fd)!
	println('HWTEST DIAGNOSTIC Wine nonblocking ' + label)
	deadline := time.sys_mono_now() + 15 * time.second
	mut bytes := []u8{cap: 65536}
	defer { unsafe { bytes.free() } }
	mut buffer := [4096]u8{}
	mut raw_status := i32(0)
	mut timed_out := false
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count > 0 {
			if bytes.len + count > 65536 { return error('diagnostic output exceeded bound') }
			for index in 0 .. int(count) { bytes << buffer[index] }
		}
		waited := C.waitpid(child.pid, &raw_status, C.WNOHANG)
		if waited == child.pid {
			reaped = true
			break
		}
		if waited < 0 && C.errno != C.EINTR { return error('diagnostic waitpid failed: ' + label) }
		if time.sys_mono_now() > deadline {
			timed_out = true
			println('HWTEST DIAGNOSTIC Wine timeout ' + label)
			child.signal_kill()
			println('HWTEST DIAGNOSTIC Wine killed ' + label)
			for {
				result := C.waitpid(child.pid, &raw_status, 0)
				if result == child.pid { reaped = true; break }
				if result < 0 && C.errno == C.EINTR { continue }
				return error('diagnostic reap failed: ' + label)
			}
			break
		}
		time.sleep(10 * time.millisecond)
	}
	// This fixture collected the raw status itself; keep os.Process cleanup
	// from waiting for the same child again. Record signal and exit separately.
	child.status = .exited
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count <= 0 { break }
		if bytes.len + count > 65536 { return error('diagnostic output exceeded bound') }
		for index in 0 .. int(count) { bytes << buffer[index] }
	}
	raw := raw_status.str()
	signal := (raw_status & 0x7f).str()
	status := ((raw_status >> 8) & 0xff).str()
	timeout := timed_out.str()
	defer { unsafe { raw.free(); signal.free(); status.free(); timeout.free() } }
	println('HWTEST DIAGNOSTIC Wine ' + label + ' exit=' + status + ' signal=' + signal +
		' raw_wait=' + raw + ' timed_out=' + timeout)
	println(unsafe { tos(bytes.data, bytes.len) })
}

fn diagnostic_server_directory(label string) ! {
	base := data + '/wine/.wine-1000'
	defer { unsafe { base.free() } }
	names := os.ls(base)!
	defer { for name in names { unsafe { name.free() } }; unsafe { (&array(&names)).free() } }
	if names.len > 64 { return error('diagnostic server inventory exceeded bound') }
	for name in names {
		if !name.starts_with('server-') { continue }
		directory := base + '/' + name
		defer { unsafe { directory.free() } }
		entries := os.ls(directory)!
		defer { for entry in entries { unsafe { entry.free() } }; unsafe { (&array(&entries)).free() } }
		if entries.len > 64 { return error('diagnostic server entries exceeded bound') }
		for entry in entries {
			path := directory + '/' + entry
			defer { unsafe { path.free() } }
			st := os.lstat(path)!
			kind := st.get_filetype().str()
			uid := st.uid.str()
			gid := st.gid.str()
			mode := (st.mode & 0o7777).str()
			defer { unsafe { kind.free(); uid.free(); gid.free(); mode.free() } }
			println('HWTEST DIAGNOSTIC Wine ' + label + ' server-entry=' + name + '/' + entry +
				' kind=' + kind + ' uid=' + uid + ' gid=' + gid + ' mode_decimal=' + mode)
		}
		if entries.len == 0 { println('HWTEST DIAGNOSTIC Wine ' + label + ' server-empty=' + name) }
	}
}

fn failure_diagnostics(state pkgcore.State, generation string) ! {
	mut repositories := pkgcore.repository_configuration('/')!
	defer { repositories.close() }
	// The signed console fixture declares exactly process; the planner emits
	// the same grants and SDK environment used by its actual CLI launch.
	config := pkgcore.Config{
		architecture: repositories.architecture
		repositories: repositories.repositories
		policy:       pkgcore.Policy{ permissions: ['process'], offline: true, reserve_bytes: 0 }
	}
	defer { unsafe { config.policy.permissions.free() } }
	mut plan := pkgcore.launch_plan(config, '/var/lib/vinix-packages', state,
		application, data, 1000, 1000, [])!
	defer { plan.close() }
	mut separator := -1
	for index, argument in plan.arguments {
		if argument == '--' {
			separator = index
			break
		}
	}
	if separator < 0 { return error('diagnostic launch plan has no command separator') }
	runtime := generation + '/apps/org.vinix.wine-runtime'
	defer { unsafe { runtime.free() } }
	for suffix in ['/bin/wine64', '/bin/wineserver', '/root/usr/bin/wineserver',
		'/root/usr/libexec/vinix-wine/wineserver']! {
		program := runtime + suffix
		defer { unsafe { program.free() } }
		mut arguments := []string{cap: separator + 3}
		defer { unsafe { (&array(&arguments)).free() } }
		for index in 0 .. separator + 1 { arguments << plan.arguments[index] }
		arguments << program
		arguments << '--version'
		diagnostic_command(plan, arguments, suffix) or {
			eprintln('HWTEST DIAGNOSTIC Wine error: ' + err.msg())
			unsafe { err.free() }
		}
	}
	for suffix in ['', '/wine', '/wine/.wine-1000']! {
		path := data + suffix
		defer { unsafe { path.free() } }
		names := os.ls(path) or {
			eprintln('HWTEST DIAGNOSTIC Wine prefix unavailable: ' + path)
			unsafe { err.free() }
			continue
		}
		defer { unsafe { names.free() } }
		if names.len > 64 { return error('diagnostic prefix inventory exceeded bound') }
		for name in names { println('HWTEST DIAGNOSTIC Wine prefix ' + suffix + '/' + name) }
	}
	diagnostic_server_directory('before-init') or {
		eprintln('HWTEST DIAGNOSTIC Wine server inventory error: ' + err.msg())
		unsafe { err.free() }
	}
	// Foreground avoids Wine's daemon fork/status translation. Each run stays
	// inside the failed launch's exact sandbox and has a bounded parent wait.
	for foreground in [true, false]! {
		program := runtime + '/bin/wineserver'
		label := if foreground { 'wineserver-foreground-debug' } else { 'wineserver-background-debug' }
		defer { unsafe { program.free() } }
		mut arguments := []string{cap: separator + 4}
		defer { unsafe { (&array(&arguments)).free() } }
		for index in 0 .. separator + 1 { arguments << plan.arguments[index] }
		arguments << program
		if foreground { arguments << '--foreground' }
		arguments << '--debug'
		diagnostic_command(plan, arguments, label) or {
			eprintln('HWTEST DIAGNOSTIC Wine error: ' + err.msg())
			unsafe { err.free() }
		}
		diagnostic_server_directory(label) or {
			eprintln('HWTEST DIAGNOSTIC Wine server inventory error: ' + err.msg())
			unsafe { err.free() }
		}
	}
}

fn run() ! {
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	for directory in ['/tmp', '/run', '/root', '/home', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/tmp', 0o1777)!
	os.write_file('/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
	os.write_file('/etc/group', 'root:x:0:\n')!
	os.chmod('/etc/passwd', 0o644)!
	os.chmod('/etc/group', 0o644)!
	command(['/usr/sbin/vinix-account', 'init'], '')!
	command(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex', 'standard'], 'Wine qualification password\n')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	mut state := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	defer { state.close() }
	if state.packages.len != 2 { return error('signed Wine closure was not installed') }
	for installed in state.packages {
		if installed.package.id == application && installed.package.permissions != ['process'] {
			return error('console fixture grants differ')
		}
	}
	generation := '/var/lib/vinix-packages/generations/' + state.generation.str()
	defer { unsafe { generation.free() } }
	$if arm64 {
		translator_smoke(generation)!
	}
	$if amd64 {
		native_loader_smoke(generation)!
	}
	mut child := os.new_process('/usr/bin/vinix-package')
	defer {
		if child.is_alive() {
			child.signal_kill()
			child.wait()
		}
		child.close()
	}
	child.set_args(['run', application])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	fd := child.stdio_fd[1]
	nonblocking(fd)!
	mut bytes := []u8{cap: 32768}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	mut buffer := [4096]u8{}
	mut observed := false
	mut pids := []string{}
	defer { unsafe { pids.free() } }
	deadline := time.sys_mono_now() + 180 * time.second
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count > 0 {
			if bytes.len + count > 1024 * 1024 { return error('Wine output exceeded bound') }
			for i in 0 .. int(count) { bytes << buffer[i] }
		}
		text := unsafe { tos(bytes.data, bytes.len) }
		if !observed && text.contains('VINIX SIGNED REAL WIN64 READY\n') {
			pids = observe(generation)!
			socket_check()!
			lease := C.open((generation + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
			if lease < 0 { return error('missing signed generation lease') }
			busy := C.flock(lease, C.LOCK_EX | C.LOCK_NB) != 0
			C.close(lease)
			if !busy { return error('Wine child did not retain signed generation lease') }
			observed = true
		}
		if !child.is_alive() { break }
		if time.sys_mono_now() > deadline { return error('Wine execution timed out:\n' + text) }
		time.sleep(20 * time.millisecond)
	}
	child.wait()
	// Drain bytes that became readable together with child exit.
	for {
		count := C.read(fd, &buffer[0], usize(buffer.len))
		if count <= 0 { break }
		if bytes.len + count > 1024 * 1024 { return error('Wine output exceeded bound') }
		for i in 0 .. int(count) { bytes << buffer[i] }
	}
	text := unsafe { tos(bytes.data, bytes.len) }
	println('HWTEST INFO Wine signed execution status=' + child.code.str() + ' observed=' + observed.str())
	println(text)
	if child.code != 0 || !observed || text.count('VINIX SIGNED REAL WIN64 READY\n') != 1
		|| text.count('VINIX SIGNED REAL WIN64 PASS\n') != 1 {
		$if amd64 {
			failure_diagnostics(state, generation) or {
				eprintln('HWTEST DIAGNOSTIC Wine failed: ' + err.msg())
				unsafe { err.free() }
			}
		}
		return error('real signed Win64 execution failed')
	}
	file := data + '/wine/drive_c/users/vinix/Temp/real-win64.txt'
	if os.read_file(file)! != 'real Win64 Windows API execution\r\n' || os.stat(file)!.uid != 1000 || os.exists('/home/alex/denied-wine.txt') {
		return error('Win64 file API or sandbox refusal evidence differs')
	}
	retire := time.sys_mono_now() + 20 * time.second
	for pid in pids {
		for os.exists('/proc/' + pid) {
			// Wine's detached server may be adopted by this fixture PID1. The
			// package CLI already waited for its own child before this reap.
			mut status := i32(0)
			for C.waitpid(-1, &status, C.WNOHANG) > 0 {
			}
			if time.sys_mono_now() > retire {
				return error('Wine client/server was not reaped: ' + pid)
			}
			time.sleep(20 * time.millisecond)
		}
	}
	lease_path := generation + '/lease'
	defer { unsafe { lease_path.free() } }
	lease := C.open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 { return error('signed generation lease disappeared after Wine exit') }
	defer { C.close(lease) }
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) != 0 {
		return error('Wine generation lease was retained after child retirement')
	}
	if C.flock(lease, C.LOCK_UN) != 0 { return error('Wine generation lease release failed') }
	println('HWTEST INFO Wine signed-real-Win64 ordinary-private-prefix socket lease Windows-API outside-write-refused natural-exit PASS')
	println('HWTEST PASS packaged-Wine')
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--translator-smoke' {
		smoke_child()
		return
	}
	if os.args.len > 1 && os.args[1] == '--native-loader-smoke' {
		native_loader_child()
		return
	}
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	println('HWTEST START packaged-Wine')
	run() or { eprintln('HWTEST FAIL packaged-Wine: ' + err.msg()) }
	for { time.sleep(time.second) }
}
