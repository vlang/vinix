// SPDX-License-Identifier: GPL-2.0-or-later
module wineserverdirectoryfixture

import os
import tools.packages.wineadapter

#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/un.h>
#define vinix_namespace_test_fcntl fcntl
#define vinix_namespace_test_flock flock
#define vinix_namespace_test_stat stat
#define vinix_namespace_test_pipe pipe
#define vinix_namespace_test_fork fork
#define vinix_namespace_test_waitpid waitpid
#define vinix_namespace_test_read read
#define vinix_namespace_test_write write
#define vinix_namespace_test_open open
#define vinix_namespace_test_close close
#define vinix_namespace_test_sysconf sysconf
#define vinix_namespace_test_link link
#define vinix_namespace_test_mkfifo mkfifo
#define vinix_namespace_test_socket socket
#define vinix_namespace_test_address sockaddr_un
#define vinix_namespace_test_bind(fd, address, length) bind((fd), (const struct sockaddr *)(address), (length))
fn C.vinix_namespace_test_fcntl(i32, i32, ...voidptr) i32
fn C.vinix_namespace_test_stat(&char, &C.stat) i32
fn C.vinix_namespace_test_pipe(&i32) i32
fn C.vinix_namespace_test_fork() i32
fn C.vinix_namespace_test_waitpid(i32, &i32, i32) i32
fn C.vinix_namespace_test_read(i32, voidptr, u64) i64
fn C.vinix_namespace_test_write(i32, voidptr, u64) i64
fn C.vinix_namespace_test_open(&char, i32, ...i32) i32
fn C.vinix_namespace_test_close(i32) i32
fn C.vinix_namespace_test_sysconf(i32) i64
fn C.vinix_namespace_test_link(&char, &char) i32
fn C.vinix_namespace_test_mkfifo(&char, u32) i32
fn C.vinix_namespace_test_socket(i32, i32, i32) i32
fn C.vinix_namespace_test_bind(i32, voidptr, u32) i32
fn C._exit(i32)
struct C.vinix_namespace_test_flock { mut: l_type i16 l_whence i16 l_start i64 l_len i64 l_pid i32 }
struct C.vinix_namespace_test_address { mut: sun_len u8 sun_family u16 sun_path [108]char }

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn need(value bool, message string) ! { if !value { return error(message) } }
fn descriptor_count() !int {
	mut count := 0
	$if macos {
		mut names := os.ls('/dev/fd')!
		for name in names { if name.int() >= 3 { count++ } }
		unsafe { names.free() }
		return count
	}
	limit := C.vinix_namespace_test_sysconf(C._SC_OPEN_MAX)
	need(limit >= 3 && limit <= 1048576, 'fixture needs a bounded descriptor limit')!
	for fd in 3 .. int(limit) {
		if C.vinix_namespace_test_fcntl(i32(fd), C.F_GETFD) >= 0 { count++ }
		else if C.errno != C.EBADF { return error('fixture cannot inspect descriptors') }
	}
	return count
}
fn capture_refused(guard &wineadapter.LaunchGuard, data string) bool {
	mut value := guard.prepare_server_directory(data) or { unsafe { err.free() }; return true }
	value.close(); return false
}
fn changed(server &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string) bool {
	server.recheck(guard, data) or { unsafe { err.free() }; return true }
	return false
}
fn idle_refused(server &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string) bool {
	server.require_idle(guard, data) or { unsafe { err.free() }; return true }
	return false
}
fn transfer(fd i32, writing bool) ! {
	mut byte := u8(42)
	for {
		n := if writing { C.vinix_namespace_test_write(fd, &byte, 1) } else { C.vinix_namespace_test_read(fd, &byte, 1) }
		if n < 0 && C.errno == C.EINTR { continue }
		need(n == 1 && byte == 42, 'fixture pipe handshake failed')!; return
	}
}
fn busy_owner(server &wineadapter.ServerDirectory, guard &wineadapter.LaunchGuard, data string, path string) ! {
	mut ready := [i32(-1), -1]!
	mut release := [i32(-1), -1]!
	need(C.vinix_namespace_test_pipe(&ready[0]) == 0, 'ready pipe failed')!
	defer { C.vinix_namespace_test_close(ready[0]); C.vinix_namespace_test_close(ready[1]) }
	need(C.vinix_namespace_test_pipe(&release[0]) == 0, 'release pipe failed')!
	defer { C.vinix_namespace_test_close(release[0]); C.vinix_namespace_test_close(release[1]) }
	pid := C.vinix_namespace_test_fork()
	if pid == 0 {
		fd := C.vinix_namespace_test_open(path.str, C.O_RDWR | C.O_CLOEXEC)
		mut owner := C.vinix_namespace_test_flock{l_type: i16(C.F_WRLCK), l_whence: i16(C.SEEK_SET), l_len: 1}
		if fd < 0 || C.vinix_namespace_test_fcntl(fd, C.F_SETLK, unsafe { &owner }) != 0 { C._exit(97) }
		transfer(ready[1], true) or { C._exit(98) }
		transfer(release[0], false) or { C._exit(98) }
		C._exit(23)
	}
	need(pid > 0, 'lock owner fork failed')!
	transfer(ready[0], false)!
	server.recheck(guard, data)!
	need(idle_refused(server, guard, data), 'busy record lock accepted')!
	need(capture_refused(guard, data), 'busy server capture accepted')!
	need(idle_refused(server, guard, data), 'failed capture released foreign lock')!
	transfer(release[1], true)!
	mut status := i32(0)
	for {
		result := C.vinix_namespace_test_waitpid(pid, &status, 0)
		if result < 0 && C.errno == C.EINTR { continue }
		need(result == pid && status == 23 << 8, 'lock owner status differs')!; break
	}
	server.require_idle(guard, data)!
}

