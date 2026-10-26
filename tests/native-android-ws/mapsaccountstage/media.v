// SPDX-License-Identifier: GPL-2.0-or-later
// Streaming media helpers. Archive metadata describes module bytes, not live inode ownership.
module mapsaccountstage

import crypto.sha256
import json2
import modulestream
import os
import tarcore
import tarstream
import time

#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
fn C.kill(int, int) int
fn C.fcntl(int, int, ...int) int
@[c: 'open']
fn C.vinix_maps_media_open(&char, int, ...int) int
@[c: 'write']
fn C.vinix_maps_media_write(int, voidptr, u64) i64
@[c: 'close']
fn C.vinix_maps_media_close(int) int

pub struct Entry {
pub:
	name     string
	kind     string
	mode     u32
	size     u64
	sha256   string
	linkname string
}

pub struct Config {
pub:
	modules []string
	updated string
}

pub fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut state := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		state.write(buffer[..n])!
	}
	return state.sum([]u8{}).hex()
}

fn safe_name(name string) bool {
	return name != '' && name !in ['.', '..'] && name.len <= 255
		&& name.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`)
			|| (it >= `0` && it <= `9`) || it in [`_`, `-`, `.`])
}

pub fn configure(original string, overlay_name string) !Config {
	if !safe_name(overlay_name) || !overlay_name.ends_with('.tar') {
		return error('expected a literal tar overlay basename')
	}
	if original == '' || original.contains_any('\x00\r') {
		return error('expected an LF-delimited Limine configuration')
	}
	mut modules := []string{}
	mut indent := ''
	mut entries := 0
	for line in original.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('/') || trimmed.starts_with(':') {
			entries++
		}
		if !trimmed.starts_with('module_path:') { continue }
		if entries != 1 || !trimmed.starts_with('module_path: boot():/boot/') {
			return error('unsupported or ambiguous Limine module path')
		}
		name := trimmed.all_after('module_path: boot():/boot/')
		if !safe_name(name) || !name.ends_with('.tar') || name == overlay_name
			|| name in modules {
			return error('unsafe, duplicate, non-tar or existing overlay module: ' + name)
		}
		prefix := line[..line.len - line.trim_left(' \t').len]
		if prefix == '' || (indent != '' && indent != prefix) {
			return error('Limine module indentation is ambiguous')
		}
		indent = prefix
		modules << name
	}
	if entries != 1 || modules.len == 0 {
		return error('exactly one populated Limine entry required')
	}
	separator := if original.ends_with('\n') { '' } else { '\n' }
	return Config{modules, original + separator + indent + 'module_path: boot():/boot/' + overlay_name + '\n'}
}

pub fn normalize(name string) !string {
	if name.starts_with('/') || name.contains_any('\x00\n\r\\') {
		return error('unsafe archive name: ' + name)
	}
	mut clean := name
	for clean.starts_with('./') { clean = clean[2..] }
	clean = clean.trim_right('/')
	if clean == '.' || clean == '' { return '' }
	if clean.split('/').any(it in ['', '.', '..']) { return error('unsafe archive name: ' + name) }
	return clean
}

pub fn command(root string, label string, argv []string) !string {
	return command_expected(root, label, argv, 0)
}

pub fn command_expected(root string, label string, argv []string, expected int) !string {
	return command_limit(root, label, argv, expected, 120 * time.second)
}

pub fn command_limit(root string, label string, argv []string, expected int, timeout time.Duration) !string {
	if argv.len == 0 || argv[0] == '' || argv.any(it.contains('\x00')) || timeout <= 0 {
		return error('invalid bounded command')
	}
	receipt := command_receipt(root, label)!
	mut child := os.new_process(argv[0])
	child.use_pgroup = true
	child.set_args(argv[1..])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer {
		if !finished {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
		}
	}
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + timeout
	for {
		out := child.stdout_read()
		error_output := child.stderr_read()
		stdout += out
		stderr += error_output
		if stdout.len + stderr.len > 2 * 1024 * 1024 {
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
			finished = true
			write_json(receipt, {
				'argv':           json2.decode[json2.Any](json2.encode(argv))!
				'exit_code':      json2.Any(child.code)
				'stdout':         json2.Any(stdout[..int_min(stdout.len, 1024 * 1024)])
				'stderr':         json2.Any(stderr[..int_min(stderr.len, 1024 * 1024)])
				'output_limited': json2.Any(true)
			})!
			return error('oversized command output: ' + label)
		}
		if !child.is_alive() && out == '' && error_output == '' { break }
		if time.sys_mono_now() >= deadline {
			// Preserve the observed command failure before returning. Killing the
			// owned process group also reaps any compiler child at the deadline.
			if child.pid > 0 { C.kill(-child.pid, 9) }
			child.wait()
			finished = true
			write_json(receipt, {
				'argv':       json2.decode[json2.Any](json2.encode(argv))!
				'exit_code':  json2.Any(child.code)
				'stdout':     json2.Any(stdout)
				'stderr':     json2.Any(stderr)
				'timed_out':  json2.Any(true)
				'timeout_ns': json2.Any(i64(timeout))
			})!
			return error('command deadline: ' + label)
		}
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	finished = true
	write_json(receipt, {
		'argv':      json2.decode[json2.Any](json2.encode(argv))!
		'exit_code': json2.Any(child.code)
		'stdout':    json2.Any(stdout)
		'stderr':    json2.Any(stderr)
	})!
	if child.code != expected {
		return error(label + ' unexpected exit ' + child.code.str() + ': ' + stderr)
	}
	return stdout
}

pub fn inventory(root string, relative_path string, prefix string, mut result []Entry) ! {
	if os.real_path(root) != root || !os.is_dir(root)
		|| (relative_path != '' && !relative(relative_path)) || !relative(prefix) {
		return error('canonical inventory root and relative paths required')
	}
	path := if relative_path == '' { root } else { root + '/' + relative_path }
	stat := os.lstat(path)!
	name := if relative_path == '' { prefix } else { prefix + '/' + relative_path }
	mode := stat.mode & 0o7777
	match stat.get_filetype() {
		.directory {
			result << Entry{ name: name, kind: 'directory', mode: mode }
			mut children := os.ls(path)!
			children.sort()
			for child in children {
				if child.contains_any('\x00\n\r\\') { return error('unsafe bundle filename') }
				next := if relative_path == '' { child } else { relative_path + '/' + child }
				inventory(root, next, prefix, mut result)!
			}
		}
		.regular {
			result << Entry{ name: name, kind: 'regular', mode: mode, size: stat.size, sha256: hash(path)! }
		}
		.symbolic_link {
			target := os.readlink(path)!
			if target == '' || target.contains_any('\x00\n\r') {
				return error('unsafe bundle symlink')
			}
			result << Entry{ name: name, kind: 'symlink', mode: mode, linkname: target }
		}
		else { return error('unsupported bundle inode: ' + name) }
	}
}

pub fn write_overlay(path string, sources map[string]string, entries []Entry) ! {
	validate_overlay(entries)!
	mut regular := 0
	for entry in entries {
		if entry.kind != 'regular' { continue }
		regular++
		source := sources[entry.name] or { return error('overlay entry has no source') }
		stat := os.lstat(source)!
		if os.real_path(source) != source || stat.get_filetype() != .regular || stat.size != entry.size {
			return error('canonical regular overlay source with exact size required')
		}
	}
	if sources.len != regular { return error('overlay source keys differ from regular entries') }
	if !os.is_abs_path(path) || os.real_path(os.dir(path)) != os.dir(path) || !os.is_dir(os.dir(path)) {
		return error('canonical overlay parent required')
	}
	fd := exclusive(path)!
	mut closed := false
	defer { if !closed { os.fd_close(fd) } }
	mut position := u64(0)
	mut buffer := []u8{len: 1024 * 1024}
	for entry in entries {
		member := tarcore.Member{
			name:     entry.name
			mode:     i64(entry.mode)
			size:     if entry.kind == 'regular' { i64(entry.size) } else { 0 }
			kind:     match entry.kind {
				'directory' { u8(`5`) }
				'symlink' { u8(`2`) }
				else { u8(`0`) }
			}
			linkname: entry.linkname
		}
		write_all(fd, tarcore.header(member)!)!
		position += 512
		if entry.kind == 'regular' {
			source := sources[entry.name] or { return error('overlay entry has no source') }
			mut file := os.open(source)!
			mut state := sha256.new()
			mut remaining := entry.size
			for remaining > 0 {
				mut part := unsafe {
					buffer[..int(if remaining < u64(buffer.len) {
						remaining
					} else {
						u64(buffer.len)
					})]
				}
				n := file.read(mut part) or {
					file.close()
					return err
				}
				if n == 0 {
					file.close()
					return error('bundle file truncated')
				}
				state.write(part[..n]) or { file.close(); return err }
				write_all(fd, part[..n]) or { file.close(); return err }
				remaining -= u64(n)
			}
			mut extra := []u8{len: 1}
			n := file.read(mut extra) or { if err is os.Eof { 0 } else { file.close(); return err } }
			file.close()
			if n != 0 || state.sum([]u8{}).hex() != entry.sha256 {
				return error('overlay source changed or hash differs')
			}
		}
		padding := (512 - entry.size % 512) % 512
		write_all(fd, []u8{len: int(padding)})!
		position += entry.size + padding
	}
	write_all(fd, []u8{len: 1024})!
	position += 1024
	write_all(fd, []u8{len: int((10240 - position % 10240) % 10240)})!
	closed = true
	if C.vinix_maps_media_close(fd) != 0 { return os.error_posix() }
}

fn validate_overlay(entries []Entry) ! {
	mut names := map[string]string{}
	for entry in entries {
		if !relative(entry.name) || normalize(entry.name)! != entry.name || entry.name in names
			|| entry.kind !in ['regular', 'directory', 'symlink'] || entry.mode > 0o7777
			|| entry.size > u64(0x7fffffffffffffff) {
			return error('invalid overlay entry or repeated name')
		}
		if entry.kind == 'regular' {
			if entry.sha256.len != 64 || !entry.sha256.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
				|| entry.linkname != '' { return error('invalid regular overlay metadata') }
		} else if entry.size != 0 || entry.sha256 != ''
			|| (entry.kind == 'directory' && entry.linkname != '')
			|| (entry.kind == 'symlink' && (entry.linkname == '' || entry.linkname.contains_any('\x00\n\r'))) {
			return error('invalid overlay link or directory metadata')
		}
		names[entry.name] = entry.kind
	}
	for entry in entries {
		mut parent := os.dir(entry.name)
		for parent != '.' {
			if parent in names && names[parent] != 'directory' { return error('overlay parent is not a directory') }
			parent = os.dir(parent)
		}
	}
}

pub fn verify_overlay(path string, expected []Entry) ! {
	validate_overlay(expected)!
	mut file := os.open(path)!
	defer { file.close() }
	mut reader := tarstream.from_descriptor(i32(file.fd))!
	defer { reader.close() }
	actual := scan_reader(mut reader, '', map[string]bool{})!
	mut buffer := []u8{len: 1024 * 1024}
	mut trailing := 0
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		trailing += n
		if trailing > 16 * 1024 * 1024 || buffer[..n].any(it != 0) {
			return error('nonzero or oversized overlay trailer')
		}
	}
	if trailing < 512 { return error('overlay requires two terminating zero blocks') }
	if actual != expected { return error('overlay readback inventory differs') }
}

pub fn module_hash(root string, label string, image string, name string) !string {
	if !safe_name(label) || !safe_name(name) || !name.ends_with('.tar') {
		return error('invalid module hash label or member')
	}
	if !os.is_abs_path(image) || os.real_path(image) != image || !os.is_file(image) {
		return error('canonical module image required')
	}
	if os.real_path(root + '/commands') != root + '/commands' || !os.is_dir(root + '/commands') {
		return error('canonical command receipt directory required')
	}
	result := modulestream.hash_member(image, name, root + '/commands/' + label + '.sha256')!
	if result.statuses.producer != 0 || result.statuses.consumer != 0 {
		return error('module hash stream failed: ' + name)
	}
	return result.sha256
}

pub fn external(path string) !string {
	requested := os.abs_path(path)
	if !os.is_dir(os.dir(requested)) { return error('output parent directory must exist') }
	absolute := os.real_path(os.dir(requested)) + '/' + os.file_name(requested)
	repo := os.real_path('/Users/alex/code/vinix')
	if absolute != path || absolute == repo || absolute.starts_with(repo + '/') || absolute.contains_any(' \t\x00\n\r') {
		return error('fresh output must be outside the repository')
	}
	if os.exists(absolute) || os.is_link(absolute) { return error('fresh output required') }
	if (absolute + '/qmp.sock').len >= 104 {
		return error('QMP Unix socket path exceeds 103 bytes')
	}
	return absolute
}

// Check both directions: replacing an input's ancestor is as unsafe as writing
// into the input. Resolved inputs may be files or directories, and must exist.
pub fn disjoint(output string, inputs []string) ! {
	for input in inputs {
		if !os.exists(input) || os.real_path(input) != input || output == input
			|| output.starts_with(input + '/') || input.starts_with(output + '/') {
			return error('canonical inputs and disjoint output required')
		}
	}
}

fn command_receipt(root string, label string) !string {
	if !safe_name(label) || !os.is_abs_path(root)
		|| os.real_path(root + '/commands') != root + '/commands' || !os.is_dir(root + '/commands') {
		return error('canonical receipt directory and literal label required')
	}
	path := root + '/commands/' + label + '.json'
	if os.exists(path) || os.is_link(path) { return error('command receipt already exists') }
	return path
}

fn exclusive(path string) !int {
	fd := C.vinix_maps_media_open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return os.error_posix() }
	return fd
}

fn write_all(fd int, bytes []u8) ! {
	mut position := 0
	for position < bytes.len {
		n := unsafe { C.vinix_maps_media_write(fd, &bytes[position], u64(bytes.len - position)) }
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 { return error('cannot write media output') }
		position += int(n)
	}
}

fn write_json[T](path string, value T) ! {
	fd := exclusive(path)!
	defer { os.fd_close(fd) }
	write_all(fd, (json2.encode(value, prettify: true) + '\n').bytes())!
}

pub fn relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\x00\n\r\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn fresh_directory(path string) ! {
	if !os.is_abs_path(path) || os.exists(path) || os.is_link(path)
		|| os.real_path(os.dir(path)) != os.dir(path) || !os.is_dir(os.dir(path))
		|| path.contains_any('\x00\n\r') || os.base(path) in ['', '.', '..'] {
		return error('fresh canonical extraction directory required')
	}
	os.mkdir(path, mode: 0o700)!
}

fn archive_entry(member tarcore.Member) !Entry {
	name := normalize(member.name)!
	kind := if member.regular() { 'regular' } else {
		match member.kind {
			`5` { 'directory' }
			`2` { 'symlink' }
			`1` { 'hardlink' }
			`3` { 'character' }
			`4` { 'block' }
			`6` { 'fifo' }
			else { return error('unsupported module inode kind') }
		}
	}
	if member.mode < 0 || member.mode > 0o7777 || member.size < 0
		|| (kind != 'regular' && member.size != 0)
		|| (name == '' && kind != 'directory') || member.linkname.contains_any('\x00\n\r') {
		return error('invalid module inode metadata')
	}
	return Entry{name: name, kind: kind, mode: u32(member.mode), size: u64(member.size), linkname: member.linkname}
}

fn selection(paths []string) !map[string]bool {
	mut selected := map[string]bool{}
	for path in paths {
		if !relative(path) || normalize(path)! != path || path in selected {
			return error('selection requires unique normalized relative paths')
		}
		selected[path] = true
	}
	return selected
}

// Preserve all entries in archive order, including repeated declarations.
// The caller constructs its effective last-wins map across original modules.
// Only explicitly selected regular files are extracted; repeated selections
// are rejected rather than silently choosing one of their versions.
fn scan_reader(mut archive tarstream.Reader, extraction_root string, selected map[string]bool) ![]Entry {
	mut actual := []Entry{}
	mut extracted := map[string]bool{}
	mut buffer := []u8{len: 1024 * 1024}
	for {
		member := archive.next() or { if err is tarstream.End { break }; return err }
		mut entry := archive_entry(member)!
		if actual.len >= 100000 { return error('module inventory exceeds bound') }
		mut fd := -1
		if entry.name in selected {
			if entry.kind != 'regular' || entry.name in extracted {
				return error('selected module member is repeated or not regular')
			}
			path := extraction_root + '/' + entry.name
			os.mkdir_all(os.dir(path), mode: 0o700)!
			if os.real_path(os.dir(path)) != os.dir(path) { return error('aliased extraction parent') }
			fd = exclusive(path)!
			extracted[entry.name] = true
		}
		if entry.kind == 'regular' {
			mut state := sha256.new()
			for {
				n := archive.read(mut buffer) or { if fd >= 0 { os.fd_close(fd) }; return err }
				if n == 0 { break }
				state.write(buffer[..n]) or { if fd >= 0 { os.fd_close(fd) }; return err }
				if fd >= 0 {
					write_all(fd, buffer[..n]) or { os.fd_close(fd); return err }
				}
			}
			entry = Entry{...entry, sha256: state.sum([]u8{}).hex()}
		}
		if fd >= 0 { os.fd_close(fd) }
		actual << entry
	}
	if extracted.len != selected.len { return error('selected module member missing') }
	return actual
}

pub fn scan_module(mcopy string, image string, name string, extraction_root string, selected_paths []string) ![]Entry {
	if !safe_name(name) || !name.ends_with('.tar') || !os.is_abs_path(mcopy)
		|| os.real_path(mcopy) != mcopy || !os.is_file(mcopy) || !os.is_abs_path(image)
		|| os.real_path(image) != image || !os.is_file(image) {
		return error('literal module and canonical mcopy executable required')
	}
	selected := selection(selected_paths)!
	if (extraction_root == '') != (selected.len == 0) {
		return error('extraction root and selection must be supplied together')
	}
	if extraction_root != '' {
		disjoint(extraction_root, [image, mcopy])!
		fresh_directory(extraction_root)!
	}
	mut child := os.new_process(mcopy)
	child.use_pgroup = true
	child.set_args(['-i', image, '::/boot/' + name, '-'])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut finished := false
	defer { if !finished { if child.pid > 0 { C.kill(-child.pid, 9) }; child.wait() } }
	fd := child.stdio_fd[1]
	flags := C.fcntl(fd, C.F_GETFL)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0 { return os.error_posix() }
	deadline := time.sys_mono_now() + 20 * time.minute
	mut archive := tarstream.from_descriptor_cancelled(i32(fd), fn [deadline] () bool {
		return time.sys_mono_now() >= deadline
	})!
	defer { archive.close() }
	actual := scan_reader(mut archive, extraction_root, selected)!
	mut stderr := ''
	mut trailing := 0
	for {
		out := child.stdout_read()
		stderr += child.stderr_read()
		trailing += out.len
		if out.bytes().any(it != 0) || trailing > 16 * 1024 * 1024 {
			return error('nonzero or oversized bytes follow module archive')
		}
		if stderr.len > 1024 * 1024 { return error('oversized module diagnostics') }
		alive := child.is_alive()
		if !alive && out == '' { break }
		if time.sys_mono_now() >= deadline { return error('module scan deadline') }
		time.sleep(time.millisecond)
	}
	child.wait()
	finished = true
	if child.code != 0 { return error('module scan failed: ' + stderr) }
	return actual
}

fn test_scan(path string, extraction_root string, paths []string) ![]Entry {
	mut file := os.open(path)!
	defer { file.close() }
	mut reader := tarstream.from_descriptor(i32(file.fd))!
	defer { reader.close() }
	return scan_reader(mut reader, extraction_root, selection(paths)!)
}

// Inline host checks are kept with the sole maintained helper source. The
// future stager can invoke this from its own --self-test mode.
pub fn self_test() ! {
	valid := '/Vinix\n    module_path: boot():/boot/base.tar\n'
	assert configure(valid, 'extra.tar')!.modules == ['base.tar']
	for bad in ['', valid + '/Other\n', valid + '    module_path: boot():/boot/base.tar\n',
		valid + '    module_path: boot():/boot/extra.tar\n', '/Vinix\n    module_path: boot():/boot/../base.tar\n'] {
		if _ := configure(bad, 'extra.tar') { return error('invalid configuration accepted') }
	}
	for bad in ['/absolute', '../escape', 'a//b', 'a/../b', 'a\\b', 'a\nb'] {
		if _ := normalize(bad) { return error('unsafe archive path accepted') }
	}
	assert normalize('./a/b/')! == 'a/b'
	if _ := selection(['a', 'a']) { return error('duplicate extraction selection accepted') }
	root := os.real_path(os.temp_dir()) + '/vinix-maps-media-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	fresh_directory(root)!
	defer { os.rmdir_all(root) or {} }
	os.mkdir(root + '/commands', mode: 0o700)!
	os.write_file(root + '/source', 'fixture-data')!
	entries := [Entry{name: 'a', kind: 'directory', mode: 0o755},
		Entry{name: 'a/file', kind: 'regular', mode: 0o644, size: 12, sha256: hash(root + '/source')!}]
	write_overlay(root + '/sample.tar', {'a/file': root + '/source'}, entries)!
	verify_overlay(root + '/sample.tar', entries)!
	fresh_directory(root + '/extracted')!
	mut file := os.open(root + '/sample.tar')!
	mut reader := tarstream.from_descriptor(i32(file.fd))!
	actual := scan_reader(mut reader, root + '/extracted', selection(['a/file'])!)!
	reader.close()
	file.close()
	assert actual == entries
	assert os.read_file(root + '/extracted/a/file')! == 'fixture-data'
	assert hash(root + '/extracted/a/file')! == entries[1].sha256
	if _ := write_overlay(root + '/sample.tar', {'a/file': root + '/source'}, entries) {
		return error('existing overlay overwritten')
	}
	if _ := write_overlay(root + '/extra-source.tar', {'a/file': root + '/source', 'extra': root + '/source'}, entries) {
		return error('extra overlay source key accepted')
	}
	assert !os.exists(root + '/extra-source.tar')
	if _ := write_overlay(root + '/duplicate.tar', {'a/file': root + '/source'}, [entries[0], entries[0], entries[1]]) {
		return error('duplicate overlay entry accepted')
	}
	wrong_hash := [entries[0], Entry{...entries[1], sha256: '0'.repeat(64)}]
	if _ := write_overlay(root + '/wrong-hash.tar', {'a/file': root + '/source'}, wrong_hash) {
		return error('changed overlay source accepted')
	}
	os.write_file(root + '/trailer.tar', os.read_file(root + '/sample.tar')! + 'x')!
	if _ := verify_overlay(root + '/trailer.tar', entries) { return error('nonzero archive trailer accepted') }
	fresh_directory(root + '/missing')!
	if _ := test_scan(root + '/sample.tar', root + '/missing', ['absent']) { return error('missing selected file accepted') }
	fresh_directory(root + '/not-regular')!
	if _ := test_scan(root + '/sample.tar', root + '/not-regular', ['a']) { return error('selected directory accepted') }
	mut duplicate := tarcore.create_stream(root + '/ordered.tar')!
	duplicate.add(tarcore.Member{name: 'a', kind: `5`}, []u8{})!
	duplicate.add(tarcore.Member{name: 'a', kind: `5`}, []u8{})!
	duplicate.add(tarcore.Member{name: 'a/file', size: 3}, 'one'.bytes())!
	duplicate.add(tarcore.Member{name: 'a/file', size: 3}, 'two'.bytes())!
	duplicate.finish()!
	duplicate.close_checked()!
	ordered := test_scan(root + '/ordered.tar', '', []string{})!
	assert ordered.len == 4 && ordered[0] == ordered[1]
	assert ordered[2].name == ordered[3].name && ordered[2].sha256 != ordered[3].sha256
	fresh_directory(root + '/repeated')!
	if _ := test_scan(root + '/ordered.tar', root + '/repeated', ['a/file']) {
		return error('ambiguous selected file accepted')
	}
	assert os.read_file(root + '/repeated/a/file')! == 'one'
	os.write_file_array(root + '/truncated.tar', tarcore.header(tarcore.Member{name: 'truncated', size: 12})!)!
	if _ := test_scan(root + '/truncated.tar', '', []string{}) { return error('truncated member accepted') }
	if _ := external(root) { return error('existing external output accepted') }
	if _ := disjoint(root + '/child', [root]) { return error('overlapping output accepted') }
	assert command(root, 'success', ['/bin/echo', 'okay'])! == 'okay\n'
	assert command_expected(root, 'expected-failure', ['/usr/bin/false'], 1)! == ''
	if _ := command(root, 'success', ['/bin/echo', 'overwritten']) { return error('existing receipt accepted') }
	if _ := command_limit(root, 'deadline', ['/bin/sleep', '1'], 0, 20 * time.millisecond) {
		return error('overdue child accepted')
	}
	deadline_receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/commands/deadline.json')!)!
	assert deadline_receipt['timed_out']!.bool()
	println('MAPS-MEDIA-SELF-TEST-PASS config paths exact-extraction ordered-duplicates strict-overlay receipt deadline')
}

