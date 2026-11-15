// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os
import time

#include <sys/wait.h>
#include <signal.h>
#include <poll.h>
#define wine_binding_test_fork fork
#define wine_binding_test_waitpid waitpid
#define wine_binding_test_kill kill
fn C.pipe(&i32) i32
fn C.wine_binding_test_fork() int
fn C.wine_binding_test_waitpid(int, &int, int) int
fn C.wine_binding_test_kill(int, int) int
fn C._exit(int)
struct C.pollfd { mut: fd i32 events i16 revents i16 }
fn C.poll(&C.pollfd, u64, int) int

fn idle_review_foreign_owner(capture &IdleBindingReview) ! {
	mut ready := [2]i32{}
	mut release := [2]i32{}
	assert C.pipe(&ready[0]) == 0
	defer { C.close(ready[0]); C.close(ready[1]) }
	assert C.pipe(&release[0]) == 0
	defer { C.close(release[0]); C.close(release[1]) }
	lock_path := capture.server.path + '/lock'
	defer { unsafe { lock_path.free() } }
	pid := C.wine_binding_test_fork()
	assert pid >= 0
	if pid == 0 {
		C.close(ready[0]); C.close(release[1])
		fd := C.open(lock_path.str, C.O_RDWR | C.O_NOFOLLOW | C.O_CLOEXEC)
		mut record := C.vinix_wine_directory_lock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1}
		mut signal := u8(1)
		if fd < 0 || C.vinix_wine_directory_fcntl(fd, C.F_SETLK, unsafe { &record }) != 0 { C._exit(2) }
		if C.write(ready[1], &signal, 1) != 1 { C._exit(3) }
		if C.read(release[0], &signal, 1) != 1 { C._exit(4) }
		C._exit(0)
	}
	mut reaped := false
	defer {
		if !reaped {
			C.wine_binding_test_kill(pid, C.SIGKILL)
			mut status := 0
			C.wine_binding_test_waitpid(pid, &status, 0)
		}
	}
	C.close(ready[1]); ready[1] = -1
	C.close(release[0]); release[0] = -1
	mut signal := u8(0)
	mut readable := C.pollfd{fd: ready[0], events: i16(C.POLLIN)}
	assert C.poll(&readable, 1, 5000) == 1 && readable.revents & C.POLLIN != 0
	assert C.read(ready[0], &signal, 1) == 1 && signal == 1
	idle_target_refused(capture, 'lock already has an owner')
	assert C.write(release[1], &signal, 1) == 1
	mut status := 0
	assert C.wine_binding_test_waitpid(pid, &status, 0) == pid && status == 0
	reaped = true
	capture.recheck()!
}

fn binding_snapshot(path string, mut files map[string]string) ! {
	if os.is_link(path) { files[path] = 'link:' + os.readlink(path)!; return }
	if os.is_dir(path) {
		files[path] = 'directory'
		for name in os.ls(path)! { binding_snapshot(path + '/' + name, mut files)! }
	} else { files[path] = 'file:' + os.read_file(path)! }
}

fn binding_refused(data string, builtins string, store string, message string) ! {
	mut before := map[string]string{}
	binding_snapshot(data, mut before)!
	mut review := review_prefix_bindings(data, builtins, store) or {
		assert err.msg().contains(message), err.msg()
		cli := os.getenv('VINIX_WINE_PREFIX_REVIEW')
		if cli != '' {
			mut child := os.new_process(cli)
			defer { child.close() }
			child.set_args([store, data, builtins])
			child.set_redirect_stdio_merged()
			child.run()
			output := child.stdout_slurp()
			child.wait()
			assert child.code == 1 && output.contains(message), output
		}
		mut after := map[string]string{}
		binding_snapshot(data, mut after)!
		assert before == after
		return
	}
	review.close()
	assert false, 'unsafe binding review accepted'
}

fn test_builtin_generation_paths_are_canonical() {
	for value in ['0', '01', '-1', '+1', '1e2', '18446744073709551616'] {
		if _, _ := builtin_generation('/store', '/store/generations/' + value + '/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows') {
			assert false, 'invalid generation accepted'
		}
	}
	generation, runtime := builtin_generation('/store', '/store/generations/18446744073709551615/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows')!
	assert generation == u64(18446744073709551615)
	assert runtime == 'org.vinix.wine'
}

