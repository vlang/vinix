// SPDX-License-Identifier: GPL-2.0-or-later
module ansreads

import crypto.sha256
import os

#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

fn C.open(&char, int, ...int) int
fn C.fstat(int, &C.stat) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.lseek(int, i64, int) i64
fn C.close(int) int
fn C.fsync(int) int

pub const schema = 'vinix-ans-reads-v1'
pub const max_offset = i64(0x7fffffffffffffff)
pub const max_range = 1048576
pub const max_ranges = 64
pub const patterns = [513, 4096, 65521]

pub struct Range {
pub:
	offset i64
	length i64
	sha256 string
}

pub fn checked_range(offset i64, length i64) !Range {
	if offset < 0 || length < 1 || length > max_range {
		return error('range requires nonnegative offset and 1..1048576 bytes')
	}
	if length > max_offset - offset {
		return error('range overflows a signed 64-bit file offset')
	}
	return Range{ offset: offset, length: length }
}

fn syscall_error(operation string) IError {
	number := int(C.errno)
	return error_with_code(operation + ': ' + os.get_error_msg(number), number)
}

fn open_path(path string, flags int, mode int) !int {
	if path.contains('\x00') { return error('embedded null byte in path') }
	for {
		fd := C.open(path.str, flags, mode)
		if fd >= 0 { return fd }
		if C.errno != C.EINTR { return syscall_error('open ' + path) }
	}
	return error('unreachable open')
}

fn descriptor_mode(fd int) !u32 {
	mut state := C.stat{}
	for {
		if C.fstat(fd, &state) == 0 { return u32(state.st_mode) & u32(C.S_IFMT) }
		if C.errno != C.EINTR { return syscall_error('inspect opened file') }
	}
	return error('unreachable fstat')
}

struct Source {
	fd   int
	kind string
}

// Inspect the opened descriptor, not a separate path lookup. This is the only
// source open used by either operation; no writable source handle exists.
fn open_source(path string) !Source {
	fd := open_path(path, C.O_RDONLY | C.O_CLOEXEC, 0)!
	mode := descriptor_mode(fd) or {
		C.close(fd)
		return err
	}
	if mode != u32(C.S_IFREG) && mode != u32(C.S_IFBLK) {
		C.close(fd)
		return error('source must be a block device or a regular test image')
	}
	return Source{fd, if mode == u32(C.S_IFBLK) { 'block-device' } else { 'regular-file' }}
}

fn read_into(fd int, mut buffer []u8) !int {
	for {
		count := C.read(fd, buffer.data, usize(buffer.len))
		if count >= 0 { return int(count) }
		if C.errno != C.EINTR { return syscall_error('read') }
	}
	return error('unreachable read')
}

fn digest(fd int, range Range, chunk int) !string {
	checked_range(range.offset, range.length)!
	if chunk < 1 || chunk > max_range { return error('invalid digest chunk') }
	for {
		if C.lseek(fd, range.offset, C.SEEK_SET) >= 0 { break }
		if C.errno != C.EINTR { return syscall_error('seek') }
	}
	mut hash := sha256.new()
	mut remaining := range.length
	mut buffer := []u8{len: chunk}
	for remaining > 0 {
		// Borrow only for this synchronous read/hash; no reference escapes.
		mut portion := unsafe { buffer[..int(if remaining < chunk { remaining } else { i64(chunk) })] }
		count := read_into(fd, mut portion)!
		if count == 0 {
			return error('short read at byte ${range.offset + range.length - remaining}')
		}
		hash.write(portion[..count])!
		remaining -= count
	}
	return hash.sum([]u8{}).hex()
}

fn system_description() string {
	u := os.uname()
	return '${u.sysname}-${u.release}-${u.machine}'
}

pub struct Manifest {
pub:
	ranges           []Range
	reference_label  string
	source_kind      string
	reference_system string
}

pub fn record(source string, ranges []Range, label string) !Manifest {
	if label == '' || label.runes().len > 256 || ranges.len < 1 || ranges.len > max_ranges {
		return error('supply a reference label and 1..64 explicit ranges')
	}
	opened := open_source(source)!
	defer { C.close(opened.fd) }
	mut values := []Range{cap: ranges.len}
	for range in ranges {
		values << Range{range.offset, range.length, digest(opened.fd, range, 65536)!}
	}
	validate_ranges(values)!
	return Manifest{values, label, opened.kind, system_description()}
}

pub struct Report {
pub:
	result                                   string = 'REFERENCE COMPARISON PASS'
	source_kind                              string
	system                                   string
	read_only                                bool = true
	physical_hardware_independently_verified bool
	passes                                   int
	chunk_patterns                           []int = patterns
	ranges                                   int
	bytes_read                               i64
}

pub fn check(source string, manifest Value, passes int) !Report {
	if passes < 1 || passes > 10 { return error('passes must be 1..10') }
	ranges := validate_manifest(manifest)!
	opened := open_source(source)!
	defer { C.close(opened.fd) }
	mut total := i64(0)
	for iteration in 1 .. passes + 1 {
		for chunk in patterns {
			for range in ranges {
				actual := digest(opened.fd, range, chunk)!
				if actual != range.sha256 {
					return error('MISMATCH pass=${iteration} chunk=${chunk} offset=${range.offset} length=${range.length} expected=${range.sha256} actual=${actual}')
				}
				total += range.length
			}
		}
	}
	return Report{
		source_kind: opened.kind
		system:      system_description()
		passes:      passes
		ranges:      ranges.len
		bytes_read:  total
	}
}
