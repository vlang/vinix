// SPDX-License-Identifier: GPL-2.0-or-later
// Derive a namespace-compatible copy of the unchanged nativeguard algorithm.
module main

import crypto.sha256
import os

#include <fcntl.h>
#include <unistd.h>
fn C.open(&char, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32

const original_sha = '5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'
const renamed = 'audio_continuation_cancelled'
const host = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01/audio-continuation-host-01'

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn source_stable(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.nlink == b.nlink
		&& a.uid == b.uid && a.gid == b.gid && a.rdev == b.rdev && a.size == b.size
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

fn ordinary(path string, directory bool) ! {
	require(os.is_abs_path(path) && os.real_path(path) == path && !path.contains('|')
		&& !path.bytes().any(it < 32 || it == 127), 'requires canonical ordinary path')!
	bits := os.lstat(path)!.mode & 0o170000
	require(bits == if directory { u32(0o040000) } else { u32(0o100000) }, 'unexpected source/output kind')!
}

fn derive(source string) !string {
	require(sha256.hexhash(source) == original_sha && !source.contains(renamed), 'requires the exact original nativeguard source')!
	mut result := source
	for before, count in {
		'__global interrupted = i32(0)': 1
		'{ interrupted = i32(signal) }': 1
		'\n\tinterrupted = 0\n': 1
		'if interrupted != 0': 5
		'|| interrupted != 0': 1
		'interrupted.str()': 1
		'if interrupted == 0': 1
	} {
		require(result.count(before) == count, 'nativeguard identifier context count differs')!
		result = result.replace(before, before.replace('interrupted', renamed))
	}
	require(result.count(renamed) == 11 && result.replace(renamed, 'interrupted') == source,
		'namespace-only inverse proof failed')!
	return result
}

fn admitted_output(output string) ! {
	ordinary(os.dir(output), true)!
	suffix := '/tests/software-hosted-x11/nativeguard/guard.v'
	require(output.ends_with(suffix), 'output must be the exact nativeguard source leaf')!
	root := output[..output.len - suffix.len]
	ordinary(root, true)!
	require(os.dir(root) == host && os.base(root).starts_with('host-overlay-')
		&& os.base(root).len > 'host-overlay-'.len, 'output must stay in a private charged host overlay')!
}

fn write_new(path string, text string) ! {
	admitted_output(path)!
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, i32(0o600))
	require(fd >= 0, 'source output must be exclusively new')!
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < text.len {
		n := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		require(n > 0 && n <= isize(text.len - offset), 'source write failed; preserve partial output')!
		offset += int(n)
	}
	closed = true
	require(C.close(fd) == 0, 'source output close failed')!
	os.chmod(path, 0o644)!
	require(os.lstat(path)!.nlink == 1 && os.read_file(path)! == text, 'derived source readback differs')!
}

fn run() ! {
	args := os.args[1..]
	require(args.len == 3 && args[0] in ['--emit', '--check', '--controls'],
		'use --emit|--check|--controls ORIGINAL_GUARD OUTPUT_GUARD')!
	ordinary(args[1], false)!
	before := os.lstat(args[1])!
	require(before.size <= 256 * 1024, 'owner source exceeds fixed text bound')!
	source := os.read_file(args[1])!
	result := derive(source)!
	if args[0] == '--emit' { write_new(args[2], result)! }
	if args[0] in ['--check', '--controls'] {
		admitted_output(args[2])!
		ordinary(args[2], false)!
		output := os.lstat(args[2])!
		require(output.nlink == 1 && (output.dev != before.dev || output.inode != before.inode)
			&& os.read_file(args[2])! == result, 'derived source differs or aliases its input')!
	}
	if args[0] == '--controls' {
		for invalid in [source + '\n', result, source.replace('interrupted = i32(0)', 'interrupted = i32(1)')] {
			mut refused := false
			derive(invalid) or { refused = true; '' }
			require(refused, 'changed or already-derived source was accepted')!
		}
	}
	after := os.lstat(args[1])!
	require(source_stable(before, after) && os.read_file(args[1])! == source, 'original source changed during derivation')!
	println('AUDIO OWNER SOURCE ' + args[0] + ' PASS ' + sha256.hexhash(result))
}

fn main() { run() or { eprintln('audio-continuation-owner-source: ' + err.msg()); exit(1) } }
