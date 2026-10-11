// SPDX-License-Identifier: BSD-2-Clause
@[has_globals]
module evidencearchive

import crypto.sha256
import json2
import os
import strconv
import time

#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>

fn C.signal(i32, voidptr) voidptr
fn C.__atomic_store_n(&i32, i32, i32)
fn C.__atomic_load_n(&i32, i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.poll(&C.pollfd, usize, i32) i32

struct C.pollfd {
	fd      i32
	events  i16
	revents i16
}

pub const campaigns = ['2026-10-02-userspace', '2026-10-03-userspace-v5', '2026-10-03-userspace-v6']
pub const source_commit = '8f7239d1fd4c593746279699f6ff25df5f4dd7bd'

__global (
	pending_signal i32
	signal_depth   int
)

fn interrupted(signal i32) {
	unsafe { C.__atomic_store_n(&pending_signal, signal, C.__ATOMIC_RELAXED) }
}

pub struct Guard {
	interrupt voidptr
	terminate voidptr
	pipe      voidptr
	installed bool
}

pub fn own_commands() Guard {
	signal_depth++
	if signal_depth > 1 { return Guard{} }
	unsafe { C.__atomic_store_n(&pending_signal, 0, C.__ATOMIC_RELAXED) }
	return Guard{unsafe { C.signal(C.SIGINT, voidptr(interrupted)) }, unsafe { C.signal(C.SIGTERM, voidptr(interrupted)) }, unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }, true}
}

pub fn (g Guard) close() {
	signal_depth--
	if g.installed {
		unsafe {
			C.signal(C.SIGINT, g.interrupt)
			C.signal(C.SIGTERM, g.terminate)
			C.signal(C.SIGPIPE, g.pipe)
		}
	}
}

pub fn checkpoint() ! {
	signal := unsafe { C.__atomic_load_n(&pending_signal, C.__ATOMIC_RELAXED) }
	if signal != 0 {
		return error_with_code('Historical evidence command interrupted', 128 + int(signal))
	}
}

pub fn digest(content string) string { return sha256.sum(content.bytes()).hex() }

pub struct Record {
pub:
	path          string
	source_commit string
	blob_sha1     string
	sha256        string
	bytes         int
	storage       string
	mode          string
}

pub struct Manifest {
pub:
	schema             int
	source_commit      string
	translation_credit int
	files              []Record
}

pub fn canonical(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\n\r\\') && path.split('/').all(it != '' && it != '.' && it != '..')
}

