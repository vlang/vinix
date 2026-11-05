// SPDX-License-Identifier: GPL-2.0-or-later
// Capture the performance adapter's literal guest tree without following links.
module main

import crypto.sha256
import json2
import os
import time

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

fn C.fstat(i32, &C.stat) i32
fn C.mkfifo(&char, u32) i32

const max_entries = 250000
const max_depth = 128
const max_text = 32 * 1024 * 1024

struct Capture {
	deadline u64
mut:
	entries int
	bytes int
	rows []string
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn inside(path string, root string) bool { return path == root || path.starts_with(root.trim_right('/') + '/') }

fn stable(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime
}

fn fd_stat(fd i32) !os.Stat {
	mut value := C.stat{}
	if C.fstat(fd, &value) != 0 { return error('cannot inspect open input') }
	return os.Stat{dev: u64(value.st_dev), inode: value.st_ino, mode: value.st_mode,
		nlink: value.st_nlink, uid: value.st_uid, gid: value.st_gid, size: u64(value.st_size),
		mtime: value.st_mtime, ctime: value.st_ctime}
}

fn digest_file(path string, before os.Stat, deadline u64) !string {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot open ordinary input') }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	require(stable(before, fd_stat(fd)!), 'input changed before hashing')!
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 65536}
	defer { unsafe { buffer.free() } }
	mut read_bytes := u64(0)
	for {
		require(time.sys_mono_now() <= deadline, 'manifest deadline exceeded')!
		count := C.read(fd, buffer.data, usize(buffer.len))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 || count > buffer.len { return error('input read failed') }
		if count == 0 { break }
		require(u64(count) <= before.size - read_bytes, 'input grew while hashing')!
		read_bytes += u64(count)
		hash.write(buffer[..int(count)])!
	}
	require(read_bytes == before.size && stable(before, fd_stat(fd)!)
		&& stable(before, os.lstat(path)!), 'input changed while hashing')!
	closed = true
	if C.close(fd) != 0 { return error('input close failed') }
	return hash.sum([]u8{}).hex()
}

fn row(mut capture Capture, text string) ! {
	require(text.len < max_text && capture.bytes <= max_text - text.len - 1,
		'manifest text exceeds 32 MiB')!
	capture.rows << text
	capture.bytes += text.len + 1
}

fn walk(root string, relative string, depth int, mut capture Capture) ! {
	require(depth <= max_depth && time.sys_mono_now() <= capture.deadline,
		'manifest depth or deadline exceeded')!
	path := if relative == '' { root } else { root + '/' + relative }
	before := os.lstat(path)!
	require(before.get_filetype() == .directory, 'manifest directory changed')!
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		require(!name.contains_any('\t\r\n'), 'unsupported inventory path')!
		capture.entries++
		require(capture.entries <= max_entries && time.sys_mono_now() <= capture.deadline,
			'manifest entry or deadline limit')!
		item := if relative == '' { name } else { relative + '/' + name }
		child := root + '/' + item
		entry := os.lstat(child)!
		match entry.get_filetype() {
			.regular {
				value := digest_file(child, entry, capture.deadline)!
				row(mut capture, 'file\t' + value + '\t' + entry.mode.str() + '\t' + item)!
			}
			.symbolic_link {
				target := os.readlink(child)!
				require(!target.contains_any('\t\r\n'), 'unsupported link target')!
				require(stable(entry, os.lstat(child)!) && os.readlink(child)! == target,
					'link changed while capturing')!
				row(mut capture, 'link\t' + item + '\t' + target)!
			}
			.directory {
				row(mut capture, 'directory\t' + entry.mode.str() + '\t' + item)!
				walk(root, item, depth + 1, mut capture)!
				require(stable(entry, os.lstat(child)!), 'directory changed while capturing')!
			}
			else { return error('unsupported root entry: ' + item) }
		}
	}
	mut after_names := os.ls(path)!
	after_names.sort()
	require(names == after_names && stable(before, os.lstat(path)!),
		'directory membership or metadata changed')!
}

