// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import time
import tools.packages.pkgprotocol

#include <sys/file.h>
#include <sys/statvfs.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
$if linux {
	#include <sys/syscall.h>
}

struct C.statvfs {
	f_bsize  usize
	f_bavail usize
}

fn C.statvfs(&char, &C.statvfs) int
fn C.flock(int, int) int
fn C.fsync(int) int
fn C.geteuid() i32
fn C.getegid() i32
fn C.execv(&char, &&char) int
fn C.chown(&char, i32, i32) int
fn C.rename(&char, &char) int
fn C.fchmod(int, u32) int
fn C.write(int, voidptr, usize) isize
fn C.syscall(i64, ...voidptr) i64
fn C.renamex_np(&char, &char, u32) int

fn publish_new_directory(source string, destination string, kind string) ! {
	// Refuse a destination created during acquisition, including an empty
	// directory or dangling symlink. Plain rename can replace those names.
	mut code := -1
	$if macos {
		code = C.renamex_np(source.str, destination.str, C.RENAME_EXCL)
	} $else $if linux {
		code = int(C.syscall(i64(C.SYS_renameat2), int(-100), source.str,
			int(-100), destination.str, u32(1)))
	} $else {
		return error('atomic ${kind} publication is unsupported on this platform')
	}
	if code != 0 {
		return error('cannot publish ${kind} without replacing ${destination}: ${os.last_error()}; destination must be new and the filesystem must support exclusive atomic rename')
	}
}

pub fn replace_path(source string, destination string) ! {
	// os.rename treats a directory symlink as a destination directory. POSIX
	// rename replaces the symlink itself, which activation requires.
	if C.rename(source.str, destination.str) != 0 {
		return error('cannot atomically replace ${destination}')
	}
}

pub fn sync_directory(path string) ! {
	fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open directory for durability: ${path}') }
	defer { C.close(fd) }
	if C.fsync(fd) != 0 { return error('cannot flush directory: ${path}') }
}

pub fn sync_file(path string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	if C.fsync(file.fd) != 0 { return error('cannot flush file: ${path}') }
}

pub fn atomic_write(path string, text string) ! {
	temporary := path + '.new'
	os.write_file(temporary, text)!
	os.chmod(temporary, 0o644)!
	sync_file(temporary)!
	os.rename(temporary, path)!
	sync_directory(os.dir(path))!
}

pub fn read_metadata(path string) !string {
	if os.is_link(path) || !os.is_file(path) || os.file_size(path) > max_metadata {
		return error('metadata must be a bounded regular file: ${path}')
	}
	text := os.read_file(path)!
	if text.len > max_metadata { return error('metadata grew while reading: ${path}') }
	return text
}

pub fn hash_file(path string) !string {
	if os.is_link(path) || !os.is_file(path) {
		return error('payload must be a regular file: ${path}')
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 64 * 1024}
	defer {
		unsafe {
			buffer.free()
			hash.free()
			free(hash)
		}
	}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	mut digest := []u8{len: sha256.size}
	hash.checksum_into(mut digest)
	result := digest.hex()
	unsafe { digest.free() }
	return result
}

pub fn verified_file(path string, payload Payload) bool {
	if os.is_link(path) || !os.is_file(path) || os.file_size(path) != payload.bytes { return false }
	digest := hash_file(path) or { return false }
	valid := digest == payload.sha256
	unsafe { digest.free() }
	return valid
}

pub fn copy_file(source string, target string, offset u64, maximum u64) ! {
	copy_file_progress(source, target, offset, maximum, pkgprotocol.Progress{}, no_progress)!
}

fn copy_file_progress(source string, target string, offset u64, maximum u64, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) ! {
	mut input := os.open(source)!
	defer { input.close() }
	input.seek(i64(offset), .start)!
	mut output := os.open_file(target, if offset == 0 { 'w' } else { 'a' }, 0o600)!
	defer { output.close() }
	output.set_unbuffered()
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	mut bytes := offset
	mut last := time.sys_mono_now()
	if event.phase != '' { report(pkgprotocol.Progress{ ...event, current: bytes }) }
	for {
		count := input.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		bytes += u64(count)
		if bytes > maximum { return error('download exceeds authenticated size: ${source}') }
		mut sent := 0
		for sent < count {
			written := output.write(buffer[sent..count])!
			if written == 0 { return error('short payload write (check disk space): ${target}') }
			sent += written
		}
		if event.phase != '' && time.sys_mono_now() - last >= 200_000_000 {
			report(pkgprotocol.Progress{ ...event, current: bytes })
			last = time.sys_mono_now()
		}
	}
	output.flush()
	if C.fsync(output.fd) != 0 { return error('cannot flush payload: ${target}') }
	if event.phase != '' { report(pkgprotocol.Progress{ ...event, current: bytes }) }
}