fn test_captured_binding_directory_enumeration_is_bounded() {
	root := os.real_path(os.temp_dir()) + '/wine-review-names-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/a.dll', 'a')!
	os.write_file(root + '/.private', 'private')!
	os.symlink('/missing', root + '/b.dll')!
	fd := absolute_directory(root)!
	defer { C.close(fd) }
	mut names := review_names(fd, 3)!
	defer { unsafe { names.free() } }
	names.sort()
	assert names == ['.private', 'a.dll', 'b.dll']
	bounded := review_names(fd, 1)!
	defer { unsafe { bounded.free() } }
	assert bounded.len == 2
	if unexpected := review_names(-1, 3) {
		unsafe { unexpected.free() }
		assert false, 'invalid captured directory accepted'
	}
}

fn idle_review_refused(capture &IdleBindingReview, message string) {
	capture.recheck() or { assert err.msg().contains(message), err.msg(); return }
	assert false, 'changed idle review accepted'
}

fn idle_target_refused(capture &IdleBindingReview, message string) {
	idle_review_refused(capture, message)
	capture.recheck_migration_binding(0) or { assert err.msg().contains(message), err.msg(); return }
	assert false, 'changed migration write admission accepted'
}

fn test_exclusive_builtin_additions_resume_without_replacing_files() {
	root := os.real_path(os.temp_dir()) + '/wine-additions-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	builtins := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(builtins)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	os.write_file(builtins + '/base.dll', 'base')!
	mut prefix := prepare_prefix(data, builtins)!
	defer { prefix.close() }
	os.write_file(builtins + '/a.dll', 'a')!; os.write_file(builtins + '/b.dll', 'b')!
	system := data + '/wine/drive_c/windows/system32'
	// Simulate interruption after one exclusive creation, before recapture.
	os.symlink(builtins + '/a.dll', system + '/a.dll')!
	mut capture := capture_idle_binding_review(data, builtins, store)!
	defer { capture.close() }
	assert capture.review.bindings[0].operation == .keep
	assert capture.review.bindings[1].operation == .create
	capture.complete_additions()!
	capture.complete_additions()!
	assert capture.review.bindings.all(it.operation == .keep)
	assert os.readlink(system + '/b.dll')! == builtins + '/b.dll'
	capture.close()
	os.rm(system + '/b.dll')!
	mut collision := capture_idle_binding_review(data, builtins, store)!
	defer { collision.close() }
	os.write_file(system + '/b.dll', 'personal contents')!
	mut refused := false
	collision.complete_additions() or { refused = true }
	assert refused && os.read_file(system + '/b.dll')! == 'personal contents'
	collision.close()
	os.rm(system + '/b.dll')!
	mut changed := capture_idle_binding_review(data, builtins, store)!
	defer { changed.close() }
	os.write_file(builtins + '/b.dll', 'changed')!
	mut target_refused := false
	changed.complete_additions() or { target_refused = err.msg().contains('asset bytes changed') }
	assert target_refused && !os.exists(system + '/b.dll')
}

