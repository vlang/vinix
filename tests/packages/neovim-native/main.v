// SPDX-License-Identifier: GPL-2.0-or-later
// Real signed Neovim, its sealed runtime and an ordinary-account terminal.
module main

import desktop.ptycore
import os
import time
import tools.packages.pkgcore

#include <fcntl.h>
#include <sys/file.h>
#include <sys/wait.h>
fn C.dup2(int, int) int
fn C.flock(int, int) int

const application = 'org.neovim.editor'
const data = '/home/alex/.local/share/vinix-apps/' + application

fn command(args []string, input string) !(int, string) {
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..]); child.set_redirect_stdio_merged(); child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp(); child.wait()
	return child.code, output
}

fn success(args []string, input string) !string {
	code, output := command(args, input)!
	if code != 0 { return error(args.join(' ') + ': ' + output) }
	return output
}

fn terminal_read(fd int, marker string) !string {
	mut output := []u8{cap: 8192}
	unsafe { output.flags |= .noslices }
	defer { unsafe { output.free() } }
	mut buffer := [4096]u8{}
	for _ in 0 .. 12000 {
		got := C.read(fd, &buffer[0], usize(buffer.len))
		if got > 0 {
			if output.len + int(got) > 1024 * 1024 { return error('terminal output exceeded 1 MiB') }
			for i in 0 .. int(got) { output << buffer[i] }
			text := unsafe { tos(output.data, output.len) }
			if text.contains(marker) { return text.clone() }
		}
		time.sleep(10 * time.millisecond)
	}
	return error('terminal marker unavailable: ' + marker + '\n' + output.bytestr())
}

fn terminal_write(fd int, text string) ! {
	if C.write(fd, text.str, usize(text.len)) != text.len { return error('short terminal write') }
}

fn terminal_diagnostics() {
	for sample in 0 .. 3 {
		println('HWTEST DIAGNOSTIC task syscall sample ' + sample.str())
		os.write_file('/proc/sysrq-trigger', 't') or { println('HWTEST DIAGNOSTIC sysrq unavailable: ' + err.msg()) }
		time.sleep(100 * time.millisecond)
	}
	for name in ['startup.log', 'nvim.log', '.local/state/nvim/log'] {
		text := os.read_file(data + '/' + name) or { continue }
		if text.len <= 32768 { println('HWTEST DIAGNOSTIC ' + name + '\n' + text) }
	}
	for name in os.ls('/proc') or { []string{} } {
		if name.len == 0 || !name.bytes().all(it >= `0` && it <= `9`) { continue }
		cmdline := os.read_file('/proc/' + name + '/cmdline') or { continue }
		if !cmdline.contains('nvim') && !cmdline.contains('vinix-package') { continue }
		println('HWTEST DIAGNOSTIC pid ' + name + ' ' + cmdline.replace('\x00', ' '))
		println(os.read_file('/proc/' + name + '/status') or { 'status unavailable' })
	}
}

fn wait_child(pid int) ! {
	mut status := i32(0)
	for _ in 0 .. 12000 {
		if C.waitpid(pid, &status, C.WNOHANG) == pid {
			if status != 0 { return error('terminal child failed: ' + status.str()) }
			return
		}
		time.sleep(10 * time.millisecond)
	}
	return error('terminal child did not exit')
}

fn check_runtime_version(architecture string, version string) ! {
	mut state := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	defer { state.close() }
	if state.packages.len != 2 || state.architecture != architecture { return error('runtime transition lost signed package closure') }
	mut matched := false
	for installed in state.packages {
		if installed.package.id == 'org.vinix.neovim-runtime' {
			if installed.package.version != version { return error('runtime transition selected wrong version: ' + installed.package.version) }
			matched = true
		}
	}
	if !matched { return error('runtime transition omitted runtime') }
	path := '/var/lib/vinix-packages/generations/' + state.generation.str() + '/apps/org.vinix.neovim-runtime/share/nvim/runtime'
	lua := "lua assert(vim.env.VIMRUNTIME=='" + path + "'); assert(vim.fn.getline(1)=='Saved from signed Neovim'); assert(vim.lpeg.match(vim.lpeg.P('updated'),'updated')==8); vim.cmd('syntax on'); assert(vim.fn.filereadable(vim.env.VIMRUNTIME..'/doc/help.txt')==1); print('NEOVIM_VERSIONED_RUNTIME_OK')"
	output := success(['/usr/bin/vinix-package', 'run-args', application, '--data-cwd', '--',
		'--headless', '-u', 'NONE', '-i', 'NONE', '-n', 'saved note.txt', '-c', lua, '-c', 'qa!'], '')!
	if !output.contains('NEOVIM_VERSIONED_RUNTIME_OK') { return error('versioned runtime failed to reopen saved document: ' + output) }
}

