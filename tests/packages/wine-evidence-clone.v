// SPDX-License-Identifier: GPL-2.0-or-later
// Replace duplicate ordinary files in a new audit workspace with APFS clones.
// This preserves paths, bytes and modes; never point it at a sealed bundle.
module main

import os
import tests.packages.winesource

$if macos {
	#include <sys/clonefile.h>
	fn C.clonefile(&char, &char, i32) i32
}

fn run() ! {
	if os.args.len != 3 { return error('usage: CLONE MATCHING_SOURCE_ROOT UNSEALED_TARGET_ROOT') }
	source := os.real_path(os.args[1]); target := os.real_path(os.args[2])
	if source == target || !os.is_dir(source) || !os.is_dir(target) { return error('distinct existing roots required') }
	mut count := 0
	mut total := u64(0)
	for path in os.walk_ext(target, '', hidden: true) {
		other := source + path[target.len..]
		if !os.exists(other) || os.real_path(path) != path || os.real_path(other) != other { continue }
		before := os.lstat(path)!; candidate := os.lstat(other)!
		if before.get_filetype() != .regular || candidate.get_filetype() != .regular
			|| before.size != candidate.size || before.mode & 0o7777 != candidate.mode & 0o7777 { continue }
		hash := winesource.file_digest(path)!
		if winesource.file_digest(other)! != hash { continue }
		temporary := path + '.evidence-clone'
		if os.exists(temporary) || os.is_link(temporary) { return error('fresh clone temporary required') }
		$if macos {
			if C.clonefile(other.str, temporary.str, 0) != 0 { return error('APFS evidence clone failed') }
		} $else { return error('APFS evidence cloning requires macOS') }
		defer { os.rm(temporary) or {} }
		cloned := os.lstat(temporary)!
		if cloned.get_filetype() != .regular || cloned.size != before.size || cloned.mode & 0o7777 != before.mode & 0o7777
			|| winesource.file_digest(temporary)! != hash || winesource.file_digest(path)! != hash {
			return error('evidence clone bytes or mode differ')
		}
		os.rename(temporary, path)!
		if winesource.file_digest(path)! != hash { return error('evidence clone replacement differs') }
		count++; total += before.size
	}
	println('WINE EVIDENCE CLONE PASS matching files=' + count.str() + ' logical bytes=' + total.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