fn test_builtin_additions_resume_after_sigkill() {
	root := os.real_path(os.temp_dir()) + '/wine-additions-kill-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	builtins := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(builtins)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	os.write_file(builtins + '/base.dll', 'base')!
	mut prefix := prepare_prefix(data, builtins)!
	defer { prefix.close() }
	for index in 0 .. 128 { os.write_file(builtins + '/add-' + index.str() + '.dll', 'addition')! }
	system := data + '/wine/drive_c/windows/system32'
	os.write_file(system + '/personal.txt', 'preserve private data')!
	pid := C.wine_binding_test_fork()
	assert pid >= 0
	if pid == 0 {
		mut capture := capture_idle_binding_review(data, builtins, store) or { C._exit(2); return }
		capture.complete_additions() or { C._exit(3); return }
		capture.close()
		C._exit(0)
	}
	mut reaped := false
	defer {
		if !reaped {
			C.wine_binding_test_kill(pid, C.SIGKILL)
			mut status := 0
			C.wine_binding_test_waitpid(pid, &status, 0)
		}
	}
	deadline := time.now().unix_milli() + 10000
	for !os.is_link(system + '/add-0.dll') && time.now().unix_milli() < deadline {
		time.sleep(time.millisecond)
	}
	assert os.is_link(system + '/add-0.dll'), 'child failed to reach first addition'
	assert C.wine_binding_test_kill(pid, C.SIGSTOP) == 0
	mut status := 0
	assert C.wine_binding_test_waitpid(pid, &status, C.WUNTRACED) == pid
	assert status & 0xff == 0x7f, 'child completed before interruption'
	mut installed := 0
	for index in 0 .. 128 { if os.is_link(system + '/add-' + index.str() + '.dll') { installed++ } }
	assert installed > 0 && installed < 128
	if mut competitor := prefix.acquire_launch(data) {
		competitor.close(); assert false, 'stopped writer lost prefix coordination'
	} else { assert err.msg().contains('already has a managed launch') }
	assert C.wine_binding_test_kill(pid, C.SIGKILL) == 0
	assert C.wine_binding_test_waitpid(pid, &status, 0) == pid && status & 0x7f == C.SIGKILL
	reaped = true
	mut resumed := capture_idle_binding_review(data, builtins, store)!
	defer { resumed.close() }
	assert resumed.review.bindings.filter(it.operation == .create).len == 128 - installed
	started := time.now().unix_milli()
	resumed.complete_additions()!
	assert resumed.review.bindings.all(it.operation == .keep)
	for index in 0 .. 128 {
		name := '/add-' + index.str() + '.dll'
		assert os.readlink(system + name)! == builtins + name
	}
	assert os.read_file(system + '/personal.txt')! == 'preserve private data'
	println('Wine additions SIGKILL partial=' + installed.str() + '/128; fresh capture completed remaining links in ' + (time.now().unix_milli() - started).str() + ' ms PASS')
}

fn test_staged_builtin_migration_resumes_and_preserves_unknown_stage() {
	root := os.real_path(os.temp_dir()) + '/wine-migration-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	for name in ['a.dll', 'b.dll'] { os.write_file(old + '/' + name, 'old')!; os.write_file(new + '/' + name, 'new')! }
	os.write_file(new + '/c.dll', 'added')!
	mut prefix := prepare_prefix(data, old)!
	defer { prefix.close() }
	system := data + '/wine/drive_c/windows/system32'
	stage := data + '/wine/' + builtin_stage_name
	os.write_file(stage, 'personal stage contents')!
	mut capture := capture_idle_binding_review(data, new, store)!
	defer { capture.close() }
	mut refused := false
	capture.migrate_bindings() or { refused = err.msg().contains('bounded symlink') }
	assert refused && os.read_file(stage)! == 'personal stage contents'
	assert os.readlink(system + '/a.dll')! == old + '/a.dll'
	os.rm(stage)!; os.symlink('/foreign', stage)!
	mut foreign := false
	capture.migrate_bindings() or { foreign = err.msg().contains('does not match a pending binding') }
	assert foreign && os.readlink(stage)! == '/foreign'
	os.rm(stage)!
	capture.close()
	// Simulate interruption after staging, before rename. Resume the pending
	// staged row even when it sorts after another old-generation binding.
	os.symlink(new + '/b.dll', stage)!
	mut resumed := capture_idle_binding_review(data, new, store)!
	defer { resumed.close() }
	resumed.migrate_bindings()!
	resumed.migrate_bindings()!
	assert resumed.review.prior_generation == 0 && resumed.review.bindings.all(it.operation == .keep)
	for name in ['a.dll', 'b.dll', 'c.dll'] { assert os.readlink(system + '/' + name)! == new + '/' + name }
	assert !os.is_link(stage) && !os.exists(stage)
}