fn run() ! {
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	for directory in ['/tmp', '/run', '/root', '/home', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/tmp', 0o1777)!
	// The minimal native image has no distribution account database. Seed only
	// root; the actual account tool creates system identities and the test user.
	os.write_file('/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\n')!
	os.write_file('/etc/group', 'root:x:0:\n')!
	os.chmod('/etc/passwd', 0o644)!
	os.chmod('/etc/group', 0o644)!
	println('HWTEST INFO Neovim initializing account database')
	success(['/usr/sbin/vinix-account', 'init'], '')!
	println('HWTEST INFO Neovim creating ordinary account')
	success(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex', 'standard'], 'Neovim qualification password\n')!
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	initial := pkgcore.read_state('/var/lib/vinix-packages', architecture)!
	if initial.packages.len != 2 { return error('signed application/runtime closure was not installed') }
	for installed in initial.packages {
		if installed.package.id == application && installed.package.permissions != ['files', 'process'] {
			return error('Neovim must have only explicit files/process grants, without network/display access')
		}
	}
	generation := '/var/lib/vinix-packages/generations/' + initial.generation.str()
	// Headless Lua executes inside the actual signed sandbox, not the fixture.
	lua := "lua assert(vim.version().major==0 and vim.version().minor==12 and vim.version().patch==5); assert(vim.uv.getuid()==1000); assert(vim.env.HOME=='" + data + "'); assert(vim.env.TMPDIR==vim.env.HOME..'/tmp'); assert(vim.v.servername:sub(1,#vim.env.TMPDIR+1)==vim.env.TMPDIR..'/'); local socket=assert(vim.uv.fs_stat(vim.v.servername)); assert(socket.type=='socket' and socket.uid==1000); local denied=assert(vim.uv.new_pipe(false)); assert(denied:bind('/home/alex/denied-neovim.sock')==nil); denied:close(); assert(vim.env.DISPLAY==nil and vim.env.XAUTHORITY==nil); assert(vim.env.VIMRUNTIME=='" + generation + "/apps/org.vinix.neovim-runtime/share/nvim/runtime'); assert(vim.fn.filereadable(vim.env.VIMRUNTIME..'/doc/help.txt')==1); assert(vim.lpeg.match(vim.lpeg.P('signed'),'signed')==7); assert(loadstring('return 6*7')()==42); vim.cmd('filetype on'); vim.cmd('syntax on'); vim.cmd('setfiletype lua'); assert(vim.bo.filetype=='lua'); assert(vim.regex('signed'):match_str('signed runtime')==0); assert(vim._ts_has_language('lua')==false); local f=io.open('/home/alex/denied-neovim','w'); assert(f==nil); assert(vim.fn.writefile({'runtime lua lpeg syntax uid=1000'},'runtime-proof.txt')==0); print('NEOVIM_RUNTIME_OK')"
	out := success(['/usr/bin/vinix-package', 'run-args', application, '--data-cwd', '--',
		'--headless', '-u', 'NONE', '-i', 'NONE', '-n', '-c', lua, '-c', 'qa!'], '')!
	if !out.contains('NEOVIM_RUNTIME_OK') || os.exists('/home/alex/denied-neovim') || os.exists('/home/alex/denied-neovim.sock') ||
		os.read_file(data + '/runtime-proof.txt')! != 'runtime lua lpeg syntax uid=1000\n' ||
		os.stat(data + '/runtime-proof.txt')!.uid != 1000 { return error('runtime/sandbox proof failed: ' + out) }
	println('HWTEST INFO Neovim signed-musl fixed-runtime Lua-LPEG Vimscript-syntax ordinary-uid outside-write-refused PASS')
	denied, reason := command(['/usr/bin/vinix-package', 'run-terminal-args', application, '--', '--version'], '')!
	if denied == 0 || !reason.contains('terminal standard input and output') { return error('pipe terminal request was not refused') }
	child := ptycore.spawn(['/usr/bin/vinix-package', 'run-terminal-args', application, '--data-cwd', '--',
		'-u', 'NONE', '-i', 'NONE', '-n', '--startuptime', 'startup.log', '-V1nvim.log', '-c', "lua print('NEOVIM_TERMINAL_READY')", 'saved note.txt'],
		['PATH=/usr/bin:/usr/sbin', 'HOME=/root', 'TERM=linux'], '/', 24, 80, 640, 384)!
	defer { C.close(child.terminal) }
	terminal_read(child.terminal, 'NEOVIM_TERMINAL_READY') or { terminal_diagnostics(); return err }
	terminal_write(child.terminal, '\r')!
	if !ptycore.resize(child.terminal, 30, 100, 800, 480) { return error('terminal resize failed') }
	lease := C.open((generation + '/lease').str, C.O_RDONLY | C.O_CLOEXEC)
	if lease < 0 { return error('cannot inspect generation lease') }
	defer { C.close(lease) }
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) == 0 { return error('live editor did not hold its signed generation lease') }
	terminal_write(child.terminal, 'iSaved from signed Neovim\x1b:w\r')!
	terminal_read(child.terminal, 'written')!
	if os.read_file(data + '/saved note.txt')! != 'Saved from signed Neovim\n' || os.stat(data + '/saved note.txt')!.uid != 1000 {
		return error('terminal save did not preserve exact ordinary-owned text')
	}
	success(['/usr/bin/vinix-package', '--offline', 'remove', application], '')!
	success(['/usr/bin/vinix-package', '--offline', 'install', application], '')!
	success(['/usr/bin/vinix-package', 'gc'], '')!
	if !os.is_dir(generation + '/apps/' + application) { return error('gc removed the live editor generation') }
	terminal_write(child.terminal, ':q!\r')!
	wait_child(child.pid)!
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) != 0 { return error('natural editor exit did not release generation lease') }
	C.flock(lease, C.LOCK_UN)
	success(['/usr/bin/vinix-package', 'gc'], '')!
	if os.exists(generation) { return error('gc retained the released obsolete generation') }
	println('HWTEST INFO Neovim real-PTY input resize exact-save ordinary-owner live-uninstall lease-held natural-exit gc PASS')
	// Both signed runtime versions contain the exact same real Neovim payload;
	// the versioned manifests exercise dependency selection and reversible state.
	key := os.read_file('/usr/share/neovim-update/public-key')!.trim_space()
	success(['/usr/bin/vinix-package', '--offline', 'repo-enroll', 'neovim-fixture', 'file:///usr/share/neovim-update', key], '')!
	success(['/usr/bin/vinix-package', '--offline', 'update'], '')!
	success(['/usr/bin/vinix-package', '--offline', 'upgrade'], '')!
	check_runtime_version(architecture, '1.1.0')!
	success(['/usr/bin/vinix-package', '--offline', 'rollback'], '')!
	check_runtime_version(architecture, '1.0.0')!
	println('HWTEST INFO Neovim signed-runtime update-1.1 rollback-1.0 exact-Lua-reopen offline PASS')
	reopen := "lua assert(vim.fn.getline(1)=='Saved from signed Neovim'); print('NEOVIM_REOPEN_OK')"
	reopened := success(['/usr/bin/vinix-package', 'run-args', application, '--data-cwd', '--',
		'--headless', '-u', 'NONE', '-i', 'NONE', '-n', 'saved note.txt', '-c', reopen, '-c', 'qa!'], '')!
	if !reopened.contains('NEOVIM_REOPEN_OK') { return error('offline reinstall lost saved contents: ' + reopened) }
	success(['/usr/bin/vinix-package', '--offline', 'remove', application], '')!
	if os.read_file(data + '/saved note.txt')! != 'Saved from signed Neovim\n' { return error('uninstall lost user data') }
	println('HWTEST INFO Neovim offline-cache reinstall exact-reopen data-preserving-uninstall pipe-refusal PASS')
	println('HWTEST PASS packaged-Neovim')
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packaged-Neovim')
	run() or { eprintln('HWTEST FAIL packaged-Neovim: ' + err.msg()) }
	for { time.sleep(time.second) }
}