fn capture(root string) !(string, u32, int) {
	require(!root.contains('\x00'), 'canonical ordinary source directory required')!
	require(os.is_abs_path(root) && root == os.real_path(root)
		&& !root.contains_any('\t\r\n') && os.lstat(root)!.get_filetype() == .directory,
		'canonical ordinary source directory required')!
	before := os.lstat(root)!
	mut state := Capture{deadline: time.sys_mono_now() + 120 * u64(time.second)}
	walk(root, '', 0, mut state)!
	text := state.rows.join('\n') + '\n'
	require(time.sys_mono_now() <= state.deadline, 'manifest deadline exceeded')!
	require(text.len <= max_text && stable(before, os.lstat(root)!), 'source changed after capture')!
	return text, before.mode, state.entries
}

fn output_admit(root string, output string) ! {
	require(!output.contains('\x00'), 'canonical ordinary output parent required')!
	require(os.is_abs_path(output) && !output.contains_any('\t\r\n')
		&& os.real_path(os.dir(output)) == os.dir(output)
		&& os.lstat(os.dir(output))!.get_filetype() == .directory,
		'canonical ordinary output parent required')!
	require(!inside(output, root), 'manifest output overlaps source')!
	require(!os.exists(output) && !os.is_link(output), 'manifest output must be fresh')!
}

fn write_exclusive(path string, text string) ! {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return error('cannot exclusively create manifest') }
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < text.len {
		written := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 || written > isize(text.len - offset) { return error('manifest write failed') }
		offset += int(written)
	}
	closed = true
	if C.close(fd) != 0 { return error('manifest close failed') }
	info := os.lstat(path)!
	require(info.get_filetype() == .regular && info.nlink == 1 && info.mode & 0o7777 == 0o600
		&& info.size == u64(text.len) && os.read_file(path)! == text, 'written manifest differs')!
}

fn create(root string, output string) !map[string]string {
	deadline := time.sys_mono_now() + 120 * u64(time.second)
	output_admit(root, output)!
	text, mode, entries := capture(root)!
	require(time.sys_mono_now() <= deadline, 'manifest deadline exceeded')!
	output_admit(root, output)!
	write_exclusive(output, text)!
	value := sha256.hexhash(text)
	require(time.sys_mono_now() <= deadline, 'manifest deadline exceeded')!
	return {'root': root, 'root_mode': mode.str(), 'entries': entries.str(),
		'manifest': output, 'sha256': value, 'bytes': text.len.str()}
}