fn test_builtin_retargeting_resumes_after_sigkill() {
	root := os.real_path(os.temp_dir()) + '/wine-retarget-kill-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	for index in 0 .. 64 {
		name := '/old-' + index.str() + '.dll'
		os.write_file(old + name, 'old')!; os.write_file(new + name, 'new')!
	}
	mut prefix := prepare_prefix(data, old)!
	defer { prefix.close() }
	system := data + '/wine/drive_c/windows/system32'
	os.write_file(system + '/personal.txt', 'preserve private data')!
	pid := C.wine_binding_test_fork()
	assert pid >= 0
	if pid == 0 {
		mut capture := capture_idle_binding_review(data, new, store) or { C._exit(2); return }
		capture.migrate_bindings() or { C._exit(3); return }
		capture.close()
		C._exit(0)
	}
	mut reaped := false
	defer {
		if !reaped {
			C.wine_binding_test_kill(pid, C.SIGKILL)
			mut status := 0
			C.wine_binding_test_waitpid(pid, &status, 0)
		}
	}
	deadline := time.now().unix_milli() + 10000
	for os.readlink(system + '/old-0.dll')! != new + '/old-0.dll' && time.now().unix_milli() < deadline {
		time.sleep(time.millisecond)
	}
	assert os.readlink(system + '/old-0.dll')! == new + '/old-0.dll'
	assert C.wine_binding_test_kill(pid, C.SIGSTOP) == 0
	mut status := 0
	assert C.wine_binding_test_waitpid(pid, &status, C.WUNTRACED) == pid && status & 0xff == 0x7f
	mut replaced := 0
	for index in 0 .. 64 {
		name := '/old-' + index.str() + '.dll'
		observed := os.readlink(system + name)!
		assert observed == old + name || observed == new + name
		if observed == new + name { replaced++ }
	}
	assert replaced > 0 && replaced < 64
	if mut competitor := prefix.acquire_launch(data) {
		competitor.close(); assert false, 'stopped migration lost prefix guard'
	} else { assert err.msg().contains('already has a managed launch') }
	assert C.wine_binding_test_kill(pid, C.SIGKILL) == 0
	assert C.wine_binding_test_waitpid(pid, &status, 0) == pid && status & 0x7f == C.SIGKILL
	reaped = true
	mut resumed := capture_idle_binding_review(data, new, store)!
	defer { resumed.close() }
	assert resumed.review.prior_generation == 1
	assert resumed.review.bindings.filter(it.operation == .replace).len == 64 - replaced
	resumed.migrate_bindings()!
	resumed.migrate_bindings()!
	assert resumed.review.prior_generation == 0 && resumed.review.bindings.all(it.operation == .keep)
	for index in 0 .. 64 {
		name := '/old-' + index.str() + '.dll'
		assert os.readlink(system + name)! == new + name
	}
	assert !os.is_link(data + '/wine/' + builtin_stage_name)
	assert os.read_file(system + '/personal.txt')! == 'preserve private data'
	println('Wine retarget SIGKILL partial=' + replaced.str() + '/64; atomic old/new targets; fresh capture resumed PASS')
}

fn expected_inventory_refused(capture &IdleBindingReview, runtime string, generation u64, expected []BuiltinExpectation) {
	capture.require_builtin_inventory(runtime, generation, expected) or { assert err.msg().contains('differs'); return }
	assert false, 'mismatched expected inventory accepted'
}

fn test_binding_digest_streams_across_buffer_boundary() {
	root := os.real_path(os.temp_dir()) + '/wine-binding-digest-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	fd := absolute_directory(root)!
	defer { C.close(fd) }
	for count in [1, 14, 65535, 65536, 65537] {
		text := 'a'.repeat(count)
		os.write_file(root + '/large.dll', text)!
		digest, size := binding_asset_digest(fd, 'large.dll')!
		assert size == u64(count) && digest == local_source_digest(text)
		unsafe { digest.free() }
	}
	os.write_file(root + '/empty.dll', '')!
	if _, _ := binding_asset_digest(fd, 'empty.dll') { assert false, 'empty DLL accepted' }
}

