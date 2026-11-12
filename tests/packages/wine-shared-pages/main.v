// SPDX-License-Identifier: GPL-2.0-or-later
// Isolate 4 KiB guest / 16 KiB host shared-file mapping semantics. No Wine
// or package qualification and no pledge/unveil coverage is claimed.
module main

import os
import time

#include <unistd.h>
#include <grp.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/wait.h>
fn C.getpagesize() i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.dup2(i32, i32) i32
fn C.ftruncate(i32, u64) i32
fn C.pread(i32, voidptr, uint, i64) i64
fn C.pwrite(i32, voidptr, uint, i64) i64
fn C.mmap(voidptr, uint, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, uint) i32
fn C.msync(voidptr, uint, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.setgroups(uint, voidptr) i32
fn C.execv(&char, &&char) i32
fn C.unlink(&char) i32
fn C.__atomic_load_n(&u8, i32) u8
fn C.__atomic_store_n(&u8, u8, i32)

fn failed(pointer voidptr) bool { return u64(pointer) == ~u64(0) }

struct AliasView { reservation voidptr base voidptr }

fn alias_view(fd i32, prot i32) !AliasView {
	reservation := C.mmap(unsafe { nil }, 131072, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if failed(reservation) { return error('alias reservation failed') }
	base := (u64(reservation) + 65535) & ~u64(65535)
	mapped := C.mmap(voidptr(base), 16384, prot, C.MAP_FIXED | C.MAP_SHARED, fd, 0)
	if failed(mapped) || mapped != voidptr(base) { C.munmap(reservation, 131072); return error('alias mapping failed') }
	return AliasView{reservation, mapped}
}

fn aliases(mode string) ! {
	path := '/tmp/shared-aliases-' + mode
	fd := C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('alias backing creation failed') }
	defer { C.close(fd); C.unlink(path.str) }
	if C.ftruncate(fd, 16384) != 0 { return error('alias backing resize failed') }
	for page in 0 .. 4 {
		mut value := u8(17 + page)
		if C.pwrite(fd, &value, 1, i64(page * 4096)) != 1 { return error('alias seed failed') }
	}
	reader_fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC)
	other_fd := C.dup(fd)
	if reader_fd < 0 || other_fd < 0 {
		if reader_fd >= 0 { C.close(reader_fd) }; if other_fd >= 0 { C.close(other_fd) }
		return error('alias descriptor creation failed')
	}
	defer { C.close(reader_fd); C.close(other_fd) }
	writer := alias_view(fd, C.PROT_READ | C.PROT_WRITE)!
	defer { C.munmap(writer.reservation, 131072) }
	reader := alias_view(reader_fd, C.PROT_READ)!
	defer { C.munmap(reader.reservation, 131072) }
	other := alias_view(other_fd, C.PROT_READ | C.PROT_WRITE)!
	defer { C.munmap(other.reservation, 131072) }
	for changed in 0 .. 4 {
		C.__atomic_store_n(unsafe { &u8(u64(writer.base) + u64(changed * 4096)) }, u8(80 + changed), 3)
		for page in 0 .. 4 {
			wanted := if page == changed { u8(80 + changed) } else { u8(17 + page) }
			for base in [writer.base, reader.base, other.base]! {
				if C.__atomic_load_n(unsafe { &u8(u64(base) + u64(page * 4096)) }, 2) != wanted { return error('alias contents or subpage isolation differs') }
			}
		}
		C.__atomic_store_n(unsafe { &u8(u64(other.base) + u64(changed * 4096)) }, u8(17 + changed), 3)
		if C.__atomic_load_n(unsafe { &u8(u64(reader.base) + u64(changed * 4096)) }, 2) != u8(17 + changed) { return error('reverse alias coherence differs') }
	}
	println('SHARED-PAGES ALIASES ' + mode + ' PASS three views four distinct subpages and separate/duplicated descriptors')
}

