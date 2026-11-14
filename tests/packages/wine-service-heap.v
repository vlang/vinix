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

fn consume_refusal(err IError, expected string) ! {
	message := err.msg()
	matches := message.contains(expected)
	unsafe { message.free(); err.free() }
	if !matches { return error('service refusal reason differs') }
}

fn refused_review(id string, expected string) ! {
	if mut owner := (pkgcore.Service{}).wine_prefix_review(id, '/tmp/private') {
		owner.close()
		return error('unsafe service review unexpectedly succeeded')
	} else { consume_refusal(err, expected)! }
}

fn phase_done(name string, cycles int) ! {
	tracking = false
	println('WINE SERVICE REFUSAL phase=${name} cycles=${cycles} live_objects=${live_objects} live_bytes=${live_bytes}')
	if invalid || live_objects != 0 || live_bytes != 0 { return error('service refusal retained V allocations: ' + name) }
}

fn require_free(fd i32) ! {
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 { return error('service refusal retained a coordination lock') }
	if C.flock(fd, C.LOCK_UN) != 0 { return error('cannot release coordination probe') }
}

fn refusals(generation string, builtins string, cycles int) ! {
	lease_path := generation + '/lease'
	lease := C.open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if lease < 0 { return error('cannot capture refusal lease probe') }
	defer { C.close(lease) }
	store_lock := C.open(c'/var/lib/vinix-packages/lock', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if store_lock < 0 { return error('cannot capture refusal reader-lock probe') }
	defer { C.close(store_lock) }
	tracking = true
	for _ in 0 .. cycles {
		refused_review('absent', 'application is not installed') or { tracking = false; return err }
	}
	phase_done('missing-app', cycles)!
	require_free(lease)!; require_free(store_lock)!
	tracking = true
	for _ in 0 .. cycles {
		refused_review('wine', 'requires a Windows application with an explicit runtime') or { tracking = false; return err }
	}
	phase_done('runtime-kind', cycles)!
	require_free(lease)!; require_free(store_lock)!
	link := '/tmp/private/wine/drive_c/windows/system32/base.dll'
	os.rm(link)!; os.write_file(link, 'personal DLL')!
	tracking = true
	for _ in 0 .. cycles {
		refused_review('app', 'requires existing bounded symlinks') or { tracking = false; return err }
	}
	phase_done('personal-dll', cycles)!
	if os.read_file(link)! != 'personal DLL' { return error('service refusal changed personal DLL') }
	require_free(lease)!; require_free(store_lock)!
	os.rm(link)!; os.symlink(builtins + '/base.dll', link)!
	mut owner := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private')!
	defer { owner.close() }
	stage := '/tmp/private/wine/.vinix-builtin-next'
	os.write_file(stage, 'personal stage')!
	tracking = true
	for _ in 0 .. cycles {
		mut refused := false
		owner.migrate_bindings() or {
			consume_refusal(err, 'stage must be a bounded symlink') or { tracking = false; return err }
			refused = true
		}
		if !refused { tracking = false; return error('personal service stage migration succeeded') }
	}
	phase_done('personal-stage', cycles)!
	if os.read_file(stage)! != 'personal stage' { return error('service refusal changed personal stage') }
	require_free(store_lock)!
	if C.flock(lease, C.LOCK_EX | C.LOCK_NB) == 0 || (C.errno != C.EAGAIN && C.errno != C.EWOULDBLOCK) {
		return error('failed migration lost its live generation lease')
	}
	refused_review('app', 'already has a managed launch')!
	os.rm(stage)!
	owner.recheck()!; owner.migrate_bindings()!; owner.close()
	require_free(lease)!; require_free(store_lock)!
	mut recovered := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private')!
	recovered.close()
	require_free(lease)!; require_free(store_lock)!
	println('WINE SERVICE REFUSALS PASS phases=4 cycles=${cycles} lease-free guard-recovered personal-data-preserved')
}

fn writes(generation string, builtins string, cycles int) ! {
	lease_path := generation + '/lease'
	lease := C.open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if lease < 0 { return error('cannot capture write lease probe') }
	defer { C.close(lease) }
	store_lock := C.open(c'/var/lib/vinix-packages/lock', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if store_lock < 0 { return error('cannot capture write reader-lock probe') }
	defer { C.close(store_lock) }
	os.write_file('/tmp/private/sentinel', 'private contents')!
	for additions in [false, true]! {
		for _ in 0 .. cycles {
			if additions {
				for name in ['base.dll', 'extra.dll']! {
					path := '/tmp/private/wine/drive_c/windows/system32/' + name
					os.rm(path) or { unsafe { path.free() }; return err }
					unsafe { path.free() }
				}
			}
			tracking = true
			mut owner := (pkgcore.Service{}).wine_prefix_review('app', '/tmp/private') or { tracking = false; return err }
			if additions {
				owner.complete_additions() or { owner.close(); tracking = false; return err }
			} else {
				owner.migrate_bindings() or { owner.close(); tracking = false; return err }
			}
			owner.recheck() or { owner.close(); tracking = false; return err }
			valid := owner.review.review.prior_generation == 0 && owner.review.review.bindings.len == 2
				&& owner.review.review.bindings.all(it.operation == .keep)
			owner.close()
			tracking = false
			if !valid { return error('service write did not complete its signed inventory') }
			require_free(lease)!; require_free(store_lock)!
			for name in ['base.dll', 'extra.dll']! {
				path := '/tmp/private/wine/drive_c/windows/system32/' + name
				observed := os.readlink(path) or { unsafe { path.free() }; return err }
				expected := builtins + '/' + name
				matches := observed == expected
				unsafe { path.free(); observed.free(); expected.free() }
				if !matches {
					return error('service write selected a different builtin target')
				}
			}
		}
		phase := if additions { 'additions' } else { 'migration-repeat' }
		println('WINE SERVICE WRITE phase=${phase} cycles=${cycles} live_objects=${live_objects} live_bytes=${live_bytes}')
		if invalid || live_objects != 0 || live_bytes != 0 { return error('service write retained V allocations') }
	}
	if os.read_file('/tmp/private/sentinel')! != 'private contents'
		|| os.exists('/tmp/private/wine/.vinix-builtin-next') || os.is_link('/tmp/private/wine/.vinix-builtin-next') {
		return error('service write changed private data or left staging')
	}
	println('WINE SERVICE WRITES PASS phases=2 cycles=${cycles} signed-links private-data lease-free reader-lock-free')
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
	$if wine_service_heap_refusals ? { refusals(generation, builtins, cycles)!; return }
	$if wine_service_heap_writes ? { writes(generation, builtins, cycles)!; return }
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
	$if wine_service_heap_refusals ? {
		$if wine_service_heap_writes ? { eprintln('select only one service heap mode'); exit(2) }
	}
	if C.getpid() != 1 { eprintln('requires guest PID 1'); exit(2) }
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL wine-service-heap: ' + err.msg()); for { time.sleep(time.second) } }
	println('HWTEST PASS wine-service-heap')
	for { time.sleep(time.second) }
}
