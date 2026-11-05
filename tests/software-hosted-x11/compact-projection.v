// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only selected-copy projection; this does not run audits or producers.
module main

import crypto.sha256
import json2
import nativeguard
import os
import time

const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const bundle = '/Users/alex/Library/Caches/vinix-codex/section14/compact-launch-entry-20261026/targets01/bundle'
const old_tools = state + '/native-supervision-host-01'
const bootstrap = state + '/compact-import-bootstrap-01'
const report = state + '/compact-stage-projection-02.json'
const frozen_record = state + '/compact-frozen-tools-01.json'
const mib = u64(1) << 20

struct Count {
mut:
	files int
	directories int
	logical u64
	rounded u64
	started i64 = time.sys_mono_now()
}

struct Part {
	path string
	files int
	directories int
	logical_bytes u64
	rounded_bytes u64
}

struct Projection {
	format int = 1
	scope string = 'Selected independent copies, each file rounded to4KiB and each directory charged4KiB; retained old tool root and all failed attempts; no original audit, import or guest execution'
	source_sha256 string
	selected []Part
	old_tools_actual_bytes u64
	old_tools_rounded_bytes u64
	old_tools_inventory_sha256 string
	bootstrap_actual_bytes u64
	allowances map[string]u64
	total_bytes u64
	ceiling_bytes u64 = u64(256) << 20
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn frozen(path string, depth int, mut count Count, mut pins map[string]string) ! {
	need(depth < 128 && count.files + count.directories < 250000
		&& time.sys_mono_now() - count.started < 120 * time.second, 'frozen inventory scan bound')!
	before := os.lstat(path)!
	identity := before.dev.str() + ':' + before.inode.str() + ':' + before.mode.str() + ':'
		+ before.uid.str() + ':' + before.gid.str() + ':' + before.nlink.str() + ':'
		+ before.size.str() + ':' + before.mtime.str() + ':' + before.ctime.str()
	mut content := ''
	match before.mode & 0o170000 {
		0o100000 {
			need(before.size <= u64(64) << 20, 'frozen inventory file bound')!
			count.files++
			count.logical += before.size
			count.rounded += (before.size + 4095) / 4096 * 4096
			content = digest(path)!
		}
		0o040000 {
			count.directories++
			count.rounded += 4096
			mut names := os.ls(path)!
			names.sort()
			for name in names { frozen(path + '/' + name, depth + 1, mut count, mut pins)! }
		}
		0o120000 {
			count.files++
			count.rounded += 4096
			content = 'link:' + os.readlink(path)!
		}
		else { return error('frozen inventory rejects special files: ' + path) }
	}
	after := os.lstat(path)!
	need(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime,
		'frozen input changed during inventory: ' + path)!
	pins[path] = identity + ':' + content
}

fn frozen_map() !(map[string]string, u64) {
	mut pins := map[string]string{}
	mut count := Count{}
	frozen(old_tools, 0, mut count, mut pins)!
	return pins, count.rounded
}

fn verify_frozen() ! {
	need(os.args == [os.executable(), '--verify-frozen'], 'requires fixed --verify-frozen')!
	before := json2.decode[map[string]string](os.read_file(frozen_record)!, strict: true)!
	after, rounded := frozen_map()!
	need(before == after && rounded <= u64(31) * mib
		&& nativeguard.allocated([old_tools], os.lstat(state)!.dev)! <= u64(31) * mib,
		'frozen old tool root changed or exceeds31MiB aggregate reservation')!
	println('PASS complete frozen old tool root metadata, paths, contents and links unchanged')
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn walk(path string, depth int, mut count Count) ! {
	need(depth < 128 && count.files + count.directories < 250000
		&& time.sys_mono_now() - count.started < 120 * time.second, 'projection scan bound')!
	before := os.lstat(path)!
	match before.mode & 0o170000 {
		0o100000 {
			need(before.size <= u64(64) << 20, 'projection file bound')!
			count.files++
			count.logical += before.size
			count.rounded += (before.size + 4095) / 4096 * 4096
		}
		0o040000 {
			count.directories++
			count.rounded += 4096
			mut names := os.ls(path)!
			names.sort()
			for name in names { walk(path + '/' + name, depth + 1, mut count)! }
		}
		else { return error('projection rejects links and special files: ' + path) }
	}
	after := os.lstat(path)!
	need(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime,
		'projection input changed: ' + path)!
}

fn selected(path string) !Part {
	mut count := Count{}
	walk(path, 0, mut count)!
	return Part{path, count.files, count.directories, count.logical, count.rounded}
}

fn run() ! {
	need(os.args == [os.executable(), '--project'] && !os.exists(report) && !os.is_link(report),
		'requires fixed fresh --project report')!
	need(!os.exists(frozen_record) && !os.is_link(frozen_record), 'requires fresh frozen inventory')!
	mut parts := []Part{}
	sources := selected(bundle + '/source')!
	for arch in ['aarch64', 'x86_64'] {
		parts << Part{bundle + '/source -> import-' + arch + '/source', sources.files,
			sources.directories, sources.logical_bytes, sources.rounded_bytes}
		for name in ['app/desktop.c', 'app/execinfo.c', 'app/presenter.c', 'vinix-desktop'] {
			parts << selected(bundle + '/' + arch + '/' + name)!
		}
	}
	device := os.lstat(state)!.dev
	old_actual := nativeguard.allocated([old_tools], device)!
	old_map, old_rounded := frozen_map()!
	bootstrap_actual := nativeguard.allocated([bootstrap], device)!
	// The former40MiB writable root is now frozen and fully retained under a
	// narrower31MiB aggregate reservation. Its historical owner limit is unchanged.
	// Bootstrap includes retained attempts and this helper. The observer budget
	// includes900 one-second samples (three4KiB df siblings each), original audit
	// logs/maps, staging/import receipts, final records and allocation rounding.
	allowances := {
		'frozen-old-tools-inclusive-bound': u64(31) * mib
		'fresh-consumer-tools-inclusive-bound': u64(40) * mib
		'bootstrap-inclusive-bound': u64(10) * mib
		'observer-audits-import-receipts-and-rounding': u64(16) * mib
		'new-import-root-and-app-directories': u64(4) * 4096
	}
	need(old_actual <= allowances['frozen-old-tools-inclusive-bound']
		&& old_rounded <= allowances['frozen-old-tools-inclusive-bound']
		&& bootstrap_actual <= allowances['bootstrap-inclusive-bound'], 'existing namespace exceeds projection allowance')!
	mut total := u64(0)
	for part in parts { total += part.rounded_bytes }
	for _, value in allowances { total += value }
	encoded_old := json2.encode(old_map) + '\n'
	projection := Projection{source_sha256: sha256.hexhash($embed_file('compact-projection.v').to_string()),
		selected: parts, old_tools_actual_bytes: old_actual,
		old_tools_rounded_bytes: old_rounded, old_tools_inventory_sha256: sha256.hexhash(encoded_old),
		bootstrap_actual_bytes: bootstrap_actual, allowances: allowances, total_bytes: total}
	os.write_file(frozen_record, encoded_old)!
	os.write_file(report, json2.encode(projection) + '\n')!
	println(json2.encode(projection))
	need(total <= projection.ceiling_bytes - u64(2) * mib, 'selected cumulative projection exceeds254MiB pre-final ceiling')!
}

fn main() {
	if os.args == [os.executable(), '--verify-frozen'] { verify_frozen() or { eprintln(err); exit(1) } }
	else { run() or { eprintln(err); exit(1) } }
}