// Single-threaded ordinary-account fixture; all checks remain active in -prod.
pub fn run(root string) ! {
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.chown(root, os.getuid(), os.getegid())!
	data := root + '/data'; builtins := root + '/builtins'
	defer { unsafe { data.free(); builtins.free() } }
	os.mkdir(data)!; os.chmod(data, 0o700)!
	os.mkdir(builtins)!; os.write_file(builtins + '/kernel32.dll', 'fixture builtin')!
	initial := descriptor_count()!
	mut prefix := wineadapter.prepare_prefix(data, builtins)!
	defer { prefix.close() }
	mut guard := prefix.acquire_launch(data)!
	defer { guard.close() }
	prefix.close()
	baseline := descriptor_count()!
	mut server := guard.prepare_server_directory(data)!
	defer { server.close() }
	uid := os.getuid().str()
	base := '${data}/wine/.wine-${uid}'
	mut info := C.stat{}
	prefix_path := data + '/wine'
	need(C.vinix_namespace_test_stat(prefix_path.str, unsafe { &info }) == 0, 'cannot stat fixture prefix')!
	device := u64(info.st_dev).hex(); inode := u64(info.st_ino).hex()
	expected := '${base}/server-${device}-${inode}'
	defer { unsafe { uid.free(); base.free(); prefix_path.free(); device.free(); inode.free(); expected.free() } }
	need(server.path == expected, 'private Wine namespace binding differs')!
	path := server.path.clone(); lock_path := path + '/lock'; socket_path := path + '/socket'
	old_base := base + '-saved'; old_directory := path + '-saved'; old_lock := path + '/saved-lock'
	defer { unsafe { path.free(); lock_path.free(); socket_path.free(); old_base.free(); old_directory.free(); old_lock.free() } }
	server.require_idle(&guard, data)!
	server.close(); server.close()
	need(changed(&server, &guard, data), 'closed server capture accepted')!
	need(os.is_file(lock_path), 'closing removed Wine lock')!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut value := guard.prepare_server_directory(data)!
		value.require_idle(&guard, data)!
		value.close(); value.close()
	}
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'server directory capture retained V allocations')! }
	need(descriptor_count()! == baseline, 'capture leaked descriptors')!
	server = guard.prepare_server_directory(data)!
	busy_owner(&server, &guard, data, lock_path)!
	// Any endpoint entry refuses, including dangling links without following
	// their targets. Refusal must leave the entry intact.
	os.write_file(socket_path, 'foreign endpoint')!
	need(idle_refused(&server, &guard, data) && capture_refused(&guard, data), 'existing endpoint accepted')!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 { need(capture_refused(&guard, data), 'repeated endpoint refusal accepted')! }
	$if track_heap ? { need(C.vinix_heap_end() == 0, 'failed server capture retained V allocations')! }
	need(os.read_file(socket_path)! == 'foreign endpoint', 'refusal changed endpoint')!
	os.rm(socket_path)!
	os.symlink('/missing-namespace-fixture-target', socket_path)!
	need(capture_refused(&guard, data) && os.is_link(socket_path), 'dangling endpoint link accepted or removed')!
	os.rm(socket_path)!
	os.mkdir(socket_path)!
	need(capture_refused(&guard, data) && os.is_dir(socket_path), 'endpoint directory accepted or removed')!
	os.rmdir(socket_path)!
	mut address := C.vinix_namespace_test_address{sun_family: u16(C.AF_UNIX)}
	$if macos { address.sun_len = u8(sizeof(C.vinix_namespace_test_address)) }
	need(socket_path.len < $if macos { 104 } $else { 108 }, 'fixture socket path too long')!
	unsafe { vmemcpy(&address.sun_path[0], socket_path.str, socket_path.len) }
	mut listener := C.vinix_namespace_test_socket(C.AF_UNIX, C.SOCK_STREAM, 0)
	need(listener >= 0, 'fixture socket failed')!
	defer { if listener >= 0 { C.vinix_namespace_test_close(listener) } }
	need(C.vinix_namespace_test_bind(listener, unsafe { &address }, u32(sizeof(C.vinix_namespace_test_address))) == 0, 'fixture bind failed')!
	need(idle_refused(&server, &guard, data) && capture_refused(&guard, data), 'existing Unix socket accepted')!
	os.rm(socket_path)!
	C.vinix_namespace_test_close(listener); listener = -1
	server.require_idle(&guard, data)!
	// Capture rejects malformed lock files without rewriting them.
	os.chmod(lock_path, 0o644)!
	need(changed(&server, &guard, data) && capture_refused(&guard, data), 'unsafe lock mode accepted')!
	os.chmod(lock_path, 0o600)!
	os.write_file(lock_path, 'foreign lock')!
	need(capture_refused(&guard, data), 'nonempty lock accepted')!
	need(os.read_file(lock_path)! == 'foreign lock', 'refusal rewrote lock')!
	os.write_file(lock_path, '')!
	need(C.vinix_namespace_test_link(lock_path.str, old_lock.str) == 0, 'hardlink fixture failed')!
	need(capture_refused(&guard, data), 'multiply linked lock accepted')!
	os.rm(old_lock)!
	os.mv(lock_path, old_lock)!
	os.symlink(old_lock, lock_path)!
	need(changed(&server, &guard, data) && capture_refused(&guard, data), 'linked lock accepted')!
	os.rm(lock_path)!
	need(C.vinix_namespace_test_mkfifo(lock_path.str, 0o600) == 0, 'FIFO fixture failed')!
	need(capture_refused(&guard, data), 'FIFO lock accepted')!
	os.rm(lock_path)!
	os.mkdir(lock_path)!
	need(capture_refused(&guard, data), 'directory lock accepted')!
	os.rmdir(lock_path)!
	os.write_file(lock_path, '')!; os.chmod(lock_path, 0o600)!
	need(changed(&server, &guard, data), 'replacement lock identity accepted')!
	os.rm(lock_path)!; os.mv(old_lock, lock_path)!
	server.require_idle(&guard, data)!
	// Both captured directories are pinned through independent descriptors.
	for directory_path in [path, base]! {
		os.chmod(directory_path, 0o755)!
		need(changed(&server, &guard, data) && capture_refused(&guard, data), 'unsafe directory mode accepted')!
		os.chmod(directory_path, 0o700)!
		os.chmod(directory_path, 0o1700)!
		need(capture_refused(&guard, data), 'special directory mode accepted')!
		os.chmod(directory_path, 0o700)!
	}
	os.mv(path, old_directory)!
	os.symlink(old_directory, path)!
	need(changed(&server, &guard, data) && capture_refused(&guard, data), 'linked server directory accepted')!
	os.rm(path)!; os.mkdir(path)!; os.chmod(path, 0o700)!
	need(changed(&server, &guard, data), 'replaced server directory accepted')!
	os.rmdir(path)!; os.mv(old_directory, path)!
	os.mv(base, old_base)!
	os.symlink(old_base, base)!
	need(changed(&server, &guard, data) && capture_refused(&guard, data), 'linked server base accepted')!
	os.rm(base)!; os.mkdir(base)!; os.chmod(base, 0o700)!
	need(changed(&server, &guard, data), 'replaced server base accepted')!
	os.rmdir(base)!; os.mv(old_base, base)!
	server.require_idle(&guard, data)!
	server.close()
	need(descriptor_count()! == baseline, 'refusal paths leaked descriptors')!
	server = guard.prepare_server_directory(data)!
	guard.close()
	need(changed(&server, &guard, data), 'closed launch guard accepted')!
	need(capture_refused(&guard, data), 'closed guard captured server directory')!
	server.close(); server.close()
	need(descriptor_count()! == initial, 'closed namespace retained descriptors')!
}
