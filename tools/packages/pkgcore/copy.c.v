// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

fn C.ftruncate(int, u64) int
fn C.lseek(int, i64, int) i64

struct CopySource {
	fd int
	bytes u64
	device u64
	inode u64
}

struct CopyOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	flush fn (int) int = atomic_flush
}

struct CopyOutput {
	fd int
	device u64
	inode u64
}

fn check_copy_output(output CopyOutput, path string, bytes u64) ! {
	mut opened := C.stat{}
	mut named := C.stat{}
	// These stat calls consume their output pointers synchronously. Keep the
	// records on the stack when each copied block rechecks its destination.
	if C.fstat(output.fd, unsafe { &opened }) != 0 || opened.st_mode & 0o170000 != 0o100000
		|| opened.st_size < 0 || u64(opened.st_size) != bytes || opened.st_nlink != 1
		|| C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o100000
		|| u64(named.st_dev) != output.device || u64(named.st_ino) != output.inode {
		return error('copy destination changed while writing; require a stable ordinary file without hard links: ${path}')
	}
}

fn copy_source(source string, maximum u64) !CopySource {
	if source.contains('\x00') { return error('copy source must be an ordinary regular file: ${source}') }
	fd := C.open(source.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open ordinary copy source: ${source}') }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000 || info.st_size < 0 {
		C.close(fd)
		return error('copy source must be an ordinary regular file: ${source}')
	}
	if u64(info.st_size) > maximum {
		C.close(fd)
		return error('copy source exceeds authenticated size: ${source}')
	}
	return CopySource{ fd: fd, bytes: u64(info.st_size), device: u64(info.st_dev), inode: u64(info.st_ino) }
}

fn copy_file_progress(source string, target string, offset u64, maximum u64, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) ! {
	input := copy_source(source, maximum)!
	defer { C.close(input.fd) }
	copy_opened(input, source, target, offset, event, report)!
}

fn fetch_file_progress(source string, target string, maximum u64, resume bool, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) !bool {
	// Admit the source before changing a retained partial, including when an
	// oversized partial would otherwise start a fresh transfer.
	input := copy_source(source, maximum) or {
		message := err.msg()
		diagnostic := 'offline repository file unavailable or invalid: ' + source + ': ' + message
		unsafe { message.free(); err.free() }
		return error(diagnostic)
	}
	defer { C.close(input.fd) }
	mut offset := u64(0)
	if resume && ordinary_file(target) { offset = os.file_size(target) }
	if offset > input.bytes { offset = 0 }
	copy_opened(input, source, target, offset, event, report)!
	return offset > 0
}

fn copy_opened(input CopySource, source string, target string, offset u64, event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) ! {
	copy_opened_with(input, source, target, offset, event, report, CopyOptions{})!
}

fn copy_opened_with(input CopySource, source string, target string, offset u64, event pkgprotocol.Progress, report fn (pkgprotocol.Progress), options CopyOptions) ! {
	if offset > input.bytes { return error('copy resume offset exceeds source size: ${source}') }
	if target.contains('\x00') { return error('copy destination must be an ordinary regular file: ${target}') }
	if C.lseek(input.fd, i64(offset), C.SEEK_SET) != i64(offset) { return error('cannot seek copy source: ${source}') }
	flags := C.O_WRONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK | if offset == 0 { C.O_CREAT } else { 0 }
	output := C.open(target.str, flags, 0o600)
	if output < 0 { return error('cannot open ordinary copy destination: ${target}') }
	defer { C.close(output) }
	mut info := C.stat{}
	if C.fstat(output, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000 || info.st_size < 0 {
		return error('copy destination must be an ordinary regular file: ${target}')
	}
	if u64(info.st_dev) == input.device && u64(info.st_ino) == input.inode {
		return error('copy source and destination must be different files: ${target}')
	}
	if info.st_nlink != 1 {
		return error('copy destination must be an ordinary regular file without hard links; retained data is unchanged: ${target}')
	}
	if offset > 0 && u64(info.st_size) != offset {
		return error('copy destination changed or has a different resume offset: ${target}')
	}
	captured := CopyOutput{ fd: output, device: u64(info.st_dev), inode: u64(info.st_ino) }
	options.checkpoint('opened', target)!
	check_copy_output(captured, target, u64(info.st_size))!
	// Never use O_TRUNC: validate type, identity and offset before modifying it.
	if offset == 0 && C.ftruncate(output, 0) != 0 { return error('cannot truncate copy destination: ${target}') }
	if C.lseek(output, i64(offset), C.SEEK_SET) != i64(offset) { return error('cannot seek copy destination: ${target}') }
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	mut bytes := offset
	mut last := time.sys_mono_now()
	if event.phase != '' { report(pkgprotocol.Progress{ ...event, current: bytes }) }
	check_copy_output(captured, target, bytes)!
	for bytes < input.bytes {
		remaining := input.bytes - bytes
		amount := if remaining < u64(buffer.len) { int(remaining) } else { buffer.len }
		count := C.read(input.fd, buffer.data, usize(amount))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read copy source: ${source}') }
		if count == 0 { return error('copy source changed size while reading: ${source}') }
		mut sent := 0
		for sent < int(count) {
			written := C.write(output, unsafe { &u8(buffer.data) + sent }, usize(int(count) - sent))
			if written < 0 && C.errno == C.EINTR { continue }
			if written <= 0 { return error('cannot write payload (check disk space): ${target}') }
			sent += int(written)
		}
		bytes += u64(count)
		if event.phase != '' && bytes < input.bytes && time.sys_mono_now() - last >= 200_000_000 {
			report(pkgprotocol.Progress{ ...event, current: bytes })
			check_copy_output(captured, target, bytes)!
			last = time.sys_mono_now()
		}
	}
	// Read one bounded sentinel instead of following a growing file to EOF.
	for {
		count := C.read(input.fd, buffer.data, 1)
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read copy source: ${source}') }
		if count != 0 || C.fstat(input.fd, unsafe { &info }) != 0 || info.st_size < 0 || u64(info.st_size) != input.bytes {
			return error('copy source changed size while reading: ${source}')
		}
		break
	}
	check_copy_output(captured, target, input.bytes)!
	for {
		if options.flush(output) == 0 { break }
		if C.errno == C.EINTR { continue }
		return error('cannot flush captured payload; retained partial data may need retry after checking storage: ${target}')
	}
	options.checkpoint('flushed', target)!
	check_copy_output(captured, target, input.bytes)!
	if event.phase != '' { report(pkgprotocol.Progress{ ...event, current: bytes }) }
	check_copy_output(captured, target, input.bytes)!
}
