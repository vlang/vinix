// SPDX-License-Identifier: GPL-2.0-or-later
module winecutservice

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.wineadapter
import tests.packages.winecutfixture

#include <sys/mount.h>
#include <sys/wait.h>
#include <unistd.h>
#include <grp.h>
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.sync()

fn seed_prefix(data string, builtins string) ! {
	pid := C.fork()
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(90) }
		mut prefix := wineadapter.prepare_prefix(data, builtins) or { eprintln(err.msg()); C._exit(91); return err }
		prefix.close()
		os.write_file(data + '/sentinel', 'private contents') or { C._exit(92) }
		C._exit(0)
	}
	mut status := i32(0)
	if pid <= 0 || C.waitpid(pid, &status, 0) != pid || status != 0 { return error('cannot seed ordinary signed prefix') }
}

fn runtime(arch string, version string) pkgcore.Package {
	return pkgcore.Package{id: 'wine', name: 'Powercut marker runtime', version: version,
		architecture: arch, license: 'MIT', kind: 'runtime', entrypoint: 'bin/wine'}
}

// Root-only preparation. Bind the persistent trees at the real public paths;
// the ordinary migration never uses a --root service or an alternate store.
pub fn setup(root string, point int, volume_path string) !bool {
	for pair in [['configuration', '/etc/vinix-packages'], ['packages', '/var/lib/vinix-packages']] {
		source := root + '/' + pair[0]
		os.mkdir_all(source)!; os.mkdir_all(pair[1])!
		if C.mount(source.str, pair[1].str, c'none', 4096, unsafe { nil }) != 0 {
			return error('cannot bind persistent real-root package directory')
		}
	}
	fresh := !os.exists(root + '/armed')
	preparing := os.exists('/etc/wine-cut-prepare')
	prepared := os.exists(root + '/prepared')
	if prepared && os.read_file(root + '/prepared')! != '741' { return error('prepared signed fixture row count differs') }
	if preparing && (!fresh || prepared) { return error('fresh signed fixture required for preparation') }
	if fresh && !prepared {
		names := winecutfixture.names($if wine_cut_scaled ? { true } $else { false })
		old_names := names[..names.len - 1]
		arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
		app := root + '/app'
		wine := root + '/runtime'
		repository := root + '/repository'
		os.mkdir_all(app + '/bin')!; os.mkdir_all(wine + '/bin')!
		os.mkdir_all(wine + '/root/usr/lib/wine/x86_64-windows')!
		os.write_file(app + '/bin/program.exe', 'marker app')!; os.chmod(app + '/bin/program.exe', 0o755)!
		os.write_file(wine + '/bin/wine', 'marker runtime')!; os.chmod(wine + '/bin/wine', 0o755)!
		for name in old_names { os.write_file(wine + '/root/usr/lib/wine/x86_64-windows/' + name, 'old bytes')! }
		key := pkgcore.keygen(root + '/seed')!
		for package in [pkgcore.Package{id: 'app', name: 'Powercut marker app', version: '1.0.0', architecture: arch,
			license: 'MIT', kind: 'windows', runtime: 'wine', entrypoint: 'bin/wine', arguments: ['bin/program.exe'],
			dependencies: [pkgcore.Dependency{id: 'wine', minimum: '1.0.0'}]}, runtime(arch, '1.0.0')] {
			os.write_file(root + '/manifest.json', json2.encode(package))!
			pkgcore.pack(root + '/manifest.json', if package.id == 'app' { app } else { wine }, repository)!
		}
		pkgcore.publish(repository, 'fixture', root + '/seed', 1, time.now().unix() + 3600)!
		os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{architecture: arch,
			repositories: [pkgcore.Repository{id: 'fixture', url: 'file://' + repository, public_key: key}],
			policy: pkgcore.Policy{reserve_bytes: 0}}))!
		mut catalog := (pkgcore.Service{}).refresh()!; catalog.close()
		mut installed := (pkgcore.Service{}).transact('install', ['app'], pkgcore.TransactionOptions{})!
		if installed.generation != 1 { installed.close(); return error('initial signed generation differs') }
		installed.close()
		old := '/var/lib/vinix-packages/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
		os.mkdir(root + '/private')!; os.chown(root + '/private', 1000, 1000)!; os.chmod(root + '/private', 0o700)!
		seed_prefix(root + '/private', old)!
		for name in old_names { os.write_file(wine + '/root/usr/lib/wine/x86_64-windows/' + name, 'selected bytes')! }
		os.write_file(wine + '/root/usr/lib/wine/x86_64-windows/' + names.last(), 'added bytes')!
		os.write_file(root + '/manifest.json', json2.encode(runtime(arch, '2.0.0')))!
		pkgcore.pack(root + '/manifest.json', wine, repository)!
		pkgcore.publish(repository, 'fixture', root + '/seed', 2, time.now().unix() + 3600)!
		mut updated := (pkgcore.Service{}).refresh()!; updated.close()
		mut upgraded := (pkgcore.Service{}).transact('upgrade', [], pkgcore.TransactionOptions{})!
		if upgraded.generation != 2 { upgraded.close(); return error('upgraded signed generation differs') }
		upgraded.close()
	}
	if preparing {
		os.write_file(root + '/prepared', '741')!
	} else if fresh {
		os.write_file(root + '/armed', point.str())!
	}
	if fresh {
		C.sync()
	}
	if !preparing && os.read_file(root + '/armed')! != point.str() { return error('persistent signed fixture cut differs') }
	mut verified := (pkgcore.Service{}).verify()!
	defer { verified.close() }
	if verified.generation != 2 || verified.packages.len != 2 { return error('persistent signed state differs') }
	mut volume := C.stat{}
	if unsafe { C.stat(volume_path.str, &volume) } != 0 || volume.st_dev == 0 { return error('cannot identify persistent volume') }
	for path in ['/etc/vinix-packages/config.json', '/var/lib/vinix-packages/current/state.json', root + '/private/sentinel'] {
		mut info := C.stat{}
		if unsafe { C.stat(path.str, &info) } != 0 || info.st_dev != volume.st_dev { return error('signed fixture inode is not on persistent volume') }
	}
	if prepared { println('WINE SERVICE POWER CUT TEMPLATE point=${point} fresh=${fresh} rows=741') }
	println('WINE SERVICE POWER CUT STORE point=${point} fresh=${fresh} generation=2 signed-root')
	return fresh
}
