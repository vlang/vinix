// SPDX-License-Identifier: GPL-2.0-or-later
module wineguardfixture

import os
import tools.packages.wineadapter

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#define vinix_guard_test_link link
#define vinix_guard_test_mkfifo mkfifo
#define vinix_guard_test_fork fork
#define vinix_guard_test_waitpid waitpid
#define vinix_guard_test_execv execv
#define vinix_guard_test_fcntl fcntl
#define vinix_guard_test_sysconf sysconf
fn C.vinix_guard_test_link(&char, &char) i32
fn C.vinix_guard_test_mkfifo(&char, u32) i32
fn C.vinix_guard_test_fork() i32
fn C.vinix_guard_test_waitpid(i32, &i32, i32) i32
fn C.vinix_guard_test_execv(&char, &&char) i32
fn C.vinix_guard_test_fcntl(i32, i32) i32
fn C.vinix_guard_test_sysconf(i32) i64
fn C._exit(i32)

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn need(value bool, message string) ! {
	if !value { return error(message) }
}

fn descriptor_limit() !int {
	// macOS can advertise an effectively unbounded soft limit. Enumerate its
	// live /dev/fd directory instead of truncating the scan to an arbitrary cap.
	$if macos { return 0 }
	limit := C.vinix_guard_test_sysconf(C._SC_OPEN_MAX)
	if limit < 3 || limit > 1048576 { return error('fixture needs a bounded descriptor limit') }
	return int(limit)
}

fn descriptor_count(limit int) !int {
	mut count := 0
	$if macos {
		mut names := os.ls('/dev/fd')!
		for name in names {
			if name.int() >= 3 { count++ }
		}
		unsafe { names.free() }
		return count
	}
	for fd in 3 .. limit {
		if C.vinix_guard_test_fcntl(i32(fd), C.F_GETFD) >= 0 { count++ }
		else if C.errno != C.EBADF { return error('cannot inspect fixture descriptors') }
	}
	return count
}

pub fn check_exec() ! {
	need(descriptor_count(descriptor_limit()!)! == 0, 'exec inherited a private descriptor')!
}

fn refused(prefix &wineadapter.Prefix, data string) bool {
	mut unexpected := prefix.acquire_launch(data) or { unsafe { err.free() }; return true }
	unexpected.close()
	return false
}

fn changed(guard &wineadapter.LaunchGuard, data string) bool {
	guard.recheck(data) or { unsafe { err.free() }; return true }
	return false
}

fn available(prefix &wineadapter.Prefix, data string) ! {
	mut value := prefix.acquire_launch(data)!
	defer { value.close() }
	value.recheck(data)!
}

fn wait_success(pid i32) ! {
	need(pid > 0, 'fixture fork failed')!
	mut status := i32(0)
	mut waited := i32(-1)
	for {
		waited = C.vinix_guard_test_waitpid(pid, &status, 0)
		if waited < 0 && C.errno == C.EINTR { continue }
		break
	}
	need(waited == pid && status == 0, 'guard fixture child failed')!
}

