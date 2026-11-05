// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the current source inputs before a separately reviewed profile edit.
module main

import crypto.sha256
import json2
import os

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const source_root = state + '/source'
const suite = source_root + '/tests/software-hosted-x11'
const consumer = state + '/native-consumer-tools-01'
const destination = consumer + '/source-before-current-01'
const maintained_source = repository + '/tests/software-hosted-x11/preserve-options-current.v'
const binder_source = repository + '/tests/software-hosted-x11/bind-options-compact.v'
const limit = u64(1024 * 1024)
const modules_sha = '7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce'

struct Tree { root string entries map[string]string }
struct Snapshot {
mut:
	files map[string]string
	modes map[string]u32
	trees []Tree
	bytes u64
	entries int
}
struct Copy { source string capture string sha256 string mode u32 }
struct BuildReceipt { pins string }

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn same(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.uid == b.uid
		&& a.gid == b.gid && a.nlink == b.nlink && a.size == b.size
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

fn text(path string) !string {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.size <= limit,
		'preserver requires an ordinary file at most1MiB: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut bytes := []u8{cap: int(before.size)}
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		need(u64(bytes.len + n) <= limit, 'preserver input exceeded1MiB')!
		bytes << buffer[..n]
	}
	need(u64(bytes.len) == before.size && same(before, os.lstat(path)!), 'preserver input changed: ' + path)!
	return bytes.bytestr()
}

fn add(path string, mut snapshot Snapshot) !string {
	need(path !in snapshot.files && snapshot.files.len < 128, 'duplicate source or128-file bound')!
	before := os.lstat(path)!
	need(os.real_path(path) == path && before.mode & 0o170000 == 0o100000
		&& before.size <= limit - snapshot.bytes,
		'ordinary source or total1MiB bound refused: ' + path)!
	hash := sha256.hexhash(text(path)!)
	need(same(before, os.lstat(path)!), 'source metadata changed during capture')!
	snapshot.files[path] = hash
	snapshot.modes[path] = before.mode
	snapshot.bytes += before.size
	return hash
}

fn walk(root string, relative string, depth int, mut snapshot Snapshot, mut tree map[string]string) ! {
	need(depth < 32 && snapshot.entries < 256, 'source traversal bound')!
	snapshot.entries++
	path := if relative == '' { root } else { root + '/' + relative }
	before := os.lstat(path)!
	match before.mode & 0o170000 {
		0o100000 { tree[relative] = add(path, mut snapshot)! }
		0o040000 {
			if relative != '' { tree[relative] = 'directory' }
			mut names := os.ls(path)!
			names.sort()
			for name in names {
				need(name != '' && name !in ['.', '..'] && !name.contains('/'), 'invalid source component')!
				next := if relative == '' { name } else { relative + '/' + name }
				walk(root, next, depth + 1, mut snapshot, mut tree)!
			}
		}
		else { return error('source alias or special file refused: ' + path) }
	}
	need(same(before, os.lstat(path)!), 'source tree changed during traversal: ' + path)!
}

fn sources() !Snapshot {
	mut result := Snapshot{}
	for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
		root := suite + '/' + name
		need(os.real_path(root) == root && os.lstat(root)!.mode & 0o170000 == 0o040000,
			'requires a canonical ordinary module root')!
		mut entries := map[string]string{}
		walk(root, '', 0, mut result, mut entries)!
		need(entries.len > 0, 'required source module is empty')!
		result.trees << Tree{root, entries}
	}
	for name in ['build-supervision.v', 'build-supervision-03.v', 'build-supervision-consumer-01.v',
		'check.v', 'collect.v', 'retain.v', 'evidence-check.v', 'run-native06.v', 'run-evidence06.v',
		'supervise.v', 'supervision-check.v', 'compactproof-check.v', 'compactproof-check-normal.v',
		'compactui-check.v', 'compactui-check-normal.v', 'nativeguard/guard.v',
		'diagnostics/recoveryguard/recoveryguard.v'] { add(suite + '/' + name, mut result)! }
	for path in [source_root + '/tests/hardware-platform/hwhost/process.v', binder_source, maintained_source] {
		add(path, mut result)!
	}
	return result
}

fn qualified(snapshot Snapshot) ! {
	for receipt, wanted in {
		state + '/native-supervision-host-01/check-02.build.json': 'fbd39c8d161e8a0828131f53e6eb47be860f7362c39c0ae61d41f08889eefc58'
		consumer + '/retain-01.build.json': '6d4eb66eeb057036a24c5f39edadb5e95e6d49c8fa4646bcd3b7aebf48302e75'
	} {
		value := text(receipt)!
		need(sha256.hexhash(value) == wanted, 'original build receipt changed')!
		pins := json2.decode[map[string]string](json2.decode[BuildReceipt](value)!.pins, strict: true)!
		for path, hash in pins {
			if path.ends_with('.v') { need(snapshot.files[path] == hash, 'captured build source differs: ' + path)! }
		}
		monitor := receipt.all_before_last('.build.json') + '.monitor'
		for name in ['modules-before.json', 'modules-after.json'] {
			module_text := text(monitor + '/' + name)!
			need(sha256.hexhash(module_text) == modules_sha, 'original module map changed')!
			for path, hash in json2.decode[map[string]string](module_text, strict: true)! {
				need(snapshot.files[path] == hash, 'captured fixture module differs: ' + path)!
			}
		}
	}
	need(snapshot.files[source_root + '/tests/hardware-platform/hwhost/process.v']
		== '1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5', 'qualified wait-width helper differs')!
}

