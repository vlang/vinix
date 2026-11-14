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
#include <signal.h>
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
fn C.kill(i32, i32) i32
fn C.flock(i32, i32) i32

fn exec_cli(command string) {
	args := ['/usr/bin/vinix-package', command, 'app', '/tmp/private']
	mut pointers := []&char{cap: args.len + 1}
	for arg in args { pointers << arg.str }
	pointers << &char(unsafe { nil })
	C.execv(args[0].str, pointers.data)
	C._exit(127)
}

fn cli_status(command string, expected i32) ! {
	pid := C.fork()
	if pid == 0 { exec_cli(command) }
	mut status := i32(0)
	if pid <= 0 || C.waitpid(pid, &status, 0) != pid || status != (expected << 8) { return error('public prefix command status differs: ' + command) }
}

fn cli(command string) ! { cli_status(command, 0)! }

fn unchanged_upgrade(system string, old_builtins string) ! {
	names := os.ls(system)!
	if names.len != 34 { return error('stage refusal changed the builtin inventory') }
	for name in names {
		if os.readlink(system + '/' + name)! != old_builtins + '/' + name {
			return error('stage refusal changed an existing builtin')
		}
	}
	if os.exists(system + '/extra.dll') || os.is_link(system + '/extra.dll') {
		return error('stage refusal created an addition')
	}
	if os.read_file('/tmp/private/sentinel')! != 'private contents' {
		return error('stage refusal changed private data')
	}
}

fn ordinary(builtins string) ! {
	mut prefix := wineadapter.prepare_prefix('/tmp/private', builtins)!
	defer { prefix.close() }
	system := '/tmp/private/wine/drive_c/windows/system32'
	os.rm(system + '/new.dll')!
	os.write_file('/tmp/private/sentinel', 'private contents')!
	cli('wine-prefix-review')!
	if os.exists(system + '/new.dll') { return error('review created a builtin') }
	mut guard := prefix.acquire_launch('/tmp/private')!
	defer { guard.close() }
	cli_status('wine-prefix-additions', 1)!
	guard.close()
	if os.exists(system + '/new.dll') { return error('competing additions changed prefix') }
	os.write_file(system + '/new.dll', 'personal DLL contents')!
	cli_status('wine-prefix-additions', 1)!
	if os.read_file(system + '/new.dll')! != 'personal DLL contents' { return error('collision replaced personal file') }
	os.rm(system + '/new.dll')!
	cli('wine-prefix-additions')!
	if os.readlink(system + '/new.dll')! != builtins + '/new.dll' { return error('addition target differs') }
	cli('wine-prefix-additions')!
	cli('wine-prefix-review')!
	if os.read_file('/tmp/private/sentinel')! != 'private contents' { return error('private data changed') }
	println('WINE PREFIX REFUSALS PASS competing managed launch; personal DLL preserved; retry')
	println('WINE PREFIX CLI PASS ordinary signed installed review; exclusive addition; repeat; private data')
}