pub fn fetch(url string, destination string, maximum u64, resume bool, offline bool) ! {
	fetch_progress(url, destination, maximum, resume, offline, pkgprotocol.Progress{}, no_progress)!
}

fn fetch_progress(url string, destination string, maximum u64, resume bool, offline bool, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) ! {
	if url.starts_with('file:///') {
		source := url[7..]
		if os.is_link(source) || !os.is_file(source) {
			return error('offline repository file unavailable: ${source}')
		}
		if os.file_size(source) > maximum {
			if os.exists(destination) { os.rm(destination)! }
			return error('offline repository file exceeds authenticated size: ${source}')
		}
		mut offset := u64(0)
		if resume && os.is_file(destination) { offset = os.file_size(destination) }
		if offset > maximum {
			os.rm(destination)!
			offset = 0
		}
		copy_file_progress(source, destination, offset, maximum, event, report)!
		return
	}
	if offline { return error('offline mode: verified payload is missing from cache: ${url}') }
	if !url.starts_with('https://') {
		return error('repository transport requires HTTPS or a local file repository')
	}
	mut args := ['--disable', '--fail', '--show-error', '--silent', '--location', '--proto', '=https',
		'--proto-redir', '=https', '--tlsv1.2', '--connect-timeout', '20', '--max-time', '1800',
		'--retry', '3', '--max-filesize', maximum.str(), '--output', destination]
	if resume { args << ['--continue-at', '-'] }
	args << ['--', url]
	mut process := os.new_process('/usr/bin/curl')
	defer { process.close() }
	process.set_args(args)
	if event.phase == '' {
		process.wait()
		if process.code != 0 { return error('download failed (${process.code}); retained partial data for retry: ${url}') }
	} else {
		process.run()
		monitor_transfer(mut process, destination, maximum, event, report) or { return error('${err}: ${url}') }
	}
	if os.file_size(destination) > maximum {
		os.rm(destination)!
		return error('download exceeded its size limit')
	}
	sync_file(destination)!
}

pub fn free_bytes(path string) !u64 {
	// Read statvfs directly: this V's os.disk_usage frees its borrowed path,
	// which corrupts the transaction's state-directory string with -gc none.
	mut usage := C.statvfs{}
	if C.statvfs(path.str, &usage) != 0 {
		return error('cannot determine available disk space: ${path}')
	}
	block := u64(usage.f_bsize)
	available := u64(usage.f_bavail)
	if block != 0 && available > ~u64(0) / block {
		return error('available disk space overflow: ${path}')
	}
	return block * available
}

pub fn disk_check(available u64, needed u64, reserve u64) ! {
	if needed > ~u64(0) - reserve || available < needed + reserve {
		return error('insufficient disk space: ${available} bytes free, ${needed} needed plus ${reserve} reserved; remove unused generations or use a larger disk')
	}
}

pub struct Lock {
	fd int
}

fn acquire_reader(directory string) !Lock {
	fd := C.open((directory + '/lock').str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('package state is unavailable; refresh trusted repositories before reviewing changes') }
	if C.flock(fd, C.LOCK_SH | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('another package transaction is running; review again when it finishes')
	}
	return Lock{ fd: fd }
}

pub fn owned_directory(path string, mode int) ! {
	if !os.exists(path) && !os.is_link(path) { os.mkdir_all(path, mode: mode)! }
	if os.is_link(path) || !os.is_dir(path) {
		return error('package state must use ordinary directories: ${path}')
	}
	info := os.lstat(path)!
	if info.uid != u32(os.geteuid()) || info.mode & 0o022 != 0 {
		return error('package state must be owned by the invoking administrator and not writable by other users: ${path}')
	}
	os.chmod(path, mode)!
}

pub fn acquire(directory string) !Lock {
	owned_directory(directory, 0o755)!
	path := directory + '/lock'
	fd := C.open(path.str, C.O_RDWR | C.O_CREAT | C.O_CLOEXEC | C.O_NOFOLLOW, 0o644)
	if fd < 0 {
		return error('cannot open package lock; package changes require administrator access')
	}
	if C.fchmod(fd, 0o644) != 0 {
		C.close(fd)
		return error('cannot set package lock reader permissions')
	}
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		C.close(fd)
		return error('another package transaction is running; try again when it finishes')
	}
	for name in ['objects', 'generations'] {
		owned_directory(directory + '/' + name, 0o755) or {
			C.close(fd)
			return err
		}
	}
	return Lock{ fd: fd }
}

pub fn (l Lock) release() { C.close(l.fd) }