fn relative(path string) !string {
	if path.starts_with(source_root + '/') { return 'fresh/' + path[source_root.len + 1..] }
	if path in [binder_source, maintained_source] { return 'repository/' + path[repository.len + 1..] }
	return error('unexpected source capture path')
}

fn directory(relative string, mut expected map[string]string) ! {
	mut prefix := ''
	for name in relative.split('/') {
		need(name != '' && name !in ['.', '..'], 'invalid capture component')!
		prefix = if prefix == '' { name } else { prefix + '/' + name }
		path := destination + '/files/' + prefix
		if !os.exists(path) && !os.is_link(path) { os.mkdir(path, mode: 0o700)! }
		need(os.lstat(path)!.mode & 0o170000 == 0o040000, 'capture directory alias refused')!
		expected[prefix] = 'directory'
	}
}

fn run() ! {
	$if prod {} $else { return error('requires production embedded source binding') }
	need(os.args == [os.executable(), '--preserve'], 'requires exact --preserve')!
	bound := sha256.hexhash($embed_file('preserve-options-current.v').to_string())
	need(sha256.hexhash(text(@FILE)!) == bound && sha256.hexhash(text(maintained_source)!) == bound,
		'compiled or maintained preserver source changed')!
	need(os.real_path(consumer) == consumer && os.lstat(consumer)!.mode & 0o170000 == 0o040000
		&& !os.exists(destination) && !os.is_link(destination), 'requires a fresh private capture root')!
	before := sources()!
	qualified(before)!
	os.mkdir(destination, mode: 0o700)!
	os.mkdir(destination + '/files', mode: 0o700)!
	mut expected := map[string]string{}
	for tree in before.trees {
		prefix := relative(tree.root)!
		directory(prefix, mut expected)!
		for name, kind in tree.entries { if kind == 'directory' { directory(prefix + '/' + name, mut expected)! } }
	}
	mut copies := []Copy{}
	mut paths := before.files.keys()
	paths.sort()
	for path in paths {
		name := relative(path)!
		directory(os.dir(name), mut expected)!
		capture := destination + '/files/' + name
		need(!os.exists(capture) && !os.is_link(capture), 'capture file already exists')!
		os.cp(path, capture)!
		os.chmod(capture, int(before.modes[path] & 0o7777))!
		info := os.lstat(capture)!
		need(info.nlink == 1 && info.mode == before.modes[path]
			&& sha256.hexhash(text(capture)!) == before.files[path], 'independent capture bytes/mode differ')!
		expected[name] = before.files[path]
		copies << Copy{path, capture, before.files[path], before.modes[path]}
	}
	after := sources()!
	qualified(after)!
	need(before.files == after.files && before.modes == after.modes
		&& json2.encode(before.trees) == json2.encode(after.trees), 'complete source set changed during preservation')!
	mut capture := Snapshot{}
	mut capture_tree := map[string]string{}
	walk(destination + '/files', '', 0, mut capture, mut capture_tree)!
	need(capture_tree == expected && capture.bytes == before.bytes, 'complete captured namespace differs')!
	mut records := {'sources-before.json': json2.encode(before) + '\n', 'sources-after.json': json2.encode(after) + '\n',
		'capture-tree.json': json2.encode(capture_tree) + '\n', 'mapping.json': json2.encode(copies) + '\n'}
	mut hashes := map[string]string{}
	for name, value in records { hashes[name] = sha256.hexhash(value) }
	records['result.json'] = json2.encode({'outcome': 'PRESERVED',
		'source_sha256': bound, 'files': copies.len.str(), 'source_bytes': before.bytes.str(),
		'records': json2.encode(hashes),
		'scope': 'Independent current source copies and exact complete maps only; original build receipts unchanged. No profile mutation, compiler, owner, audit, import or guest execution.'}) + '\n'
	mut total := before.bytes
	for _, value in records { total += u64(value.len); need(u64(value.len) <= limit, 'record exceeds1MiB')! }
	need(copies.len + records.len <= 128 && total <= limit, 'inclusive capture and receipt bound exceeds128files/1MiB')!
	for name, value in records { os.write_file(destination + '/' + name, value)! }
	mut final := Snapshot{}
	mut final_tree := map[string]string{}
	walk(destination, '', 0, mut final, mut final_tree)!
	mut final_expected := {'files': 'directory'}
	for name, hash in capture_tree { final_expected['files/' + name] = hash }
	for name, value in records { final_expected[name] = sha256.hexhash(value) }
	need(final_tree == final_expected, 'final complete capture/receipt namespace differs')!
	for copy in copies {
		need(final.files[copy.capture] == copy.sha256 && final.modes[copy.capture] == copy.mode
			&& os.lstat(copy.capture)!.nlink == 1, 'captured bytes/mode/link count changed after receipts')!
	}
	println('PRESERVED complete current source copies; files=' + copies.len.str() + ' source_bytes=' + before.bytes.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
