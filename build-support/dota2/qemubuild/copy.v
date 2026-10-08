// SPDX-License-Identifier: GPL-2.0-or-later
module qemubuild

import os

pub struct CopyFailure {
pub:
	source      string
	destination string
	message     string
}

pub struct CopyError {
pub:
	entries []CopyFailure
}

pub fn (e CopyError) msg() string { return 'Source copy failed' }

pub fn (e CopyError) code() int { return 0 }

// shutil.copytree(..., symlinks=True) owns a new destination and accumulates
// per-entry errors while preserving links and metadata on successful entries.
pub fn clone_tree(source string, destination string) ! {
	names := os.ls(source) or { return FileError{err.code(), source} }
	mkdir(destination, false, false)!
	mut failures := []CopyFailure{}
	for name in names {
		from := join(source, name)
		to := join(destination, name)
		clone_entry(from, to) or {
			if err is CopyError {
				failures << err.entries
			} else {
				failures << CopyFailure{from, to, copy_message(err)}
			}
			continue
		}
	}
	copy_stat(source, destination, true) or { failures << CopyFailure{source, destination, copy_message(err)} }
	if failures.len != 0 { return CopyError{failures} }
}

fn clone_entry(source string, destination string) ! {
	if is_link(source)! {
		target := os.readlink(source) or { return FileError{err.code(), source} }
		os.symlink(target, destination) or { return FileError{err.code(), destination} }
		copy_stat(source, destination, false)!
	} else if is_dir(source)! {
		clone_tree(source, destination)!
	} else {
		copy2(source, destination)!
	}
}

fn copy_message(err IError) string {
	if err is FileError {
		return '[Errno ${err.number}] ' + err.msg() + if err.filename == '' {
			''
		} else {
			': ' + python_repr(err.filename)
		}
	}
	return err.msg()
}

fn python_repr(value string) string {
	quote := if value.contains("'") && !value.contains('"') { '"' } else { "'" }
	return quote + value.replace('\\', '\\\\').replace(quote, '\\' + quote)
		.replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + quote
}

$if linux {
	#include <sys/xattr.h>
	fn C.listxattr(&char, voidptr, usize) isize
	fn C.llistxattr(&char, voidptr, usize) isize
	fn C.getxattr(&char, &char, voidptr, usize) isize
	fn C.lgetxattr(&char, &char, voidptr, usize) isize
	fn C.setxattr(&char, &char, voidptr, usize, i32) i32
	fn C.lsetxattr(&char, &char, voidptr, usize, i32) i32
}

fn copy_xattrs(source string, destination string, follow bool) ! {
	$if linux {
		length := if follow {
			C.listxattr(source.str, unsafe { nil }, 0)
		} else {
			C.llistxattr(source.str, unsafe { nil }, 0)
		}
		if length < 0 {
			if C.errno in [C.ENOTSUP, C.ENODATA, C.EINVAL] { return }
			return io_error(source)
		}
		if length == 0 { return }
		mut names := []u8{len: int(length)}
		count := if follow {
			C.listxattr(source.str, names.data, usize(names.len))
		} else {
			C.llistxattr(source.str, names.data, usize(names.len))
		}
		if count < 0 { return io_error(source) }
		for name in names[..int(count)].bytestr().split('\x00') {
			if name == '' { continue }
			size := if follow {
				C.getxattr(source.str, name.str, unsafe { nil }, 0)
			} else {
				C.lgetxattr(source.str, name.str, unsafe { nil }, 0)
			}
			if size < 0 {
				if C.errno in [C.EPERM, C.ENOTSUP, C.ENODATA, C.EINVAL] { continue }
				return io_error(source)
			}
			mut value := []u8{len: int(size)}
			got := if follow {
				C.getxattr(source.str, name.str, value.data, usize(value.len))
			} else {
				C.lgetxattr(source.str, name.str, value.data, usize(value.len))
			}
			if got < 0 {
				if C.errno in [C.EPERM, C.ENOTSUP, C.ENODATA, C.EINVAL] { continue }
				return io_error(source)
			}
			result := if follow {
				C.setxattr(destination.str, name.str, value.data, usize(got), 0)
			} else {
				C.lsetxattr(destination.str, name.str, value.data, usize(got), 0)
			}
			if result != 0 && C.errno !in [C.EPERM, C.ENOTSUP, C.ENODATA, C.EINVAL] {
				return io_error(destination)
			}
		}
	}
}