fn ordinary_upgrade(old_builtins string, selected_builtins string) ! {
	cli('wine-prefix-review')!
	cli_status('wine-prefix-additions', 1)!
	system := '/tmp/private/wine/drive_c/windows/system32'
	for name in ['base.dll', 'new.dll'] {
		if os.readlink(system + '/' + name)! != old_builtins + '/' + name { return error('upgrade refusal changed existing link') }
	}
	if os.exists(system + '/extra.dll') { return error('upgrade refusal created an addition before retargeting') }
	if os.read_file('/tmp/private/sentinel')! != 'private contents' { return error('upgrade refusal changed private data') }
	println('WINE PREFIX UPGRADE PASS signed generation change; review; retarget refusal; old links and private data preserved')
	stage := '/tmp/private/wine/.vinix-builtin-next'
	os.write_file(stage, 'personal stage contents')!
	cli_status('wine-prefix-migrate', 1)!
	if os.is_link(stage) || os.read_file(stage)! != 'personal stage contents' { return error('migration changed personal stage') }
	unchanged_upgrade(system, old_builtins)!
	os.rm(stage)!
	os.mkdir(stage)!
	os.write_file(stage + '/sentinel', 'personal directory contents')!
	cli_status('wine-prefix-migrate', 1)!
	if !os.is_dir(stage) || os.read_file(stage + '/sentinel')! != 'personal directory contents' { return error('migration changed stage directory') }
	unchanged_upgrade(system, old_builtins)!
	os.rmdir_all(stage)!
	os.symlink('/tmp/private/sentinel', stage)!
	cli_status('wine-prefix-migrate', 1)!
	if os.readlink(stage)! != '/tmp/private/sentinel' { return error('migration changed foreign stage link') }
	unchanged_upgrade(system, old_builtins)!
	os.rm(stage)!
	// Reconstruct an interrupted, authenticated stage whose row sorts after base.
	// The public writer must consume this row before staging any other binding.
	os.symlink(selected_builtins + '/new.dll', stage)!
	writer := C.fork()
	if writer == 0 {
		exec_cli('wine-prefix-migrate')
	}
	if writer < 0 { return error('cannot fork migration owner') }
	mut reaped := false
	defer {
		if !reaped { C.kill(writer, C.SIGKILL); mut ignored := i32(0); C.waitpid(writer, &ignored, 0) }
	}
	deadline := time.now().unix_milli() + 10000
	for os.readlink(system + '/base.dll')! != selected_builtins + '/base.dll' && time.now().unix_milli() < deadline {
		time.sleep(time.millisecond)
	}
	if os.readlink(system + '/base.dll')! != selected_builtins + '/base.dll' { return error('migration owner did not reach first retarget') }
	if C.kill(writer, C.SIGSTOP) != 0 { return error('cannot stop migration owner') }
	mut status := i32(0)
	if C.waitpid(writer, &status, C.WUNTRACED) != writer || status & 0xff != 0x7f { return error('migration owner did not stop during partial progress') }
	if os.readlink(system + '/new.dll')! != selected_builtins + '/new.dll' { return error('public migration did not prioritize the retained stage') }
	mut remaining := 0
	for index in 0 .. 32 {
		name := '/retarget-' + index.str() + '.dll'
		observed := os.readlink(system + name)!
		if observed == old_builtins + name { remaining++ }
		else if observed != selected_builtins + name { return error('partial migration link is neither old nor selected') }
	}
	if remaining == 0 { return error('migration completed before interruption') }
	cli_status('wine-prefix-additions', 1)!
	suffix := '/apps/wine/root/usr/lib/wine/x86_64-windows'
	lease_path := selected_builtins[..selected_builtins.len - suffix.len] + '/lease'
	lease := C.open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if lease < 0 { return error('cannot capture generation lease probe') }
	defer { C.close(lease) }
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) == 0 { return error('live migration owner lost generation lease') }
	if C.kill(writer, C.SIGKILL) != 0 || C.waitpid(writer, &status, 0) != writer || status & 0x7f != C.SIGKILL {
		return error('migration owner SIGKILL was not collected')
	}
	reaped = true
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) != 0 { return error('dead migration owner retained generation lease') }
	if C.flock(lease, C.LOCK_UN) != 0 { return error('cannot retire generation lease probe') }
	cli('wine-prefix-migrate')!
	cli('wine-prefix-migrate')!
	mut owner := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private')!
	defer { owner.close() }
	owner.recheck()!
	if owner.review.review.prior_generation != 0 || !owner.review.review.bindings.all(it.operation == .keep) {
		return error('migration did not complete the selected generation')
	}
	owner.close()
	for name in ['base.dll', 'new.dll', 'extra.dll'] {
		if os.readlink(system + '/' + name)! != selected_builtins + '/' + name { return error('migrated builtin target differs') }
	}
	for index in 0 .. 32 {
		name := '/retarget-' + index.str() + '.dll'
		if os.readlink(system + name)! != selected_builtins + name { return error('resumed migration target differs') }
	}
	cli('wine-prefix-review')!
	cli('wine-prefix-additions')!
	mut prepared := wineadapter.prepare_prefix('/tmp/private', selected_builtins)!
	prepared.close()
	if os.read_file('/tmp/private/sentinel')! != 'private contents' { return error('migration changed private data') }
	if os.exists(stage) || os.is_link(stage) { return error('migration left a staging entry') }
	println('WINE PREFIX MIGRATION PASS signed runtime retarget; added link; repeat; public review; private data')
	println('WINE PREFIX OWNER DEATH PASS partial retarget; live lease and guard; SIGKILL release; admitted resume')
	println('WINE PREFIX MIGRATE CLI PASS public writer SIGKILL; public resume; repeat; admitted verification')
	println('WINE PREFIX STAGE CLI PASS personal file; directory; foreign link preserved; authenticated stage resumed first')
}

