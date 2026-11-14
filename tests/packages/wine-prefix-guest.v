// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/wait.h>
fn C.getpid() i32
fn C.open(&char, i32, ...i32) i32
fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.execv(&char, &&char) i32
fn C._exit(i32)
fn C.alarm(u32) u32

fn cli(command string) ! {
	args := ['/usr/bin/vinix-package', command, 'app', '/tmp/private']
	mut pointers := []&char{cap: args.len + 1}
	for arg in args { pointers << arg.str }
	pointers << &char(unsafe { nil })
	pid := C.fork()
	if pid == 0 { C.execv(args[0].str, pointers.data); C._exit(127) }
	mut status := i32(0)
	if pid <= 0 || C.waitpid(pid, &status, 0) != pid || status != 0 { return error('public prefix command failed: ' + command) }
}

fn ordinary(builtins string) ! {
	mut prefix := wineadapter.prepare_prefix('/tmp/private', builtins)!
	prefix.close()
	system := '/tmp/private/wine/drive_c/windows/system32'
	os.rm(system + '/new.dll')!
	os.write_file('/tmp/private/sentinel', 'private contents')!
	cli('wine-prefix-review')!
	if os.exists(system + '/new.dll') { return error('review created a builtin') }
	cli('wine-prefix-additions')!
	if os.readlink(system + '/new.dll')! != builtins + '/new.dll' { return error('addition target differs') }
	cli('wine-prefix-additions')!
	cli('wine-prefix-review')!
	if os.read_file('/tmp/private/sentinel')! != 'private contents' { return error('private data changed') }
	println('WINE PREFIX CLI PASS ordinary signed installed review; exclusive addition; repeat; private data')
}

fn run() ! {
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	os.mkdir_all('/etc/vinix-packages')!
	os.mkdir_all('/tmp/app/bin')!; os.mkdir_all('/tmp/runtime/bin')!
	os.mkdir_all('/tmp/runtime/root/usr/lib/wine/x86_64-windows')!
	os.write_file('/tmp/app/bin/program.exe', 'marker application, never executed')!; os.chmod('/tmp/app/bin/program.exe', 0o755)!
	os.write_file('/tmp/runtime/bin/wine', 'marker runtime, never executed')!; os.chmod('/tmp/runtime/bin/wine', 0o755)!
	for name in ['base.dll', 'new.dll'] { os.write_file('/tmp/runtime/root/usr/lib/wine/x86_64-windows/' + name, 'marker builtin')! }
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	os.mkdir_all('/root/prefix-fixture')!; os.chmod('/root/prefix-fixture', 0o700)!
	key := pkgcore.keygen('/root/prefix-fixture/seed')!
	for p in [pkgcore.Package{id: 'app', name: 'Guest Windows fixture', version: '1.0.0', architecture: arch, license: 'MIT',
		kind: 'windows', runtime: 'wine', entrypoint: 'bin/wine', arguments: ['bin/program.exe'],
		dependencies: [pkgcore.Dependency{id: 'wine', minimum: '1.0.0'}]},
		pkgcore.Package{id: 'wine', name: 'Guest runtime fixture', version: '1.0.0', architecture: arch, license: 'MIT', kind: 'runtime', entrypoint: 'bin/wine'}] {
		os.write_file('/tmp/manifest.json', json2.encode(p))!
		pkgcore.pack('/tmp/manifest.json', if p.id == 'app' { '/tmp/app' } else { '/tmp/runtime' }, '/tmp/repository')!
	}
	pkgcore.publish('/tmp/repository', 'fixture', '/root/prefix-fixture/seed', 1, time.now().unix() + 3600)!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{architecture: arch,
		repositories: [pkgcore.Repository{id: 'fixture', url: 'file:///tmp/repository', public_key: key}], policy: pkgcore.Policy{reserve_bytes: 0}}))!
	mut catalog := (pkgcore.Service{}).refresh()!; catalog.close()
	mut state := (pkgcore.Service{}).transact('install', ['app'], pkgcore.TransactionOptions{})!
	defer { state.close() }
	builtins := '/var/lib/vinix-packages/generations/' + state.generation.str() + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	os.mkdir('/tmp/private')!; os.chmod('/tmp/private', 0o700)!; os.chown('/tmp/private', 1000, 1000)!
	pid := C.fork()
	if pid == 0 {
		C.alarm(90)
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		ordinary(builtins) or { eprintln('HWTEST FAIL wine-prefix-cli: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.waitpid(pid, &status, 0) != pid || status != 0 { return error('ordinary prefix fixture failed') }
}

fn main() {
	if C.getpid() != 1 { eprintln('requires guest PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL wine-prefix-cli: ' + err.msg()); for { time.sleep(time.second) } }
	println('HWTEST PASS wine-prefix-cli fixture')
	for { time.sleep(time.second) }
}