fn test_idle_binding_review_coordinates_launches_and_rechecks_changes() {
	root := os.real_path(os.temp_dir()) + '/wine-idle-binding-review-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!
	os.chmod(data, 0o700)!; os.chown(data, int(C.geteuid()), os.getegid())!
	os.write_file(old + '/kernel32.dll', 'old')!; os.write_file(new + '/kernel32.dll', 'new')!
	mut prefix := prepare_prefix(data, old)!
	defer { prefix.close() }
	system := data + '/wine/drive_c/windows/system32'
	mut before := map[string]string{}
	binding_snapshot(system, mut before)!
	baseline := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert baseline >= 0
	C.close(baseline)
	mut capture := capture_idle_binding_review(data, new, store)!
	defer { capture.close() }
	assert capture.review.prior_generation == 1
	capture.recheck()!
	expected := [BuiltinExpectation{name: 'kernel32.dll', sha256: local_source_digest('new'), bytes: 3}]
	capture.require_builtin_inventory('org.vinix.wine', 2, expected)!
	for entry in [BuiltinExpectation{name: 'kernel32.dll', sha256: local_source_digest('NEW'), bytes: 3},
		BuiltinExpectation{name: 'kernel32.dll', sha256: expected[0].sha256, bytes: 4},
		BuiltinExpectation{name: 'foreign.dll', sha256: expected[0].sha256, bytes: 3}] {
		capture.require_builtin_inventory('org.vinix.wine', 2, [entry]) or {
			assert err.msg().contains('differs'); continue
		}
		assert false, 'mismatched expectations accepted'
	}
	expected_inventory_refused(&capture, 'foreign', 2, expected)
	expected_inventory_refused(&capture, 'org.vinix.wine', 3, expected)
	expected_inventory_refused(&capture, 'org.vinix.wine', 2, [])
	if mut competitor := prefix.acquire_launch(data) {
		competitor.close(); assert false, 'review failed to exclude competing launch'
	} else { assert err.msg().contains('already has a managed launch') }
	cli := os.getenv('VINIX_WINE_PREFIX_REVIEW')
	if cli != '' {
		mut child := os.new_process(cli)
		defer { child.close() }
		child.set_args([store, data, new, '--idle'])
		child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait()
		assert child.code == 1 && output.contains('already has a managed launch'), output
	}
	// An endpoint appearing after capture must refuse even if its bytes are
	// not a socket. Never remove it as part of admission or cleanup.
	os.write_file(capture.server.path + '/socket', 'foreign endpoint')!
	idle_target_refused(&capture, 'socket entry already exists')
	assert os.read_file(capture.server.path + '/socket')! == 'foreign endpoint'
	os.rm(capture.server.path + '/socket')!
	idle_review_foreign_owner(&capture)!
	lock_path := capture.server.path + '/lock'
	os.mv(lock_path, lock_path + '.saved')!
	os.write_file(lock_path, '')!; os.chmod(lock_path, 0o600)!
	os.chown(lock_path, int(C.geteuid()), os.getegid())!
	idle_target_refused(&capture, 'lock identity changed')
	os.rm(lock_path)!; os.mv(lock_path + '.saved', lock_path)!
	os.write_file(new + '/added.dll', 'new asset')!
	idle_review_refused(&capture, 'review changed')
	// Unrelated inventory changes are rejected by full admission/final review;
	// the write-loop check is intentionally scoped to the current target.
	capture.recheck_migration_binding(0)!
	os.rm(new + '/added.dll')!
	os.write_file(new + '/kernel32.dll', 'NEW')!
	idle_target_refused(&capture, 'asset bytes changed')
	os.write_file(new + '/kernel32.dll', 'new')!
	capture.recheck()!
	os.rm(new + '/kernel32.dll')!
	os.symlink('/dev/null', new + '/kernel32.dll')!
	idle_target_refused(&capture, 'asset is linked or unavailable')
	os.rm(new + '/kernel32.dll')!
	os.write_file(new + '/kernel32.dll', 'new')!
	os.symlink(old + '/retired.dll', system + '/retired.dll')!
	idle_review_refused(&capture, 'absent from the selected builtin inventory')
	capture.recheck_migration_binding(0)!
	os.rm(system + '/retired.dll')!
	capture.recheck()!
	// Equal names and link text must not disguise replacement directories.
	os.mv(new, new + '.saved')!
	os.mkdir(new)!; os.write_file(new + '/kernel32.dll', 'new')!
	idle_target_refused(&capture, 'captured directory identity changed')
	os.rmdir_all(new)!; os.mv(new + '.saved', new)!
	os.mv(system, system + '.saved')!
	os.mkdir(system)!; os.chmod(system, 0o700)!
	os.chown(system, int(C.geteuid()), os.getegid())!
	os.symlink(old + '/kernel32.dll', system + '/kernel32.dll')!
	idle_target_refused(&capture, 'captured directory identity changed')
	os.rmdir_all(system)!; os.mv(system + '.saved', system)!
	os.rm(system + '/kernel32.dll')!; os.symlink(new + '/kernel32.dll', system + '/kernel32.dll')!
	idle_target_refused(&capture, 'review changed')
	os.rm(system + '/kernel32.dll')!; os.symlink(old + '/kernel32.dll', system + '/kernel32.dll')!
	capture.recheck()!
	mut after := map[string]string{}
	binding_snapshot(system, mut after)!
	assert before == after
	capture.close(); capture.close()
	closed_fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert closed_fd == baseline
	C.close(closed_fd)
	idle_target_refused(&capture, 'canonical absolute data path')
	mut released := prefix.acquire_launch(data)!
	released.close()
	if cli != '' {
		mut child := os.new_process(cli)
		defer { child.close() }
		child.set_args([store, data, new, '--idle'])
		child.set_redirect_stdio_merged(); child.run()
		output := child.stdout_slurp(); child.wait()
		assert child.code == 0 && output.contains('"operation":"replace"'), output
	}
	// A failed capture releases its guard so the owner can launch again.
	os.rm(system + '/kernel32.dll')!; os.write_file(system + '/kernel32.dll', 'personal contents')!
	if mut invalid := capture_idle_binding_review(data, new, store) {
		invalid.close(); assert false, 'ordinary file accepted'
	} else { assert err.msg().contains('symlinks') }
	mut recovered := prefix.acquire_launch(data)!
	recovered.close()
	assert os.read_file(system + '/kernel32.dll')! == 'personal contents'
}