fn hex(text string, size int) bool {
	return text.len == size && text.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

pub fn manifest(root string) !Manifest {
	data := json2.decode[Manifest](os.read_file(root + '/tests/alloc-bench/results/source-archive.json')!)!
	if data.schema != 1 || data.translation_credit != 0 || !hex(data.source_commit, 40) {
		return error('Unsupported source archive manifest')
	}
	mut paths := map[string]bool{}
	for r in data.files {
		if !canonical(r.path) { return error('Noncanonical evidence path: ' + r.path) }
		if r.path in paths { return error('Duplicate evidence path: ' + r.path) }
		paths[r.path] = true
		if !hex(r.source_commit, 40) || !hex(r.blob_sha1, 40) || !hex(r.sha256, 64) || r.bytes < 0 || r.mode !in [
			'100644',
			'100755',
		] || r.storage !in ['git-history', 'checkout-third-party'] {
			return error('Invalid evidence record: ' + r.path)
		}
	}
	return data
}

pub struct Blob {
pub:
	id      string
	content string
}

// One owned Git process, length-framed binary reads, bounded diagnostics and
// checkpoints. Even a malformed reply, EOF or signal retires and reaps Git.
pub struct Reader {
mut:
	process  &os.Process = unsafe { nil }
	buffer   string
	detail   string
	deadline i64
	closed   bool
}

pub fn reader(root string) !Reader {
	checkpoint()!
	executable := os.find_abs_path_of_executable('git')!
	mut p := os.new_process(executable)
	p.set_args(['cat-file', '--batch'])
	p.set_work_folder(root)
	p.use_pgroup = true
	p.set_redirect_stdio()
	p.run()
	if p.pid <= 0 {
		p.close()
		return error('Cannot start Git source reader')
	}
	return Reader{ process: p, deadline: time.now().unix_milli() + 60000 }
}

fn (mut r Reader) pump() ! {
	checkpoint()!
	if time.now().unix_milli() > r.deadline { return error('Git source reader timed out') }
	detail := r.process.stderr_read()
	if r.detail.len < 16384 { r.detail += detail[..int_min(detail.len, 16384 - r.detail.len)] }
	chunk, eof := pipe_read(r.process.stdio_fd[1])!
	r.buffer += chunk
	if eof { return error('Incomplete Git object: ' + r.detail.trim_space()) }
}

fn pipe_read(fd int) !(string, bool) {
	mut descriptor := C.pollfd{ fd: fd, events: i16(C.POLLIN) }
	ready := C.poll(&descriptor, 1, 10)
	if ready < 0 && C.errno == C.EINTR {
		checkpoint()!
		return '', false
	}
	if ready < 0 { return error('Cannot poll Git source reader') }
	if ready == 0 { return '', false }
	mut buffer := [16384]u8{}
	count := unsafe { C.read(fd, &buffer[0], usize(buffer.len)) }
	if count < 0 && C.errno == C.EINTR {
		checkpoint()!
		return '', false
	}
	if count < 0 { return error('Cannot read Git source reader') }
	return buffer[..int(count)].bytestr().clone(), count == 0
}

pub fn (mut r Reader) read(reference string) !Blob {
	checkpoint()!
	if r.closed || reference == '' || reference.len > 4095 || reference.contains_any('\x00\n\r') {
		return error('Invalid Git object reference')
	}
	r.deadline = time.now().unix_milli() + 60000
	request := reference + '\n'
	mut offset := 0
	for offset < request.len {
		count := unsafe { C.write(r.process.stdio_fd[0], request.str + offset, usize(request.len - offset)) }
		if count < 0 && C.errno == C.EINTR {
			checkpoint()!
			continue
		}
		if count <= 0 { return error('Git source reader failed') }
		offset += int(count)
	}
	mut newline := -1
	for {
		newline = r.buffer.index('\n') or { -1 }
		if newline >= 0 { break }
		if r.buffer.len > 4096 { return error('Invalid Git object header') }
		r.pump()!
	}
	header := r.buffer[..newline].split(' ')
	if header.len != 3 || header[1] != 'blob' || !hex(header[0], 40) || header[2] == '' || !header[2].bytes().all(it.is_digit()) {
		return error('Cannot recover historical blob: ' + reference)
	}
	length := strconv.parse_uint(header[2], 10, 64) or { return error('Invalid Git object length') }
	if length > 256 * 1024 * 1024 { return error('Historical Git object exceeds 256 MiB') }
	r.buffer = r.buffer[newline + 1..].clone()
	for r.buffer.len < int(length) + 1 { r.pump()! }
	if r.buffer[int(length)] != `\n` { return error('Incomplete Git object: ' + reference) }
	content := r.buffer[..int(length)].clone()
	r.buffer = r.buffer[int(length) + 1..].clone()
	return Blob{header[0], content}
}

pub fn (mut r Reader) close() {
	if r.closed { return }
	r.closed = true
	// No is_alive()/wait() runs while reading: an exited leader stays unreaped,
	// reserving its PID until the owned process group has been killed. EOF is
	// detected on the pipe, so a surviving descendant cannot escape cleanup.
	r.process.signal_pgkill()
	r.process.signal_kill()
	r.process.wait()
	r.process.close()
}

pub fn checked(record Record, blob Blob) !string {
	if blob.id != record.blob_sha1 {
		return error('Historical source blob differs: ' + record.path)
	}
	if blob.content.len != record.bytes || digest(blob.content) != record.sha256 {
		return error('Historical source bytes differ: ' + record.path)
	}
	return blob.content
}

pub fn read_source(root string, path string) !string {
	data := manifest(root)!
	for record in data.files {
		if record.path == path {
			mut r := reader(root)!
			defer { r.close() }
			return checked(record, r.read(record.source_commit + ':' + path)!)
		}
	}
	return error('Source is absent from the evidence manifest: ' + path)
}

pub fn verify(root string, data Manifest) ! {
	mut r := reader(root)!
	defer { r.close() }
	for record in data.files {
		checked(record, r.read(record.source_commit + ':' + record.path)!)!
		if record.storage == 'checkout-third-party' {
			checked(record, Blob{record.blob_sha1, os.read_file(root + '/' + record.path)!})!
		}
	}
	println('Historical source archive PASS: ${data.files.len} immutable blobs verified')
}

fn resolved(path string, depth int) !string {
	if depth > 64 { return error('Evidence destination symlink loop') }
	absolute := os.abs_path(path)
	if absolute == '/' { return '/' }
	parent := resolved(os.dir(absolute), depth + 1)!
	candidate := os.join_path(parent, os.file_name(absolute))
	if os.is_link(candidate) {
		target := os.readlink(candidate)!
		return resolved(if target.starts_with('/') { target } else { os.join_path(parent, target) }, depth + 1)
	}
	return candidate
}

fn within(root string, path string) bool {
	return path == root || path.starts_with(root.trim_right('/') + '/')
}

pub fn destination(root string, output string, relative string) !string {
	if !canonical(relative) { return error('Noncanonical evidence path: ' + relative) }
	out := resolved(output, 0)!
	path := resolved(os.join_path(out, relative), 0)!
	if !within(out, path) { return error('Evidence destination escapes output: ' + path) }
	if within(os.real_path(root), path) {
		return error('Historical source must be recovered outside the checkout')
	}
	return path
}

pub fn write_source(root string, output string, relative string, content string, mode string) ! {
	path := destination(root, output, relative)!
	os.mkdir_all(os.dir(path))!
	// Recheck after creating ancestors; exclusive creation never truncates an
	// existing object. Existing evidence must match before its mode is restored.
	if destination(root, output, relative)! != path { return error('Evidence destination changed') }
	if os.exists(path) {
		if os.read_file(path)! != content {
			return error('Refusing to overwrite changed evidence: ' + path)
		}
	} else {
		fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
		if fd < 0 { return error('Cannot create evidence: ' + path) }
		mut complete := false
		defer {
			C.close(fd)
			if !complete { os.rm(path) or {} }
		}
		mut cursor := 0
		for cursor < content.len {
			checkpoint()!
			count := unsafe { C.write(fd, content.str + cursor, usize(content.len - cursor)) }
			if count < 0 && C.errno == C.EINTR { continue }
			if count <= 0 { return error('Cannot write evidence: ' + path) }
			cursor += int(count)
		}
		complete = true
	}
	os.chmod(path, if mode == '100755' { 0o755 } else { 0o644 })!
}

pub fn materialize(root string, data Manifest, output string, paths []string, snapshot string) ! {
	destination(root, output, '.source-archive-output')!
	if snapshot != '' {
		if snapshot !in campaigns || paths.len > 0 { return error('Invalid snapshot selection') }
		prefix := 'tests/alloc-bench/results/' + snapshot
		// ls-tree only returns trusted names from the immutable commit. It is
		// captured through the same owned, bounded process lifetime as blob reads.
		listing := command(root, ['ls-tree', '-r', '-z', data.source_commit, '--', prefix])!
		mut r := reader(root)!
		defer { r.close() }
		mut count := 0
		for entry in listing.split('\x00') {
			if entry == '' { continue }
			parts := entry.split_nth('\t', 2)
			if parts.len != 2 { return error('Invalid historical tree entry') }
			meta := parts[0].split(' ')
			if meta.len != 3 || meta[1] != 'blob' || meta[0] !in ['100644', '100755'] {
				return error('Unsupported historical tree entry: ' + parts[1])
			}
			blob := r.read(meta[2])!
			if blob.id != meta[2] { return error('Git object identity changed') }
			write_source(root, output, parts[1], blob.content, meta[0])!
			count++
		}
		println('Recovered ${count} exact snapshot files under ${os.join_path(os.abs_path(output), prefix)}')
	} else {
		mut selected := map[string]bool{}
		for path in paths { selected[path] = true }
		if paths.len == 0 {
			for item in data.files {
				if item.storage == 'git-history' { selected[item.path] = true }
			}
		}
		mut records := map[string]Record{}
		for item in data.files { records[item.path] = item }
		mut names := selected.keys()
		names.sort()
		for name in names {
			if name !in records { return error('Unknown evidence source: ' + name) }
		}
		mut r := reader(root)!
		defer { r.close() }
		for name in names {
			record := records[name]
			content := checked(record, r.read(record.source_commit + ':' + name)!)!
			write_source(root, output, name, content, record.mode)!
		}
		println('Recovered ${names.len} exact source files under ${os.abs_path(output)}')
	}
}

pub fn command(root string, args []string) !string {
	checkpoint()!
	mut p := os.new_process(os.find_abs_path_of_executable('git')!)
	p.set_args(args)
	p.set_work_folder(root)
	p.set_redirect_stdio()
	p.use_pgroup = true
	p.run()
	defer {
		p.signal_pgkill()
		p.signal_kill()
		p.wait()
		p.close()
	}
	if p.pid <= 0 { return error('Cannot start Git') }
	C.close(p.stdio_fd[0])
	p.stdio_fd[0] = -1
	mut output := ''
	mut detail := ''
	deadline := time.now().unix_milli() + 60000
	for {
		checkpoint()!
		chunk := p.stderr_read()
		if detail.len < 16384 { detail += chunk[..int_min(chunk.len, 16384 - detail.len)] }
		part, eof := pipe_read(p.stdio_fd[1])!
		output += part
		if output.len > 16 * 1024 * 1024 { return error('Git tree listing exceeds 16 MiB') }
		if eof { break }
		if time.now().unix_milli() > deadline { return error('Git command timed out') }
		time.sleep(time.millisecond)
	}
	p.signal_pgkill()
	p.wait()
	if p.code != 0 { return error('Git source reader failed: ' + detail.trim_space()) }
	return output
}