fn selfcheck(state string) ! {
	require(os.is_abs_path(state) && os.real_path(os.dir(state)) == os.dir(state)
		&& !os.exists(state) && !os.is_link(state), 'fresh canonical selfcheck state required')!
	os.mkdir(state)!
	root := state + '/root'; os.mkdir(root)!
	os.write_file(root + '/z', 'payload\x00tail')!; os.chmod(root + '/z', 0o640)!
	os.mkdir(root + '/d')!; os.chmod(root + '/d', 0o750)!
	os.write_file(root + '/d/empty', '')!
	os.symlink('/guest/absolute', root + '/absolute')!
	os.symlink('../missing', root + '/dangling')!
	os.symlink('d', root + '/intermediate')!
	before := os.lstat(root)!
	text, mode, entries := capture(root)!
	expected := 'link\tabsolute\t/guest/absolute\n'
		+ 'directory\t' + os.lstat(root + '/d')!.mode.str() + '\td\n'
		+ 'file\t' + sha256.hexhash('') + '\t' + os.lstat(root + '/d/empty')!.mode.str() + '\td/empty\n'
		+ 'link\tdangling\t../missing\nlink\tintermediate\td\n'
		+ 'file\t' + sha256.hexhash('payload\x00tail') + '\t' + os.lstat(root + '/z')!.mode.str() + '\tz\n'
	require(text == expected && entries == 6 && mode == before.mode && stable(before, os.lstat(root)!),
		'literal legacy manifest differs')!
	result := create(root, state + '/manifest.tsv')!
	require(result['sha256'] == sha256.hexhash(expected) && os.read_file(state + '/manifest.tsv')! == expected,
		'created manifest differs')!
	mut controls := ['exact legacy rows, modes and order', 'literal absolute/dangling/intermediate guest links',
		'unchanged source metadata', 'exclusive complete manifest output']
	for triple in [[root + '\x00ignored', state + '/nul-root.tsv', 'canonical ordinary source directory required'],
		[root, state + '/nul-output.tsv\x00ignored', 'canonical ordinary output parent required']] {
		mut refused := ''
		create(triple[0], triple[1]) or { refused = err.msg(); map[string]string{} }
		require(refused == triple[2] && !os.exists(state + '/nul-root.tsv')
			&& !os.exists(state + '/nul-output.tsv'), 'NUL pathname refusal created a prefix output')!
		controls << 'refused NUL pathname before native path use'
	}
	for pair in [[root, state + '/manifest.tsv', 'manifest output must be fresh'],
		[root, root + '/inside', 'manifest output overlaps source']] {
		mut refused := ''
		create(pair[0], pair[1]) or { refused = err.msg(); map[string]string{} }
		require(refused == pair[2], 'freshness or source containment refusal differs: ' + refused)!
		controls << 'refused ' + pair[1].all_after_last('/')
	}
	os.symlink(root, state + '/alias')!
	for pair in [[state + '/alias', state + '/aliased-source.tsv', 'canonical ordinary source directory required'],
		[root, state + '/alias/output', 'canonical ordinary output parent required']] {
		mut refused := ''
		create(pair[0], pair[1]) or { refused = err.msg(); map[string]string{} }
		require(refused == pair[2] && !os.exists(pair[1]), 'source or output parent alias refusal differs: ' + refused)!
		controls << 'refused canonical alias'
	}
	os.write_file(root + '/bad\tname', '')!
	mut failure := ''
	capture(root) or { failure = err.msg(); '', u32(0), 0 }
	require(failure == 'unsupported inventory path', 'unsupported path accepted')!
	os.rm(root + '/bad\tname')!
	controls << 'refused tab path'
	os.symlink('bad\nlink', root + '/bad-link')!
	failure = ''
	capture(root) or { failure = err.msg(); '', u32(0), 0 }
	require(failure == 'unsupported link target', 'unsupported link accepted')!
	os.rm(root + '/bad-link')!
	controls << 'refused newline link'
	require(C.mkfifo((root + '/fifo').str, 0o600) == 0, 'cannot create unsupported fixture')!
	failure = ''
	capture(root) or { failure = err.msg(); '', u32(0), 0 }
	require(failure == 'unsupported root entry: fifo', 'unsupported special entry accepted')!
	os.rm(root + '/fifo')!
	controls << 'refused FIFO without opening it'
	entry := os.lstat(root + '/z')!
	os.chmod(root + '/z', 0o600)!
	require(!stable(entry, os.lstat(root + '/z')!), 'metadata change guard accepted chmod')!
	controls << 'metadata identity change guard'
	mut limited := Capture{deadline: 0}
	failure = ''
	walk(root, '', 0, mut limited) or { failure = err.msg() }
	require(failure == 'manifest depth or deadline exceeded', 'expired deadline accepted')!
	controls << 'expired walk deadline'
	limited = Capture{deadline: time.sys_mono_now() + u64(time.second), entries: max_entries}
	failure = ''
	walk(root, '', 0, mut limited) or { failure = err.msg() }
	require(failure == 'manifest entry or deadline limit', 'entry bound accepted')!
	controls << 'entry bound'
	limited = Capture{deadline: time.sys_mono_now() + u64(time.second)}
	failure = ''
	walk(root, '', max_depth + 1, mut limited) or { failure = err.msg() }
	require(failure == 'manifest depth or deadline exceeded', 'depth bound accepted')!
	controls << 'depth bound'
	limited = Capture{bytes: max_text}
	failure = ''
	row(mut limited, 'x') or { failure = err.msg() }
	require(failure == 'manifest text exceeds 32 MiB', 'text bound accepted')!
	controls << 'text bound'
	require(controls.len == 18, 'selfcheck count differs')!
	os.write_file(state + '/result.json', json2.encode(controls) + '\n')!
	println('LITERAL MANIFEST PASS 18 controls')
}

fn run() ! {
	if os.args.len == 3 && os.args[1] == 'selfcheck' { selfcheck(os.args[2])!; return }
	if os.args.len != 4 || os.args[1] != 'create' {
		return error('usage: literal-manifest selfcheck NEW_STATE | create ROOT NEW_MANIFEST')
	}
	println(json2.encode(create(os.args[2], os.args[3])!))
}

fn main() { run() or { eprintln('literal-manifest: ' + err.msg()); exit(1) } }