fn test_binding_review_is_read_only_and_refuses_foreign_or_mixed_links() {
	root := os.real_path(os.temp_dir()) + '/wine-binding-review-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!; os.chmod(data, 0o700)!
	os.chown(data, int(C.geteuid()), os.getegid())!
	for name in ['kernel32.dll', 'ntdll.dll'] { os.write_file(old + '/' + name, 'old')!; os.write_file(new + '/' + name, 'new')! }
	mut prefix := prepare_prefix(data, old)!
	prefix.close()
	mut before := map[string]string{}
	binding_snapshot(data, mut before)!
	mut review := review_prefix_bindings(data, new, store)!
	assert review.generation == 2 && review.prior_generation == 1
	assert review.runtime_id == 'org.vinix.wine' && review.bindings.len == 2
	assert review.bindings[0].observed == old + '/kernel32.dll'
	assert review.bindings[0].replacement == new + '/kernel32.dll'
	assert review.bindings[0].operation == .replace
	review.close(); review.close()
	cli := os.getenv('VINIX_WINE_PREFIX_REVIEW')
	if cli != '' {
		mut child := os.new_process(cli)
		defer { child.close() }
		child.set_args([store, data, new])
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait()
		assert child.code == 0, output
		assert output.contains('read-only structural review') && output.contains('org.vinix.wine')
	}
	mut after := map[string]string{}
	binding_snapshot(data, mut after)!
	assert before == after
	system := data + '/wine/drive_c/windows/system32'
	// Inventory shrinkage must not hide a stale packaged DLL, even when its
	// old generation has already been collected. User-owned additions survive.
	os.write_file(system + '/personal.dll', 'private contents')!
	os.symlink('/private/user-library.dll', system + '/personal-link.dll')!
	mut personal := review_prefix_bindings(data, new, store)!
	assert personal.bindings.len == 2
	personal.close()
	for target in [old + '/retired.dll', new + '/retired.dll', store + '/generations/invalid/apps/foreign/retired.dll'] {
		os.symlink(target, system + '/retired.dll')!
		binding_refused(data, new, store, 'absent from the selected builtin inventory')!
		assert os.readlink(system + '/retired.dll')! == target
		os.rm(system + '/retired.dll')!
	}
	assert os.read_file(system + '/personal.dll')! == 'private contents'
	assert os.readlink(system + '/personal-link.dll')! == '/private/user-library.dll'
	for name in ['kernel32.dll', 'ntdll.dll'] {
		os.rm(system + '/' + name)!; os.symlink(new + '/' + name, system + '/' + name)!
	}
	mut current := review_prefix_bindings(data, new, store)!
	assert current.prior_generation == 0 && current.bindings.len == 2
	assert current.bindings[0].operation == .keep && current.bindings[1].operation == .keep
	current.close()
	// An upgrade may add a DLL. Distinguish absent entries from user files or
	// directories; keep review read-only even when a link would be created.
	os.write_file(new + '/new.dll', 'new builtin')!
	mut additions_before := map[string]string{}
	binding_snapshot(data, mut additions_before)!
	mut additions := review_prefix_bindings(data, new, store)!
	assert additions.prior_generation == 0 && additions.bindings.len == 3
	assert additions.bindings[1].name == 'new.dll'
	assert additions.bindings[1].operation == .create && additions.bindings[1].observed == ''
	assert additions.bindings[1].replacement == new + '/new.dll'
	additions.close(); additions.close()
	if cli != '' {
		mut child := os.new_process(cli)
		defer { child.close() }
		child.set_args([store, data, new])
		child.set_redirect_stdio_merged()
		child.run()
		output := child.stdout_slurp()
		child.wait()
		assert child.code == 0, output
		assert output.contains('"operation":"create"') && output.contains('"observed":""'), output
	}
	mut additions_after := map[string]string{}
	binding_snapshot(data, mut additions_after)!
	assert additions_before == additions_after
	assert !os.exists(system + '/new.dll')
	os.rm(system + '/kernel32.dll')!
	os.symlink(old + '/kernel32.dll', system + '/kernel32.dll')!
	mut mixed := review_prefix_bindings(data, new, store)!
	assert mixed.prior_generation == 1 && mixed.bindings.len == 3
	assert mixed.bindings[0].operation == .replace
	assert mixed.bindings[1].operation == .create
	assert mixed.bindings[2].operation == .keep
	mixed.close()
	os.rm(system + '/kernel32.dll')!
	os.symlink(new + '/kernel32.dll', system + '/kernel32.dll')!
	os.write_file(system + '/new.dll', 'personal file')!
	binding_refused(data, new, store, 'symlinks')!
	os.rm(system + '/new.dll')!
	os.mkdir(system + '/new.dll')!
	binding_refused(data, new, store, 'symlinks')!
	os.rmdir(system + '/new.dll')!
	os.symlink('/missing/personal-new.dll', system + '/new.dll')!
	binding_refused(data, new, store, 'basename')!
	os.rm(system + '/new.dll')!
	os.rm(new + '/new.dll')!
	for name in ['kernel32.dll', 'ntdll.dll'] {
		os.rm(system + '/' + name)!; os.symlink(old + '/' + name, system + '/' + name)!
	}
	os.rm(new + '/kernel32.dll')!; os.symlink(old + '/kernel32.dll', new + '/kernel32.dll')!
	binding_refused(data, new, store, 'linked or unavailable')!
	assert os.readlink(new + '/kernel32.dll')! == old + '/kernel32.dll'
	os.rm(new + '/kernel32.dll')!; os.write_file(new + '/kernel32.dll', 'new')!
	os.write_file(new + '/unexpected.txt', 'invalid inventory')!
	binding_refused(data, new, store, 'name is invalid')!
	os.rm(new + '/unexpected.txt')!
	for target in ['/outside/kernel32.dll', store + '/generations/1/apps/foreign/root/usr/lib/wine/x86_64-windows/kernel32.dll', old + '/wrong.dll'] {
		os.rm(system + '/kernel32.dll')!; os.symlink(target, system + '/kernel32.dll')!
		binding_refused(data, new, store, if target.starts_with('/outside') { 'outside' } else if target.ends_with('wrong.dll') { 'basename' } else { 'different runtime' })!
	}
	os.rm(system + '/kernel32.dll')!; os.symlink(old + '/kernel32.dll', system + '/kernel32.dll')!
	os.rm(system + '/ntdll.dll')!; os.symlink(store + '/generations/3/apps/org.vinix.wine/root/usr/lib/wine/x86_64-windows/ntdll.dll', system + '/ntdll.dll')!
	binding_refused(data, new, store, 'multiple prior')!
	os.rm(system + '/ntdll.dll')!; os.write_file(system + '/ntdll.dll', 'personal file')!
	binding_refused(data, new, store, 'symlinks')!
	os.mv(data + '/wine/drive_c/windows', data + '/wine/drive_c/original-windows')!
	os.symlink('original-windows', data + '/wine/drive_c/windows')!
	binding_refused(data, new, store, 'directory components')!
	os.mkdir(root + '/empty-data')!; os.chmod(root + '/empty-data', 0o700)!
	os.chown(root + '/empty-data', int(C.geteuid()), os.getegid())!
	binding_refused(root + '/empty-data', new, store, 'directory components')!
	assert !os.exists(root + '/empty-data/wine')
}