// Caller provides a fresh ordinary-account-owned directory, with no other
// threads opening descriptors. All refusal assertions run in production too.
pub fn run(root string, executable string) ! {
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.chown(root, os.getuid(), os.getegid())!
	data := root + '/data'; builtins := root + '/builtins'
	guard_path := data + '/wine/.vinix-managed-launch'
	old_lock := data + '/wine/.saved-managed-launch'
	old_prefix := data + '/saved-wine'
	old_data := root + '/saved-data'
	defer { unsafe { data.free(); builtins.free(); guard_path.free(); old_lock.free(); old_prefix.free(); old_data.free() } }
	os.mkdir(data)!; os.chmod(data, 0o700)!
	os.mkdir(builtins)!
	os.write_file(builtins + '/kernel32.dll', 'fixture builtin')!
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	defer { prefix.close() }
	limit := descriptor_limit()!
	baseline := descriptor_count(limit)!
	mut guard := prefix.acquire_launch(data)!
	defer { guard.close() }
	guard.recheck(data)!
	need(refused(&prefix, data), 'concurrent independent open accepted')!
	// Cross-process contention, with the child explicitly reaped. Inheriting
	// the parent's description must not make a new independent open succeed.
	pid := C.vinix_guard_test_fork()
	if pid == 0 { C._exit(if refused(&prefix, data) { 0 } else { 97 }) }
	wait_success(pid)!
	// The native fixture's exec mode refuses every descriptor >= 3. This
	// checks the real exec path, with both Prefix and LaunchGuard still live.
	if executable != '' {
		argv := [&char(executable.str), c'guard-exec', unsafe { nil }]!
		child := C.vinix_guard_test_fork()
		if child == 0 {
			C.vinix_guard_test_execv(executable.str, unsafe { &argv[0] })
			C._exit(98)
		}
		wait_success(child)!
	}
	// Closing the prefix must not invalidate or release the owned guard.
	prefix.close(); prefix.close()
	guard.recheck(data)!
	prefix = wineadapter.prepare_prefix(data, builtins)!
	need(refused(&prefix, data), 'prefix close released guard')!
	guard.close(); guard.close()
	need(os.is_file(guard_path), 'close removed coordination file')!
	available(&prefix, data)!
	need(changed(&guard, data), 'closed guard recheck accepted')!
	// Repeated acquisition, contention refusal and rechecks must retain
	// neither parent V allocations nor descriptors.
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut value := prefix.acquire_launch(data)!
		value.recheck(data)!
		need(refused(&prefix, data), 'stress contention accepted')!
		value.close(); value.close()
	}
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'guard retained V allocations')! }
	need(descriptor_count(limit)! == baseline, 'guard leaked descriptors')!
	// Existing malformed files are refused without normalization/removal.
	for mode in [0o644, 0o700, 0o660, 0o1600]! {
		os.chmod(guard_path, mode)!
		need(refused(&prefix, data), 'unsafe lock mode accepted')!
		info := os.stat(guard_path)!
		need(u32(info.mode) & 0o7777 == u32(mode), 'refusal changed file mode')!
	}
	os.chmod(guard_path, 0o600)!
	os.write_file(guard_path, 'foreign guard')!
	need(refused(&prefix, data), 'nonempty lock accepted')!
	need(os.read_file(guard_path)! == 'foreign guard', 'refusal changed file content')!
	os.write_file(guard_path, '')!
	need(C.vinix_guard_test_link(guard_path.str, old_lock.str) == 0, 'cannot create hardlink control')!
	need(refused(&prefix, data), 'multiply linked guard accepted')!
	os.rm(old_lock)!
	available(&prefix, data)!
	os.mv(guard_path, old_lock)!
	os.symlink(old_lock, guard_path)!
	need(refused(&prefix, data), 'symlink guard accepted')!
	need(os.is_link(guard_path), 'refusal removed symlink')!
	os.rm(guard_path)!
	need(C.vinix_guard_test_mkfifo(guard_path.str, 0o600) == 0, 'cannot create FIFO control')!
	need(refused(&prefix, data), 'FIFO guard accepted')!
	os.rm(guard_path)!
	os.mkdir(guard_path)!
	need(refused(&prefix, data), 'directory guard accepted')!
	os.rmdir(guard_path)!
	os.mv(old_lock, guard_path)!
	guard = prefix.acquire_launch(data)!
	// Mutating the held file's metadata is detected as well as replacing it.
	os.chmod(guard_path, 0o644)!
	need(changed(&guard, data), 'changed lock metadata accepted')!
	os.chmod(guard_path, 0o600)!
	guard.recheck(data)!
	os.mv(guard_path, old_lock)!
	os.write_file(guard_path, '')!; os.chmod(guard_path, 0o600)!
	need(changed(&guard, data), 'replacement guard accepted')!
	os.rm(guard_path)!; os.mv(old_lock, guard_path)!
	guard.recheck(data)!
	os.mv(data + '/wine', old_prefix)!
	os.symlink(old_prefix, data + '/wine')!
	need(changed(&guard, data), 'linked prefix accepted')!
	os.rm(data + '/wine')!
	os.mkdir(data + '/wine')!; os.chmod(data + '/wine', 0o700)!
	need(changed(&guard, data), 'replacement prefix accepted')!
	need(refused(&prefix, data), 'stale prefix acquired guard')!
	os.rmdir(data + '/wine')!; os.mv(old_prefix, data + '/wine')!
	guard.recheck(data)!
	os.mv(data, old_data)!
	os.symlink(old_data, data)!
	need(changed(&guard, data), 'linked data accepted')!
	os.rm(data)!
	os.mkdir(data)!; os.chmod(data, 0o700)!
	need(changed(&guard, data), 'replacement data accepted')!
	os.rmdir(data)!; os.mv(old_data, data)!
	guard.recheck(data)!
	os.chmod(data + '/wine', 0o755)!
	need(changed(&guard, data), 'changed prefix permissions accepted')!
	os.chmod(data + '/wine', 0o700)!
	os.chmod(data, 0o755)!
	need(changed(&guard, data), 'changed data permissions accepted')!
	os.chmod(data, 0o700)!
	guard.recheck(data)!
	guard.close()
	available(&prefix, data)!
	need(descriptor_count(limit)! == baseline, 'guard refusals leaked descriptors')!
}