fn one(mode string, length int, is_shared bool, writable bool) ! {
	path := '/tmp/shared-pages-' + mode + '-' + length.str() + '-' + is_shared.str() + '-' + writable.str()
	fd := C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot create private mapping fixture') }
	defer { C.close(fd); C.unlink(path.str) }
	if C.ftruncate(fd, 65536) != 0 { return error('cannot size mapping fixture') }
	mut initial := u8(17)
	if C.pwrite(fd, &initial, 1, 0) != 1 { return error('cannot seed mapping fixture') }
	reserved := C.mmap(unsafe { nil }, 131072, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if failed(reserved) { return error('cannot reserve test address space') }
	defer { C.munmap(reserved, 131072) }
	// The full reservation contains this aligned range and its host-page tail.
	base := (u64(reserved) + 65535) & ~u64(65535)
	prot := C.PROT_READ | if writable { C.PROT_WRITE } else { 0 }
	flags := C.MAP_FIXED | if is_shared { C.MAP_SHARED } else { C.MAP_PRIVATE }
	mapped := C.mmap(voidptr(base), uint(length), prot, flags, fd, 0)
	code := C.errno
	if mode == 'translated' && is_shared && writable && length == 4096 {
		if !failed(mapped) || code != C.EINVAL { return error('partial shared write did not refuse with EINVAL') }
		println('SHARED-PAGES translated 4096 shared writable refused EINVAL')
		return
	}
	if failed(mapped) || mapped != voidptr(base) { return error('mapping failed errno=' + code.str()) }
	bytes := unsafe { &u8(mapped) }
	if C.__atomic_load_n(bytes, 2) != initial { return error('mapped initial byte differs') }
	if !writable {
		mut changed := u8(85)
		if C.pwrite(fd, &changed, 1, 0) != 1 { return error('cannot update mapped backing') }
		wanted := if mode == 'translated' && is_shared && length == 4096 { initial } else { changed }
		if C.__atomic_load_n(bytes, 2) != wanted { return error('read-only shared coherence differs') }
		println('SHARED-PAGES ' + mode + ' ' + length.str() + ' shared readonly coherent=' + (wanted == changed).str())
		return
	}
	C.__atomic_store_n(bytes, 34, 3)
	pid := C.fork()
	if pid < 0 { return error('mapping fork failed') }
	if pid == 0 {
		if C.__atomic_load_n(bytes, 2) != 34 { C._exit(80) }
		C.__atomic_store_n(bytes, 51, 3)
		C._exit(0)
	}
	mut status := i32(0)
	for {
		answer := C.waitpid(pid, &status, 0)
		if answer == pid { break }
		if answer < 0 && C.errno == C.EINTR { continue }
		return error('mapping child wait failed')
	}
	if status != 0 || C.__atomic_load_n(bytes, 2) != if is_shared { u8(51) } else { u8(34) } { return error('mapping fork visibility differs') }
	if is_shared && C.msync(mapped, uint(length), C.MS_SYNC) != 0 { return error('shared mapping sync failed') }
	mut stored := u8(0)
	if C.pread(fd, &stored, 1, 0) != 1 || stored != if is_shared { u8(51) } else { initial } { return error('mapping backing visibility differs') }
	println('SHARED-PAGES ' + mode + ' ' + length.str() + if is_shared { ' shared fork coherent' } else { ' private fork isolated' })
}

fn probe(mode string) ! {
	if mode !in ['native', 'translated'] { return error('unknown mapping probe mode') }
	if C.setgid(1000) != 0 || C.setuid(1000) != 0 || os.geteuid() != 1000 || os.getegid() != 1000 { return error('ordinary probe identity failed') }
	wanted := if mode == 'native' { 16384 } else { 4096 }
	if C.getpagesize() != wanted { return error('unexpected actual page size') }
	for length in [4096, 16384]! {
		one(mode, length, false, true)!
		one(mode, length, true, true)!
		one(mode, length, true, false)!
	}
	aliases(mode)!
	println('SHARED-PAGES PASS ' + mode + ' pagesize=' + wanted.str() + ' six ordinary mapping controls; diagnostic only')
}

fn invoke(args []string) ! {
	mut pointers := []&char{}
	for argument in args { pointers << &char(argument.str) }
	pointers << &char(unsafe { nil })
	defer { unsafe { pointers.free() } }
	pid := C.fork()
	if pid < 0 { return error('probe fork failed') }
	if pid == 0 {
		if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0 { C._exit(81) }
		C.execv(args[0].str, pointers.data)
		C._exit(82)
	}
	mut status := i32(0)
	for {
		answer := C.waitpid(pid, &status, 0)
		if answer == pid { break }
		if answer < 0 && C.errno == C.EINTR { continue }
		return error('probe subprocess wait failed')
	}
	if status != 0 { return error('mapping subprocess failed status=' + status.str()) }
}

fn run_init() ! {
	os.mkdir_all('/tmp')!; os.chmod('/tmp', 0o1777)!
	os.unsetenv('VINIX_ALLOW_WX')
	invoke(['/probe-native', 'native'])!
	invoke(['/qemu-x86_64', '-B', '0x100000000', '/probe-x86', 'translated'])!
	println('HWTEST PASS shared-page-diagnostic')
}

fn main() {
	if C.getpid() == 1 {
		fd := C.open(c'/dev/console', C.O_WRONLY)
		if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
		run_init() or { eprintln('HWTEST FAIL shared-page-diagnostic: ' + err.msg()) }
		for { time.sleep(time.second) }
	}
	if os.args.len != 2 { eprintln('SHARED-PAGES FAIL missing mode'); exit(1) }
	probe(os.args[1]) or { eprintln('SHARED-PAGES FAIL ' + err.msg()); exit(1) }
}
