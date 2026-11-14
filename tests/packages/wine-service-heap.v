// SPDX-License-Identifier: GPL-2.0-or-later
// Real-root guest probe; signed marker assets are never executed.
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/file.h>
#include <errno.h>
fn C.getpid() i32
fn C.open(&char, i32, ...i32) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.setgroups(u64, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.flock(i32, i32) i32

struct Slot { mut: pointer u64 bytes u64 }
__global (
	slots [65536]Slot
	tracking bool
	invalid bool
	live_bytes u64
	live_objects u64
)

@[export: 'vheap_alloc']
fn heap_alloc(pointer voidptr, bytes u64) {
	if !tracking || pointer == unsafe { nil } { return }
	key := u64(pointer)
	mut index := int((key >> 4) & 65535)
	for _ in 0 .. 65536 {
		if slots[index].pointer <= 1 {
			slots[index] = Slot{pointer: key, bytes: bytes}
			live_bytes += bytes; live_objects++
			return
		}
		if slots[index].pointer == key { invalid = true; return }
		index = (index + 1) & 65535
	}
	invalid = true
}

@[export: 'vheap_free']
fn heap_free(pointer voidptr) {
	if !tracking || pointer == unsafe { nil } { return }
	key := u64(pointer)
	mut index := int((key >> 4) & 65535)
	for _ in 0 .. 65536 {
		if slots[index].pointer == 0 { return }
		if slots[index].pointer == key {
			live_bytes -= slots[index].bytes; live_objects--
			slots[index] = Slot{pointer: 1}
			return
		}
		index = (index + 1) & 65535
	}
}

fn setup() !string {
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	os.mkdir_all('/root/service-heap')!
	os.mkdir_all('/tmp/app/bin')!; os.mkdir_all('/tmp/wine/bin')!
	os.mkdir_all('/tmp/wine/root/usr/lib/wine/x86_64-windows')!
	os.write_file('/tmp/app/bin/program.exe', 'marker app')!; os.chmod('/tmp/app/bin/program.exe', 0o755)!
	os.write_file('/tmp/wine/bin/wine', 'marker runtime')!; os.chmod('/tmp/wine/bin/wine', 0o755)!
	for name in ['base.dll', 'extra.dll'] {
		os.write_file('/tmp/wine/root/usr/lib/wine/x86_64-windows/' + name, 'marker builtin')!
	}
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	key := pkgcore.keygen('/root/service-heap/seed')!
	for package in [
		pkgcore.Package{id: 'app', name: 'Heap Windows fixture', version: '1.0.0', architecture: arch, license: 'MIT',
			kind: 'windows', runtime: 'wine', entrypoint: 'bin/wine', arguments: ['bin/program.exe'],
			dependencies: [pkgcore.Dependency{id: 'wine', minimum: '1.0.0'}]},
		pkgcore.Package{id: 'wine', name: 'Heap runtime fixture', version: '1.0.0', architecture: arch,
			license: 'MIT', kind: 'runtime', entrypoint: 'bin/wine'},
	] {
		os.write_file('/tmp/manifest.json', json2.encode(package))!
		pkgcore.pack('/tmp/manifest.json', if package.id == 'app' { '/tmp/app' } else { '/tmp/wine' }, '/tmp/repository')!
	}
	pkgcore.publish('/tmp/repository', 'fixture', '/root/service-heap/seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{architecture: arch,
		repositories: [pkgcore.Repository{id: 'fixture', url: 'file:///tmp/repository', public_key: key}],
		policy: pkgcore.Policy{reserve_bytes: 0}}))!
	mut catalog := (pkgcore.Service{}).refresh()!; catalog.close()
	mut state := (pkgcore.Service{}).transact('install', ['app'], pkgcore.TransactionOptions{})!
	defer { state.close() }
	return '/var/lib/vinix-packages/generations/' + state.generation.str()
}

fn run() ! {
	$if track_heap ? {} $else { return error('service heap probe requires -d track_heap') }
	generation := setup()!
	os.mkdir('/tmp/private')!; os.chmod('/tmp/private', 0o700)!; os.chown('/tmp/private', 1000, 1000)!
	if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 {
		return error('cannot enter ordinary service account')
	}
	builtins := generation + '/apps/wine/root/usr/lib/wine/x86_64-windows'
	mut prefix := wineadapter.prepare_prefix('/tmp/private', builtins)!; prefix.close()
	tracking = true
	block := unsafe { malloc(37) }
	allocated := live_objects == 1 && live_bytes == 37
	unsafe { free(block) }
	tracking = false
	if !allocated || live_objects != 0 || live_bytes != 0 || invalid { return error('heap hook control failed') }
	// Warm setup is outside the measured repeated-operation lifetime.
	mut warm := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private')!; warm.close()
	cycles := $if wine_service_heap_diagnostic ? { 1 } $else { 100 }
	tracking = true
	for _ in 0 .. cycles {
		mut owner := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private') or { tracking = false; return err }
		owner.recheck() or { owner.close(); tracking = false; return err }
		owner.close()
	}
	tracking = false
	println('WINE SERVICE HEAP cycles=${cycles} live_objects=${live_objects} live_bytes=${live_bytes}')
	if live_objects != 0 {
		mut histogram := map[u64]int{}
		for slot in slots { if slot.pointer > 1 { histogram[slot.bytes]++ } }
		println('WINE SERVICE HEAP retained sizes=' + histogram.str())
	}
	if invalid { return error('service heap tracker overflow or duplicate allocation') }
	if live_objects != 0 || live_bytes != 0 { return error('service review retains V-managed allocations') }
	mut owner := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private')!
	defer { owner.close() }
	lease := C.open((generation + '/lease').str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if lease < 0 { return error('cannot open generation lease probe') }
	defer { C.close(lease) }
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) == 0 || (C.errno != C.EAGAIN && C.errno != C.EWOULDBLOCK) {
		return error('service owner did not retain a busy generation lease')
	}
	owner.close()
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) != 0 { return error('service close retained its generation lease') }
	if C.flock(lease, C.LOCK_UN) != 0 { return error('cannot release generation lease probe') }
	println('WINE SERVICE HEAP PASS signed installed ordinary-account review/recheck/close; lease released')
}

fn main() {
	if C.getpid() != 1 { eprintln('requires guest PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL wine-service-heap: ' + err.msg()); for { time.sleep(time.second) } }
	println('HWTEST PASS wine-service-heap')
	for { time.sleep(time.second) }
}