fn ordinary_rollback(previous string, restored string) ! {
	system := '/tmp/private/wine/drive_c/windows/system32'
	mut before := map[string]string{}
	for name in os.ls(system)! { before[name] = os.readlink(system + '/' + name)! }
	if before.len != 35 || before['extra.dll'] != previous + '/extra.dll' {
		return error('rollback fixture lacks the added generation binding')
	}
	if os.read_file(previous + '/base.dll')! != 'upgraded marker builtin'
		|| os.read_file(restored + '/base.dll')! != 'marker builtin'
		|| os.exists(restored + '/extra.dll') || os.is_link(restored + '/extra.dll') {
		return error('rollback fixture did not restore the distinct older payload')
	}
	// Rollback removed extra.dll from the signed inventory. Refuse before any
	// rewrite, including additions-only, rather than deleting an unknown entry.
	mut reason := ''
	if mut owner := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private') {
		owner.close()
		return error('rollback admitted the obsolete generation link')
	} else {
		reason = err.msg()
	}
	if !reason.contains('package-generation link absent from the selected builtin inventory') {
		return error('rollback did not refuse the obsolete generation link: ' + reason)
	}
	for command in ['wine-prefix-review', 'wine-prefix-additions', 'wine-prefix-migrate'] {
		cli_status(command, 1)!
		if os.ls(system)!.len != before.len { return error('rollback refusal changed inventory') }
		for name, target in before {
			if os.readlink(system + '/' + name)! != target { return error('rollback refusal changed binding') }
		}
		if os.read_file('/tmp/private/sentinel')! != 'private contents'
			|| os.exists('/tmp/private/wine/.vinix-builtin-next') || os.is_link('/tmp/private/wine/.vinix-builtin-next') {
			return error('rollback refusal changed private data or stage')
		}
	}
	println('WINE PREFIX ROLLBACK REFUSAL PASS removed builtin; all public commands; bindings and private data preserved')
	// Explicit fixture-owner cleanup, not an automatic migration policy.
	os.rm(system + '/extra.dll')!
	cli('wine-prefix-review')!
	cli('wine-prefix-migrate')!
	cli('wine-prefix-migrate')!
	mut verified := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private')!
	defer { verified.close() }
	verified.recheck()!
	if verified.review.review.prior_generation != 0 || verified.review.review.bindings.len != 34
		|| !verified.review.review.bindings.all(it.operation == .keep) {
		return error('rollback migration did not admit the restored inventory')
	}
	for name in os.ls(system)! {
		if os.readlink(system + '/' + name)! != restored + '/' + name { return error('rollback migration target differs') }
	}
	if os.read_file(restored + '/base.dll')! != 'marker builtin'
		|| os.read_file('/tmp/private/sentinel')! != 'private contents' {
		return error('rollback did not restore old bytes or preserve private data')
	}
	println('WINE PREFIX ROLLBACK RECOVERY PASS explicit obsolete-link cleanup; restored payload; public migration; repeat')
}

fn run() ! {
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	os.mkdir_all('/etc/vinix-packages')!
	os.mkdir_all('/tmp/app/bin')!; os.mkdir_all('/tmp/runtime/bin')!
	os.mkdir_all('/tmp/runtime/root/usr/lib/wine/x86_64-windows')!
	os.write_file('/tmp/app/bin/program.exe', 'marker application, never executed')!; os.chmod('/tmp/app/bin/program.exe', 0o755)!
	os.write_file('/tmp/runtime/bin/wine', 'marker runtime, never executed')!; os.chmod('/tmp/runtime/bin/wine', 0o755)!
	for name in ['base.dll', 'new.dll'] { os.write_file('/tmp/runtime/root/usr/lib/wine/x86_64-windows/' + name, 'marker builtin')! }
	for index in 0 .. 32 { os.write_file('/tmp/runtime/root/usr/lib/wine/x86_64-windows/retarget-' + index.str() + '.dll', 'marker retarget')! }
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
	os.write_file('/tmp/runtime/root/usr/lib/wine/x86_64-windows/base.dll', 'upgraded marker builtin')!
	os.write_file('/tmp/runtime/root/usr/lib/wine/x86_64-windows/extra.dll', 'added upgraded marker')!
	os.write_file('/tmp/manifest.json', json2.encode(pkgcore.Package{id: 'wine', name: 'Guest runtime fixture',
		version: '2.0.0', architecture: arch, license: 'MIT', kind: 'runtime', entrypoint: 'bin/wine'}))!
	pkgcore.pack('/tmp/manifest.json', '/tmp/runtime', '/tmp/repository')!
	pkgcore.publish('/tmp/repository', 'fixture', '/root/prefix-fixture/seed', 2, time.now().unix() + 3600)!
	mut refreshed := (pkgcore.Service{}).refresh()!; refreshed.close()
	mut upgraded := (pkgcore.Service{}).transact('upgrade', [], pkgcore.TransactionOptions{})!
	defer { upgraded.close() }
	if upgraded.generation == state.generation { return error('runtime upgrade did not change generation') }
	selected := '/var/lib/vinix-packages/generations/' + upgraded.generation.str() + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	upgrade_child := C.fork()
	if upgrade_child == 0 {
		C.alarm(90)
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		ordinary_upgrade(builtins, selected) or { eprintln('HWTEST FAIL wine-prefix-cli: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	if upgrade_child <= 0 || C.waitpid(upgrade_child, &status, 0) != upgrade_child || status != 0 { return error('ordinary upgrade fixture failed') }
	mut rolled := (pkgcore.Service{}).rollback('')!
	defer { rolled.close() }
	if rolled.generation == upgraded.generation || rolled.generation == state.generation {
		return error('rollback did not create a fresh generation')
	}
	restored := '/var/lib/vinix-packages/generations/' + rolled.generation.str() + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	rollback_child := C.fork()
	if rollback_child == 0 {
		C.alarm(90)
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		ordinary_rollback(selected, restored) or { eprintln('HWTEST FAIL wine-prefix-cli: ' + err.msg()); C._exit(91) }
		C._exit(0)
	}
	if rollback_child <= 0 || C.waitpid(rollback_child, &status, 0) != rollback_child || status != 0 { return error('ordinary rollback fixture failed') }
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
