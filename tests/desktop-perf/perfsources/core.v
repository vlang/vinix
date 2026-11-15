// SPDX-License-Identifier: GPL-2.0-or-later
// Frozen source inputs for the fixed performance adapters, not a full checkout.
module perfsources

import crypto.sha256
import json2
import os

#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
fn C.lchmod(&char, u32) i32

pub const seeds = ['build-support/compile-v-module', 'build-support/run-v-tool.sh',
	'build-support/find-v.sh', 'tests/linuxkpi/generate_module.v', 'tests/desktop-perf',
	'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso',
	'tests/linuxkpi/hosttest', 'tools/hosttest', 'tools/sourcecommand', 'tools/qmpclient']

pub struct Entry {
pub:
	path string
	kind string
	mode u32
	size u64
	sha256 string
	link string
	resolved string
}

pub struct Receipt {
pub:
	format int = 1
	source string
	destination string
	selected []string
	entries []Entry
}

struct Scan {
	root string
mut:
	entries map[string]Entry
	expanded map[string]bool
	bytes u64
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn inside(path string, root string) bool { return path == root || path.starts_with(root + '/') }
fn mode(path string) !u32 { return u32(os.lstat(path)!.mode) & 0o7777 }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn admitted(path string) bool {
	return os.file_ext(path) in ['.v', '.c', '.h', '.sh', '.md', '.json', '.txt', '.inc', '.S']
		|| os.base(path) == 'v.mod' || os.base(path).starts_with('LICENSE')
}

fn relative(root string, path string) !string {
	require(inside(path, root), 'source link escapes the selected tree: ' + path)!
	return if path == root { '' } else { path[root.len + 1..] }
}

fn (mut scan Scan) parent(rel string, depth int) ! {
	if rel == '.' || rel == '' { return }
	require(depth <= 128, 'source parent nesting exceeds its bound')!
	scan.parent(os.dir(rel), depth + 1)!
	path := scan.root + '/' + rel
	if os.is_link(path) { scan.add(rel, true, depth + 1)! }
	else {
		require(os.is_dir(path), 'source parent is not a directory')!
		resolved := os.real_path(path)
		if resolved != path { scan.parent(relative(scan.root, resolved)!, depth + 1)!; return }
		scan.entries[rel] = Entry{path: rel, kind: 'directory', mode: mode(path)!}
	}
}

fn (mut scan Scan) add(rel string, force bool, depth int) ! {
	require(depth <= 128 && scan.entries.len < 10000, 'source closure exceeds its bound')!
	if rel in scan.expanded { return }
	require(!os.is_abs_path(rel) && !rel.contains_any('\r\n\t')
		&& (rel == '' || rel.split('/').all(it != '' && it !in ['.', '..'])), 'invalid source relative path')!
	path := if rel == '' { scan.root } else { scan.root + '/' + rel }
	scan.expanded[rel] = true
	if rel != '' {
		parent := os.dir(rel)
		scan.parent(parent, depth + 1)!
		// Parent aliases are copied as links with their physical target trees.
		resolved_parent := os.real_path(os.dir(path))
		parent_rel := relative(scan.root, resolved_parent)!
		if resolved_parent != os.dir(path) {
			scan.add(if parent_rel == '' { os.base(path) } else { parent_rel + '/' + os.base(path) }, force, depth + 1)!
			return
		}
	}
	if os.is_link(path) {
		link := os.readlink(path)!
		require(!os.is_abs_path(link), 'absolute source links are not relocatable')!
		resolved := os.real_path(path)
		require(resolved != '' && os.exists(resolved), 'dangling source link')!
		target := relative(scan.root, resolved)!
		scan.entries[rel] = Entry{path: rel, kind: 'link', mode: mode(path)!, link: link, resolved: target}
		// Also retain intermediate aliases needed by the literal link spelling.
		literal := relative(scan.root, os.abs_path(os.join_path(os.dir(path), link)))!
		scan.add(literal, true, depth + 1)!
		scan.add(target, true, depth + 1)!
	} else if os.is_dir(path) {
		scan.entries[rel] = Entry{path: rel, kind: 'directory', mode: mode(path)!}
		mut names := os.ls(path)!; names.sort()
		for name in names {
			if name in ['.git', 'results'] { continue }
			scan.add(if rel == '' { name } else { rel + '/' + name }, false, depth + 1)!
		}
	} else if os.is_file(path) {
		if !force && !admitted(rel) { scan.expanded.delete(rel); return }
		size := os.file_size(path)
		require(size <= 5 * 1024 * 1024, 'source file exceeds 5 MiB: ' + rel)!
		require(scan.bytes + size <= 64 * 1024 * 1024, 'source closure exceeds 64 MiB')!
		scan.bytes += size
		scan.entries[rel] = Entry{path: rel, kind: 'file', mode: mode(path)!, size: size, sha256: digest(path)!}
	} else { return error('missing or unsupported source node: ' + rel) }
}

fn source_entries(root string, selected []string) ![]Entry {
	mut scan := Scan{root: root}
	// Root is recorded without traversing unrelated repository directories.
	scan.entries[''] = Entry{path: '', kind: 'directory', mode: mode(root)!}
	for seed in selected { scan.add(seed, true, 0)! }
	mut entries := scan.entries.values()
	entries.sort(a.path < b.path)
	return entries
}

fn check_destination(receipt Receipt) ! {
	mut expected := map[string]bool{}
	for entry in receipt.entries {
		path := receipt.destination + if entry.path == '' { '' } else { '/' + entry.path }
		expected[path] = true
		require(mode(path)! == entry.mode, 'staged source mode differs: ' + entry.path)!
		match entry.kind {
			'directory' { require(!os.is_link(path) && os.is_dir(path), 'staged directory differs')! }
			'file' {
				require(!os.is_link(path) && os.is_file(path) && os.file_size(path) == entry.size
					&& digest(path)! == entry.sha256, 'staged source bytes differ: ' + entry.path)!
			}
			'link' {
				require(os.is_link(path) && os.readlink(path)! == entry.link
					&& relative(receipt.destination, os.real_path(path))! == entry.resolved,
					'staged source link differs: ' + entry.path)!
			}
			else { return error('unknown source entry type') }
		}
	}
	check_extra(receipt.destination, expected)!
}

fn check_extra(path string, expected map[string]bool) ! {
	require(path in expected, 'unexpected staged source node: ' + path)!
	if !os.is_link(path) && os.is_dir(path) {
		for name in os.ls(path)! { check_extra(path + '/' + name, expected)! }
	}
}

pub fn verify(receipt Receipt) ! {
	require(receipt.format == 1 && receipt.source == os.real_path(receipt.source)
		&& receipt.destination == os.real_path(receipt.destination) && receipt.selected.len > 0
		&& !inside(receipt.source, receipt.destination) && !inside(receipt.destination, receipt.source),
		'invalid source receipt roots or selection')!
	require(source_entries(receipt.source, receipt.selected)! == receipt.entries, 'selected source changed')!
	check_destination(receipt)!
}

pub fn stage(source string, destination string, selected []string) !Receipt {
	require(source == os.real_path(source) && os.is_dir(source), 'canonical source root required')!
	require(os.is_abs_path(destination) && os.dir(destination) == os.real_path(os.dir(destination))
		&& destination == os.abs_path(destination), 'canonical destination parent required')!
	require(!inside(destination, source) && !inside(source, destination), 'source snapshot roots overlap')!
	require(!os.exists(destination) && !os.is_link(destination) && selected.len > 0, 'fresh destination and explicit seeds required')!
	entries := source_entries(source, selected)!
	for entry in entries {
		path := destination + if entry.path == '' { '' } else { '/' + entry.path }
		match entry.kind {
			'directory' { os.mkdir(path)! }
			'file' { os.cp(source + '/' + entry.path, path, fail_if_exists: true)! }
			'link' { os.symlink(entry.link, path)! }
			else { return error('unknown source entry') }
		}
		if entry.kind == 'file' { os.chmod(path, int(entry.mode))! }
		else if entry.kind == 'link' && mode(path)! != entry.mode {
			$if macos { require(unsafe { C.lchmod(&char(path.str), entry.mode) } == 0, 'source link mode copy failed')! }
			$else { return error('source link mode cannot be preserved on this host') }
		}
	}
	for index := entries.len - 1; index >= 0; index-- {
		entry := entries[index]
		if entry.kind == 'directory' {
			os.chmod(destination + if entry.path == '' { '' } else { '/' + entry.path }, int(entry.mode))!
		}
	}
	receipt := Receipt{source: source, destination: destination, selected: selected.clone(), entries: entries}
	verify(receipt)!
	return receipt
}

pub fn save(receipt Receipt, path string) ! {
	require(os.is_abs_path(path) && os.dir(path) == os.real_path(os.dir(path))
		&& !os.exists(path) && !os.is_link(path) && !inside(path, receipt.source)
		&& !inside(path, receipt.destination), 'fresh external source receipt required')!
	verify(receipt)!
	text := json2.encode(receipt, prettify: true) + '\n'
	fd := unsafe { C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, i32(0o644)) }
	require(fd >= 0, 'source receipt exclusive creation failed')!
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut offset := 0
	for offset < text.len {
		count := unsafe { C.write(fd, text.str + offset, uint(text.len - offset)) }
		if count < 0 && C.errno == C.EINTR { continue }
		require(count > 0 && count <= text.len - offset, 'source receipt write failed')!
		offset += int(count)
	}
	closed = true
	require(C.close(fd) == 0, 'source receipt close failed')!
}
